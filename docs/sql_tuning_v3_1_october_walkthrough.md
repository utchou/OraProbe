# Paper acceptance walkthrough — October production incident on V3.1

This is a **paper** exercise. No engine exists and no telemetry was collected. It traces how the V3.1 catalog (`knowledge/sql_tuning_catalog_v3_1.yaml`) would investigate the user-supplied October narrative (acceptance case `production_family_allocation`).

**The narrative is treated as a set of hypotheses to test, not as the answer.** No measured value below is real.

## Narrative under test (user-supplied, unverified)

A month-end / control-table rollover led to:
1. a workload of many different literal SQL_IDs;
2. which are believed to be one logical SQL family;
3. which share a dependency on `PS_C_FEED_DEF_V` despite view merging;
4. which repeatedly process about 1M rows;
5. which allocate more than about 8 GB TEMP per execution;
6. which run concurrently;
7. which together create large aggregate CPU demand;
8. which saturates Resource Manager CPU allocation;
9. which leaves about 1,159 normal sessions waiting on `resmgr:cpu quantum`.

## Investigation assumptions (demo reality)

| Item | Assumption | Consequence |
| --- | --- | --- |
| Timing | Investigation runs days after the incident (historical) | Live cursor cache, `V$TEMPSEG_USAGE`, `V$SQL_MONITOR` (≥1 min retention) and `V$RSRCMGRMETRIC_HISTORY` (~1 hour) no longer cover the window |
| Modules | Query Tuner only; OS, Database Health, Storage, RAC/Network, Jobs/Changes are not implemented | `OS-CPU`, `DB-RESOURCE`, `STORAGE-CAPACITY`, `RAC-NETWORK` requests return `unresolved_additional_evidence_required` |
| SQL parser | None | `ast` evidence is `unsupported`. Every metric needing AST is UNKNOWN. |
| Application log / change log | Not available | `executions` comes only from ASH/AWR reports. `changes` comes only from `V$RSRC_PLAN_HISTORY`. |
| Threshold profile | None (P8) | Every threshold comparison is `configuration_required`. Only literal structural comparisons (`> 0`, `> 1`) evaluate. |
| Licensing | Demo authorization recorded in `license_policy` | ASH/AWR/SQL Monitor sources are permitted; entitlement is not inferred from parameters |
| Lab trials | None | Every validation stage is `validation_pending` |

Each conclusion is shown in two columns:
- **As shipped:** no threshold profile.
- **With an approved profile:** what would change once the DBA calibrates values. No values are assumed here; "> bound" means "exceeds whatever the approved profile states".

Confidence uses CP-01 unchanged:
- base 40;
- +15 per independent supporting group, at most two (so at most 70);
- −30 per direct counter;
- −60 for a controlled disconfirmation;
- capped at **40** when the counter-search or timeline is unknown.

Scores rank candidates. They are not probabilities, and they never override the causal gates.

---

## Step 0 — Intake, capability record and measured degradation

**OBSERVATION.** The request is: database, one SQL_ID (one of the literal statements), the October incident window with timezone, and the symptom "normal sessions slow".

**DETECTION EVIDENCE.** `capability` (P7) is recorded first:
- `STATISTICS_LEVEL`: if `TYPICAL`, `V$SQL_PLAN_STATISTICS_ALL` holds no actual row counts.
- `CONTROL_MANAGEMENT_PACK_ACCESS`
- AWR `SNAP_INTERVAL`/`RETENTION`/`TOPNSQL`
- earliest ASH/AWR sample per instance
- RAC instances and startup times; a restart inside the window breaks counter deltas.
- `CPU_COUNT`, the active resource plan and the caging state now, compared with `V$RSRC_PLAN_HISTORY` for the incident window
- collector privilege mode
- the requested window

