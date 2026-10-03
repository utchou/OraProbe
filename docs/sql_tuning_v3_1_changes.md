# V3 → V3.1 change record

Status: V3.1 is a **reviewable knowledge specification**. No engine, collector, SQL*Plus integration, MCP or agent code exists. V3.1 applies only the decisions on P1–P8 recorded on 2026-10-03 (see [proposals](sql_tuning_v3_1_change_proposals.md)).

## Files

| File | State | Purpose |
| --- | --- | --- |
| `knowledge/sql_tuning_catalog.yaml` | unchanged (V2, sha256 `f8ce81…ced4d2`) | Preserved engineering explanations |
| `knowledge/sql_tuning_catalog_v3.yaml` | unchanged (V3, sha256 `9b2a36…fe1461`) | Historical checkpoint; still validates |
| `knowledge/sql_tuning_sources_19c.json` | unchanged (sha256 `c5564b…771cba`) | V3 source allowlist |
| `knowledge/sql_tuning_catalog_v3_1.yaml` | **new** | V3.1 catalog (YAML 1.2, JSON subset) |
| `knowledge/sql_tuning_sources_19c_v3_1.json` | **new** | V3.1 source/column/pack allowlist |
| `knowledge/threshold_profiles/template.json` | **new** | P8 profile template; all 39 values `null` |
| `tools/migrate_catalog_v3_to_v3_1.ps1` | **new** | Deterministic generator of V3.1 from V3 (re-run gives byte-identical output) |
| `tools/validate_sql_tuning_catalog.ps1` | **changed** | Validates 3.0 and 3.1; default target is now V3.1 |
| `tools/test_validate_sql_tuning_catalog.ps1` | **new** | 22 regression cases; 20 deliberate violations must be rejected |
| `docs/sql_tuning_v3_1_rule_stage_map.md` | **new, generated** | Where every V3 decision condition went, per rule |

V3.1 records the V3 catalog and V3 allowlist SHA-256 hashes. The validator fails if either file changes. Every V3 rule ID and every V3 metric ID is preserved, and all 171 V3 metric definitions are byte-identical in V3.1.

Run:

```powershell
tools\validate_sql_tuning_catalog.ps1                       # V3.1
tools\validate_sql_tuning_catalog.ps1 -CatalogPath knowledge\sql_tuning_catalog_v3.yaml   # V3 checkpoint
tools\test_validate_sql_tuning_catalog.ps1                  # validator regression tests
```

## Counts

| | V3 | V3.1 |
| --- | ---: | ---: |
| Rule IDs (incl. 2 aliases) | 87 | 88 (+HEALTH-002) |
| Canonical rules | 85 | 86 (3 lab-only) |
| Rules with detection / attribution / validation stage | – | 83 / 59 / 51 |
| Sources | 61 | 68 (+5 Oracle, +2 external) |
| Evidence tables | 27 | 28 (+`capability`) |
| Metrics | 171 | 180 (+9) |
| Thresholds (all `null`) | 39 | 39 (unchanged) |
| Causal edges | 16 | 16 (restructured) |
| Acceptance cases | 3 | 4 (+`database_side_only`, +6 negative perturbations) |

## P1 — Three evidence stages (accepted with modification)

**Rule schema.** `decision` and `required_evidence` are replaced by `stages`:

```text
stages.detection    { evidence, optional_evidence, decision, conclusion, meaning }        null only when lab_only
stages.attribution  { evidence, optional_evidence, test, binds_to, conclusion, when_unknown, [classification_tests] } | null
stages.validation   { evidence:[trials], test, disconfirm_test, validates: mechanism|remediation_gain, conclusion, when_missing } | null
lab_only            true only when V3's decision consisted solely of a controlled trial
```

**Partition rule.** Each V3 decision condition was assigned to exactly one stage by an explicit per-rule table. The migration fails if any condition is unassigned, assigned twice, or if a trial metric lands outside validation. All 59 assignments are listed in the [stage map](sql_tuning_v3_1_rule_stage_map.md).

**Policy (contract.stage_policy).**
- Stages evaluate independently over their own evidence.
- Attribution and validation are evaluated whenever detection is TRUE.
- Missing attribution gives `attribution_unresolved`: the finding stays at its detection conclusion, with the gap and next test named.
- Missing validation gives `validation_pending`, with no penalty and no cap.
- Disconfirmed validation applies the existing −60 weight to the mechanism or remediation claim only. Detection and attribution findings remain.
- No stage may conclude `supported_cause`. That still requires all five causal gates.

