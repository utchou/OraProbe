# SQL Tuning Source Notes (V2)

This document records the authoritative sources and technical references that support the OraProbe SQL Query Tuning catalog.

## 1. Primary Oracle sources

### Oracle Database SQL Tuning Guide
Relevant for:

- access path selection
- optimizer statistics
- histograms
- bind peeking
- execution plan reading
- SQL plan stability
- SQL tuning methodology

### Oracle Database Performance Tuning Guide
Relevant for:

- runtime waits
- system-side contributors
- concurrency and CPU patterns
- I/O tuning context
- workload and resource analysis

### Oracle Database Reference
Relevant for:

- V$ views
- DBA_ views
- underlying metadata definitions
- optimizer and SQL performance dictionary objects

### Oracle Optimizer and execution-plan documentation
Relevant for:

- plan types
- row-source behavior
- join methods
- cardinality estimation
- partition pruning
- workarea memory spill
- dynamic statistics behavior

## 2. Evidence sources by topic

### SQL text and identity
- V$SQL
- V$SQLAREA
- V$SQLSTATS
- DBA_HIST_SQLTEXT
- DBA_HIST_SQLSTAT

### Execution plan and runtime behavior
- V$SQL_PLAN
- V$SQL_PLAN_STATISTICS_ALL
- V$SQL_PLAN_STATISTICS
- DBMS_XPLAN
- SQL Monitor when available

### Cursor behavior and plan stability
- V$SQL_SHARED_CURSOR
- V$SQL
- DBA_HIST_SQL_PLAN
- V$SQL_BIND_CAPTURE
- V$SQL_CS_HISTOGRAM

### Statistics and optimizer metadata
- DBA_TABLES
- DBA_TAB_STATISTICS
- DBA_TAB_COL_STATISTICS
- DBA_HISTOGRAMS
- DBA_INDEXES
- DBA_IND_COLUMNS
- DBA_IND_STATISTICS
- DBA_TAB_PARTITIONS
- DBA_TAB_SUBPARTITIONS

### Wait and workload behavior
- V$SESSION
- V$SESSION_EVENT
- V$ACTIVE_SESSION_HISTORY
- DBA_HIST_ACTIVE_SESS_HISTORY
- V$SYSTEM_EVENT

### Partitioning and object design
- DBA_PART_KEY_COLUMNS
- DBA_TAB_PARTITIONS
- DBA_TAB_SUBPARTITIONS
- DBA_IND_PARTITIONS
- DBA_IND_SUBPARTITIONS

### Parallel execution and resource behavior
- V$PX_SESSION
- V$PX_PROCESS
- V$PQ_SESSTAT
- V$SESSION
- V$TEMPSEG_USAGE

## 3. License-dependent evidence

### Base capability
These are generally available and should remain the primary target for the initial OraProbe Query Tuner:

- SQL text
- execution plans
- table and index metadata
- runtime SQL statistics
- dictionary statistics
- session waits and active sessions when available

### Optional / licensed / advanced capability
These should be treated as optional if present:

- AWR historical comparison
- ASH deep analysis and historical baselines
- SQL Monitor
- SQL Tuning Advisor output
- Diagnostics Pack features
- certain advanced workload and tracing features

OraProbe should degrade gracefully when the system lacks those capabilities and must describe the evidence gap explicitly.

## 4. Oracle-specific reasoning categories

### Access path reasoning
Oracle documentation is central for:

- index range scans vs full scan vs fast full scan
- composite indexes and leading columns
- index selectivity and costs
- partition pruning and partition-local behavior

### Cardinality reasoning
The main sources are:

- table stats
- column stats
- histograms
- extended statistics
- optimizer-dependent behavior
- actual vs estimated rows

### Bind and cursor reasoning
Key Oracle guidance is used for:

- bind peeking
- adaptive cursor sharing
- child cursor behavior
- cursor sharing and plan instability

### Parallel and workarea reasoning
Sources are used for:

- PX skew
- parallel distribution decisions
- TEMP and workarea spill
- operation cost amplification under concurrency

## 5. Source traceability rules

When writing a rule, the catalog should distinguish:

- Oracle guidance explicitly documented by Oracle
- Oracle documentation with some engineering interpretation applied
- engineering heuristic without oracle wording

The final catalog should classify this clearly. For example:

- Oracle reference: documented behavior described in official Oracle docs
- engineering interpretation: reasonable DBA reading of Oracle guidance
- engineering heuristic: useful but not explicitly documented as a formal rule

## 6. Authoritative reference list

The following are primary supporting references for the catalog:

- Oracle Database 19c SQL Tuning Guide
- Oracle Database 19c Performance Tuning Guide
- Oracle Database 19c Database Reference
- Oracle Database 19c SQL Language Reference
- Oracle Database 19c Database SQL Language Reference
- Oracle optimizer and execution-plan documentation related to DBMS_XPLAN
- Oracle partitioning documentation for pruning and partition-wise operations
- Oracle parallel execution documentation for PX and workarea behavior

## 7. Caveat

This catalog is built from Oracle guidance and standard DBA reasoning; it is not a substitute for live validation in a test environment. Because this project is still in the specification stage, all rules remain subject to human Oracle DBA review before implementation.
