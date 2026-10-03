# V3.1 → V3.2 change record

Status: V3.2 is a **reviewable knowledge specification**. No engine, collector, SQL*Plus integration, tokenizer/normalizer, MCP or agent code exists. V3.2 applies only the V3.2 decisions recorded on 2026-10-03 (see [proposals](sql_tuning_v3_2_proposals.md)).

**Numbering note.** In the decisions:
- "V32-09 historical concurrency" maps to the concurrency half of proposal V32-08.
- "V32-10 historical host CPU" maps to proposal V32-09.
- Proposal V32-10 (graded dependency evidence) was initially deferred as backlog BL-05 through a numbering mismatch. **Correction (2026-10-03): accepted with conditions and encoded in V3.2** (change-log ID `V32-10-dependency`; see the section below). BL-05 no longer exists.

## Files

| File | State |
| --- | --- |
| `knowledge/sql_tuning_catalog.yaml` (V2) | unchanged, sha256 `f8ce81…ced4d2` |
| `knowledge/sql_tuning_catalog_v3.yaml` (V3) | unchanged, sha256 `9b2a36…fe1461` |
| `knowledge/sql_tuning_catalog_v3_1.yaml` (V3.1) | unchanged, sha256 `a0fb1e…0f7093`; still regenerates byte-identically |
| `knowledge/sql_tuning_sources_19c.json`, `…_v3_1.json`, `threshold_profiles/template.json` | unchanged |
| `knowledge/sql_tuning_catalog_v3_2.yaml` | **new** |
| `knowledge/sql_tuning_sources_19c_v3_2.json` | **new** allowlist (adds 9 sources, extends 6) |
| `knowledge/threshold_profiles/v3_2/template.json` | **new** V3.2 profile template, all 39 values `null` |
| `tools/migrate_catalog_v3_1_to_v3_2.ps1` | **new** deterministic generator (V3.1 → V3.2) |
| `tools/catalog_json_helpers.ps1` | **new** shared JSON/expression helpers. The V3.1 generator keeps its own frozen copy. |
| `tools/validate_sql_tuning_catalog.ps1` | **changed**: validates 3.0, 3.1 and 3.2; default target V3.2; walks the predecessor hash chain 3.2 → 3.1 → 3.0 |
| `tools/test_validate_sql_tuning_catalog.ps1` | **changed**: 71 cases: P1–P8 on both 3.1 and 3.2, 24 V3.2 invariants, 4 hash-chain cases |

## Counts

| | V3.1 | V3.2 |
| --- | ---: | ---: |
| Rule IDs / canonical | 88 / 86 | 88 / 86 (no new rules) |
| Sources | 68 | 77 (+9 audited Oracle views) |
| Evidence providers | – | 15 (each source owned exactly once) |
| Evidence tables | 28 | 29 (+`sql_template`) |
| Metrics | 180 | 196 (+16; 8 existing metrics revised) |
| Thresholds | 39, all `null` | 39, all `null`; IDs and units identical (validator-enforced) |
| Lab-verification items | – | 7 (5 block production use) |
| Backlog items | – | 4 (all deferred) |

## Changes by decision

### V32-01 Family tiers — accepted
- `contract.family_policy` adds:
  - tiers **C** (cohort), **F1** (candidate), **F2** (strongly supported) and **F3** (confirmed), each with requirements, what it establishes and what it does not;
  - split rules;
  - the plan-hash rule (never merges or splits);
  - the unverified-member rule (signature-only members capped at F1);
  - selectivity strata;
  - a purpose matrix: FAM-001 needs F2, family aggregates need F2, FAM-004 needs F2, remediation scope needs F3;
  - the below-minimum behavior (cohort figures, `indirect_family_cap`, reason `family_tier_insufficient`).