**Counter and supporting tests** carry a `stage` tag. Each V3 `*-disconfirm` counter test (a controlled-trial group) moved into `validation.disconfirm_test`, so a trial is counted once.

**Causal edges.** `test` became `attribution_test`, with `validation_test`, `validation_evidence` and `validation_disconfirm_test` added. Only CE-01 (`statistics_gain`) and CE-02 (`join_order_gain`) had trial conditions. Their `required_evidence` no longer includes `trials`.

**Semantic differences from V3.** These need explicit review:

1. **Optimization-opportunity rules no longer need a trial to be reported.** This affects 13 rules: AP-001/002/003, JOIN-003, SORT-003, SUBQ-003/004, PART-004, IDX-003, PRED-001…004. In V3 they required a lab trial gain.
   - V3.1 reports *observation* at detection.
   - It reports *optimization_opportunity* at attribution. For most rules, that attribution is the new `flagged_operation_activity_share`, the ASH share of the execution's time on the flagged plan line.
   - `validates=remediation_gain` records the trial when one exists.
   - Benefit is never claimed without validation.
2. **DATA-001/002/003 and JOIN-005 have no attribution stage.** Without a trial they stop at *observation*.
3. **Lab-only rules: PART-003, IDX-001, IDX-002.** Their V3 decision was only a trial, so they cannot produce a read-only production finding.
4. **Six rules keep V3 semantics with no attribution stage:** PAR-003, PAR-004, EXT-005, FAM-002, RAC-001 and WAIT-003. Detection TRUE gives `candidate_contributor` exactly as V3's decision did. Adding attribution tests to them would be new diagnostic content and was not done.
5. **Disconfirmation now uses each rule's specific trial metric** (e.g. `access_gain` instead of the generic `controlled_gain`) where V3's decision named one.
6. **CARD-001 and CARD-002 validation uses `statistics_gain`.** This metric existed in V3 but was unused.
7. **`hypothesis_gates.measured_degradation` also accepts `db_time_deviation`.** This is a consequence of P5/P6, not an independent decision. Without it, AWR-only historical investigations could never establish degradation when only database time grew. **Please confirm.**
8. **Four pairs of rules share an identical detection decision:** JOIN-005/CARD-005, TEMP-005/SUBQ-004, RAC-002/EXT-004 and CUR-006/FAM-001. Per `stage_policy.shared_detection`, each pair produces one observation, scored once. The validator reports these pairs as INFO.

## P2 — SQL Monitor as an additional plan-line source (accepted with conditions)

- **`plan` evidence:** adds `V$SQL_PLAN_MONITOR`, `DBA_HIST_REPORTS` and `DBA_HIST_REPORTS_DETAILS` bindings, plus fields `actuals_source`, `execution_key` and `monitor_status`. The `V$SQL_PLAN_STATISTICS_ALL` binding is retained, and the validator enforces that.
- **Normalization:** one actuals source per execution, never mixed in one row-error calculation. `OUTPUT_ROWS` is cumulative, so a = `OUTPUT_ROWS/STARTS`. A missing monitored execution leaves values UNKNOWN, never 0.
- **`workarea` evidence:** adds plan-line `WORKAREA_MAX_TEMPSEG`/`WORKAREA_MAX_MEM`. `WORKAREA_TEMPSEG` is NULL when there was no spill or the execution has finished.
- **`executions` evidence:** adds `KEY`, `PROCESS_NAME`, `PX_SERVER#/SET/GROUP`, `PX_IS_CROSS_INSTANCE`, `FETCHES` and others.
- **`contract.monitor_policy`:**
  - Monitoring eligibility: at least 5 s of CPU or I/O, parallel execution, the `MONITOR` hint, or the `sql_monitor` event.
  - Licensing: Diagnostics+Tuning, with the validator enforcing the gate.
  - Retention: live entries persist at least one minute after completion.
  - QC and PX semantics: the coordinator and each PX server have separate entries sharing the execution key. Count the execution once, and sum plan-line values across all entries, including GV$ for cross-instance PX.
  - Absence is never zero rows or no problem.
