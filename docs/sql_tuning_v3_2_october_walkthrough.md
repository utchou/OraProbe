# Paper acceptance walkthrough — October incident on V3.2

This is a **paper** exercise against `knowledge/sql_tuning_catalog_v3_2.yaml`. It repeats the [V3.1 walkthrough](sql_tuning_v3_1_october_walkthrough.md) and shows only what changes. **The user-supplied narrative is still treated as an untested hypothesis.** No measured value below is real.

## Assumptions

| Item | V3.1 walkthrough | V3.2 walkthrough |
| --- | --- | --- |
| Incident age | Historical (days old) | Same |
| Modules | Query Tuner only | Same, but Resource Manager knowledge (owner `database_health`) is consumed directly through the shared engine and the `resource_mgr` provider (V32-04) |
| Normalizer | None | **Specified, assumed implemented as designed.** If it is not built, every member is capped at F1. |
| Threshold profile | None | Same. Two columns again: **as shipped** (no profile) and **with an approved profile** (values not assumed) |
| AWR settings | Not recorded | `TOPNSQL`, interval and retention recorded in `capability`. **Default retention is 8 days, so the previous month-end is normally no longer in AWR.** |
| Licensing | Demo authorization | Same; every new source is Diagnostics Pack |
| OS / Storage / RAC / change telemetry | None | None; `oracle_host` gives partial OS-CPU only |

---

## 1–2. Literal SQL_IDs and the logical family — **improved**

| | V3.1 | V3.2 |
| --- | --- | --- |
| Signature evidence (historical) | Not allowlisted | `DBA_HIST_SQLSTAT.FORCE_MATCHING_SIGNATURE` for captured SQL; ASH `FORCE_MATCHING_SIGNATURE` for sampled SQL (V32-05) |
| Text for templates | None | `DBA_HIST_SQLTEXT` for captured SQL (complete CLOB) |
| Family tiering | UNKNOWN (no parser) | Tier per member (V32-01/02) |

**OBSERVATION.** Many literal SQL_IDs appear in the window.

**DETECTION EVIDENCE.**
- **F1 (candidate):** members sharing a non-zero FMS in ASH or SQLSTAT.
  - FMS does not transform statements mixing literals and binds, so such members can only join through the loose template.
- **F2 (strongly supported):** members whose captured full text gives the same strict template, with:
  - the same `PARSING_SCHEMA_NAME` and `COMMAND_TYPE`;
  - the same literal-type vector and identical risk-literal values;
  - at least one corroboration (same FMS, or same `MODULE`/`ACTION`).
- **FAM-001 detection** `family_member_count > 1` is a literal comparison. It can be **TRUE as shipped**, at F2, for the captured-text members.

**ATTRIBUTION EVIDENCE.** Not applicable to FAM-001. CUR-006 (which shares the FAM-001 detection) needs `hard_parse_rate > hard_parse_rate_bound`, which is configuration-required.

**COUNTER-EVIDENCE SEARCH.**
- The split rules: different schema, statement type, literal types or risk-literal values.
- Plan hash neither merges nor splits.

**CONCLUSION / ROLE.**
- `derived_fact`: "a strongly supported family of N captured members".
- ASH-only members are listed as `unverified_member` (F1).
- **No application equivalence is claimed (that would be F3).**

**CONFIDENCE.** Not scored (derived fact).

**WHAT REMAINS UNPROVEN.**
- Application-level equivalence.
- Completeness of membership: uncaptured members are `not_captured`, never "did not run".

**OPTIONAL VALIDATION EVIDENCE.** An application or DBA confirmation record raises the family to F3. That is needed only for "one fix covers all members".

## 3. `PS_C_FEED_DEF_V` — **improved at detection (correction: proposal V32-10)**

- **What's new:** the normalizer's `identifier_set` can show that every F2 member's text contains the identifier token `PS_C_FEED_DEF_V`. This is reported as a lexical observation.
- **Dependency grades (added by the V3.2 correction):**
  - D2 resolves the token for each captured-text member under `PARSING_SCHEMA_NAME` through `DBA_OBJECTS`/`DBA_SYNONYMS` to one `OBJECT_ID`.
  - The member's AWR plan (`DBA_HIST_SQL_PLAN.OBJECT#`) must not contradict the view's closure.
  - D1 (`V$OBJECT_DEPENDENCY`) is days-old evidence. Cursors have usually aged out, and it is LV-03-gated anyway, so it doesn't count.