**ATTRIBUTION EVIDENCE.** `measured_degradation` gate for the requested SQL:
- `wall_deviation`: UNKNOWN (no application log; ASH durations are lower bounds and need the same estimate kind on both sides).
- `logical_read_deviation`, `frequency_deviation`, `db_time_deviation`: from `DBA_HIST_SQLSTAT` deltas against a **matched** baseline (P5 policy). That means a comparable month-end stratum, not an average weekday.

**COUNTER-EVIDENCE SEARCH.** Baseline comparability: same instances, service, resource plan and consumer group, and workload stratum. A baseline from a non-month-end day is reported as a stratum difference, not silently used.

**CONCLUSION / ROLE.**
- As shipped: the gate is `configuration_required`. The report lists each deviation's measured value, unit and window next to the missing `material_deviation` / `frequency_deviation_bound`.
- With a profile: the gate can be TRUE through frequency or DB time even though wall time is unknown.

**CONFIDENCE.** Not scored. This is a gate, not a hypothesis.

**WHAT REMAINS UNPROVEN.** End-to-end latency of the victims; whether the chosen baseline stratum is representative.

**OPTIONAL VALIDATION EVIDENCE.** Application response-time records for the window (`APP-NETWORK`).

---

## Step 1 — Multiple different literal SQL_IDs

**OBSERVATION.** Many SQL_IDs with different literal text executed in the window.

**DETECTION EVIDENCE.**
- `sql` evidence: SQL_IDs from `DBA_HIST_SQLSTAT`, plus `V$SQL` signatures only if the cursors are still cached.
- **CUR-006 detection** `family_member_count > 1` requires a *validated* family (Step 2), so it is UNKNOWN (`unsupported_capability`).
- What can be reported is a raw count of distinct SQL_IDs observed, and nothing more.

**ATTRIBUTION EVIDENCE.** CUR-006 attribution `hard_parse_rate > hard_parse_rate_bound` comes from `V$SYSSTAT` deltas, which are instance-wide, not per family. It is not evaluated while detection is UNKNOWN.

**COUNTER-EVIDENCE SEARCH.**
- **CUR-003** (child-cursor churn within one SQL_ID) is a different mechanism and is kept separate. Literal proliferation adds SQL_IDs; child churn adds children.
- The `CUR-006-normal` counter test: comparable wall latency weakens the impact claim.

**CONCLUSION / ROLE.** Observation: "N distinct SQL_IDs in window". CUR-006 is `unresolved_hypothesis`, with the family unvalidated and the threshold unconfigured. Role `unresolved`.

**CONFIDENCE.** Not scored (detection UNKNOWN).

**WHAT REMAINS UNPROVEN.**
- Whether the statements are one workload.
- Whether parsing cost matters.
- The historical cohort may be **incomplete**: `DBA_HIST_SQLSTAT` captures top SQL only, and each literal statement may individually fall below the top-N cut.

**OPTIONAL VALIDATION EVIDENCE.** None needed for detection. A parser or an application semantic-equivalence record is needed for membership.

---

## Step 2 — Potential logical SQL family

**OBSERVATION.** The statements look like variants of one query.

**DETECTION EVIDENCE.** **FAM-001** `family_member_count > 1` uses `family_members` (operator `family_group`):
- A signature-only match gives a *candidate*.
- Validation needs AST template, resolved objects, operator path and bind positions, or a supplied semantic-equivalence record.
- In the demo there is no parser and no record, so detection is UNKNOWN (`unsupported_capability`).
- `FORCE_MATCHING_SIGNATURE` is available only from cached `V$SQL`. For history, neither `DBA_HIST_SQLSTAT` nor ASH signature columns are in the V3.1 allowlist (a gap).

**ATTRIBUTION EVIDENCE.** Not applicable (FAM-001 is a derived fact).

**COUNTER-EVIDENCE SEARCH.**
- `FAM-001-semantic-split` (`family_semantic_conflicts > 0`) splits membership when resolved schemas, predicates or bind positions differ.
- Literal selectivity strata are kept as subfamilies.