- **New metric `monitored_execution_share`** makes unmonitored executions visible.
- **Source:** column lists audited against the 19c Reference ([V$SQL_PLAN_MONITOR](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SQL_PLAN_MONITOR.html), [V$SQL_MONITOR](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SQL_MONITOR.html), [Monitoring Database Operations](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/monitoring-database-operations.html)).

## P3 — Historical execution evidence (accepted with strict limits)

- **`executions` evidence:**
  - Bindings added: ASH (`V$`/`DBA_HIST_ACTIVE_SESS_HISTORY`) and AWR SQL Monitor reports.
  - Fields added: `estimate_kind`, `sample_interval_s`, `sample_count`, `plan_hash` and `actuals_source`.
  - ASH columns added after audit: `SQL_PLAN_HASH_VALUE`, `IS_SQLID_CURRENT`, `TEMP_SPACE_ALLOCATED`, `TM_DELTA_CPU_TIME`, `TM_DELTA_TIME`, `CON_ID`.
- **`contract.historical_execution_policy.estimate_kinds`:**
  - `exact_logged`
  - `monitor_db_time`
  - `report_bounded`
  - `sampled_lower_bound`: ASH durations, where `max(SAMPLE_TIME) − SQL_EXEC_START` is a lower bound and executions shorter than the sample spacing can be missing entirely.
  - `polled_censored`

  Incident and baseline must use the same kind, otherwise they are incomparable.
- **AWR sample spacing** comes from `USECS_PER_ROW` and the observed sample times. The 19c Reference does not document a fixed spacing, so none is assumed.
- **New sources** `DBA_HIST_REPORTS` and `DBA_HIST_REPORTS_DETAILS` (`COMPONENT_NAME='sqlmonitor'`, `KEY1`=SQL_ID, `KEY2`=SQL_EXEC_ID):
  - Gated conservatively as Diagnostics+Tuning.
  - The report XML structure is not documented in the Reference, so it must be fixture-verified on a live 19c lab.
  - A parse failure yields `incomplete`, never `absent`.

## P4 — Executed-plan predicate patterns (accepted with conditions)

- **New operator `plan_predicate_pattern_count`** and a new top-level `plan_predicate_patterns` section:
  - Conversion wrappers: `TO_NUMBER`, `TO_CHAR`, `TO_DATE`, `TO_TIMESTAMP`, `SYS_OP_C2C`, and `INTERNAL_FUNCTION` (marked ambiguous).
  - Function wrappers: `UPPER`, `LOWER`, `TRUNC`, `SUBSTR`, `NVL`.
  - Patterns apply to the column side of a comparison only.
- **Classifications:** `candidate`, then `datatype_verified` (column datatype from `DBA_TAB_COLUMNS` disagrees with the wrapper), then `implicit_confirmed` (parsed source shows no explicit conversion). Uncertain cases are `candidate_unverified` or `unparseable`, which count as UNKNOWN.
- **New metrics:** `plan_conversion_candidates`, `plan_conversion_verified`, `plan_conversion_implicit_confirmed`, `plan_function_candidates`.
- **PRED-004:**
  - Detection is `ANY(parsed conversion, plan candidate)`.
  - Attribution is `ALL(datatype verified, flagged operation's activity share > bound)`.
  - A classification test reports implicit, explicit or undetermined.

  **Predicate text alone never proves an implicit conversion.**
- **PRED-003:** detection is `ANY(parsed function, plan candidate)`.
- **`ast` evidence** became optional for PRED-003/004 and **remains** the alternative path, so a SQL parser can be added later without restructuring rules.
- **Authority:** the patterns are marked `engineering_interpretation`, pending live-lab fixtures.

## P5 — Historical plan regression from AWR (accepted)

- **New metrics:** `awr_plan_elapsed_ratio` and `awr_plan_buffer_ratio`, per plan hash, from `DBA_HIST_SQLSTAT` deltas.
- **CUR-004** attribution is `ANY(plan_runtime_ratio, awr_plan_elapsed_ratio, awr_plan_buffer_ratio)`. `executions` evidence becomes optional.
- **`contract.awr_plan_policy`:**
  - `*_DELTA` values are never re-differenced.
  - Snapshot join requires startup continuity.
  - Windows must be comparable: same instances, service, Resource Manager plan/group, stratum and interval.
  - Snapshots below `minimum_samples` are excluded.
  - AWR elapsed is DB time including PX.
  - Executions that span snapshots are flagged.

