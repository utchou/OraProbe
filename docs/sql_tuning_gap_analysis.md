# SQL Tuning Gap Analysis

This file identifies the remaining gaps between the V2 catalog and a production implementation.

## 1. What is already strong

The catalog already provides the core design foundation:

- Oracle-focused taxonomy and rule families
- candidate root causes and symptoms separated from external contributors
- evidence requirements and counter-evidence rules
- confidence logic and safety concerns
- explicit no-defect and insufficient-evidence outcomes
- source-aware design for future implementation

## 2. Remaining implementation gaps

### 2.1 Collector contract is not finalized

The catalog describes what evidence is needed, but it does not yet define:

- exact input names
- field types
- optional vs required fields
- whether the source is JSON, YAML, CSV, or database query output
- validation rules for malformed or partial evidence

### 2.2 Scoring model is not yet fixed

The catalog states that confidence should be logic-driven, but it does not define:

- exact scoring weights
- evidence strength levels
- when a rule should be suppressed
- how contradictory findings should reduce confidence
- how multiple rules should be merged into one root-cause explanation

### 2.3 Rule execution order is not designed yet

The catalog helps classify issues, but it does not yet define:

- execution order across all domains
- whether rules are independent or chained
- how local symptoms are grouped into a single root-cause narrative
- how a rule can escalate or downgrade because of data quality

### 2.4 No deterministic fixtures exist yet

There are no concrete test cases to validate:

- query text with known poor plan
- plan with estimate mismatch
- child cursor churn scenario
- blocking scenario
- storage-latency scenario
- no-defect valid case

### 2.5 Product output contract is not defined

The system is not yet specifying:

- JSON response fields
- severity levels
- explanation format
- recommendation structure
- final diagnosis ranking
- how to present unresolved evidence versus a definite root cause

### 2.6 UI and workflow boundaries are missing

The design does not yet describe:

- whether findings are consumed by a CLI, API, or web interface
- how users can approve or reject a recommendation
- how the tool should show confidence and evidence status
- whether the SQL tuner is a one-query model or a whole-workload model

## 3. Priority gaps to close first

The first working prototype should focus on these missing items:

1. Evidence schema for a single SQL statement and one plan
2. Rule scoring model and confidence threshold
3. First-tier deterministic rules to implement
4. Fixture-based validation strategy
5. Final diagnosis output contract

## 4. Recommended approach

The next step should not be a broad engine build. It should be a narrow implementation plan:

1. Pick a minimal evidence set.
2. Implement a small deterministic rule set.
3. Encode test fixtures for known Oracle patterns.
4. Validate scores and exclusions.
5. Expand only after the first slice is stable.

## 5. Conclusion

The V2 catalog is a good specification layer, but it is not yet a finished implementation contract. It is strong enough to inform the first deterministic prototype, yet still missing the exact execution and output rules needed for production-grade behavior.