**CONCLUSION / ROLE.** `candidate_cohort_only; no semantic family certainty` (`outcomes.family_unknown`). Every downstream metric whose population is `validated_family_members` is UNKNOWN: `family_cpu_share`, `group_cpu_share`, `common_path_work` and `cpu_demand_deviation` at family grain.

**CONFIDENCE.** Not scored.

**WHAT REMAINS UNPROVEN.** That the variants are semantically equivalent; that they share a cost profile, since different literals can select very different volumes.

**OPTIONAL VALIDATION EVIDENCE.** A deterministic SQL parser (future), or an application-supplied equivalence record.

> **Does not conclude: same plan hash means same family.** `family_group` explicitly says "Plan/object/module similarities only support candidate paths, never merge alone". The acceptance perturbation "SQL_IDs grouped only because they share PLAN_HASH_VALUE" expects a candidate cohort only. Equal plan hashes across SQL_IDs say nothing about predicates, literals or selectivity.

---

## Step 3 — Common `PS_C_FEED_DEF_V` dependency

**OBSERVATION.** The members appear to reference the same view, which is merged away in their plans.

**DETECTION EVIDENCE.** **FAM-004** `common_dependency_count > 1` uses `dependency_path_count`. The path runs from the query's reference, through the stored view (`DBA_DEPENDENCIES`/`DBA_VIEWS`), to the executed plan objects (`V$SQL_PLAN`/`DBA_HIST_SQL_PLAN`). The first hop needs `ast.resolved_object`, which is unsupported, so detection is UNKNOWN.

What *can* be reported is that each candidate member's executed plan touches base objects inside `PS_C_FEED_DEF_V`'s dependency closure. That is **object coincidence**, which the acceptance case says is insufficient. Because the view is merged, the plans show base tables, not the view.

**ATTRIBUTION EVIDENCE.** `common_path_work > common_path_work_bound`: row and start counts on the shared leaf operations, summed across member executions. It needs plan-line actuals (Step 4) and validated membership.

**COUNTER-EVIDENCE SEARCH.**
- `FAM-004-normal`: comparable wall latency weakens impact.
- Work concentrated outside the common path refutes "shared path is the expensive part".

**CONCLUSION / ROLE.** As shipped: "common base-object access observed (candidate)". FAM-004 is unresolved, and CE-05 (FAM-001 → FAM-004) is untested.

**CONFIDENCE.** Not scored.

**WHAT REMAINS UNPROVEN.** That the view, rather than coincidental base-table use, is the shared path; that the shared path dominates cost.

**OPTIONAL VALIDATION EVIDENCE.** A lab comparison of one member with and without the view path (result-equivalent).

---

## Step 4 — About 1M-row intermediate processing

**OBSERVATION.** Executions repeatedly push about 1M rows through some operation.

**DETECTION EVIDENCE.**
- **Actual rows per plan line (P2/P3):**
  - Live `V$SQL_PLAN_MONITOR` is gone (historical).
  - `DBA_HIST_REPORTS`/`_DETAILS` SQL Monitor reports exist only if AWR captured them; it captures the most expensive completed statements.
  - `V$SQL_PLAN_STATISTICS_ALL` only if `STATISTICS_LEVEL=ALL` or a hint, as recorded in P7.
  - Each source is recorded in `actuals_source`. `monitored_execution_share` shows how many executions have any plan-line actuals.
- **CARD-005** detection: `estimate_error_ratio > estimate_error_bound` (configuration_required) OR `zero_estimate_mismatch > 0`, which is literal and evaluates where actuals exist.
- **JOIN-001** detection: `nested_loop_operations > 0` evaluates; `inner_starts > starts_bound` is configuration_required.
- **TEMP-002** detection: `operation_spill_bytes > 0`, from plan-line workarea data in the report.

**ATTRIBUTION EVIDENCE.**
- JOIN-001 attribution `nl_buffers_deviation`.
- TEMP-002 attribution `estimate_error_ratio` AND `intermediate_row_deviation`: does *this* operation normally process this volume in the matched month-end stratum?