- `family_member_count`, `family_cpu_share`, `group_cpu_share`, `common_path_work`, `family_temp_share` and `cpu_demand_deviation` now require tier ≥ F2.
- `family_members` (operator `family_group`) gains template, schema, plan, module/action and ASH-signature inputs. The AST inputs remain as an optional F2 path for a future parser.
- `family_tier` is added to the evidence envelope.

### V32-02 Lexical normalizer — accepted with constraints
- `contract.normalizer_policy` specifies:
  - inputs: complete text only;
  - Oracle lexical rules;
  - literal handling and semantic-risk positions;
  - strict and loose templates;
  - normalization statuses;
  - explicit `can_establish` / `cannot_establish` lists.
- **Constraints recorded in the policy:**
  - grouping and supporting evidence only;
  - normalized text alone never establishes semantic or application equivalence;
  - no grammar parser is required for the first engine.
- New evidence `sql_template`, bound to `V$SQL.SQL_FULLTEXT`, `DBA_HIST_SQLTEXT.SQL_TEXT` and `V$SQL_MONITOR.SQL_TEXT`/`IS_FULL_SQLTEXT`. It is `unsupported` until a normalizer version exists. **The normalizer itself is not implemented.**

### V32-03 Value bounds — strongly accepted
- **Bound kinds:** `contract.bound_policy` defines `exact`, `lower_bound`, `upper_bound`, `bounded_interval`, `sampled_estimate`, `interval_average` and `incomplete_unknown`.
- **Comparisons** use interval semantics: `gt` is TRUE only if lower > t and FALSE only if upper ≤ t; `eq`/`ne`/`in` apply to exact values only.
- **No silent comparison.** A bound kind that is not in the metric's `value_semantics.accepts` evaluates as UNKNOWN (`bound_not_comparable` / `estimate_not_accepted`).
- **Propagation rules** cover sums, ratios, percentiles over incomplete populations, baselines and lab-verification contamination.
- **Health rule:** lower bounds and estimates can never establish HEALTH-001/002.
- **Every metric (196) declares `value_semantics.accepts`.** Defaults by operator:
  - `rate` accepts `interval_average`;
  - `weighted_sample_share` accepts `sampled_estimate`;
  - explicit overrides: `host_busy`, `rm_wait_share`, `group_limit_utilization` (`interval_average`) and `host_queue` (`sampled_estimate`).
- The evidence envelope gains `lower_bound`, `upper_bound`, `bound_kind`, `estimate_kind`, `provider_id`, `provenance` and `lab_verification_refs`.

### V32-04 Shared evidence flow — strongly accepted with architecture modification
- **`contract.evidence_flow_policy`** states the principle verbatim (validator-enforced): **COLLECT ONCE → NORMALIZE ONCE → DEFINE CANONICAL FACT/HYPOTHESIS ONCE → ALLOW MULTIPLE DIAGNOSTIC MODULES TO CONSUME IT.**
- **`contract.provider_policy`** defines 15 providers; each source has a `provider` and belongs to exactly one:
  - 8 shared-core providers available in the demo: capability, sql_runtime, sql_history, ash, instance_runtime, resource_mgr, oracle_host, dictionary;
  - plus `snapshot_capture`;
  - 6 future module-owned providers.

  Providers hold no rules and no thresholds.
- **Every canonical rule has `knowledge_owner` and `consumers`.**
  - RM-001…006 are owned by `database_health` and consumed directly by `query_tuner`. Consumption never requires the owner module to be installed, and nothing is re-evaluated or copied.
  - The validator rejects RM rules owned elsewhere and any duplicated staged decision. A test confirms that a copy of RM-001 placed inside Query Tuner is rejected.
- **`cross_module_requests` gain `provider_fulfillment`:**
  - `DB-RESOURCE` is fully served by `resource_mgr` (`rm`) plus `instance_runtime` (`system`).
  - `OS-CPU` is partially served by `oracle_host`.

  Every request also gains `owner_module_required: false` and a `consumption` statement.

