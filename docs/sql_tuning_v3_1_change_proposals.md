# V3 → V3.1 catalog change proposals (for review)

Status: **decided 2026-10-03; implemented as V3.1.** See [V3.1 change record](sql_tuning_v3_1_changes.md).

| ID | User decision | Conditions recorded |
| --- | --- | --- |
| P1 | Accept with modification | Three stages: detection, attribution, validation. Not every rule needs all three. Missing validation never erases a detection finding. |
| P2 | Accept with conditions | Additional source, not a replacement. Account for eligibility, licensing, unmonitored executions, RAC/PX QC-worker semantics and historical availability. Absence ≠ zero rows or no problem. |
| P3 | Accept with strict limits | ASH reconstruction is sampled and incomplete, never presented as exact. AWR SQL Monitor reports may be stronger. Preserve licensing, retention and coverage status. |
| P4 | Accept with conditions | Predicate text alone never proves implicit conversion. Verify datatype metadata; classify uncertain cases; keep a future parser possible. |
| P5 | Accept | Comparable windows and correct aggregate/delta semantics. |
| P6 | Accept with wording change | Fixed wording; never concludes the problem is outside the database; distinct from insufficient database evidence. |
| P7 | Strongly accept | Expanded item list; `CONTROL_MANAGEMENT_PACK_ACCESS` is not entitlement. |
| P8 | Strongly accept | Thresholds stay null; separate versioned profiles; always report the measured value, metric, unit, scope/window, missing threshold and reason. |

The original proposal text follows unchanged.

Decisions already recorded (2026-10-03): Python 3.8+, SQL*Plus executor, thresholds stay `null` (configuration required), catalog changes reviewed individually.

Oracle facts below were re-checked against the 19c documentation on 2026-10-03 (links inline).

---

## P1. Separate detection evidence from confirmation evidence

**Problem.** 21 canonical rules list `trials` (controlled lab comparisons) as *required* evidence, and several put the trial gain inside the `decision` conjunction. Examples:

- PRED-004 decision = `conversion_predicates > 0` **AND** `conversion_gain > controlled_cost_gain`
- AP-001, AP-002, AP-003, JOIN-003, JOIN-005, SORT-003, SUBQ-003, SUBQ-004, CUR-002, PART-003, PART-004, IDX-001..003, PRED-001..004, DATA-001..003

A read-only production investigation never has trial results. Under the unknown policy ("missing required evidence prevents evaluation"), these rules can never report anything, not even the observation that a conversion predicate exists.

**Proposal.** Split each affected rule into two levels:

| Field | Meaning | Allowed conclusion |
| --- | --- | --- |
| `detection_evidence` + `decision` | Mechanism is present in the executed plan/metadata | `observation` / `optimization_opportunity` |
| `confirmation_evidence` + `confirmation` | Equivalent controlled trial or matched comparison shows cost impact | Eligible for `candidate_contributor` → `supported_cause` via causal gates |

Trial gain moves from `decision` to `confirmation`. The causal gates are unchanged. A rule detected but unconfirmed reports "opportunity — confirmation test proposed", with the trial as the `next_test`.

**Effect.** Strictness about causes is preserved. Detection becomes possible in production. No rule becomes a cause without the trial.

**Risk.** More "opportunity" findings appear. The report must group them below causes and must not rank them as causes.

---

## P2. Bind actual row-source statistics to V$SQL_PLAN_MONITOR

**Problem.** `plan.a_rows` / `plan.starts` / `plan.buffers` are bound only to `V$SQL_PLAN_STATISTICS_ALL` (`LAST_OUTPUT_ROWS`, `LAST_STARTS`). Plan execution statistics are only collected at `STATISTICS_LEVEL=ALL` (or for statements run with the `GATHER_PLAN_STATISTICS` hint). The default `TYPICAL` does not collect them ([STATISTICS_LEVEL](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/STATISTICS_LEVEL.html)). On a typical production system, CARD-005, JOIN-001, TEMP-002 and edges CE-02/CE-03 would therefore be UNKNOWN almost always.

SQL Monitor is collected at `TYPICAL` automatically for executions using ≥5 s of CPU or I/O, for parallel statements, and with the `MONITOR` hint. It requires the Tuning Pack ([Monitoring Database Operations](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/monitoring-database-operations.html)), and demo licensing is authorized. `V$SQL_PLAN_MONITOR` is already in the allowlist and is currently bound only to `px`. It holds `STARTS`, `OUTPUT_ROWS` (cumulative for the execution; divide by `STARTS`), `PLAN_LINE_ID` and `WORKAREA_TEMPSEG` ([V$SQL_PLAN_MONITOR](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SQL_PLAN_MONITOR.html)).

**Proposal.**