## P6 — HEALTH-002 database-side verdict (accepted with wording change)

- **New rule HEALTH-002** with new class `no_material_database_side_degradation`. Its fixed text is in `contract.database_side_policy.conclusion_text`, and the validator enforces it verbatim:

  > No material database-side degradation detected in the investigated evidence/window; end-to-end application/network/client response time was not evaluated.
- **Decision:** HEALTH-001's decision with `wall_deviation` replaced by the new `db_time_deviation` (DB time per execution). Without that replacement, a storage-latency slowdown with unchanged buffer gets would pass as healthy.
- **Preconditions:** `wall_deviation` status is unknown, and HEALTH-001 is not TRUE.
- **Withhold list:** never imply the application, network or client is responsible; never state that no problem exists. The role stays `unresolved` and an `APP-NETWORK` request is raised.
- **Distinct from insufficient evidence:** HEALTH-002 still requires coverage and a comparable baseline. When those are unknown the outcome is `insufficient_evidence`.

## P7 — Collection/environment capability record (strongly accepted)

- **New `capability` evidence** recorded at investigation start, before any diagnostic collection. `contract.capability_policy.items` lists:
  - Oracle version
  - database, container and instance identity and startup
  - RAC topology and instance coverage
  - `STATISTICS_LEVEL`
  - `CONTROL_MANAGEMENT_PACK_ACCESS`
  - configured license policy
  - SQL Monitor availability
  - AWR interval, retention and earliest snapshot
  - earliest ASH sample per instance
  - collector privilege and connection mode
  - Resource Manager plan, `CPU_COUNT` and caging
  - collection timestamps and requested window
- **New Oracle sources (audited):** `V$INSTANCE`, `V$DATABASE`, `DBA_HIST_WR_CONTROL`.
- **New external sources:** `license_policy` (the configured entitlement record) and `collector_runtime` (privileges and per-query timing as reported by the collector).
- **Entitlement:** `CONTROL_MANAGEMENT_PACK_ACCESS` and source existence are explicitly *not* entitlement.
- **`gap_reasons`:** every UNKNOWN cites a concrete reason, for example `statistics_level_typical_no_plan_statistics` or `execution_not_monitored`.

## P8 — Threshold profiles (strongly accepted)

- **Catalog thresholds:** all 39 remain `null`. The validator fails if any receives a value.
- **`contract.threshold_profile_policy`:**
  - Profiles live in `knowledge/threshold_profiles/`, separate from the catalog.
  - A profile needs id, version, author, approval and scope. Scope must match the investigation.
  - Every configured value needs a rationale and the catalog unit. The validator checks every profile file.
- **`blocked_decision_report`:** whenever a comparison cannot cross its boundary, the engine must report `rule_id`, `stage`, `metric_id`, `measured_value`, `unit`, `scope`, window, `threshold_id`, `threshold_unit` and `reason`.
- **Template:** `template.json` has every value `null`. No defaults are implied.

## Other edits made only to support P1–P8

- **`confidence_policy`:** `revision: 3.1` and `stage_scoring`. V3's numbers are unchanged (40 / +15 ×2 / −30 / −60 / cap 40).
- **`hypothesis_gates`:**
  - `mechanism_link` is satisfied by a TRUE edge attribution test or a TRUE rule attribution stage.
  - `comparable_control` is satisfied by a matched baseline or a TRUE validation.
- **`outcomes`:** adds `database_side_rule`, `detection_without_attribution`, `detection_without_validation` and `lab_only_rule`.
- **`feature_requirements.sql_monitor`:** adds eligibility and the AWR-report fallback.
- **`contract.unknown_reasons`:** a fixed list.
- **`acceptance_cases`:** six negative perturbations that encode the walkthrough's "must not conclude" list, plus the `database_side_only` case.

## Not changed

- Rule IDs, names, domains, hypotheses, scopes, roles, recommendations, references, relationships and cross-module requests (HEALTH-002 adds `APP-NETWORK`).
- All V3 metrics and thresholds.
- Evidence tables other than `plan`, `workarea` and `executions`.
- The confidence numbers and the five causal-gate names.

No diagnostic rule was added beyond HEALTH-002.

## Remaining gaps (found by the October walkthrough and the migration)

These are recorded here, not fixed: fixing them would go beyond P1–P8.

