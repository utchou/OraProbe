# SQL Query Tuning Knowledge Taxonomy (V2)

This document is the V2 taxonomy for OraProbe's SQL Query Tuner. It is a knowledge-specification artifact only. It does not implement production detection logic or any runtime collector.

## 1. Design principles

OraProbe follows a deterministic-first, LLM-last approach.

The SQL Query Tuner must:

- prefer evidence over intuition
- distinguish observation, symptom, and root cause
- reject unsafe or premature recommendations
- keep a visible record of exclusions and uncertainty
- support a valid "no high-confidence SQL defect found" outcome

The future reasoning model is:

1. observe
2. collect evidence
3. classify evidence quality
4. test competing explanations
5. rank root-cause candidates
6. recommend only with justified confidence
7. validate before changing a production system

## 2. Taxonomy summary

The catalog currently recognizes 12 major SQL performance domains.

| Domain | Code | Purpose |
| --- | --- | --- |
| Access path | AP | Indexes, scans, predicate matching, access strategy |
| Cardinality and statistics | CARD | Row estimates, stale stats, histograms, skew |
| Join and set operations | JOIN | Join type, join order, set operators, row propagation |
| Sort and aggregation | SORT | Sort, hash aggregation, DISTINCT, group-by, temp spill |
| Subquery and transformation | SUBQ | Correlated subqueries, query rewrites, CTE behavior |
| Cursor and plan stability | CUR | Bind peeking, child cursors, plan regression, plan management |
| Parallelism and resource profile | PAR | CPU, I/O, memory, PX skew, serial bottlenecks |
| Partitioning and segment scope | PART | Pruning, partition-wise joins, partition-local design |
| Index and object design | IDX | Composite indexes, covering indexes, redundant or bad index design |
| Predicate and bind behavior | PRED | Sargability, implicit conversion, OR, LIKE, function traps |
| Data and workload shape | DATA | Top-N, repeated work, pagination, skew, result-set shape |
| External contributors | EXT | Blocking, backup, storage, RAC, OS contention, infrastructure |

## 3. Classification model for every rule

Each rule must be classified as one or more of:

- observation
- symptom
- root-cause candidate
- environmental contributor
- optimization opportunity

This matters because many SQL problems are chains rather than isolated causes.

Example:

- stale statistics (root cause candidate)
- cardinality mismatch (symptom and root-cause candidate)
- join order problem (secondary symptom/root-cause candidate)
- temp spill (symptom)
- high elapsed time (observation)

OraProbe should report the highest defensible cause, not every stage as an independent root cause.

## 4. Domain definitions

### AP — Access path

This domain covers plan choices that change how Oracle reads rows: full scan, index scan, range scan, access path mismatch, and predicate-driven access strategy decisions.

### CARD — Cardinality and statistics

This domain covers row estimates, stale or missing statistics, skew, histograms, column correlation, dynamic statistics, and estimate-to-actual mismatch.

### JOIN — Join and set operations

This domain covers nested loops, hash joins, merge joins, join order, cartesian joins, set operators, and missing partition-wise opportunities.

### SORT — Sort and aggregation

This domain covers sort, hash aggregate, DISTINCT, GROUP BY, union elimination, workarea memory, and TEMP spill.

### SUBQ — Subquery and transformation

This domain covers correlated subqueries, scalar subqueries, subquery unnesting, CTE behavior, transformation choices, and repeated work patterns.

### CUR — Cursor and plan stability

This domain covers child cursor behavior, bind peeking, adaptive cursor sharing, plan instability, and SQL plan management.

### PAR — Parallelism and resource profile

This domain covers CPU-bound SQL, I/O-bound SQL, parallel skew, serial bottlenecks, memory pressure, and frequency amplification.

### PART — Partitioning and segment scope

This domain covers partition pruning, partition-wide access, partition-wise joins, local index mismatch, and uneven partition behavior.

### IDX — Index and object design

This domain covers leading-column issues, redundant indexes, covering indexes, composite order issues, and index maintenance overhead.

### PRED — Predicate and bind behavior

This domain covers explicit and implicit datatype conversion, function-based predicates, OR conditions, like patterns, null handling, and bind-type mismatch.

### DATA — Data and workload shape

This domain covers pagination, Top-N, repeated execution, large result-set shape, and data skew that distorts plan fit.

### EXT — External contributors

This domain covers the cases where SQL is not necessarily defective but is slowed by racing SQL, backup activity, storage latency, RAC global cache, OS pressure, or blocking.

## 5. Rule naming and ID scheme

Rules use stable identifiers such as:

- AP-001
- CARD-002
- JOIN-010
- CUR-004

This keeps the catalog implementable later in Python without relying on fragile text-based matching.

## 6. Evidence-first rule requirements

A rule must clearly answer:

- What is being evaluated?
- Which Oracle view or metadata source is relevant?
- What evidence supports the diagnosis?
- What weakens or excludes it?
- What additional evidence or next diagnostic test would resolve uncertainty?

The catalog therefore distinguishes between:

- required evidence
- optional evidence
- historical evidence
- cross-module evidence
- unavailable-evidence handling

## 7. Rule quality standard

A rule is not accepted simply because it has a plausible name.

A rule must have:

- a clear Oracle-specific behavior description
- a clearly described evidence combination
- clear false-positive risks
- defined confidence logic
- a recommendation that is safe and context-aware
- a validation procedure

This is the main improvement over the initial draft.

## 8. Oracle-specific coverage focus

This V2 taxonomy deliberately emphasizes Oracle SQL behaviors that matter in real production work:

- access path selection
- stats and histograms
- bind peeking and child cursor churn
- partition pruning
- join cardinality propagation
- workarea and TEMP spill
- parallel execution skew
- plan instability
- SQL Plan Management
- sargability and coercion issues
- physical I/O vs. logical I/O distinction
- environmental slowdown vs. SQL-level defects

## 9. Gaps and limitations

This taxonomy intentionally does not assume Diagnostics Pack or Tuning Pack is always present. It keeps base-license capability distinct from historical and licensed evidence.

It also keeps the catalog conservative. Not every full scan, hash join, or high buffer-get pattern is bad. That is why the rule model requires exclusions and confidence scoring.

## 10. Related artifacts

- [docs/sql_tuning_catalog.md](sql_tuning_catalog.md)
- [docs/sql_tuning_sources.md](docs/sql_tuning_sources.md)
- [docs/sql_tuning_correlations.md](docs/sql_tuning_correlations.md)
- [docs/sql_tuning_evidence_map.md](docs/sql_tuning_evidence_map.md)
- [docs/sql_tuning_coverage_matrix.md](sql_tuning_coverage_matrix.md)
- [docs/sql_tuning_gap_analysis.md](sql_tuning_gap_analysis.md)
- [knowledge/sql_tuning_catalog.yaml](../knowledge/sql_tuning_catalog.yaml)

## 11. Coverage statement

This is the V2 catalog specification. It is designed to be readable by humans and useful to future Python implementation without turning into executable detection logic.
