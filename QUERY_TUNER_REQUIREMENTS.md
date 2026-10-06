# Query Tuner requirements

Captured from the user's requirements on 2026-10-01. Read with PROJECT_CONTEXT.md and DEMO_SCOPE.md. This is a requirements record, not an approved implementation design.

## Inputs and topology

- Required investigation inputs: database name, SQL ID, incident time/window including timezone. Symptoms are optional.
- Support user-supplied local Excel inventory mapping databases to primary/standby hosts. CSV may be a portable alternative, not a silent replacement for Excel support.
- A connection to the inventory database is an optional future source, subject to availability after management approval.
- Automatic database configuration/topology discovery is deferred beyond the initial demo. Minimal connection identity checks do not substitute for inventory or full discovery. (AR-04 and decision C-2 in docs/oraprobe_architecture_requirements.md: Excel/CSV stays the demo seed inventory; the demo may perform bounded runtime validation of the selected target after connecting; a mismatch is a topology/inventory warning, not a V3.2 diagnostic evidence type.)

## Diagnostic outcomes

- Produce evidence-backed RCA for SQL slowness where evidence permits.
- Investigate whether the reported degradation actually occurred. Report no observed degradation when adequate, comparable evidence supports that outcome.
- Distinguish no observed degradation from insufficient evidence, lack of a baseline, or incomplete incident coverage. Do not claim that the user is wrong or that no problem exists solely because telemetry is missing.
- Support currently occurring and historical incidents using execution evidence and related data for the relevant time window.
- Separate symptoms, likely contributing factors, and established causes. State unresolved alternatives and next tests.

## Diagnostic breadth

- User requests exhaustive diagnostic intelligence, informed by Oracle documentation and recognized Oracle experts worldwide.
- Engineering interpretation proposed for design review: maintain a broad, source-backed hypothesis catalog and a visible coverage matrix; do not promise guaranteed root-cause detection for every incident regardless of evidence availability.
- Research before implementing diagnostic logic, prioritizing Oracle 19c primary documentation. Assess expert guidance for version applicability, evidence, and reproducibility before encoding it.
- Cover SQL-local causes and external contributors, including execution-plan changes, access paths/indexes, SQL design, storage latency, CPU contention, competing SQL, blocking, RMAN activity, other database waits, and database parameters.
- A changed plan, overlapping backup, or unusual parameter is not by itself proof of causation. Test competing explanations and use comparable observations.

## Cross-module investigation and recommendations

- Query Tuner must be able to request additional evidence from other modules through the shared orchestration/capability interfaces. Architectural basis: evidence-driven cross-module investigation and the Evidence Resolution / Investigation Planner, AR-01 in docs/oraprobe_architecture_requirements.md.
- Preserve database, SQL, incident window, topology scope, evidence provenance, and the hypothesis being tested in these requests.
- Correlate returned evidence and provide actionable fix recommendations with their evidence and validation steps.
- Production remediation remains recommendation-only under the existing read-only requirement.
- Implement modules incrementally. If a required module is not yet available in the demo, report the diagnostic gap and next collection/test needed; never claim it ran or that an untested external cause was eliminated.

## Execution plan comparison (AR-03 in docs/oraprobe_architecture_requirements.md; recorded 2026-10-06)

Status: requirement only. It is not implemented and not encoded in the frozen V3.2 catalog.

**Requirements:**
- Query Tuner compares two execution plans for the same SQL (or a validated family member / the same workload). It deterministically identifies meaningful differences and, when runtime evidence is sufficient, explains why one plan performs better or worse.
- Evidence, where available and applicable:
  - plan shape and operation changes; join order; join methods; access paths and index usage; predicates and predicate placement;
  - E-Rows versus A-Rows; Starts; buffers/logical reads; physical I/O; CPU; elapsed time; TEMP/workarea spills;
  - parallelism; partition pruning; row-source amplification; datatype conversions;
  - optimizer/environment changes; bind, peeking and statistics evidence.
- A plan is never judged better or worse from optimizer COST or PLAN_HASH_VALUE.
- If only estimates/cost are available and runtime evidence is insufficient, the conclusion is UNKNOWN / insufficient evidence.
- A plan change without degradation is not automatically a regression.
- An unchanged PLAN_HASH_VALUE during degradation is not evidence that the plan or workload is healthy.
- Comparison follows the existing V3.2 contracts:
  - comparable windows and strata (`baseline_policy`, `awr_plan_policy`);
  - the executed adaptive branch and child, with A-Rows/Starts per start (`plan_policy`);
  - actuals from one source per execution (`monitor_policy`);
  - bound semantics and family tiers.

**V3.2 relation (gap G-02; future design decision, V3.2 unchanged):**
- V3.2 detects plan regression per SQL_ID from aggregate per-plan runtime (CUR-004: `plan_runtime_ratio`, `awr_plan_elapsed_ratio`, `awr_plan_buffer_ratio`), and its line-level rules evaluate one plan at a time.
- It has no request type naming two plans/executions, no operator aligning plan lines across plans, and no per-difference attribution metrics. `investigation_keys` holds a single `sql_id`.
- An additive extension is expected; its form is decided in plan-comparison design.

**Future acceptance scenario `plan_comparison`:**
1. Two plans with comparable executions and per-line runtime evidence: differences are identified, and the slower plan's extra work is localized to operations with evidence.
2. Only estimates and COST available: differences are listed, and the performance conclusion is UNKNOWN (insufficient runtime evidence).
3. The lower-COST plan is the slower one at runtime: runtime evidence governs; COST is never cited as proof.
4. Plan changed while runtime stays within material deviation: not reported as a regression.
5. Same PLAN_HASH_VALUE in the baseline and the degraded window: not taken as evidence of health; other hypotheses stay active.
6. Executions from non-comparable windows, binds or workload strata: comparison is flagged non-comparable, with no better/worse conclusion.
7. Parallel versus serial plan: QC and PX actuals are aggregated per execution before comparison.

## Validation expectations

- Test known degraded scenarios, healthy/comparable scenarios, misleading symptoms, missing evidence, and external contributors.
- Include runtime and historical scenarios, with fixture-based tests and repeated live Oracle lab validation.
- Track supported, contradicted, and unresolved hypotheses with traceable evidence and explainable scoring.