1. Add a `V$SQL_PLAN_MONITOR` binding to `plan` for `starts`, `a_rows`, `temp_bytes`, keyed by `SQL_ID/SQL_EXEC_START/SQL_EXEC_ID/PLAN_LINE_ID`.
2. Record `plan.actuals_source` ∈ {`plan_statistics_last_execution`, `sql_monitor_execution`} because the semantics differ: last execution of the child versus one specific monitored execution. Prefer SQL Monitor when an execution in the incident window is identified.
3. `normalized_row_error` is unchanged (a = rows/starts, e = CARDINALITY), but its evidence must come from one execution and one source, never mixed.

**Effect.** CARD-005, JOIN-001 and TEMP-002 become evaluable for monitored executions. These are exactly the long-running ones that cause incidents.

**Risk.** Short statements (<5 s, serial, unhinted) still lack actual row counts. They remain UNKNOWN with an explicit gap and next test, such as a lab run with `GATHER_PLAN_STATISTICS`.

---

## P3. Historical execution evidence (ASH execution reconstruction + AWR SQL Monitor reports)

**Problem.** `executions` (per-execution wall time, completeness) binds only to `application_execution_log`, `V$SQL_MONITOR` and `V$SESSION`, all of which are current-state sources. For a historical incident, `wall_p95` → `wall_deviation` is UNKNOWN. That means:

- HEALTH-001 (requires `wall_deviation`) can never conclude healthy for a past incident.
- CUR-004 (requires `executions`) cannot evaluate plan regression historically.

**Proposal.** Add two historical sources:

1. **ASH execution reconstruction.** Sources: `V$ACTIVE_SESSION_HISTORY` / `DBA_HIST_ACTIVE_SESS_HISTORY` (both allowlisted). Group by QC identity + `SQL_ID` + `SQL_EXEC_START` + `SQL_EXEC_ID`. The observed duration is `max(SAMPLE_TIME) − SQL_EXEC_START`, tagged `estimate_kind = sampled_lower_bound`, with sample interval recorded (1 s in memory, 10 s in AWR). Executions shorter than the sample interval are invisible, so coverage must say so. These values feed `executions.wall_s` only with that tag. Percentiles computed from sampled lower bounds are reported as such and never mixed with logged wall times.
2. **AWR-captured SQL Monitor reports.** Sources: `DBA_HIST_REPORTS` / `DBA_HIST_REPORTS_DETAILS`. Filter on `COMPONENT_NAME='sqlmonitor'`, `KEY1`=SQL_ID, `KEY2`=SQL_EXEC_ID. AWR captures these by default for the most expensive completed statements ([Monitoring Database Operations](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/monitoring-database-operations.html); [DBA_HIST_REPORTS](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_REPORTS.html)). The XML contains per-line actual rows/starts, so it also feeds P2 historically. Parsing uses stdlib `xml.etree`.

**New allowlist entries.** `DBA_HIST_REPORTS` and `DBA_HIST_REPORTS_DETAILS`. Gate them conservatively: `requires_all: [diagnostics_pack, tuning_pack]` (DBA_HIST_ prefix → Diagnostics; SQL Monitor content → Tuning). Column lists need audit.

**Effect.** Historical incidents can establish degradation and plan regression with honestly labelled precision.

**Risk.** ASH-derived durations are lower bounds and biased against short executions. The baseline must use the same estimator (same source and sample interval), or the comparison is `incomparable`.

---

## P4. Detect conversions and column functions from executed plan predicates

**Problem.** PRED-003 and PRED-004 (and the AP-004/AP-005 aliases) require `ast` evidence produced by a "deterministic parser". No such parser exists in the Python standard library, and adding one is a large dependency or a large build. A source-text AST also shows what was *written*, not what the optimizer *applied*. Implicit conversion is only visible after binding and typing.

**Proposal.** Add a `plan_predicate_pattern_count` operator over `plan.access_predicate` / `plan.filter_predicate` (already bound from `V$SQL_PLAN`). It tokenizes the predicate text Oracle emits and matches an allowlisted set of column-side wrappers: `TO_NUMBER("COL")`, `TO_CHAR("COL")`, `TO_DATE`/`TO_TIMESTAMP("COL")`, `SYS_OP_C2C("COL")`, `INTERNAL_FUNCTION("COL")`, `UPPER/LOWER/TRUNC/SUBSTR("COL")`. Matching is token-based, with quoted identifiers resolved to the plan line's object and validated against `DBA_TAB_COLUMNS.DATA_TYPE` (`metadata`). `ast` becomes optional supporting evidence for these rules.

**Important caveat to encode.** `INTERNAL_FUNCTION` also appears for non-conversion cases such as IN-list and collection handling. It is therefore a *candidate* match that needs the column datatype and comparison-side check before it counts. Unsupported or unparseable predicate text yields UNKNOWN, never a negative.

**Effect.** PRED-003 and PRED-004 become detectable (as observations, per P1) from base-licensed plan data without a SQL parser.

**Risk.** Predicate text formats need fixture coverage from a live 19c lab before the engine relies on them.

---

## P5. Allow plan-regression evaluation from AWR per-plan aggregates