**Gaps that block the October case:**

1. **Family validation needs a SQL parser or an application semantic-equivalence record.** Without one, FAM-001/004, CUR-006 and every `validated_family_members` metric are UNKNOWN. P4 removed the parser dependency only for conversions and functions.
2. **Historical Resource Manager metrics are not allowlisted.** `V$RSRCMGRMETRIC_HISTORY` covers about one hour. `DBA_HIST_RSRC_*` sources would need a column/licensing audit. As a result `rm_wait_share`, `group_cpu_share`, `victim_cpu_share` and the RM onsets are unavailable for past incidents.
3. **Historical family signatures are not allowlisted:** `DBA_HIST_SQLSTAT.FORCE_MATCHING_SIGNATURE` and ASH `FORCE_MATCHING_SIGNATURE`. In addition, AWR top-N capture can omit literal members, so cohort CPU is a lower bound.
4. **No historical simultaneous TEMP occupancy.** `temp` evidence binds only the current `V$TEMPSEG_USAGE`. An ASH `TEMP_SPACE_ALLOCATED` simultaneous-sum metric (a sampled lower bound) would need a proposal.
5. **ASH `TM_DELTA_CPU_TIME` is bound but unused.** No metric yet derives per-execution consumed CPU from it.
6. **Change and trigger evidence:** there is no change-log provider or Jobs/Changes module, so TIME-001 and CE-06 cannot be tested.

**Module and confidence limits:**

7. **Missing modules cap confidence.** OS, Database Health (DB-RESOURCE), Storage, RAC/Network and Application are absent. `counter_search_complete` therefore stays UNKNOWN, every contributor candidate is capped at 40, and `supported_cause` is unreachable in the demo. A decision is needed on whether the Query Tuner may collect the `rm` base views itself, or whether a minimal DB-RESOURCE capability ships with the demo.

**Facts that need live-lab verification:**

8. **Unverified in a live lab:**
   - the SQL Monitor report XML structure;
   - QC/PX plan-line aggregation across `KEY` entries and instances;
   - `WORKAREA_MAX_TEMPSEG` semantics after completion;
   - the predicate-text patterns, including `INTERNAL_FUNCTION` cases;
   - ASH reconstruction accuracy against known executions.

**Specification gaps:**

9. **Some metric recipes are still partly prose**, e.g. `match: contract.baseline_policy` and named populations. The implementation design must define each implemented metric precisely and test it.
10. **Engine-level algorithms exist only as policy text:** shared-detection deduplication, stage evaluation order, blocked-decision reporting and the exact independence-group accounting.
11. **Some rules are thin or unreachable:**
    - Six rules have no attribution stage (PAR-003, PAR-004, EXT-005, FAM-002, RAC-001, WAIT-003).
    - Three rules are lab-only.
    - DATA-001…003 and JOIN-005 stop at observation without a trial.
12. **Item 7 under P1 above** (the `db_time_deviation` addition to `measured_degradation`) awaits confirmation.
13. **Acceptance cases are narrative.** There are no fixture datasets yet, and the validator still does not evaluate expressions.

**Environment gaps:**

14. **This development machine has no Python and no Oracle 19c lab.**

## Implementation-readiness recommendation

**Conditionally ready to start the deterministic core; not ready for the October family/RM path.**

**Ready now.** Everything here is fully specified and testable offline with fixtures:
- request and window model;
- evidence envelope with statuses;
- catalog loader that reuses these validator rules;
- three-valued expression evaluator;
- stage evaluator with the conclusion ladder;
- CP-01 scoring with caps;
- causal-gate checks;
- threshold-profile loader with blocked-decision reporting;
- capability record model;
- fixture executor;
- HTML/JSON report skeleton.

Good candidates for the first rule slice, because their evidence is base/ASH/AWR and largely literal-evaluable:
- HEALTH-001/002 and the `measured_degradation` gate;
- CUR-004 (P5);
- CARD-005 (zero-estimate branch);
- TEMP-001/003;
- RM-001;
- EXT-005;
- PRED-004 (P4);
- WAIT-005.

**Decide before coding the family/RM path:** gaps 1–4 and 7 (a small V3.2 proposal set).

**Before any live collector code:**
- install Python 3.8+ matching the RHEL 8 server's version;
- build a 19c lab, e.g. a VirtualBox VM;
- fix the read-only query catalog.