- **FAM-004 detection:** **can be TRUE as shipped** (observation: two or more F2 members with D2 links to the same view; the count is a lower bound). It stays UNKNOWN if `LAST_DDL_TIME` of the view or a view on its closure is after the incident start (`definition_may_have_changed`), or if the normalizer is not built.
- **Unchanged:** FAM-004 attribution (`common_path_work`) needs plan-line actuals (live monitor gone; report LV-05), so it stays **UNKNOWN**. Members without captured text or plan are ungraded (`not_captured`).
- **Conclusion:** the common view dependency becomes a graded observation. The shared path being expensive, family equivalence, identical work beneath the view, and causation are **not** established.

## 4. About 1M-row processing — **unchanged**

Plan-line actuals still depend on live SQL Monitor (gone for a past incident) or AWR SQL Monitor reports, which stay `lab_verification_required` (LV-05). CARD-005, JOIN-001 and TEMP-002 remain **UNKNOWN** historically. This is the largest remaining gap for the SQL-level mechanism.

## 5. More than 8 GB TEMP per execution — **improved (bounds)**

| | V3.1 | V3.2 |
| --- | --- | --- |
| Per-execution TEMP | Sampled lower bound (concept) | `ash_execution_temp_peak_lb`: QC + PX sessions summed per instant, as `lower_bound` |
| Upper bound | – | `report_execution_temp_ub` is defined but **LV-05**, not usable in production |
| Spilling operation | Unnamed | Unnamed (needs plan-line evidence) |

**CONCLUSION.** The report can say "execution E allocated **at least** X GB TEMP (sampled, session level)". "≥ 8 GB" can be shown if the lower bound reaches it. It is **never reported as the exact peak**, and the operation is not named.

## 6. Concurrent executions and simultaneous TEMP — **improved (bounds)**

**DETECTION EVIDENCE.** FAM-003 detection:
- First condition: `ANY(concurrent_execution_count > 1, ash_concurrent_executions_lb > 1)`. This is literal, so it can be **TRUE as shipped** from a lower bound.
- Second condition: `concurrency_deviation > bound`, which is configuration-required. FAM-003 detection therefore stays UNKNOWN as shipped.

**ATTRIBUTION EVIDENCE.** FAM-003 attribution and TEMP-004 detection use `ANY(peak_temp_occupancy > temp_budget_bytes, ash_cluster_temp_occupancy_lb > temp_budget_bytes)`.
- As shipped: configuration-required, and the measured lower bound is reported.
- With a profile: **TRUE if the lower bound exceeds the budget**. It is never FALSE from a lower bound, because "within budget" is unprovable.

**WHAT REMAINS UNPROVEN.** The exact peak occupancy and the exact concurrency peak (bound policy). 8 GB × N is still a projection.

## 7. Aggregate CPU demand — **improved (honest coverage)**

**DETECTION EVIDENCE.**
- Family CPU = sum of `CPU_TIME_DELTA` over F2 members **with SQLSTAT rows**, giving a **lower bound** (V32-07).
- Reported alongside it:
  - `family_ash_member_count` (lower bound);
  - `family_sqlstat_capture_share`: the sampled estimate of how much family activity SQLSTAT covers;
  - `family_text_capture_share`.
- `sql_interval_db_time_rate`: average database-time load per interval.

**CONCLUSION.**
- FAM-002 / EXT-001 `gt` comparisons can become TRUE with a profile when the lower bound exceeds the bound.
- If the lower bound is below the bound, the result is **UNKNOWN, never "small"**.

**WHAT REMAINS UNPROVEN.** CPU of uncaptured members; per-execution CPU.

## 8. Resource Manager allocation pressure — **substantially improved**

