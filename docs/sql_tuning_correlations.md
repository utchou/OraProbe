# SQL Tuning Correlation Model (V2)

This document defines how OraProbe should reason about relationships between findings so it does not present every symptom as a separate root cause.

## 1. Correlation principle

A single SQL problem often produces several visible symptoms:

- bad cardinality estimate
- poor join order
- large temporary workarea use
- high elapsed time
- buffer gets or reads growth
- resource contention

These may be connected. The system must therefore reason about causal chains and not just individual symptoms.

## 2. Causal hierarchy used by OraProbe

The catalog distinguishes the following:

- root-cause candidate
- downstream symptom
- environmental factor
- optimization opportunity
- observational result

Example:

- stale statistics -> cardinality mismatch -> poor join order -> larger intermediate row set -> temp spill -> high elapsed time

The final report should identify the most defensible upstream cause, while keeping the downstream symptoms visible.

## 3. Rule relationships

### Reinforcing rules
These findings strengthen one another:

- CARD-001 + CARD-005 + JOIN-005
- AP-004 + PRED-003
- PART-001 + AP-007
- CUR-001 + CARD-005
- SORT-001 + PAR-004
- EXT-001 + PAR-001

### Contradictory rules
These findings may reduce confidence in a diagnosis:

- AP-001 may be acceptable if table is small or result set is large by design
- JOIN-002 may be acceptable under a large data set and well-managed memory
- SORT-003 may be intentional if DISTINCT is required by business logic
- CUR-002 may be adaptive and not necessarily a defect

### Dependency relationships

Examples:

- PRED-004 may trigger AP-003
- CARD-002 may trigger JOIN-005
- SUBQ-001 may trigger SORT-003
- CUR-001 may trigger CARD-005
- EXT-001 may amplify a benign SQL shape into an apparent defect

## 4. Duplicate and overlap handling

The catalog uses a stricter rule review standard.

Overlaps addressed in V2:

- function-on-column issues are assigned to PRED and referenced from AP
- implicit conversion appears as both a predicate and access-path problem, but is now clearly classified by its primary trigger
- sort spill and hash aggregation spill are separated as distinct but related problems
- partition pruning is tracked as both an access-path and partitioning issue, with one primary root-cause classification

This avoids the old problem of multiple rules describing the same root cause in slightly different forms.

## 5. Proposed correlation logic for future implementation

A Python implementation should eventually do the following:

1. evaluate all rules supported by available evidence
2. group rules by object set and time window
3. detect shared objects and shared SQL IDs
4. classify root causes, symptoms, and external contributors
5. rank the most defensible root cause
6. suppress duplicate symptom findings when a stronger upstream cause is present

Pseudo-model:

- if Rule A and Rule B share the same object and same time window, increase confidence in a single cause
- if Rule A explains Rule B, downgrade Rule B as a standalone root cause
- if Rule C directly contradicts Rule A, reduce confidence in A
- if evidence is missing, do not force an outcome

## 6. Cross-domain correlation examples

### Example 1: stale stats -> wrong plan
- CARD-001
- CARD-005
- JOIN-005
- SORT-001
- PAR-004

Interpretation: optimizer estimate error triggers poor join order, leading to more work and temp spill.

### Example 2: predicate conversion issue
- PRED-004
- AP-003
- CARD-005

Interpretation: coercion prevents index use, which then creates poor row estimates and access strategy mismatch.

### Example 3: external pressure mistaken for SQL defect
- EXT-001
- PAR-001
- SORT-003

Interpretation: the SQL may not be the root cause; the broader workload or storage pressure may be dominating the runtime profile.

## 7. Important caution

Correlation is not proof of causation. OraProbe must keep explicit unresolved alternatives and must not claim that SQL is root cause when the evidence points elsewhere.

## 8. Implementation guidance

The future deterministic engine should maintain a correlation map containing:

- rule ID
- root-cause or symptom role
- reinforcing rules
- contradictory rules
- dependent rules
- recommended next hypothesis test

This makes reports more useful and avoids noisy, repetitive findings.
