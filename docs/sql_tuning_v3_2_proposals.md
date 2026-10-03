# V3.2 proposals — closing October-incident design gaps

Status: **decided 2026-10-03; implemented as V3.2.** See the [V3.2 change record](sql_tuning_v3_2_changes.md), the [V3.2 October walkthrough](sql_tuning_v3_2_october_walkthrough.md) and the [readiness assessment](implementation_readiness_v3_2.md).

| ID | Decision |
| --- | --- |
| V32-01 | Accept |
| V32-02 | Accept with constraints (grouping/supporting evidence only; no semantic claim; no parser for first engine) |
| V32-03 | Strongly accept (exact / lower / upper / sampled estimate / unknown-incomplete; no silent bound comparison) |
| V32-04 | Strongly accept with modification: collect once → normalize once → define canonical fact once → many consumers; RM knowledge has one owner and is consumed directly by Query Tuner |
| V32-05 | Accept (capture bias modeled; missing ≠ not executed) |
| V32-06 | Accept with conditions (undocumented semantics are lab_verification_required) |
| V32-07 | Strongly accept (coverage restricts conclusions) |
| V32-08 (ASH TEMP) / decision "V32-09" (concurrency) / decision "V32-10" (host CPU) | Accept as estimate/bound evidence; host CPU never eliminates noisy neighbors |
| Proposal V32-10 (dependency grades) | **Accepted with conditions** (correction after a numbering mismatch; formerly backlog BL-05). Attribution/supporting evidence only; never family equivalence, object causation, identical work beneath a view, or causation from a common reference. Encoded in V3.2. |
| V32-11 … V32-14 | Deferred to backlog |

The original proposal text follows unchanged.

Decision carried forward: `db_time_deviation` in `measured_degradation` is **approved**. It is evidence that database-side degradation occurred, never evidence identifying a root cause or contributor.

## Sources checked (Oracle 19c documentation, 2026-10-03)

**Reference pages:**
- [DBA_HIST_RSRC_CONSUMER_GROUP](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_RSRC_CONSUMER_GROUP.html)
- [DBA_HIST_RSRC_PLAN](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_RSRC_PLAN.html)
- [DBA_HIST_RSRC_METRIC](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_RSRC_METRIC.html)
- [DBA_HIST_SQLSTAT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQLSTAT.html)
- [DBA_HIST_SQLTEXT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQLTEXT.html)
- [DBA_HIST_SQL_PLAN](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQL_PLAN.html)
- [DBA_HIST_SQL_BIND_METADATA](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQL_BIND_METADATA.html)
- [DBA_HIST_COLORED_SQL](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_COLORED_SQL.html)
- [DBA_HIST_ACTIVE_SESS_HISTORY](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_ACTIVE_SESS_HISTORY.html)
- [DBA_HIST_SERVICE_NAME](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SERVICE_NAME.html)
- [DBA_HIST_OSSTAT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_OSSTAT.html) / [V$OSSTAT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-OSSTAT.html)
- [DBA_HIST_PARAMETER](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_PARAMETER.html)
- [DBA_HIST_SYSTEM_EVENT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SYSTEM_EVENT.html)
- [DBA_HIST_SQL_WORKAREA_HSTGRM](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQL_WORKAREA_HSTGRM.html)
- [DBA_HIST_TBSPC_SPACE_USAGE](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_TBSPC_SPACE_USAGE.html)
- [V$OBJECT_DEPENDENCY](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-OBJECT_DEPENDENCY.html)
- [V$SQL](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SQL.html)

**Other guides:**
- [DBMS_WORKLOAD_REPOSITORY](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_WORKLOAD_REPOSITORY.html)
- [DBMS_SQLTUNE (force_match)](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SQLTUNE.html)
- [Performance Tuning Guide: Measuring Database Performance](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/measuring-database-performance.html)
- [Gathering Database Statistics](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/gathering-database-statistics.html)
- [Licensing Information](https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html)

## Documented facts that drive the design

