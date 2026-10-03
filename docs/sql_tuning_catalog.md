# SQL Query Tuning Catalog (V2)

This catalog is the V2 knowledge specification for OraProbe's SQL Query Tuner. It is a planning artifact and should not be treated as production code.

## 1. Catalog purpose

This catalog exists to support a future deterministic Python implementation. It captures Oracle-specific SQL performance patterns, the evidence needed to evaluate them, and the causal relationships between findings.

It is deliberately conservative. The product must prefer:

- evidence over guesswork
- exclusions over simplistic rules
- explainability over flashy diagnosis
- a valid no-defect outcome when the SQL is not the problem

## 2. V2 scope and counts

- Original draft rule count: 42
- V2 rule count: 54
- Added: 12 new rules
- Merged or clarified: several overlaps removed or renamed
- Retained: core Oracle SQL tuning family structure from the earlier draft

The YAML file is the canonical rule list. The markdown file provides the review-oriented summary.

## 3. Domain summary

| Domain | Code | Scenario count |
| --- | --- | ---: |
| Access path | AP | 5 |
| Cardinality and statistics | CARD | 5 |
| Join and set operations | JOIN | 5 |
| Sort and aggregation | SORT | 4 |
| Subquery and transformation | SUBQ | 4 |
| Cursor and plan stability | CUR | 5 |
| Parallelism and resource profile | PAR | 4 |
| Partitioning and segment scope | PART | 4 |
| Index and object design | IDX | 4 |
| Predicate and bind behavior | PRED | 5 |
| Data and workload shape | DATA | 4 |
| External contributors | EXT | 5 |
| Total |  | 54 |

## 4. Rule list by domain

### AP
- AP-001: Full scan not justified by row set or predicate
- AP-002: Missing selective access path
- AP-003: Index exists but is bypassed
- AP-004: Function on indexed column blocks access path
- AP-005: Implicit conversion blocks index access

### CARD
- CARD-001: Stale stats
- CARD-002: Missing histogram for skewed predicate
- CARD-003: Skew not reflected in estimate
- CARD-004: Correlated predicate estimate drift
- CARD-005: Large estimate-to-actual mismatch

### JOIN
- JOIN-001: Nested loops on large driving set
- JOIN-002: Hash join spill
- JOIN-003: Merge join causing avoidable sort movement
- JOIN-004: Cartesian join
- JOIN-005: Poor join order

### SORT
- SORT-001: Sort spill to TEMP
- SORT-002: Hash aggregation spill
- SORT-003: DISTINCT or GROUP BY over-works data
- SORT-004: ORDER BY or window step dominates runtime

### SUBQ
- SUBQ-001: Correlated subquery repeated
- SUBQ-002: Scalar subquery repeated
- SUBQ-003: Poor IN/EXISTS transformation
- SUBQ-004: CTE or inline materialization issue

### CUR
- CUR-001: Bind peeking instability
- CUR-002: Adaptive cursor sharing problem
- CUR-003: Child cursor churn
- CUR-004: Plan regression after change
- CUR-005: SQL Plan Management not controlling drift

### PAR
- PAR-001: CPU-bound SQL
- PAR-002: I/O-bound SQL
- PAR-003: Parallel execution skew or serial bottleneck
- PAR-004: Memory pressure and workarea spill

### PART
- PART-001: Partition pruning failure
- PART-002: Partition-local mismatch
- PART-003: Partition-wise join missed
- PART-004: Broad partition scan from weak predicate

### IDX
- IDX-001: Bad leading column order
- IDX-002: Redundant or weak index
- IDX-003: Missing covering index
- IDX-004: Unusable or badly maintained index state

### PRED
- PRED-001: Leading wildcard LIKE
- PRED-002: OR predicate suppresses efficient access
- PRED-003: Function traps on indexed column
- PRED-004: Implicit conversion
- PRED-005: Bind-type mismatch

### DATA
- DATA-001: Pagination repeated work
- DATA-002: Top-N repeated execution
- DATA-003: Large result set returned unnecessarily
- DATA-004: Data skew causes biased plan behavior

### EXT
- EXT-001: Competing SQL contention
- EXT-002: RMAN or backup load
- EXT-003: Storage or ASM latency
- EXT-004: RAC or interconnect issue
- EXT-005: Blocking or lock chain

## 5. Rule structure

Each rule in the canonical YAML includes:

- Rule ID
- Name
- Domain
- Classification
- Problem description
- Why it matters
- Required evidence
- Oracle source mapping
- Detection conditions
- Counter-evidence / exclusions
- False-positive risks
- Confidence logic
- Root-cause statement template
- Recommendation
- Validation procedure
- Safety/change risk
- Related rules
- Reinforcing rules
- Contradictory rules
- Dependency relationships
- Evidence availability behavior
- Oracle version considerations
- Licensing status
- Reference

## 6. Causal model

The catalog separates:

- observation
- symptom
- root cause candidate
- environmental contributor
- optimization opportunity

Example:

- stale stats -> cardinality mismatch -> poor join choice -> larger rowset -> temp spill -> high elapsed time

The system should report the upstream cause with supporting symptoms, not a long list of unrelated findings.

## 7. No-defect outcome

OraProbe must explicitly support:

- no high-confidence SQL defect found

This occurs when:

- workload is legitimate
- plan is appropriately efficient
- evidence is incomplete or contradictory
- the issue is external to SQL itself

## 8. Implementation boundary

This is still a knowledge-engineering phase. No Python logic, no collectors, and no production runtime code are being built here.

## 9. Related files

- [sql_tuning_taxonomy.md](sql_tuning_taxonomy.md)
- [sql_tuning_sources.md](sql_tuning_sources.md)
- [sql_tuning_correlations.md](sql_tuning_correlations.md)
- [sql_tuning_evidence_map.md](sql_tuning_evidence_map.md)
- [sql_tuning_coverage_matrix.md](sql_tuning_coverage_matrix.md)
- [sql_tuning_gap_analysis.md](sql_tuning_gap_analysis.md)
- [../knowledge/sql_tuning_catalog.yaml](../knowledge/sql_tuning_catalog.yaml)

## 10. Final state

This V2 catalog is deeper and more implementation-ready than the initial draft while still intentionally staying in the specification layer. It is built for human review before any production implementation begins.