**COUNTER-EVIDENCE SEARCH.**
- The acceptance perturbation "Large legitimate rowset, stable cost and no allocation pressure" means a legitimate month-end volume is not a defect.
- CE-02/CE-03 counter tests weaken only their specific chain.

**CONCLUSION / ROLE.**
- Observation: "operation X produced A rows over S starts (source, execution)".
- CARD-005 may be TRUE only on the zero-estimate branch, unless a profile is present.
- No cause, no estimate defect asserted from volume alone.
- Role unresolved.

**CONFIDENCE.** Not scored (observation). JOIN-001/TEMP-002 candidates could score only once attribution is TRUE under a profile, and are then capped at 40 while the counter search is incomplete.

**WHAT REMAINS UNPROVEN.** Whether 1M rows is abnormal; whether an estimate error drove the plan choice (CE-01 needs `statistics_gain`, CE-02 needs `join_order_gain`); executions without monitor reports.

**OPTIONAL VALIDATION EVIDENCE.** Lab trials with corrected statistics or cardinality (`statistics_gain`, `join_order_gain`). Without them the result is `validation_pending`, and no finding is erased.

---

## Step 5 — More than about 8 GB TEMP per execution

**OBSERVATION.** Individual executions allocate more than about 8 GB of TEMP.

**DETECTION EVIDENCE.**
- **Per-execution TEMP (P3):** ASH `TEMP_SPACE_ALLOCATED` per sampled session, grouped to the execution key (QC plus PX sessions at the same sample), feeds `executions.temp_peak_bytes`. That makes `temp_bytes_per_execution` a **sampled lower bound** at session level.
- **TEMP-001** detection `attributed_temp_allocations > 0` needs `V$TEMPSEG_USAGE` allocation keys, which are current state only. Historically it is UNKNOWN; for a live incident it would be TRUE.
- **TEMP-003** `max_workarea_passes > 1` needs `V$SQL_WORKAREA`, which is gone if the cursor aged out, or plan-line pass data.

**ATTRIBUTION EVIDENCE.**
- **TEMP-001 attribution** `operation_spill_bytes > 0` needs plan-line workarea data: `V$SQL_PLAN_MONITOR` `WORKAREA_MAX_TEMPSEG` (P2) or the AWR report. Only this names the spilling operation.
- **JOIN-002 / SORT-001 / SORT-002** require workarea operation types.

**COUNTER-EVIDENCE SEARCH.**
- `TEMP-001-normal` (cost within tolerance).
- `temp_occupancy_deviation` against the matched baseline: large TEMP may be normal at month-end.

**CONCLUSION / ROLE.**
- Observation: "execution E allocated at least X GB TEMP (sampled lower bound, session level)".
- Spilling operation: **not named** unless plan-line evidence exists.
- Hash-join spill, multipass and insufficient PGA (PAR-004) are **not concluded**.

**CONFIDENCE.** Not scored.

**WHAT REMAINS UNPROVEN.** The operation; one-pass vs multipass; whether usage is abnormal for the stratum.

**OPTIONAL VALIDATION EVIDENCE.** A lab rerun with SQL Monitor capture, which gives a live plan-line `WORKAREA_MAX_TEMPSEG`.

> **Does not conclude: TEMP allocation alone proves which plan operation spilled.** TEMP-001 splits execution-level detection from operation-level attribution. ASH `TEMP_SPACE_ALLOCATED` is per session, and `V$TEMPSEG_USAGE` has no operation ID. The acceptance perturbation expects `attribution_unresolved` and JOIN-002/SORT-001/002 not evaluated.

---

## Step 6 — Concurrent executions

**OBSERVATION.** Several executions overlap in time.