| Fact (as documented) | Design consequence |
| --- | --- |
| `EXACT_MATCHING_SIGNATURE` is "calculated on the normalized SQL text… removal of white space and the uppercasing of all non-literal strings". `FORCE_MATCHING_SIGNATURE` is the "signature used when CURSOR_SHARING is set to FORCE". | EMS equality means formatting variants with the same literals. FMS equality means a lexically same statement up to literal values. Neither states application semantics. |
| DBMS_SQLTUNE `force_match`: "if a combination of literal values and bind values is used in a SQL statement, no bind transformation occurs" | Literal variants of a statement that also uses a bind get **different** FMS values. FMS can under-group as well as fail to prove equivalence. |
| `DBA_HIST_SQLSTAT` has `FORCE_MATCHING_SIGNATURE`, `MODULE`, `ACTION`, `PARSING_SCHEMA_NAME`, `PLAN_HASH_VALUE`; **no** `EXACT_MATCHING_SIGNATURE`, **no** `SERVICE`. It "captures the top SQL statements based on a set of criteria". | Historical EMS is unavailable from AWR statistics. Coverage is biased towards top SQL. |
| `topnsql`: default top 30 per criterion at `TYPICAL` (elapsed, CPU, parse calls, sharable memory, version count). `MAXIMUM` captures "the complete set of SQL in the cursor cache". A colored SQL_ID "will be captured in every snapshot… if the SQL is found in the cursor cache at snapshot time." | Even `MAXIMUM` or coloring misses SQL aged out of the cursor cache before a snapshot. AWR SQL coverage is never provably complete. |
| ASH samples active sessions every second. "Only a portion of the session samples is written to disk." No ratio is documented. | Persisted ASH is a sampled subset with an undocumented selection rule. Instant-level counts from it are **lower bounds**; spacing comes from `USECS_PER_ROW` / sample times. |
| `DBA_HIST_ACTIVE_SESS_HISTORY` has `FORCE_MATCHING_SIGNATURE`, `TOP_LEVEL_SQL_ID`, `SQL_OPCODE`, `MODULE`, `ACTION`, `SERVICE_HASH`, `CONSUMER_GROUP_ID`, `TEMP_SPACE_ALLOCATED`, `PGA_ALLOCATED` and `TM_DELTA_CPU_TIME`/`TM_DELTA_TIME`. | History has an activity-based (not top-N) record of SQL, signature, group and per-session TEMP, all sampled. |
| `DBA_HIST_RSRC_CONSUMER_GROUP` holds snapshots of `V$RSRC_CONS_GROUP_HISTORY`: cumulative `CONSUMED_CPU_TIME` (ms), `CPU_WAIT_TIME`, `CPU_WAITS`, `YIELDS`, queueing, per `INSTANCE_NUMBER` and `SEQUENCE#` (reset at restart). | Per-snapshot-interval, per-group, per-instance consumed CPU and Resource Manager CPU wait are derivable historically. |
| `DBA_HIST_RSRC_PLAN`: plan `START_TIME`/`END_TIME`, `CPU_MANAGED`, `INSTANCE_CAGING`, per instance. | The plan and caging state during the incident are historically knowable. |
| `DBA_HIST_RSRC_METRIC`: 1-minute rows (`BEGIN_TIME`, `END_TIME`, `INTSIZE_CSEC`) with `AVG_RUNNING_SESSIONS`, `AVG_WAITING_SESSIONS`, `AVG_CPU_UTILIZATION`. Intro says "for the past hour". | Minute-level history may or may not be retained across AWR retention. **This must be lab-verified, not assumed.** |
| `V$OSSTAT`/`DBA_HIST_OSSTAT`: `RSRC_MGR_CPU_WAIT_TIME` (all platforms, cumulative), `NUM_CPUS` (all platforms), `BUSY_TIME`/`IDLE_TIME`/`OS_CPU_WAIT_TIME`/`LOAD` (OS-dependent). | Oracle-recorded host CPU busy and run-queue context exists historically, per instance host. |
| `DBA_HIST_PARAMETER` holds snapshots of `V$SYSTEM_PARAMETER` per instance. | Historical `CPU_COUNT` (caging limit) and `RESOURCE_MANAGER_PLAN`. |
| `V$OBJECT_DEPENDENCY` lists "objects depended on by… cursor that is currently loaded in the shared pool". | It can show a merged view's dependency for **cached** cursors only. |
| `DBA_HIST_TBSPC_SPACE_USAGE` does not state whether TEMP tablespaces are included. | Lab verification needed; snapshot-instant only. |
| Licensing: "All data dictionary views beginning with the prefix DBA_HIST_ are part of this pack" (Diagnostics), except `DBA_HIST_SNAPSHOT`, `_DATABASE_INSTANCE`, `_SNAP_ERROR`, `_SEG_STAT`, `_SEG_STAT_OBJ`, `_UNDOSTAT`. `V$ACTIVE_SESSION_HISTORY` and `DBMS_WORKLOAD_REPOSITORY` are Diagnostics. | Every historical source proposed here needs Diagnostics Pack. That is authorized for the demo, but must be gated. |

---

## A. SQL-family design

### A.1 Principle

A *family* is a workload-grouping claim at a stated tier. It is never an assertion of application semantics unless confirmed outside Oracle. Plan hash, module/action, objects or time co-occurrence form a **cohort**, never a family (consistent with V3 `family_group`: "never merge alone").

### A.2 Tiers

| Tier | Name | Requirements (all must hold) | Establishes | Does not establish |
| --- | --- | --- | --- | --- |
| C | Cohort | Shared plan hash, module/action/service, objects or time window | Co-occurrence worth examining | Any statement identity |
| F1 | Candidate family | Same non-zero `FORCE_MATCHING_SIGNATURE` from any source, **or** the same *loose* OraProbe template (A.4) | Lexically similar statements | Same object resolution, same semantics, complete membership |
| F2 | Strongly supported family | Same *strict* OraProbe template hash (A.4) for every member; normalization status `ok` from **full** SQL text; same statement type; same literal-type vector; identical values at semantic-risk literal positions; same `PARSING_SCHEMA_NAME` (or every identifier resolved to the same dictionary objects); **plus at least one corroboration**: same non-zero FMS, overlapping executed-plan object set, or same module/action | Same statement template under the same name resolution, differing only in ordinary literal values; valid for **aggregating resource demand** | Application-level equivalence; equal cost behavior (literal values can select very different volumes) |
| F3 | Confirmed family | F2 **plus** a recorded external confirmation: an application equivalence record (same generating code path or report ID) or a DBA confirmation with author and time | Semantic equivalence for remediation scope ("one fix covers all members") | Nothing beyond F2 about cost or causation |