### V32-05 Historical signature sources — accepted
- **Allowlist:**
  - `DBA_HIST_SQLSTAT` + `FORCE_MATCHING_SIGNATURE`, `MODULE`, `ACTION`, `PARSING_SCHEMA_NAME`, `PARSE_CALLS_DELTA`, `END_OF_FETCH_COUNT_DELTA`, `PX_SERVERS_EXECS_DELTA`, `CON_ID`;
  - ASH (both views) + `FORCE_MATCHING_SIGNATURE`, `TOP_LEVEL_SQL_ID`, `SQL_OPCODE`, `PGA_ALLOCATED` (and `MODULE`/`ACTION`/`SERVICE_HASH` for history);
  - `V$SQL_MONITOR` + `SQL_TEXT`, `IS_FULL_SQLTEXT`, `EXACT_MATCHING_SIGNATURE`, `FORCE_MATCHING_SIGNATURE`;
  - new `DBA_HIST_SQLTEXT` and `DBA_HIST_SERVICE_NAME`. All Diagnostics Pack.
- **`contract.capture_bias_policy`:**
  - describes the selective-capture behavior of SQLSTAT, SQLTEXT, SQL_PLAN, persisted ASH and SQL Monitor reports;
  - **missing historical SQL never means the SQL did not execute**;
  - new status `not_captured` (distinct from `absent`, which requires a complete search);
  - capture settings (`TOPNSQL`) recorded in `capability`.
- **`sql` evidence** gains `module`, `action`, `service`, `capture_status` and `command_type`.
- **`sessions` evidence** gains signature, top-level SQL, opcode, module/action/service, plan hash, TEMP/PGA, `is_sqlid_current`, `TM_DELTA_*` and the sample instant.

### V32-06 Historical Resource Manager — accepted with conditions
- **New sources:**
  - `DBA_HIST_RSRC_PLAN`: plan activation, `CPU_MANAGED`, `INSTANCE_CAGING`;
  - `DBA_HIST_RSRC_CONSUMER_GROUP`: `CONSUMED_CPU_TIME` in documented ms; `CPU_WAIT_TIME` **marked `lab_verification_required` (LV-01)** at source, binding and metric level;
  - `DBA_HIST_PARAMETER`: `cpu_count` and `resource_manager_plan` only.
- **New metrics:**
  - `rm_group_consumed_cpu_interval`: documented, usable;
  - `rm_group_cpu_wait_interval`: LV-01, not usable in production;
  - `rm_instance_wait_share_interval`: from documented `DBA_HIST_OSSTAT.RSRC_MGR_CPU_WAIT_TIME`, usable;
  - `caged_capacity_utilization`;
  - `family_observed_group_mapping`.
- **Rule edits (minimal, Resource-Manager scope only):**
  - RM-001 detection accepts the group-level OR the documented instance-level wait (`> 0`);
  - RM-002 attribution accepts either wait share above `rm_pressure_share`;
  - RM-002 gains a `caged_capacity_utilization > allocation_utilization_bound` supporting test.
- **`contract.historical_resource_manager_policy`** records:
  - granularity: the snapshot interval;
  - RAC: per instance, never pooled;
  - reset rules: restart or `SEQUENCE#` change gives UNKNOWN;
  - group mapping only via ASH;
  - the list of things it cannot establish.

### V32-07 Family coverage measures — strongly accepted
- New metrics:
  - `family_ash_member_count` (lower bound);
  - `family_sqlstat_capture_share` and `family_text_capture_share` (sampled estimates).
- `contract.family_coverage_policy` makes coverage restrict conclusions:
  - historical family aggregates are lower bounds;
  - only `gt`/`ge` comparisons can become TRUE on them;
  - a family can never be concluded a non-contributor from incomplete coverage;
  - incomplete family aggregates can never feed HEALTH-001/002;
  - coverage is always reported.