| | V3.1 | V3.2 |
| --- | --- | --- |
| Plan and caging during incident | Current state only | `DBA_HIST_RSRC_PLAN` per instance (`CPU_MANAGED`, `INSTANCE_CAGING`, start/end) + `DBA_HIST_PARAMETER.cpu_count` |
| Allocation wait | Unavailable (~1 h retention) | **Instance level:** `rm_instance_wait_share_interval` from documented `RSRC_MGR_CPU_WAIT_TIME`. **Group level:** LV-01, not usable. |
| Caged capacity used | – | `caged_capacity_utilization` = group consumed CPU (documented ms) / (interval × cpu_count) |

**DETECTION EVIDENCE.**
- **RM-001** `rm_waiter_count > 0` (ASH) AND `ANY(group wait > 0, instance wait > 0)`: all literal, so it **can be TRUE as shipped** historically (symptom).
- **RM-002** `active_cpu_plan > 0` AND `caging_enabled > 0`: literal flags from `DBA_HIST_RSRC_PLAN`, so it **can be TRUE as shipped**.

**ATTRIBUTION EVIDENCE.** RM-002 attribution is `instance wait share > rm_pressure_share`, which is configuration-required as shipped. The supporting test is `caged_capacity_utilization > allocation_utilization_bound`.

**COUNTER-EVIDENCE SEARCH.**
- `RM-002-host-saturated` and `RM-004-host-spare` (Step 8a below).
- RM-006 plan change from plan history.
- RM-003 group policy: its attribution needs group-level wait (LV-01), so it stays UNKNOWN.

**CONCLUSION / ROLE.**
- **As shipped:** "Resource Manager CPU waiting observed (symptom); instance caging was active with CPU_COUNT=n; caged capacity utilization = x (interval average)". The pressure decision is configuration-required.
- **With a profile:** RM-002 can become `candidate_contributor` (caging constraint) **at interval granularity**.

**CONFIDENCE (with profile).** 40 base, +15 for capacity utilization, then **capped at 40**: OS-CPU fulfilment is partial, so `counter_search_complete` is not TRUE.

**WHAT REMAINS UNPROVEN.** Sub-interval peaks; which consumer group waited (LV-01).

### 8a. Host CPU vs caging differentiation — **new**

`oracle_host` (`DBA_HIST_OSSTAT`) gives `host_busy` as an interval average, plus `LOAD` against `NUM_CPUS` (point sample). Statistic availability on RHEL 8 is LV-07.

With a profile:
- **Spare host CPU while Resource Manager wait is high** supports caging/group policy: `RM-004-host-spare` weakens RM-004.
- **A busy host** weakens "caging is the sole constraint" (`RM-002-host-saturated`). Both may coexist.

**Never concluded:** "no noisy neighbor". Host CPU is host-wide and interval-averaged, with no per-database attribution (`host_cpu_policy`).

## 9. About 1,159 waiters — **unchanged in kind**

Still a lower bound of distinct sessions seen waiting in persisted ASH (LV-06 cannot upgrade it). The instant figure remains unreproducible. Waiters are still not contributors.

## 10. Contributor vs victim — **partially improved**

**FAM-005 (contributor).**
- **Detection:** `group_cpu_share > contributor_share`.
  - The numerator is F2 family CPU, a lower bound, attributed to a group only if `family_observed_group_mapping` shows a single consumer group in ASH.
  - The denominator is the group's documented consumed CPU.
  - The share is therefore a **lower bound**, and with a profile detection can be TRUE.
- **Attribution:** `rm_wait_share > rm_pressure_share` at **group** level needs LV-01, so it is **lab_verification_required**.
- **Result:** FAM-005 stops at observation ("the family consumed at least X% of its group's CPU"), with attribution unresolved. **No primary contributor role.**

**RM-005 (victim).**
- **Detection:** `victim_wait_share` from ASH (accepted as a sampled estimate) > `rm_pressure_share`, with a profile.
- **Attribution:** `victim_cpu_share ≤ bound` AND `logical_read_deviation ≤ material`. Both are `le` comparisons:
  - For an **individual captured victim SQL_ID**, its own SQLSTAT row is exact for that SQL_ID, so the victim role is testable when its baseline is also retained.
  - For the **victim population** (~1,159 sessions), the aggregate is a lower bound, so `le` gives **UNKNOWN**. A population-level victim claim is not provable.

**CONCLUSION.** At best, victim roles for specific captured SQL_IDs, and a contributor observation without a role.