**Split rules (counter-evidence).** Any of the following splits a member out, or creates a subfamily:
- different parsing schema with different resolved objects;
- different statement type;
- literal-type mismatch at the same position;
- different values at a semantic-risk literal position;
- truncated or unparseable text.

**Plan hash never splits or merges.** Different plans inside an F2 family are recorded as plan strata. That is exactly the literal-sensitivity evidence CUR-001/CUR-004 need.

**Selectivity strata.** Within F2/F3, members are stratified by literal value class and by observed per-execution cost band. Baselines compare like strata (existing `baseline_policy`).

**Members seen only in ASH** (FMS known, no text captured) are capped at **F1** and listed as `unverified_member`.

### A.3 What each tier unlocks (purpose matrix)

| Use | Minimum tier | Below the minimum |
| --- | --- | --- |
| FAM-001 derived fact | F2 | Reported as candidate cohort; FAM-001 stays UNKNOWN |
| Family aggregate demand: FAM-002/003/005, EXT-001, `family_cpu_share`, `group_cpu_share`, TEMP by family | F2 | Values reported as cohort figures; existing `indirect_family_cap` (40) applies; no family-grain TRUE |
| FAM-004 common dependency | F2 plus dependency evidence (A.5) | Object coincidence only |
| Recommendation scoped to "all members" | F3 | Recommendation scoped per template / per SQL_ID |

### A.4 Is a full SQL parser required for the first implementation? **No.**

A **deterministic lexical normalizer** (a tokenizer, not a grammar parser) is sufficient for F1/F2 and for lexical dependency references. A parser remains necessary for the AST-based rules (SUBQ-*, PRED-001/002, DATA-001/002, PART-001 requested partitions) and for equivalence across reordered predicates. Those stay UNKNOWN, as V3.1 already handles.

**Normalizer specification** (design only; not implemented here):

1. **Input**
   - Full text only: `V$SQL.SQL_FULLTEXT`, `DBA_HIST_SQLTEXT.SQL_TEXT` (CLOB), or `V$SQL_MONITOR.SQL_TEXT` only when `IS_FULL_SQLTEXT='Y'`.
   - Truncated text gives `truncated`, which prevents F2.
2. **Lexing** follows Oracle SQL lexical rules:
   - Text literals, including `''` escapes, `N'…'` and alternative quoting `q'<delim>…<delim>'`.
   - Numeric literals, including decimals, exponent and `f/F/d/D` suffixes.
   - `DATE '…'`, `TIMESTAMP '…'` and `INTERVAL '…' <unit>` as single typed literals.
   - Bind placeholders `:name` and `:n`.
   - Quoted identifiers preserved exactly; unquoted words uppercased; whitespace collapsed.
   - `--` and `/* */` comments removed. Optimizer hints `/*+ … */` and `--+` are kept verbatim as opaque tokens and never normalized.
   - **Any lexing ambiguity** (unterminated literal, unknown q-delimiter, PL/SQL block) gives `unparseable`. That member stays a SQL_ID singleton.
3. **Literal handling**
   - Each literal becomes a typed placeholder (`<STR>`, `<NUM>`, `<DATE>`, `<TS>`, `<INTERVAL>`).
   - A literal vector records position, type, value and context class.
4. **Semantic-risk literal positions** (detected from preceding tokens): ordinal `ORDER BY`/`GROUP BY` positions, `ROWNUM` comparisons, `FETCH FIRST/NEXT n`, `OFFSET n`, `SAMPLE (n)`.
   - At these positions the literal **value stays in the strict template**, so differing values split the family.
   - An uncertain context is treated as risk (conservative).
5. **Outputs**
   - `strict_template_hash`;
   - `loose_template_hash`: the same, plus literal IN-lists collapsed to one placeholder. Used **only** for F1, because IN-list length changes produce different strict templates;
   - literal vector;
   - bind positions;
   - identifier set (identifiers outside literals and comments);
   - statement keyword;
   - `normalization_status ∈ {ok, truncated, unparseable, unsupported_statement_type}`;
   - normalizer version.

**It can establish:**
- two texts are identical up to whitespace, unquoted case, non-hint comments and ordinary literal values;
- where the literals sit and what types they are;
- which identifier tokens appear (e.g. `PS_C_FEED_DEF_V`).

It handles mixed literal and bind statements, which FMS does not transform.

**It cannot establish:**
- name resolution: which schema object an identifier binds to;
- whether an identifier is a table, view, alias, column or function;
- equivalence of reordered or rewritten SQL;
- semantics of literals outside the risk list (e.g. a literal steering a `CASE` branch);
- PL/SQL or dynamic-SQL provenance;
- view definitions changing over time.

It never claims its hash equals Oracle's signatures; Oracle's signature algorithm is not documented.

### A.5 Dependency evidence (for `PS_C_FEED_DEF_V`)

Graded, highest first:

