# V2 review and V3 gap analysis

Reviewed 2026-10-03 against all repository requirements, both management prompts, the discussion record, and all seven V2 knowledge documents. V2 is an approved knowledge foundation, not an implemented detector. The current request authorizes specification changes and a catalog validator, not engine implementation. Local Excel inventory, timezone-qualified investigations, read-only predefined capabilities, demo licensing authorization, offline runtime, and incremental module development remain requirements.

## Strengths

All 54 IDs provide useful engineering context: problem explanations, evidence, false positives, next tests, safety, and relationships. The 12 domains cover access, estimates, joins, transformations, cursors, partitions, predicates, workload shape and external contributors. That material remains unchanged in `knowledge/sql_tuning_catalog.yaml` (V2). The versioned `knowledge/sql_tuning_catalog_v3.yaml` retains every ID, with explicit aliases for exact overlaps; the preserved V2 explanations remain review material rather than executable truth.

## Findings from the actual baseline

| Gap | V2 location | Consequence and V3 correction |
| --- | --- | --- |
| Qualitative predicates and confidence | Every active rule | Replace decision paths with typed observations, calculated metrics, structured comparisons and explicit unknown propagation; retain explanations separately. |
| Column datatype source wrong | AP-005, PRED-004 use DBA_TAB_COL_STATISTICS | Use DBA_TAB_COLUMNS.DATA_TYPE and bind metadata; determine conversion direction from executed plan predicates. Conversion of a value alone does not prove index obstruction. |
| Bind types/values unavailable from listed views | AP-005, CUR-001, PRED-005 | Add V$SQL_BIND_CAPTURE and application bind records. Capture is incomplete and not execution-specific; missing values cannot eliminate bind hypotheses. |
| TEMP allocated to SQL but not to operation | JOIN-002, SORT-001/002, PAR-004 | Add V$SQL_WORKAREA_ACTIVE/WORKAREA and actual row-source statistics. TEMPSEG_USAGE alone cannot prove hash versus sort spill or historical peak. |
| Statistics stale flag treated as cause | CARD-001 | Require estimate error and comparable cost impact. DBA_TAB_MODIFICATIONS adds DML context, not proof of stale estimates. Stats changes carry plan-change risk. |
| Column correlation asserted without joint distribution | CARD-004 | Add DBA_STAT_EXTENSIONS and supplied joint selectivity measurements. Multiple predicates alone do not demonstrate dependence. |
| Adaptive cursor sharing evidence incomplete | CUR-002 lists V$SQL twice | Add CS_SELECTIVITY/CS_STATISTICS/CS_HISTOGRAM and IS_BIND_SENSITIVE/IS_BIND_AWARE. Multiple children can be appropriate adaptation. |
| Child count and literal proliferation confused | CUR-003 and missing parsing rules | Count distinct SQL_IDs separately from CHILD_NUMBER; add hard/soft parse, invalidation and library cache evidence. SQL PARSE_CALLS is not a hard-parse counter. |
| Generic optional license values | ASH, DBA_HIST_SQL_PLAN/SQLSTAT | Explicit Diagnostics Pack; SQL Monitor requires Tuning plus Diagnostics. Source presence or parameter settings are not entitlement. |
| SPM unnecessarily marked licensed/optional | CUR-005 DBA_SQL_PLAN_BASELINES | SPM metadata is base functionality with offering restrictions; AWR-based loading and automatic features have separate gates. No baseline does not itself diagnose regression. |
| Exact duplicates | AP-004/PRED-003, AP-005/PRED-004 | AP IDs become aliases to canonical predicate rules. Preserve ID lookup and all archived knowledge; emit one finding per canonical rule/scope/window. |
| Skew overlap | CARD-003/DATA-004 and CARD-002 | Keep distribution mismatch, workload value bias and missing histogram as separate observations; group findings by mechanism instead of triple-counting confidence. |
| Invalid contradiction logic | CARD-001/005 versus EXT-001, PAR-001 versus EXT-001, JOIN-001 versus JOIN-002 | CPU demand, external pressure and plan defects can coexist. Use evidence-based competition within the same scope, not rule-ID exclusion. |
| Undefined documentation reference | correlations.md references AP-007 | Remove stale reference in current navigation; V3 relationships reference defined IDs only. |
| Unsafe causal wording | EXT-002/003/004/005 statements exclude SQL defect | Rewrite conclusions as candidate contributors/symptoms until mechanism and comparable evidence establish attribution. Backup overlap is insufficient. |
| Healthy conflated with missing/external evidence | catalog.md section 7 | Separate healthy, unresolved, unavailable history and insufficient coverage. A healthy statement requires baseline, adequate coverage and all tracked cost/latency bounds. |
| No SQL-family model | All V2 | First-class FAM domain, signatures plus parser/dependency evidence, reversible grouping and exclusion criteria. Shared plan hash or object is not semantic identity. |
| No Resource Manager model | EXT/PAR | First-class RM domain: active plan, caging, group limits/shares, consumed CPU versus allocation wait, contribution versus victim. |
| No temporal model | All V2 | TIME domain with onset intervals, clock uncertainty, overlap and mechanism-qualified causal edges. |
| RAC predominantly instance-local | EXT-004 and all V$ mappings | GV$ capability, INST_ID/DBID/CON_ID/startup keys, coordinator/worker attribution and instance-comparable baselines. |
| No cross-module contract | External prose only | Named requests preserve topology, hypothesis, incident and provenance; unavailable modules leave hypotheses unresolved. |

## Coverage extensions and boundaries

Add family demand/concurrency/common dependency, TEMP operation/materialization/multipass, Resource Manager, parsing/invalidation, RAC distribution, temporal testing and healthy coverage. Add targeted rules for commit/redo, hot blocks, read consistency, client/fetch effects and unrecognized waits to avoid overfitting the production case. Broader SQL semantics and index design remain optimization opportunities unless a controlled equivalent comparison exists.

The formula in the request is interpreted dimensionally: CPU demand is CPU seconds per execution times executions per second; simultaneous TEMP occupancy is the sum of bytes allocated by overlapping executions. Multiplying an already measured execution rate by concurrency double-counts demand. Concurrency can alter per-execution cost, so compare equivalent concurrency strata or derive an explicit saturation relationship. Do not infer 160 GB as a measured peak merely from 8 GB times 20 executions.

The October case is supplied acceptance evidence, not independently verified telemetry. Exact operation, rollover causation, memory shortage and infrastructure health are unknown until collected. Slow RMAN remains an external module case; no SQL detector claims to diagnose a restore.

See [schema](sql_tuning_v3_schema.md), [V3 catalog](../knowledge/sql_tuning_catalog_v3.yaml), and [source allowlist](../knowledge/sql_tuning_sources_19c.json). Acceptance mappings are currently embedded in the V3 catalog. Separate V3 research/source-audit, coverage-matrix, and acceptance-mapping documents remain unfinished; the previously proposed files do not yet exist.