**Problem.** CUR-004 requires `executions`. Its comparison is per plan hash: cost per execution for plan A vs plan B. `DBA_HIST_SQLSTAT` already provides this per snapshot and `PLAN_HASH_VALUE` through the `sql` evidence.

**Proposal.** Make `executions` optional for CUR-004. Allow `plan_runtime_ratio` to be computed from `sql` interval deltas grouped by `plan_hash`: per-execution elapsed, CPU and buffer gets, using only snapshots with `EXECUTIONS_DELTA ≥ minimum_samples`. Retain the existing caution that AWR elapsed is DB time (including PX workers), not wall response.

**Effect.** Historical plan regression is evaluable from AWR alone.

**Risk.** Executions spanning snapshots distort per-snapshot ratios. Long-running statements need the P3 execution evidence instead, and the rule must state which basis was used.

---

## P6. Scoped "no DB-side degradation" verdict when wall time is unavailable

**Problem.** Even with P3, some investigations have no wall-latency evidence (short statements, no app log). HEALTH-001 then always ends in `insufficient_evidence`, even when AWR shows per-execution DB time, buffer gets, frequency and plan unchanged.

**Proposal.** Keep HEALTH-001 strictly as is. Add **HEALTH-002 "No material database-side cost change"**. It has the same decision without `wall_deviation`, and its conclusion text is fixed as:

> no material change in database-side cost observed; end-to-end response time not covered

The report must never present HEALTH-002 as "no problem exists".

**Effect.** This gives a useful, honest result for the common case where the problem is outside the database (application, network, client fetch). It points to WAIT-004 / APP-NETWORK as next tests.

**Risk.** Users may misread it as a full healthy verdict. The wording and placement in the report must prevent that.

---

## P7. Collection-capability evidence (why evidence is missing)

**Problem.** The catalog distinguishes `unavailable`, `unlicensed` and `not_collected`, but has no evidence describing collection-relevant configuration. Without it, the engine cannot explain *why* actual row counts or history are missing.

**Proposal.** Add a `capability` evidence table populated at the start of each investigation:

- `STATISTICS_LEVEL`, `CONTROL_MANAGEMENT_PACK_ACCESS`, `CLUSTER_DATABASE` (from allowlisted `V$PARAMETER`)
- AWR snapshot interval and retention (new allowlist entry `DBA_HIST_WR_CONTROL`, Diagnostics Pack; column audit needed)
- earliest available ASH sample per instance (from ASH, already allowlisted)
- instance list and startup times (new allowlist entry `GV$INSTANCE`/`V$INSTANCE`, base)

Per the licensing policy, these values describe *configuration*, never entitlement.

**Effect.** Every evidence gap in the report states its concrete reason and a remedy, for example: "actual rows unavailable: STATISTICS_LEVEL=TYPICAL and execution not monitored."

**Risk.** Low. These are read-only, cheap queries.

---

## P8. Threshold-profile contract (values stay null)

This item does not change any threshold value; your decision was to keep them null.

**Problem.** With null thresholds, almost every decision involving a threshold evaluates to `configuration_required`. To calibrate, the DBA needs to see the measured values and to supply values in a traceable way.

**Proposal.** Add `threshold_profiles` to the contract: an external, versioned JSON file (`profile_id`, `version`, `author`, `approved_on`, `scope` = database/workload/SQL family, `values{threshold_id: value, rationale}`). The engine:

- loads no profile by default, so every threshold stays null;
- for every rule blocked on a threshold, reports the **measured metric value**, the threshold ID and its unit, so lab and production runs build the calibration evidence;
- records the profile ID/version in every finding that used a configured value.

Literal structural boundaries already in the catalog (`> 0` operations, `zero_estimate_mismatch > 0`) still evaluate without a profile.

**Effect.** The tool is useful before calibration (it shows measurements and gaps) and becomes decisive once values are configured, with audit trail.

**Risk.** Profiles copied between workloads could be misapplied. Mitigation: the scope is checked against the investigation's database and SQL family.

---

## Summary

| ID | Change | Touches | Recommendation |
| --- | --- | --- | --- |
| P1 | Detection vs confirmation evidence | 21 rules, rule schema, validator | Accept |
| P2 | Actual rows from V$SQL_PLAN_MONITOR | `plan` evidence | Accept |
| P3 | Historical executions: ASH + DBA_HIST_REPORTS | `executions` evidence, 2 new sources | Accept |
| P4 | Plan-predicate pattern detection | new operator, PRED-003/004 | Accept |
| P5 | CUR-004 from AWR per-plan aggregates | CUR-004, `plan_runtime_ratio` | Accept |
| P6 | HEALTH-002 database-side-only verdict | new rule, outcomes | Accept with strict wording |
| P7 | Capability evidence | new evidence, 2–3 new sources | Accept |
| P8 | Threshold-profile contract (values stay null) | contract, engine | Accept |