1. `V$OBJECT_DEPENDENCY` for cached cursors. This is the cursor's recorded dependency, and it should show the view even if merged. It joins on `FROM_ADDRESS`/`FROM_HASH`. Lab-verify the join and that views appear.
2. A lexical identifier in full text, resolved through `PARSING_SCHEMA_NAME` against dictionary objects and synonyms. This needs `DBA_OBJECTS`/`DBA_SYNONYMS`, which are not yet audited.
3. `DBA_DEPENDENCIES`/`DBA_VIEWS` for the view's closure down to base objects. Already allowlisted.
4. `DBA_HIST_SQL_PLAN.OBJECT#` intersected with that closure. Already allowlisted columns, plus `OBJECT#`.

FAM-004 "common dependency" requires grade 1, or grade 2 resolved. Grades 3 and 4 alone remain object coincidence.

---

## B. Historical Resource Manager design

### B.1 What exists historically

| Source | Granularity | Retention | RAC semantics | Licensing |
| --- | --- | --- | --- | --- |
| `DBA_HIST_RSRC_PLAN` | Plan activation intervals (`START_TIME`/`END_TIME`), captured each snapshot | AWR retention (default 8 days, configurable) | Per `INSTANCE_NUMBER`; plans can differ per instance | Diagnostics |
| `DBA_HIST_RSRC_CONSUMER_GROUP` | Cumulative counters per snapshot; deltas give per-snapshot-interval values (default 1 h) | AWR retention | Per instance, per `SEQUENCE#` (plan activation); reset on restart or plan change | Diagnostics |
| `DBA_HIST_RSRC_METRIC` | 1-minute rows per group | **Unclear**: documentation intro says "for the past hour". Must lab-verify whether minute rows persist for full AWR retention. | Per instance | Diagnostics |
| `DBA_HIST_PARAMETER` (`cpu_count`, `resource_manager_plan`) | Per snapshot | AWR retention | Per instance | Diagnostics |
| `DBA_HIST_OSSTAT` (`RSRC_MGR_CPU_WAIT_TIME`, `NUM_CPUS`, `BUSY_TIME`, `IDLE_TIME`, `OS_CPU_WAIT_TIME`, `LOAD`) | Cumulative per snapshot, except `LOAD`/`NUM_CPUS` which are instantaneous | AWR retention | Per instance; host-wide OS values for that instance's host. Several stats are OS-dependent. | Diagnostics |
| `DBA_HIST_SYSTEM_EVENT` (`resmgr:cpu quantum`) | Cumulative per snapshot | AWR retention | Per instance | Diagnostics |
| `DBA_HIST_ACTIVE_SESS_HISTORY` (`CONSUMER_GROUP_ID`, event, `SESSION_STATE`, `TM_DELTA_CPU_TIME`) | Persisted sample subset | AWR retention | Per instance | Diagnostics |

**Unit caveat.** `CONSUMED_CPU_TIME` is documented in ms. `CPU_WAIT_TIME` has **no unit stated** in `DBA_HIST_RSRC_CONSUMER_GROUP`; it is ms in `DBA_HIST_RSRC_METRIC`. Lab verification is required before computing a wait share from the consumer-group view.

### B.2 What it can establish historically

1. **The plan and caging state in force during the window, per instance:** `DBA_HIST_RSRC_PLAN` plus `DBA_HIST_PARAMETER.cpu_count`.
2. **Per instance, per group, per snapshot interval:** consumed CPU seconds and Resource Manager CPU wait seconds. That gives `rm_wait_share = wait / (wait + consumed)` as an **interval average**. This is enough to make RM-001 detection evaluable historically.
3. **Caged-capacity utilization per interval:** total group consumed CPU / (interval seconds × historical `CPU_COUNT`). This distinguishes "database used its caged allocation" from "database was idle".
4. **Host context per interval:** host busy fraction from `BUSY_TIME/(BUSY_TIME+IDLE_TIME)`, `OS_CPU_WAIT_TIME`, and `LOAD` vs `NUM_CPUS`.
   - High Resource Manager wait while the host has idle CPU supports **caging or group policy** (RM-002/RM-003) over **host contention** (RM-004).
   - A busy host leaves both open.
5. **Sampled per-group timeline:** ASH `CONSUMER_GROUP_ID` with `resmgr:cpu quantum` vs ON CPU, at persisted-sample resolution, for onset ordering (TIME-002). This is lower-bound and sampled.
6. **Observed group mapping of a family:** the consumer groups in which the family's sampled sessions ran. This is required because `DBA_HIST_SQLSTAT` carries no consumer group.

### B.3 What it cannot establish

- Peaks shorter than the snapshot interval. Hourly averages smear spikes, unless `DBA_HIST_RSRC_METRIC` minute rows are retained.
- Exact CPU consumed by a given SQL **inside** a group. SQLSTAT has no group, and ASH ON CPU is not consumed CPU. Persisted-ASH `TM_DELTA_CPU_TIME` windows do not tile time, so they cannot be summed to totals. They are usable only as per-sample CPU rates.
- Exact counts of waiting sessions at an instant.
- Which **other database** consumed host CPU. Host busy minus this instance's CPU shows only that *some* other consumer existed.
- Intervals crossing an instance restart or plan change (`SEQUENCE#` change). Those are UNKNOWN.

---

## C. Historical signature and SQL-family coverage design

### C.1 Which historical sources preserve what

