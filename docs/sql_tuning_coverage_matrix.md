# SQL Tuning Coverage Matrix

This document maps the V2 rule catalog to the major engineering concerns for the future OraProbe Query Tuner.

## 1. Coverage by category

| Category | Covered | Notes |
| --- | --- | --- |
| Access-path problems | Yes | AP domain covers index mismatch, function traps, and scan issues |
| Cardinality and statistics | Yes | CARD domain counts key optimizer estimation failures |
| Join defects | Yes | JOIN domain covers join order, cartesian joins, and hash/merge problems |
| Sort and aggregation | Yes | SORT domain covers spill, duplicate elimination, and ordering cost |
| Subquery issues | Yes | SUBQ domain covers correlated and scalar patterns |
| Cursor and plan stability | Yes | CUR domain covers bind peeking, child cursor churn, and regression |
| Parallelism and resource profile | Yes | PAR domain covers CPU, I/O, memory pressure, and parallel skew |
| Partitioning | Yes | PART domain covers pruning, partition-wise optimization, and broad scans |
| Index design and health | Yes | IDX domain covers leading-column fit, covering indexes, and index health |
| Predicate and bind behavior | Yes | PRED domain covers wildcard, OR, function traps, type conversion, and bind mismatch |
| Data shape and high-frequency workload | Yes | DATA domain covers pagination, top-N, and skew |
| External contributors | Yes | EXT domain covers blocking, storage, RAC, and workload contention |
| No-defect outcome | Yes | Explicitly supported as a valid result |
| Evidence classification | Yes | Each rule defines evidence, exclusions, and confidence logic |
| Source traceability | Yes | Each rule ties back to Oracle sources and plan metadata |

## 2. Coverage by rule family

| Rule family | Count | Representative examples |
| --- | ---: | --- |
| AP | 5 | full scan, missing selective path, function trap |
| CARD | 5 | stale stats, histogram gap, skew, estimate mismatch |
| JOIN | 5 | nested loops on wide set, cartesian join, join order |
| SORT | 4 | sort spill, aggregation spill, distinct cost |
| SUBQ | 4 | correlated subquery, scalar subquery, CTE issue |
| CUR | 5 | bind peeking, child cursor churn, plan regression |
| PAR | 4 | CPU-bound SQL, I/O-bound SQL, parallel skew |
| PART | 4 | pruning failure, partition-wise join opportunity |
| IDX | 4 | leading column order, covering index, index health |
| PRED | 5 | wildcard LIKE, OR, conversion, bind mismatch |
| DATA | 4 | pagination, top-N, skew, result size |
| EXT | 5 | resource contention, backup load, storage, RAC, blocking |

## 3. Engineering readiness view

The catalog is strong in these design areas:

- Oracle-specific rule families
- evidence and counter-evidence model
- causal dependency model
- no-defect and insufficient-evidence outcomes
- source-aware design for future Python evaluation

The catalog is still weak in these implementation areas:

- exact input schema for collector modules
- exact field naming for runtime data objects
- exact scoring weights and threshold logic
- test fixtures and regression datasets
- user-facing recommendation text templates

## 4. Required follow-up before implementation

Before writing code, the team should still define:

1. The exact evidence object schema for SQL, ASH, AWR, plan, and object metadata.
2. The exact scoring model: evidence strength, confidence, exclusions, and overrides.
3. A small list of high-priority rules to implement first.
4. A deterministic test suite with expected outcomes for each major rule family.
5. The exact UI or API contract for final diagnosis output.

## 5. Implementation priority recommendation

The first implementation slice should likely be:

- AP-001: full scan not justified
- CARD-005: large estimate-to-actual mismatch
- JOIN-004: cartesian join
- CUR-001: bind-peeking instability
- PRED-004: implicit conversion
- EXT-005: blocking or lock chain

These are high-signal, evidence-rich, and easy to validate with a deterministic rule engine.

## 6. Final assessment

The V2 catalog has broad domain coverage and a realistic evidence-driven design. It is not yet an implementation, but it is ready for a next engineering step: selecting the first deterministic rule-evaluation model and validating it with a small set of Oracle fixtures.