## 11. Temporal chain — **marginal improvement**

- **TIME-002** onsets can be compared at **snapshot granularity**: family CPU per interval vs instance Resource Manager wait per interval. With hourly snapshots, onsets in the same interval straddle zero and give UNKNOWN. Minute-level history is deferred (BL-01 / LV-02).
- **TIME-001** (the rollover trigger) is **still untestable**: there is no independent change record.

---

## What improved, side by side

| Area | V3.1 result | V3.2 result |
| --- | --- | --- |
| SQL-family candidate / strong support | UNKNOWN (no parser) | F1 from historical signatures; **F2 for captured-text members (FAM-001 TRUE as shipped)**; F3 still needs external confirmation |
| Historical Resource Manager evidence | RM-001 UNKNOWN; caging unknown | **RM-001 symptom and RM-002 caging detection TRUE as shipped**; instance-level wait share and caged utilization measured; group-level wait gated by LV-01 |
| Family coverage uncertainty | Implicit | Explicit lower bounds plus capture shares; uncaptured = `not_captured`; no "small family" or bystander from incomplete coverage |
| Historical TEMP / concurrency | Concept-level lower bounds | Defined lower-bound metrics; concurrency `> 1` TRUE as shipped; occupancy can be proven over budget, never within it; upper bound gated (LV-05) |
| Host CPU / caging differentiation | Not possible (OS module absent) | Interval-level differentiation with explicit counter-tests; noisy neighbors never eliminated |
| Common `PS_C_FEED_DEF_V` dependency | UNKNOWN | **FAM-004 detection TRUE as shipped at grade D2** (observation; lower-bound count), unless a later DDL caps links; attribution still UNKNOWN |
| Contributor / victim | Unresolved | Contributor: **observation only** (LV-01 blocks attribution). Victim: **testable per captured SQL_ID**, not for the population |

## Expected outcome

- **As shipped (no profile):** the report has more TRUE observations, all labelled with their evidence quality:
  - F2 family;
  - Resource Manager wait symptom;
  - caging active;
  - concurrency > 1;
  - TEMP and CPU lower bounds;
  - capture shares;
  - host busy level.

  Every threshold decision is listed as blocked, with measured values.
- **With an approved profile:** ranked candidates become possible (RM-002 caging constraint, FAM-002/003 demand and concurrency, TEMP-004 over budget), each **capped at 40**.
- **`supported_cause` remains blocked** by:
  - `counter_search_complete`: OS-CPU partial; storage and RAC absent;
  - `comparable_control`: with default 8-day AWR retention, no matched prior month-end exists unless retention was extended or an AWR baseline was kept;
  - `mechanism_link` for FAM-005: LV-01;
  - `compatible_temporal_order`: hourly granularity.
- **The trigger remains unprovable.**

**Final classification: plausible, partially supported, unresolved.** V3.2 makes more of the chain *testable*, and tells the DBA precisely which evidence (LV-01, an extended AWR retention or baseline, OS telemetry, a change record) would move it further.

## Explicit "would NOT conclude" checks (additions to V3.1)

| Must not conclude | V3.2 mechanism |
| --- | --- |
| A member missing from AWR did not run | `capture_bias_policy`: status `not_captured`, never `absent` |
| The family is small / not a contributor because captured CPU is low | `family_coverage_policy` + `bound_policy`: a lower bound cannot satisfy `le`; no bystander from incomplete coverage |
| Normalized text proves the statements are the same application query | `normalizer_policy` constraints; F3 needs external confirmation |
| ASH TEMP is the execution's exact peak | `historical_temp_concurrency_policy`; lower bound only |
| Spare host CPU proves no noisy neighbor | `host_cpu_policy` limits; `RM-004-host-spare` only weakens host contention |
| Group-level Resource Manager wait from `DBA_HIST_RSRC_CONSUMER_GROUP` is usable | LV-01 `lab_verification_required` → UNKNOWN in production |
| Members referencing `PS_C_FEED_DEF_V` form a family, did identical work, or the view caused the degradation | `dependency_evidence_policy.cannot_establish`; `family_tier_effect: none`; FAM-004 capped at `derived_fact` |