| Source | SQL_ID | FMS | EMS | Plan | Module / action | Service | SQL text | Coverage character |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `V$SQL` (current) | yes | yes | yes | plan hash | yes | yes | full | Cursor cache only; not historical |
| `DBA_HIST_SQLSTAT` | yes | yes | **no** | plan hash | yes | **no** | no | Top-N per criterion per snapshot, unless `MAXIMUM`/colored; cursor-cache at snapshot only |
| `DBA_HIST_SQLTEXT` | yes | – | – | – | – | – | full (CLOB) | For SQL captured in the repository |
| `DBA_HIST_SQL_PLAN` | yes | – | – | full plan lines incl. objects/predicates | – | – | – | For captured SQL |
| `DBA_HIST_SQL_BIND_METADATA` | yes | – | – | – | – | – | – | Bind positions/types for captured SQL |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | yes, plus `TOP_LEVEL_SQL_ID` | yes | no | `SQL_PLAN_HASH_VALUE`, plan line | yes | `SERVICE_HASH` (with `DBA_HIST_SERVICE_NAME`) | no | Activity-weighted persisted sample subset; **not** top-N biased, but sampled |
| `DBA_HIST_REPORTS(_DETAILS)` SQL Monitor | `KEY1` | lab-verify XML | lab-verify XML | per line | lab-verify | lab-verify | lab-verify | Only most expensive completed monitored statements |
| `DBA_HIST_COLORED_SQL` | colored IDs | – | – | – | – | – | – | Shows which IDs were force-captured |

### C.2 AWR top-SQL capture bias

A literal-SQL family is the worst case for top-N capture. Each member can be individually small while the family as a whole dominates. Members fall below every top-N criterion, so `DBA_HIST_SQLSTAT` **under-counts family demand, and can miss the family entirely**. Even `TOPNSQL=MAXIMUM` or coloring misses members that aged out of the cursor cache between snapshots.

### C.3 Coverage evidence and the correct UNKNOWN behavior

**New family coverage metrics per window and instance** (proposed):
- `family_ash_members`: distinct member SQL_IDs seen in persisted ASH, matched by FMS or template.
- `family_sqlstat_capture_share`: ASH-weighted activity of members that *have* SQLSTAT rows, divided by ASH-weighted activity of all members. This is a sampled estimate of how much of the family's activity the SQLSTAT aggregates cover.
- `family_text_capture_share`: the same, for members with `DBA_HIST_SQLTEXT`. It determines how many members can reach F2.
- The capture settings in force (`TOPNSQL` from `DBA_HIST_WR_CONTROL`, already allowlisted, plus colored SQL) are recorded in `capability`.

**Bounded-value semantics** (proposed contract addition; it also serves D):
- Every metric value may carry `lower_bound` and/or `upper_bound`, with `bound_kind ∈ {exact, lower_bound, upper_bound, interval, sampled_estimate, interval_average}`.
- Comparisons then follow interval logic:
  - `gt`/`ge`: TRUE if lower > bound; FALSE if upper ≤ bound; otherwise UNKNOWN.
  - `lt`/`le`: TRUE if upper < bound; FALSE if lower ≥ bound; otherwise UNKNOWN.
- This is compatible with the existing true/false/unknown logic.
- Examples:
  - A family CPU **lower bound** from incomplete SQLSTAT can prove "family demand > bound".
  - It can never prove "≤ bound", so it can never support HEALTH-001/002.
  - A ratio whose numerator is a lower bound and whose denominator is exact is a lower bound. If both are bounds in the same direction, the result is UNKNOWN unless both are bracketed.

**Rules:**
- When `family_sqlstat_capture_share` is below a configured coverage bound (threshold profile, null until calibrated), every family aggregate is marked `incomplete` with `bound_kind=lower_bound`.
- If no ASH evidence exists to estimate coverage, the aggregate is `incomplete` with unknown coverage. Only `gt` comparisons on its lower bound may evaluate.
- Missing members are never treated as zero.

---

## D. Historical TEMP and concurrency design

| Quantity | Best historical source | What Oracle provides | Classification |
| --- | --- | --- | --- |
| **A. TEMP per execution** | AWR SQL Monitor report (when captured): per-line, per-process maximum TEMP | Measured maxima per line and process, but they need not coincide in time | **Upper bound** of the execution's simultaneous peak (sum of maxima) |
| | Persisted ASH `TEMP_SPACE_ALLOCATED` summed over the execution's sessions (QC + PX via QC identity) at each sample instant, then max | Session TEMP at sampled instants | **Sampled lower bound** |
| | Combined | Report and ASH for the same execution | **Interval [ASH lower bound, report upper bound]** |
| | `DBA_HIST_SQLSTAT` | No TEMP column (write deltas include, but do not isolate, TEMP) | **Unavailable** |
| **B. Concurrent executions** | Persisted ASH: distinct execution keys (QC dedupe) per sample instant | Active (non-idle) sessions only; persisted portion undocumented | **Sampled lower bound** of instantaneous concurrency; executions idle between fetches are invisible |
| | Reconstructed ASH intervals `[SQL_EXEC_START, last sample]` overlap | Shortened intervals | **Lower bound** of overlap |
| | `DBA_HIST_SQLSTAT` `ELAPSED_TIME_DELTA / interval` | Average DB time per second (includes PX) | **Interval average** of active load; **not** an execution count or peak |
| | Exact peak concurrency | – | **Unavailable** |
| **C. Simultaneous TEMP occupancy** | Persisted ASH: sum of `TEMP_SPACE_ALLOCATED` over all sessions per sample instant, per instance; cluster = sum of instances at aligned instants within spacing tolerance | Sampled active sessions only; sessions holding TEMP while idle are not sampled | **Sampled lower bound**; exact peak **unavailable** |
| | `DBA_HIST_TBSPC_SPACE_USAGE` | Snapshot-instant used size; TEMP coverage undocumented | **Lab-verify**; at most a snapshot-instant value, never a peak |
| | Alert-log ORA-1652 (external) | Proves exhaustion occurred at a time | Strong point evidence; **can wait** (external provider) |
| **D. TEMP by SQL family** | Persisted ASH TEMP per instant grouped by member SQL_ID (FMS/template), with `TOP_LEVEL_SQL_ID` and `IS_SQLID_CURRENT` checks | Session TEMP is attributed to the session's *current* SQL, which may not be the allocating cursor | Bytes: **sampled lower bound**. Share of total at the same instant: **sampled estimate**. Membership tier applies (A.3). |

