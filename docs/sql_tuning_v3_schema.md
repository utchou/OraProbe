# V3 deterministic knowledge contract

## Scope and serialization

The versioned V3 draft, `knowledge/sql_tuning_catalog_v3.yaml`, is a YAML 1.2 document serialized in the JSON subset. This keeps typed comparisons readable and allows offline parsing/validation with standard PowerShell or Python libraries, without a YAML runtime dependency. Do not use `eval`, arbitrary expressions, YAML tags or dynamically generated database queries. V2 remains byte-for-byte unchanged in `knowledge/sql_tuning_catalog.yaml`; no separate V2 archive was created. It supplies preserved engineering explanations. V3 proposes the decision and source-licensing contracts and remains a draft pending semantic review.

## Major fields

| Field | Future deterministic use |
| --- | --- |
| taxonomy.domains | Route hypotheses and enforce domain references. |
| sources | Audited Oracle/API/external names, columns, units, granularity, feature/pack gates, limitations and fallback capabilities. |
| evidence | Typed normalized observations, source-column bindings and normalization requirements. |
| metrics | Named arithmetic/aggregation recipes with evidence inputs, unit, grouping and null/zero policy. |
| thresholds | Operator operand IDs, policy type, units and configuration requirements. No undocumented universal cutoffs. |
| rules | Stable ID/name/domain, archived explanation pointer, hypothesis, required/optional evidence, metric IDs, decision trees, recommendation, relationships and version. |
| decision | All/any/not trees over typed `evidence`, `metric`, `threshold`, or `literal` operands. Metric filters additionally allow row `field` operands. |
| counter_tests | Comparisons which weaken/support an alternative; missing counter-evidence remains unknown. |
| confidence_policy | Explainable support/counter weights, independence groups, missing-evidence caps and cause gates; scores are ranking weights, not calibrated probabilities. |
| causal_edges | Candidate mechanism, matching scope/window, temporal and supporting tests; acyclic explanatory graph. Reinforcement can be symmetric without creating causal loops. |
| roles | Explicit conditions for contributor, amplifier, victim and trigger; unresolved is default. |
| recommendation | Evidence references, next test, expected result, safety/rollback, validation and actions withheld pending evidence. |
| cross_module_requests | Owner capability, request keys, expected evidence and unavailable outcome. |
| outcomes | Healthy/evidence-completeness and unresolved contracts. |
| acceptance_cases | Evidence-to-metric/rule mappings and negative perturbations for later engine tests. |

## Evidence envelope and granularity

Every normalized observation includes value, unit, status, source, source_row_key, collected_at UTC, start/end UTC, original timezone, clock_error_ms, DBID/database, CON_ID, INST_ID, startup epoch, host, topology ID, session SID/SERIAL#, SQL_ID/child/plan and execution identity when available. Record license/capability/collection status separately: observed, absent, not_collected, unavailable, unlicensed, unsupported, incomplete, reset, incomparable. `absent` means an adequately collected search returned no matching evidence; it does not mean NULL.

Execution key: DBID/CON_ID/QCINST_ID/QCSID/QC serial if known/SQL_ID/SQL_EXEC_START/SQL_EXEC_ID. SQL_EXEC_ID alone is insufficient. Row-source key adds child cursor, plan hash, operation ID and instance. Associate workers to the coordinator, count executions once, but sum actual worker resource consumption once. Session IDs can be reused; require serial and timestamp. SQL-family identity is versioned with member IDs and grouping rationale.

All windows are half-open. Normalize units before calculation. Cumulative counter deltas require matching entity/startup/cursor incarnation, monotonic counters and two timestamps; eviction/reload/restart makes the delta unknown. In-flight work and partially fetched executions can bias EXECUTIONS denominators. AWR aggregates cannot be split into arbitrary subwindows; retain snapshot bounds and coverage. Last-execution statistics are not historical incident evidence without captured association.

## Expression and metric semantics

Comparisons: eq/ne/gt/ge/lt/le/in. Boolean nodes: all/any/not. Evidence operands refer to evidence IDs; metrics refer to recipe IDs; thresholds refer to policy IDs; literals are typed values. Evidence/metric unavailable yields UNKNOWN. Kleene logic: FALSE dominates all, TRUE dominates any, NOT UNKNOWN stays UNKNOWN. Required evidence, comparability and licensing are prerequisites even if a boolean subtree could short-circuit.

Metric recipes use an allowlisted operator and named inputs/parameters, never executable text. Operators include `delta`, `ratio`, `sum`, `rate`, `max`, `count_distinct`, `normalized_row_error`, `overlap_count`, `weighted_sample_share`, `baseline_ratio`, and `onset_lag`; the catalog's `operators` object contains the complete list. Each recipe records group_by and quality constraints. Zero denominator/null is UNKNOWN, except documented zero-row estimate categories; never insert an epsilon silently.

E-Rows is per row-source start. Compare A-Rows/Starts to E-Rows for the same execution/operation and resolved adaptive branch. For E=0/A>0 flag zero-estimate mismatch separately; E=A=0 is no observed mismatch. Inclusive row-source elapsed/buffers cannot be added through parents and children to derive exclusive cost. SQL Monitor operation activity is sampled attribution, not exact additive elapsed time.

Policy thresholds default to null unless a definition supplies a semantic boundary (e.g. >0 allocated bytes or >1 pass). Null configuration means unresolved/configuration required. Baselines must match bind/selectivity, data volume, fetch completion, plan context, hardware/caging/group/service/instance and concurrency; differences must be reported rather than silently averaged. Ratio policies include minimum baseline magnitude and minimum sample count. Threshold profiles are versioned per workload and must be calibrated in the lab.

## Hypotheses, scoring and recommendations

Observation rules describe resource profile/spill without declaring defects. Optimization opportunities require an equivalent controlled comparison before a causal conclusion. Candidate cause requires measured degradation, mechanism evidence, compatible temporal order, searched counter-evidence and meaningful comparisons. Trigger status additionally requires independently recorded change and tested linkage. Otherwise role/cause is unresolved.

Support weights are added once per independent evidence group, counter weights subtracted once, clipped to [0,100]. Base support 40, each independent corroboration +15 (maximum two), direct counter -30, controlled disconfirmation -60. Unknown required evidence: not evaluated. Unknown counter search, indirect family membership or missing timeline caps confidence at 40. Scores >=70 may rank strongly but cannot override cause gates. Role classification is per workload/resource domain, so one family can contribute CPU while being a storage victim. Compatible contributors are not globally contradictory.

Recommendations bind evidence IDs/values and operation/member identity to a next test. A test is a proposal; collection is predefined read-only. Lab SQL executions, statistics, hints, indexes, Resource Manager changes, service relocation and backup rescheduling are never automatic production actions. Record expected result, result-equivalence checks, rollback and representative workload validation before proposing remediation.

## Validation boundary

The validator checks serialization, required schema fields, IDs, selected types, expression operands, source columns against the reviewed allowlist, licensing gates, aliases, dependency/causal cycles, undefined references, duplicate decision paths, V2 baseline integrity and acceptance-mapping references. It does not evaluate diagnostic expressions, prove semantic coverage, validate every recipe parameter, or verify Oracle views on a live database. Later work must add validator regression tests, semantic review, fixture evaluation and repeated Oracle 19c lab tests; knowledge completeness is not measured by rule count.