**DETECTION EVIDENCE.** **FAM-003** detection is `concurrent_execution_count > 1` AND `concurrency_deviation > concurrency_deviation_bound`.
- The first condition is literal and evaluates. Execution intervals come from ASH reconstruction (`sampled_lower_bound`, deduplicated by QC key). Sampled intervals are shortened, so overlap is under-estimated.
- The second is configuration_required, so FAM-003 detection is UNKNOWN as shipped. The blocked-decision report shows the measured overlap.
- **FAM-006** covers cross-instance concurrency and instance skew on RAC.

**ATTRIBUTION EVIDENCE.** `peak_temp_occupancy > temp_budget_bytes` uses `simultaneous_sum` over `temp` allocation keys, which are bound only to the current `V$TEMPSEG_USAGE`. Historically it is UNKNOWN. **TEMP-004** is likewise UNKNOWN, and its `STORAGE-CAPACITY` request is unavailable.

**COUNTER-EVIDENCE SEARCH.**
- `FAM-003-normal`.
- Concurrency equal to the matched month-end baseline means no amplifier.

**CONCLUSION / ROLE.** As shipped: "at least K executions overlapped at time T (sampled)". The amplifier role (FAM-003 roles test) is **not assigned**.

**CONFIDENCE.** Not scored.

**WHAT REMAINS UNPROVEN.** Actual simultaneous TEMP occupancy; proximity to TEMP capacity. **8 GB × N is a projection, not a measured peak**: `demand_policy` says "TEMP occupancy is simultaneous sum, not sum of peaks".

**OPTIONAL VALIDATION EVIDENCE.** A live recurrence with `V$TEMPSEG_USAGE` snapshots, or Storage & Capacity module evidence.

---

## Step 7 — Aggregate CPU demand

**OBSERVATION.** The workload consumed a lot of CPU.

**DETECTION EVIDENCE.**
- **FAM-002** detection: `frequency_deviation > bound` AND `cpu_demand_deviation > material_deviation`.
- `cpu_demand_cores` = `CPU_TIME_DELTA` seconds / window seconds (`demand_policy`). The rate is never multiplied by concurrency.
- The population should be the validated family. As shipped, the value is computable per SQL_ID and summed over the cohort labelled `candidate_cohort_only`. It is undercounted when members fell outside AWR top-N.
- **ASH ON CPU samples are not consumed CPU** (`weighted_sample_share` says "scheduled-or-runnable").

**ATTRIBUTION EVIDENCE.** FAM-002 has no attribution stage (V3 semantics preserved). Resource-domain attribution happens at FAM-005 (Step 10). **EXT-001** detection `family_cpu_share > contributor_share` needs a validated family.

**COUNTER-EVIDENCE SEARCH.**
- `FAM-002-normal`: wall latency unknown, so the counter-search is unknown.
- `OS-CPU` request: other databases or processes on the host. Unavailable.

**CONCLUSION / ROLE.**
- As shipped: configuration_required, with the measured CPU-seconds and cores reported.
- With a profile and TRUE detection: `candidate_contributor`.

**CONFIDENCE.** With a profile, base 40, capped at **40** because the counter-search (OS-CPU, wall) is unknown.

**WHAT REMAINS UNPROVEN.** That this CPU came from one family; that it, rather than other host or database workloads, saturated capacity.

**OPTIONAL VALIDATION EVIDENCE.** OS & Noisy Neighbors per-database CPU attribution; complete family membership.

---

## Step 8 — Resource Manager CPU allocation pressure

**OBSERVATION.** The database was CPU-limited by Resource Manager.

**DETECTION EVIDENCE.**
- **RM-001** detection is `rm_waiter_count > 0` AND `rm_wait_share > 0` (both literal).
  - `rm_waiter_count` comes from ASH `event='resmgr:cpu quantum'` and evaluates historically.
  - `rm_wait_share` needs consumer-group CPU wait vs consumed time. `V$RSRCMGRMETRIC_HISTORY` holds about one hour, and `V$RSRC_CONSUMER_GROUP` is cumulative since plan activation, needing two captured endpoints. So it is **historical_telemetry_unavailable**, and RM-001 is UNKNOWN historically. It would be TRUE (a `symptom`) for a live incident.