**Explicitly not derivable:**
- Per-operation TEMP without a monitor report.
- One-pass vs multipass per execution historically. `DBA_HIST_SQL_WORKAREA_HSTGRM` is instance-wide cumulative histograms only.
- The 8 GB × N projection, which remains forbidden (`demand_policy`).

---

## E. Resource Manager ownership — recommendation: **C, shared evidence-provider model**

**Recommended architecture:**

```
Diagnostic knowledge (catalog rules, one owner each)      Evidence providers (shared core, no diagnosis)
  Query Tuner pack      ─┐                                   sql_history   (SQLSTAT/SQLTEXT/SQL_PLAN)
  Database Health pack  ─┼─ orchestrator ── evidence ID ───> ash           (V$/DBA_HIST ASH)
  OS / RAC / DG / RMAN  ─┘   requests + session cache       resource_mgr  (RSRC_* views, parameters)
                                                            oracle_host   (OSSTAT)
                                                            os_telemetry  (OS module, future)
```

- **Providers** own predefined read-only queries, normalization into catalog evidence tables, licensing/capability gates, coverage, `bound_kind` and provenance. They hold **no thresholds and no rules**. They are shared code in the core, owned by no diagnostic module.
- **Knowledge has exactly one owner.** RM-001…006 are resource-allocation knowledge and belong to the **Database Health** knowledge pack. Query Tuner rules reference them **by rule ID** (cross-pack references through causal edges and `cross_module_requests`); they never copy them.
- **Because the engine is catalog-driven,** "the Database Health pack" in the demo is the same generic engine evaluating RM-* plus the `resource_mgr` provider. No Database Health *module code* is needed for the demo, and nothing is duplicated when that module arrives.
- **The orchestrator caches evidence per investigation session.** ASH collected for the Query Tuner is reused by RM rules and later by the RAC and OS modules; it is not re-queried.
- **OS evidence gets two provenances.**
  - `oracle_host` (OSSTAT, available now, coarse, host-level, no per-database attribution).
  - `os_telemetry` (future OS module, per-process attribution).
  - Rules must record which provenance satisfied a counter-search. `oracle_host` can satisfy "host CPU saturated?" at interval granularity; it can never satisfy "which neighbor consumed it?".

**Why not A (Query Tuner collects directly):** RM interpretation would end up embedded in the SQL module and later duplicated in Database Health, OS and RAC.

**Why not B (Database Health only):** the October investigation would be blocked until a whole module exists, even though the evidence is plain read-only views.

---

## F. Exact V3.2 changes recommended

Classification is relative to starting engine implementation. "Audit" means the column list must be checked against the 19c Reference before allowlisting; items already audited in this research are marked ✓.

