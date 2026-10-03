# Query Tuner requirements

Captured from the user's requirements on 2026-10-01. Read with PROJECT_CONTEXT.md and DEMO_SCOPE.md. This is a requirements record, not an approved implementation design.

## Inputs and topology

- Required investigation inputs: database name, SQL ID, incident time/window including timezone. Symptoms are optional.
- Support user-supplied local Excel inventory mapping databases to primary/standby hosts. CSV may be a portable alternative, not a silent replacement for Excel support.
- A connection to the inventory database is an optional future source, subject to availability after management approval.
- Automatic database configuration/topology discovery is deferred beyond the initial demo. Minimal connection identity checks do not substitute for inventory or full discovery.

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

- Query Tuner must be able to request additional evidence from other modules through the shared orchestration/capability interfaces.
- Preserve database, SQL, incident window, topology scope, evidence provenance, and the hypothesis being tested in these requests.
- Correlate returned evidence and provide actionable fix recommendations with their evidence and validation steps.
- Production remediation remains recommendation-only under the existing read-only requirement.
- Implement modules incrementally. If a required module is not yet available in the demo, report the diagnostic gap and next collection/test needed; never claim it ran or that an untested external cause was eliminated.

## Validation expectations

- Test known degraded scenarios, healthy/comparable scenarios, misleading symptoms, missing evidence, and external contributors.
- Include runtime and historical scenarios, with fixture-based tests and repeated live Oracle lab validation.
- Track supported, contradicted, and unresolved hypotheses with traceable evidence and explainable scoring.
