# SQL Tuning Evidence Map (V2)

This file describes what evidence OraProbe must collect before evaluating SQL performance hypotheses. It is a specification artifact, not an executable collector.

## 1. Evidence categories

The knowledge model separates evidence into the following layers:

1. SQL identity and metadata
2. execution plan and row-source metadata
3. object stats and optimizer metadata
4. runtime metrics
5. historical and comparative evidence
6. environmental and cross-module evidence
7. evidence exclusions and unresolved gaps

## 2. Core evidence collection items

### SQL identity
- SQL_ID
- SQL text
- plan hash value
- child cursor count
- parsing schema
- database name and instance
- timestamp and timezone
- number of executions
- current and historical user/session context when relevant

### Execution plan and row-source evidence
- operation type
- object name and alias
- access method
- predicates used at each step
- estimated rows
- actual rows
- cost estimates
- sort and aggregation actions
- join methods and join order
- partition steps
- row-source filters and filters applied

### Object and optimizer metadata
- table row counts
- index definitions and status
- clustering factor
- histogram state
- extended statistics
- column statistics
- partition metadata
- optimizer parameters
- materialized view or rewrite context if relevant

### Runtime metrics
- elapsed time
- CPU time
- buffer gets
- physical reads
- logical reads
- write cost and temp usage
- rows processed
- workarea memory usage
- sort/aggregation spill indicators
- parse counts

### Historical and comparative evidence
- AWR or ASH data when available
- SQL plan history
- previous executions
- change windows after stats refresh or code change
- comparison against baseline periods

### Environmental evidence
- competing SQL activity
- RMAN or backup windows
- RAC node or interconnect data
- storage or ASM latency
- OS CPU and memory pressure
- blocking or lock chains

## 3. Oracle sources by evidence type

### Base capability
These should be the default sources for a first usable version:

- V$SQL
- V$SQL_PLAN
- V$SQL_PLAN_STATISTICS_ALL
- V$SQLSTATS
- V$SESSION
- V$SESSION_EVENT
- DBA_TABLES
- DBA_TAB_STATISTICS
- DBA_TAB_COL_STATISTICS
- DBA_INDEXES
- DBA_IND_COLUMNS
- DBA_IND_STATISTICS
- DBA_TAB_PARTITIONS
- DBA_TAB_SUBPARTITIONS
- DBA_HISTOGRAMS
- DBA_OBJECTS
- DBMS_XPLAN

### Optional or licensed capability
These should be considered only when available and approved:

- ASH/AWR historical views
- SQL Monitor
- SQL Tuning Advisor
- advanced workload tracing
- vendor-specific storage or RAC telemetry

## 4. Rule-to-source mapping examples

### Access-path rules
Need:
- V$SQL_PLAN
- DBA_INDEXES
- DBA_IND_COLUMNS
- DBA_TABLES
- V$SQL

### Cardinality rules
Need:
- DBA_TAB_STATISTICS
- DBA_TAB_COL_STATISTICS
- DBA_HISTOGRAMS
- V$SQL_PLAN_STATISTICS_ALL
- V$SQL

### Cursor and plan-stability rules
Need:
- V$SQL_SHARED_CURSOR
- V$SQL
- DBA_HIST_SQL_PLAN
- V$SQL_PLAN

### Partition rules
Need:
- DBA_TAB_PARTITIONS
- DBA_IND_PARTITIONS
- V$SQL_PLAN
- DBA_TAB_STATISTICS

### External-contributor rules
Need:
- V$SESSION
- V$SESSION_EVENT
- V$ACTIVE_SESSION_HISTORY
- OS or storage telemetry if present

## 5. Evidence quality levels

OraProbe should classify evidence as:

- direct
- supporting
- historical
- indirect
- unavailable

This matters because a diagnosis built on indirect evidence should not be treated as equally strong as one built on direct runtime and plan evidence.

## 6. Missing evidence handling

The system must distinguish clearly between:

- evidence that contradicts a hypothesis
- evidence that is missing
- evidence that is insufficient for a decision
- evidence that is unavailable due to licensing or database restriction

When evidence is missing, the result should be "not evaluated" or "insufficient evidence" rather than a false negative.

## 7. Implementation guardrails

- base-license capability remains the default target
- optional licensed data is supplemental only
- raw evidence must be preserved separately from normalized findings
- every diagnosis should retain evidence provenance
- no rule should be accepted without a traceable evidence path

## 8. Future collector boundary

This file defines the required evidence model so that later Python collection code can be built deterministically. It does not implement that code itself.