| ID | Change | Class |
| --- | --- | --- |
| **V32-01** | **Family tier contract.** Add `contract.family_policy`: tiers C/F1/F2/F3, split rules, purpose matrix (A.3), unverified-member rule. Redefine `membership: validated` in `family_member_count`, `family_cpu_share`, `group_cpu_share`, `common_path_work`, `family_temp_share` as "tier ≥ F2", with the tier recorded on each finding. | **MUST HAVE BEFORE ENGINE** |
| **V32-02** | **Lexical normalizer capability contract.** New evidence `sql_template`: `strict_template_hash`, `loose_template_hash`, literal vector, bind positions, identifier set, statement keyword, `normalization_status`, normalizer version. Add operator semantics for `family_group` tiers. Specification only; implementation is engine work. | **MUST HAVE BEFORE ENGINE** |
| **V32-03** | **Bounded-value semantics.** Add evidence envelope fields `lower_bound`, `upper_bound`, `bound_kind`, and interval comparison rules in `unknown_policy`. Ratio bound propagation. | **MUST HAVE BEFORE ENGINE** (changes the evaluator core) |
| **V32-04** | **Shared evidence-provider contract.** Add `contract.provider_policy`; mark RM-001…006 `knowledge_owner: database_health`, referenced not copied. `DB-RESOURCE` becomes provider-served (`resource_mgr`) in the demo. Providers emit coverage, `bound_kind` and provenance. | **MUST HAVE BEFORE ENGINE** (architecture boundary) |
| **V32-05** | **Historical signature sources.** Extend `DBA_HIST_SQLSTAT` columns (`FORCE_MATCHING_SIGNATURE`, `MODULE`, `ACTION`, `PARSING_SCHEMA_NAME`, `PARSE_CALLS_DELTA`, `END_OF_FETCH_COUNT_DELTA`, `PX_SERVERS_EXECS_DELTA`) ✓. Add `DBA_HIST_SQLTEXT` (`SQL_ID`, `SQL_TEXT`, `COMMAND_TYPE`) ✓. Extend ASH (`FORCE_MATCHING_SIGNATURE`, `TOP_LEVEL_SQL_ID`, `SQL_OPCODE`, `MODULE`, `ACTION`, `SERVICE_HASH`, `PGA_ALLOCATED`) ✓. Add `DBA_HIST_SERVICE_NAME` ✓. Bind `sql.force_signature`, `sessions.*`. All Diagnostics. | **MUST HAVE BEFORE ENGINE** |
| **V32-06** | **Historical Resource Manager sources.** Add `DBA_HIST_RSRC_PLAN` ✓, `DBA_HIST_RSRC_CONSUMER_GROUP` ✓ (`CONSUMED_CPU_TIME`, `CPU_WAIT_TIME`, `CPU_WAITS`, `YIELDS`, `SEQUENCE#`, queue fields) and `DBA_HIST_PARAMETER` ✓ (`cpu_count`, `resource_manager_plan` only), bound to `rm`/`capability`. New metrics: `rm_wait_share_interval` (per instance, per `SEQUENCE#`, delta-based), `caged_capacity_utilization`, `family_observed_group_mapping` (ASH). Record the `CPU_WAIT_TIME` unit as lab-verify. | **MUST HAVE BEFORE ENGINE** |
| **V32-07** | **Family coverage metrics:** `family_ash_members`, `family_sqlstat_capture_share`, `family_text_capture_share`, plus a coverage threshold ID (null). | **MUST HAVE BEFORE ENGINE** |
| **V32-08** | **ASH TEMP and concurrency metrics:** `ash_execution_temp_peak_lb`, `ash_concurrent_executions_lb`, `ash_temp_occupancy_lb` (instance and cluster-aligned), `ash_family_temp_lb`, `ash_family_temp_share`. Rebind `peak_temp_occupancy`/TEMP-004/FAM-003 attribution to accept `lower_bound` (provable only for `gt`). New estimate kinds `monitored_max_upper_bound`, `interval_average`. | **SHOULD HAVE BEFORE ENGINE** |
| **V32-09** | **Oracle-recorded host context:** add `DBA_HIST_OSSTAT` ✓ (`RSRC_MGR_CPU_WAIT_TIME`, `NUM_CPUS`, `BUSY_TIME`, `IDLE_TIME`, `OS_CPU_WAIT_TIME`, `LOAD`; OS-dependent ones flagged), bound to `os` with provenance `oracle_host`. Satisfies RM-004 host-saturation counter-search at interval granularity only. | **SHOULD HAVE BEFORE ENGINE** |
| **V32-10** | **Dependency grades** (A.5): add `V$OBJECT_DEPENDENCY` ✓ and `DBA_OBJECTS`/`DBA_SYNONYMS` (audit), plus `V$SQL.ADDRESS`/`HASH_VALUE` (audit) for the join; `DBA_HIST_SQL_PLAN.OBJECT#` ✓. FAM-004 requires grade 1 or resolved grade 2. | **SHOULD HAVE BEFORE ENGINE** |
| **V32-11** | `DBA_HIST_RSRC_METRIC` ✓ for minute-level group running/waiting/utilization, **gated on lab verification of retention**. | **CAN WAIT** (lab-gated) |
| **V32-12** | `DBA_HIST_SYSTEM_EVENT` ✓ (`resmgr:cpu quantum`, instance-level cross-check) and `DBA_HIST_COLORED_SQL` ✓ (coverage note). | **CAN WAIT** |
| **V32-13** | `DBA_HIST_SQL_BIND_METADATA` ✓ (bind type vectors, to strengthen F2 for bind-bearing members); `DBA_HIST_TBSPC_SPACE_USAGE` ✓ (TEMP coverage lab-verify); ORA-1652 alert-log external provider. | **CAN WAIT** |
| **V32-14** | Guidance only, outside OraProbe's read-only actions: DBA-side preventive AWR settings (`TOPNSQL`, `ADD_COLORED_SQL` for known families, retention) to improve future coverage. These are configuration changes and are never executed by OraProbe. | **CAN WAIT** |

**Lab-verification items these changes create:**
- `DBA_HIST_RSRC_CONSUMER_GROUP.CPU_WAIT_TIME` unit;
- `DBA_HIST_RSRC_METRIC` retention;
- `V$OBJECT_DEPENDENCY` lists merged views and joins to `V$SQL`;
- `DBA_HIST_TBSPC_SPACE_USAGE` covers TEMP;
- SQL Monitor report XML contains signatures and per-line TEMP maxima;
- persisted-ASH per-instant completeness;
- OS-dependent `V$OSSTAT` stats on RHEL 8.

---

## G. October acceptance improvement