### V32-08 ASH historical TEMP — accepted as estimate/bound only
- New metrics:
  - `ash_execution_temp_peak_lb`, `ash_temp_occupancy_lb`, `ash_cluster_temp_occupancy_lb`, `ash_family_temp_lb` (lower bounds);
  - `ash_family_temp_share` (sampled estimate);
  - `report_execution_temp_ub` (upper bound, **LV-05**).
- FAM-003 attribution and TEMP-004 detection accept `ash_cluster_temp_occupancy_lb > temp_budget_bytes` as an alternative to live `peak_temp_occupancy`. As a lower bound it can only prove "exceeded", never "within budget".
- `contract.historical_temp_concurrency_policy` keeps the projection rule (TEMP × concurrency is never a measurement).

### V32-09 Historical concurrency — accepted as sampled/bound evidence
- New metrics:
  - `ash_concurrent_executions_lb`: distinct execution keys per sample instant, a lower bound;
  - `sql_interval_db_time_rate`: an interval average of database time, not an execution count or peak.
- FAM-003 detection accepts either the interval-overlap count or the ASH lower bound for `> 1`.

### V32-10 Historical host CPU — accepted
- New source `DBA_HIST_OSSTAT` (provider `oracle_host`): `NUM_CPUS`, `BUSY_TIME`, `IDLE_TIME`, `OS_CPU_WAIT_TIME`, `LOAD`, `RSRC_MGR_CPU_WAIT_TIME`. OS-dependent statistics are flagged **LV-07**.
- `os` evidence gains `provenance`, `num_cpus`, `rsrc_mgr_cpu_wait_s`, `os_cpu_wait_s`, `busy_s`, `idle_s`.
- **RM-002** gains counter-test `RM-002-host-saturated`: a busy host means caging is not the sole constraint.
- **RM-004** gains counter-test `RM-004-host-spare`: spare interval-average host CPU weakens host contention.
- **`contract.host_cpu_policy`:** host CPU alone never eliminates noisy-neighbor or other external contributors, and OS-CPU stays only partially fulfilled.

### Proposal V32-10 Graded dependency evidence — accepted with conditions (correction)

Purpose: graded attribution/supporting evidence that statements or family members depend on or access a common object or view. Full contract: `contract.dependency_evidence_policy`.

| Grade | Basis | Counts as common dependency | Production use |
| --- | --- | --- | --- |
| D1 recorded cursor dependency | `V$OBJECT_DEPENDENCY` row for a cached cursor, joined to `V$SQL` `ADDRESS`/`HASH_VALUE` on the same instance and container | yes | **no** while LV-03 is open (`lab_verification_required`) |
| D2 resolved text reference | `sql_template.identifier_set` token resolved to exactly one local object under `PARSING_SCHEMA_NAME` through `DBA_OBJECTS`/`DBA_SYNONYMS` | yes | yes |
| D3 executed-plan access in closure | Plan `OBJECT#` inside the object's `DBA_DEPENDENCIES` closure | no (object coincidence) | yes |
| D4 coincidence | Unresolved or ambiguous match, closure without access, or downgraded link | no | yes |

- **Downgrades:**
  - a captured plan that touches nothing in the closure drops D2 to D4;
  - `CREATED`/`LAST_DDL_TIME` after the window start drops D2/D3 to D4 (conservative, because grants also move `LAST_DDL_TIME`);
  - ambiguous, editioned or remote objects give no D1/D2 link.
- **Coverage:**
  - missing cursor, text or plan means `not_captured`, never "no dependency";
  - `common_dependency_count` is a lower bound unless every member is graded;
  - the per-object report lists members by grade, ungraded members and downgrade reasons.