- **RM-002** detection: `active_cpu_plan`, `caging_enabled` (flags), using `V$RSRC_PLAN_HISTORY` to confirm the plan in force during the window.
- **RM-003**: `group_limit_utilization` (about one hour of retention).
- **RM-006**: `resource_plan_changes > 0` from `V$RSRC_PLAN_HISTORY`.

**ATTRIBUTION EVIDENCE.** RM-002/003 attribution `rm_wait_share > rm_pressure_share` is unavailable historically. CE-11 (caging) and CE-12 (group limit) are untested.

**COUNTER-EVIDENCE SEARCH.**
- **RM-004**: host CPU contention, not caging. Needs `OS-CPU`, which is unavailable.
- **RM-006**: a plan switch, e.g. a month-end maintenance plan, changes the allocation basis.

**CONCLUSION / ROLE.**
- As shipped, historical: "sessions were sampled waiting on `resmgr:cpu quantum`". RM-001 unresolved.
- Caging vs group policy vs host saturation is **not decided**. The actual configuration decides the branch, per the acceptance case.

**CONFIDENCE.** RM-001 is a symptom (not scored). RM-002/003 candidates are capped at 40 (OS-CPU and DB-RESOURCE unresolved).

**WHAT REMAINS UNPROVEN.** Allocation saturation itself; which policy limited CPU.

**OPTIONAL VALIDATION EVIDENCE.** A historical Resource Manager metric source (not in the V3.1 allowlist; see Gaps); host CPU from the OS module.

---

## Step 9 — About 1,159 `resmgr:cpu quantum` waiters

**OBSERVATION.** About 1,159 normal sessions were waiting.

**DETECTION EVIDENCE.** `rm_waiter_count` = count of distinct `(inst_id, sid, serial#)` with `state=WAITING, event='resmgr:cpu quantum'` in the samples.
- The value is reported with its estimate kind.
- From `DBA_HIST_ACTIVE_SESS_HISTORY` it is a **lower bound of distinct sessions seen over the window**: a persisted subset that is not simultaneous.
- A figure like 1,159 taken from a point-in-time `V$SESSION` snapshot cannot be reproduced historically. If supplied, it is narrative, not collected evidence.

**ATTRIBUTION EVIDENCE.** None at this step. The count is `not=execution count`, and it assigns no resource role.

**COUNTER-EVIDENCE SEARCH.** Not applicable to a count.

**CONCLUSION / ROLE.** RM-001 roles say `wait_event_does_not_assign_resource_contribution`. The waiters are **not** contributors.

**CONFIDENCE.** Not scored.

**WHAT REMAINS UNPROVEN.** The simultaneous peak; the waiters' own workload changes.

**OPTIONAL VALIDATION EVIDENCE.** None needed.

> **Does not conclude: every `resmgr:cpu quantum` waiter caused CPU pressure.** `contract.role_policy`: "Waiting is not consumption." A contributor role requires measured consumed CPU share (`group_cpu_share`, FAM-005 detection). The acceptance perturbation expects RM-001 as a symptom only, with waiters being RM-005 victim candidates or unresolved.

---

## Step 10 — Contributor vs victim classification

**OBSERVATION.** The heavy workload appears to be the contributor; the normal sessions appear to be victims.

**DETECTION EVIDENCE.**
- **FAM-005** detection: `group_cpu_share > contributor_share`. This is the validated family's *consumed* CPU over the same consumer group's consumed CPU. It needs a validated family plus historical Resource Manager CPU, so it is UNKNOWN.
- **RM-005** detection: `victim_wait_share > rm_pressure_share`. This is the share of each victim workload's active samples on `resmgr:cpu quantum`. It is computable from ASH; the threshold is configuration_required.

**ATTRIBUTION EVIDENCE.**
- **FAM-005** attribution: `rm_wait_share > rm_pressure_share`. Then the roles:
  - `primary_contributor` when share > `contributor_share`;
  - `secondary_contributor` when share is > 0 and ≤ `contributor_share`.