What becomes **testable** with each change (historical incident, demo). "Testable" means the rule can be evaluated; the outcome is not presumed.

| Walkthrough step | V3.1 status | Change(s) | Newly testable | Ceiling |
| --- | --- | --- | --- | --- |
| 1. Literal SQL_IDs | Raw count only | V32-05, 07 | Distinct members seen in ASH by FMS or template; SQLSTAT capture share for them | Count of *observed* members (lower bound) |
| 2. Logical family | UNKNOWN (no parser) | V32-01, 02, 05 | F1 via ASH/SQLSTAT FMS; **F2** for members with captured full text, same template and schema; CUR-006 detection can evaluate at F2 | F2; F3 only with an application/DBA confirmation |
| 3. `PS_C_FEED_DEF_V` | Object coincidence | V32-02, 10 | Lexical reference in captured text, resolved via parsing schema (grade 2); grade 1 only if cursors are still cached | FAM-004 detection at grade 2; "shared path is expensive" still needs plan-line actuals |
| 4. ~1M rows | Monitor reports only | – (V3.1 P2/P3 already) | Unchanged | Unchanged |
| 5. >8 GB TEMP / execution | ASH lower bound | V32-08 | Bracket [ASH lower bound, report upper bound] where a report exists; "≥ X GB" provable as a lower bound | Operation still unnamed without a report |
| 6. Concurrency | Lower bound; FAM-003 attribution UNKNOWN | V32-03, 08 | Instant concurrency and cluster TEMP occupancy as lower bounds; FAM-003/TEMP-004 `gt` comparisons can become TRUE if the lower bound exceeds the profile value | Never an exact peak; never "occupancy ≤ budget" |
| 7. Aggregate CPU | Cohort, config-blocked | V32-01, 03, 05, 07 | F2 family CPU from SQLSTAT as a **lower bound**, with capture share; ASH-sampled share of DB time | `gt` comparisons only; coverage stated |
| 8. RM pressure | UNKNOWN historically | V32-04, 06, 09 | Plan/caging and `CPU_COUNT` in force; per-interval group consumed CPU vs Resource Manager wait (RM-001 detection); caged-capacity utilization; host busy vs idle distinguishes RM-002/003 from RM-004 at interval granularity | Hourly averages unless V32-11 verifies minute retention |
| 9. ~1,159 waiters | Lower-bound distinct sessions | – | Unchanged; additionally the instance-level wait totals (V32-12) | The 1,159 instant figure remains unreproducible |
| 10. Contributor vs victim | Unresolved | V32-01, 03, 06 | FAM-005 detection: F2 family CPU lower bound / group consumed CPU (group mapping from ASH) can prove share > bound; RM-005 attribution: victims' own SQLSTAT work and CPU **if captured** | Contributor candidate and victim role can become evaluable; still capped at 40 if the OS counter-search is only `oracle_host` and the profile requires per-database attribution |
| 11. Trigger chain | Untestable | V32-06 (onset at interval level), V32-11 (minute level) | TIME-002 order between family demand and Resource Manager wait at snapshot or minute granularity | **TIME-001 stays untestable**: no change record; the rollover is an application event |

**Expected October outcome after V3.2, if the evidence turns out as the narrative claims:**
- **Possible:** F2 family; family CPU share above the bound (lower bound); interval Resource Manager pressure under caging with spare host CPU; victims with unchanged own work. These can be **ranked candidate contributor and victim findings**.
- **Still blocked:** `supported_cause` stays blocked by `comparable_control` (needs a matched prior month-end or a validation) and by `compatible_temporal_order` (hourly onsets may straddle). The **trigger stays unprovable**.
- **Outcome:** "plausible, partially supported, unresolved". Contradictory evidence instead would weaken or refute specific links. Either outcome is acceptable.

---

## H. Fundamentally unprovable from historical Oracle evidence

1. **Application-level semantic equivalence** of family members. Only the application owner or a reviewing DBA can confirm it (F3).
2. **The business trigger** (month-end/control-table rollover) as a cause. Oracle can show activity of identifiable SQL, but not the business event or its intent without an external change record.
3. **Exact peaks:** per-execution TEMP, simultaneous TEMP occupancy, instantaneous concurrency, instantaneous waiter count (the ~1,159 figure). Oracle history provides sampled lower bounds, interval averages and monitor-report upper bounds only.
4. **Sub-snapshot Resource Manager dynamics,** unless minute-level `DBA_HIST_RSRC_METRIC` retention is verified.
5. **Exact CPU per SQL inside a consumer group,** and the CPU of SQL never captured by AWR, including members that aged out before a snapshot.
6. **Which other database or process consumed host CPU** on shared RAC hosts. That needs the OS module or each neighbor's own repository.
7. **The counterfactual:** "victims would have been fine without the family". It needs a controlled comparison (another month-end, a replay or a lab trial).
8. **Plan-line behavior** of executions without a captured SQL Monitor report: rows, starts, spilling operation, pass count.
9. **Text-dependent facts** for SQL_IDs whose text was never captured. They remain FMS-only F1 members.
10. **Representativeness of persisted ASH,** because Oracle does not document how the persisted portion is selected. All persisted-ASH counts stay lower bounds or sampled estimates.
11. **End-to-end user impact.** It needs application telemetry (V3.1 HEALTH-002 wording applies).