- **Fixed limits** (`cannot_establish`, validator-enforced): semantic family equivalence; that the object caused degradation; identical work beneath the view; causation because several statements reference the object. `family_tier_effect: none`. FAM-004 stays capped at `derived_fact`.
- **Catalog changes:**
  - new sources `V$OBJECT_DEPENDENCY` (base, LV-03 on `FROM_ADDRESS`/`FROM_HASH`/`TO_NAME`), `DBA_OBJECTS` and `DBA_SYNONYMS` (base);
  - column additions `V$SQL.ADDRESS`/`HASH_VALUE` and `DBA_HIST_SQL_PLAN.OBJECT#`;
  - the `dependencies` evidence gains grade fields and bindings;
  - `common_dependency_count` now takes graded inputs, has a minimum grade of D2 and no longer requires `ast`;
  - FAM-004 detection now requires only `dependencies` evidence (`sql_template`, `plan`, `ast` optional);
  - LV-03 now names the source;
  - 1 acceptance fact and 7 negative perturbations were added.
- **Not changed:** no new rules, metrics or thresholds; FAM-004 attribution (`common_path_work`), causal edges and confidence numbers.

### Serialization defect fixed in the same regeneration

80 single-consumer rules had `consumers` serialized as a string instead of a one-element list (a PowerShell array-unrolling bug in the generator). The content was unchanged; the shape is now a list for all 86 canonical rules, and the validator rejects a scalar.

## Lab-verification registry (`lab_verification_registry`)

Each entry in the catalog records the exact question, affected sources/metrics/rules, why the documentation is insufficient, the proposed lab test, and the consequence if unresolved. Items with `blocks_production_use: true` make dependent values `lab_verification_required`, which is UNKNOWN in production conclusions.

| ID | Question (short) | Blocks production use | Consequence if unresolved |
| --- | --- | --- | --- |
| LV-01 | Unit of `DBA_HIST_RSRC_CONSUMER_GROUP.CPU_WAIT_TIME` | yes | Group-level historical Resource Manager wait unusable; instance-level (OSSTAT) remains |
| LV-02 | `DBA_HIST_RSRC_METRIC` minute-row retention | yes (source deferred) | Resource Manager onset limited to snapshot granularity |
| LV-03 | `V$OBJECT_DEPENDENCY` lists merged views; join to `V$SQL` | yes | Grade D1 unusable in production; FAM-004 detection rests on D2 |
| LV-04 | `DBA_HIST_TBSPC_SPACE_USAGE` covers TEMP | yes (deferred) | Historical TEMP occupancy from ASH lower bounds only |
| LV-05 | SQL Monitor report XML structure | yes | Report-derived plan-line actuals and TEMP upper bound unusable |
| LV-06 | Persisted-ASH per-instant completeness | no | Already treated as lower bounds; nothing becomes exact |
| LV-07 | OS-dependent `V$OSSTAT` stats on RHEL 8 / virtualization | no | Absent stats → host_busy unavailable; accuracy under virtualization a stated limitation |

## Backlog (deferred, not encoded)

| ID | Origin | Item | Linked LV |
| --- | --- | --- | --- |
| BL-01 | V32-11 | `DBA_HIST_RSRC_METRIC` minute-level history | LV-02 |
| BL-02 | V32-12 | `DBA_HIST_SYSTEM_EVENT` `resmgr:cpu quantum` totals; `DBA_HIST_COLORED_SQL` | – |
| BL-03 | V32-13 | `DBA_HIST_SQL_BIND_METADATA`; `DBA_HIST_TBSPC_SPACE_USAGE`; ORA-1652 provider | LV-04 |
| BL-04 | V32-14 | DBA guidance on AWR capture settings (never executed by OraProbe) | – |

## Not changed

- All V3.1 rules other than RM-001, RM-002, RM-004, FAM-003, TEMP-004 and FAM-004 (detection evidence only).
- All P1–P8 contracts, the stage structure and the confidence numbers.
- The 39 thresholds (IDs, units, `null` values).
- V3.1 metrics other than the seven revised for family tiers and `common_dependency_count` (dependency grades). All 180 V3.1 metric IDs are preserved; their only additions are `value_semantics` and the stated revisions.