- **RM-005** attribution: `victim_cpu_share ≤ victim_cpu_share_bound` (the victim's own consumed CPU is small) AND `logical_read_deviation ≤ material_deviation` (its own work is unchanged), giving role `victim`.
- **CE-13** (RM-001 → RM-005) also needs `victim_onset_order > 0`.

**COUNTER-EVIDENCE SEARCH.**
- **Victim's own buffer work rose sharply** means reconsider the victim-only role; a coexisting SQL defect is possible.
- **Bystander** requires normal matched costs and no mechanism link.
- **Per resource domain:** a workload can contribute CPU while being a TEMP victim.

**CONCLUSION / ROLE.** As shipped, historical: both roles are `unresolved`. The FAM-005 population is unvalidated and RM CPU is unavailable; RM-005 thresholds are unconfigured.

With a profile, a live incident and a validated family:
- FAM-005 → `candidate_contributor` / `primary_contributor`.
- RM-005 → `victim`.
- Still not `supported_cause`.

**CONFIDENCE.** FAM-005 with a profile:
- 40 base;
- +15 if an independent group is TRUE, e.g. temporal order;
- capped at **40** because `OS-CPU` and `DB-RESOURCE` are unavailable, leaving the counter-search incomplete.

**WHAT REMAINS UNPROVEN.** That the family's CPU, rather than other groups, databases or host load, created the allocation wait.

**OPTIONAL VALIDATION EVIDENCE.** A controlled comparison: a month-end with the family's concurrency limited, or a peer database without the family.

---

## Step 11 — Temporal rollover / trigger chain

**OBSERVATION.** The rollover happened first, then demand, then TEMP/CPU pressure, then victims.

**DETECTION EVIDENCE.**
- **TIME-001** detection: `frequency_deviation > frequency_deviation_bound` (configuration_required).
- **TIME-002** detection: `cpu_demand_deviation > material_deviation` (configuration_required).

**ATTRIBUTION EVIDENCE.**
- **TIME-001** attribution: `onset_order > 0`. It needs an **independent change record** (`changes`: an external `change_log` or `V$RSRC_PLAN_HISTORY`) plus a pre-change baseline. A month-end/control-table rollover is an application event, and no Jobs/Changes module or change log exists in the demo, so it is UNKNOWN. The `trigger` role (roles test `onset_order > 0`) **cannot be assigned**, and CE-06 is untested.
- **TIME-002** attribution: `rm_onset_order > 0` AND `victim_onset_order > 0`. It needs a Resource Manager time series, unavailable historically.
- **Onset intervals** are widened by clock error and ASH/AWR sample spacing. An interval straddling zero is UNKNOWN.

**COUNTER-EVIDENCE SEARCH.**
- `TIME-001-reversed` (`onset_order < 0`): pressure before the rollover weakens the trigger.
- `TIME-002-reversed`.
- The acceptance perturbation "Resource pressure precedes rollover" means investigate an alternative upstream event.

**CONCLUSION / ROLE.** As shipped: the chain is untested. Even with full evidence, TIME-001/002 are `derived_fact` (compatible order). Order alone is never `supported_cause`.

**CONFIDENCE.** Capped at 40: an unknown timeline caps every dependent candidate.

**WHAT REMAINS UNPROVEN.**
- That the rollover occurred in the window. It is an independently recorded change, not narrative.
- That it changed this workload's demand: CE-06 needs `frequency_deviation` after onset.
- A comparable control, e.g. a previous month-end without the rollover.

**OPTIONAL VALIDATION EVIDENCE.** Application/scheduler change records; a controlled replay.

> **Does not conclude: temporal overlap proves causation.** TIME rules are `derived_fact`. `supported_cause` additionally requires `mechanism_link`, `counter_search_complete` and `comparable_control`. The acceptance perturbation expects compatible order with the trigger role and `supported_cause` blocked by those gates. The same applies to EXT-002 RMAN overlap, which stops at observation without `device_latency_deviation` attribution.

---

## Chain status summary (as shipped, historical, demo)

| Edge | Link | Status | Blocking reason |
| --- | --- | --- | --- |
| CE-06 | TIME-001 → FAM-002 | untested | no change record; thresholds unconfigured |
| CE-05 | FAM-001 → FAM-004 | untested | no parser; family unvalidated |
| CE-02 / CE-03 / CE-04 | rows/estimates → join / TEMP / multipass | partially evaluable where AWR SQL Monitor reports exist | thresholds; executions without monitor reports |
| CE-07 | FAM-002 → FAM-003 | untested | thresholds |
| CE-08 | FAM-003 → TEMP-004 | untested | no historical simultaneous TEMP occupancy |
| CE-09 | FAM-004 → FAM-005 | untested | family unvalidated; historical Resource Manager CPU unavailable |
| CE-10 / CE-11 / CE-12 | contributor / caging / group limit → RM-001 | untested | historical `rm_wait_share` unavailable |
| CE-13 | RM-001 → RM-005 | untested | Resource Manager time series unavailable |

**Expected report outcome:**
- **Not healthy:** HEALTH-001/002 require a comparable baseline and coverage; the result is `insufficient_evidence` for the health statements.
- **Not "no evidence":** observations exist.

The report lists:
- **Observations:** distinct SQL_IDs; a candidate cohort; common base-object access; plan-line rows where reports exist; sampled per-execution TEMP lower bounds; sampled overlap; cohort CPU-seconds; distinct `resmgr:cpu quantum` waiters.
- **Every blocked decision** with its measured value, unit, window and missing threshold (P8).
- **Every unavailable module request**, and every capability gap with its reason (P7).
- **No `supported_cause`. No primary contributor. No trigger.**
- **Next tests:**
  1. family equivalence (parser or application record);
  2. historical Resource Manager and TEMP evidence;
  3. OS-CPU;
  4. the change record;
  5. threshold calibration.

That is the correct and honest result for this evidence set. The narrative stays a **plausible, untested chain**, neither confirmed nor rejected.

**A live recurrence** with an approved profile, OS/DB-Resource modules and family validation could reach ranked candidates with contributor/victim roles.

**`supported_cause`** additionally needs `comparable_control`, either from a matched month-end baseline or from validation.

## Explicit "would NOT conclude" checks

| Must not conclude | V3.1 mechanism preventing it |
| --- | --- |
| Every `resmgr:cpu quantum` waiter caused CPU pressure | RM-001 is a `symptom` with role `wait_event_does_not_assign_resource_contribution`; `role_policy` says "Waiting is not consumption"; contributor roles need measured consumed-CPU share (FAM-005); waiters default to RM-005 victim candidates or unresolved |
| Same plan hash means same SQL family | `family_group`: plan/object similarity "never merge[s] alone"; FAM-001 needs validated membership; acceptance perturbation |
| TEMP allocation alone proves which plan operation spilled | TEMP-001 detection (execution) vs attribution (`operation_spill_bytes` from plan-line workarea); ASH TEMP is per session; `V$TEMPSEG_USAGE` has no operation ID; JOIN-002/SORT-00x require workarea operation types |
| Temporal overlap proves causation | TIME rules are `derived_fact`; onset intervals straddling zero are UNKNOWN; `supported_cause` requires all five causal gates; EXT-002 overlap stops at observation |
| Missing evidence means healthy | HEALTH-001/002 require `coverage_ratio ≥ healthy_coverage` and `comparable_baseline_count > 0`; `absent` requires an adequate negative search; missing data gives `insufficient_evidence` / `historical_telemetry_unavailable` |
| No database-side degradation proves the application/network is responsible | HEALTH-002 fixed text says "end-to-end … was not evaluated"; withhold list forbids naming another layer; role `unresolved`; raises `APP-NETWORK` |
