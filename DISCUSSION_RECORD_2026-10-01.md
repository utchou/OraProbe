# OraProbe discussion record — 2026-10-01

This is a consolidated summary of the conversation and its decisions, not a verbatim transcript. User requirements are distinguished from proposed design details. Read this alongside PROJECT_CONTEXT.md, DEMO_SCOPE.md, and QUERY_TUNER_REQUIREMENTS.md.

## Naming and status

- User named the product **OraProbe**, replacing the earlier OraProble name. The workspace remains C:\OraProble; no directory rename was requested.
- Work is at requirements and design stage. No diagnostic application has been implemented or tested yet.
- Research and a concrete design proposal precede implementation; the original instruction requires agreement on the design before coding.
- The original bootstrap context is preserved in PROJECT_CONTEXT.md.

## Product principles

- Deterministic first, LLM last. Python performs collection, analysis, hypothesis testing, elimination, correlation, and explainable scoring.
- AI receives structured findings for synthesis and conversation, not unrestricted production execution control.
- Production investigation is read-only through predefined capabilities. Fixes are recommendations, not automatic modifications.
- Oracle expertise remains independent of LLM provider, LangChain, and MCP implementation. Integration adapters are replaceable.
- The reported database may be a victim of another workload or shared infrastructure. Correlation alone does not establish causation.
- Evidence gaps, uncertainty, and competing explanations must remain visible. Comprehensive scope does not imply guaranteed diagnosis of every incident.

## Immediate demo requirements confirmed by user

- Develop on the personal machine, then transfer code into the company environment and run locally on an OraaS POC database server.
- Start with Query Tuner plus only the shared core needed for meaningful standalone reporting.
- User authorizes local `/ as sysdba` access for predefined read-only diagnostic collection. The privileged connection itself does not enforce read-only behavior.
- Use relevant DBA, V$, GV$, ASH, and AWR evidence. User confirms full licensing and asks that licensing not be a repeated blocker.
- No runtime internet, central inventory service, or LLM API dependency.
- Accept local Excel inventory for primary/standby host mapping. Inventory DB integration follows availability/approval. Automatic full configuration discovery is deferred beyond the demo.
- User inputs database name, SQL ID, incident time/window including timezone, and optional symptoms.
- No representative SQL is currently supplied. Use fixtures during development, followed by controlled degraded-SQL scenarios and repeated live personal-lab validation. A running Oracle lab and its version have not yet been verified.

## Query Tuner expected outcomes

- Investigate both runtime and historical degradation.
- Establish whether slowdown occurred using adequate, comparable evidence.
- Distinguish: supported degradation; no observed degradation with adequate coverage; and insufficient evidence.
- Examine SQL-local and external causes, including plans, statistics, access paths, workload differences, blocking, CPU, storage, competing SQL, backups, waits, and configuration.
- Request additional evidence via the shared orchestrator when another domain is implicated.
- Where a module is not implemented, report the missing capability and next test. Never imply it ran or ruled out a cause.
- Produce an HTML RCA with evidence, hypotheses, alternatives, confidence rationale, gaps, and recommended actions. Preserve structured evidence for repeatable analysis.

## Proposed module boundaries discussed

These are the architectural module proposal discussed with the user, not completed implementations or a final detailed design approval.

1. Query Tuner — SQL execution performance, plans, cardinality, statistics, binds, parsing, and SQL-specific waits.
2. Database Health & Resources — database-wide performance, memory, limits, resource management/caging, redo/commit/checkpoint behavior, parameters, and database availability evidence.
3. Blocking & Transactions — blocking chains, deadlocks, long transactions, contention, and impact.
4. Connectivity & Services — listener/services, failed or slow connections, disconnects, authentication, and pool evidence where available.
5. OS & Noisy Neighbors — CPU, memory, process states, consumption attribution, and competing workloads.
6. RAC & Clusterware — global cache, cluster services, imbalance, interconnect symptoms, evictions, and cluster availability.
7. Storage & Capacity — ASM, I/O, paths, filesystems, tablespaces, TEMP, UNDO, and FRA.
8. Network — relevant public, cluster, storage, and replication paths.
9. Data Guard — transport/apply, gaps, standby recovery, role transitions, and primary/standby dependencies.
10. RMAN & Recovery — backup, restore, duplicate, recovery, channels, and source/destination bottlenecks.
11. Jobs, Changes & Lifecycle — scheduler/batch, maintenance, changes, patching, provisioning, cloning, and refresh workflows.
12. Replication / GoldenGate — replication health, lag, failures, and data freshness.

Cross-cutting concerns: CDB/PDB scope, application response time, configuration/change timelines, availability, internal errors, corruption, and authentication/security configuration. These are coordinated across relevant modules rather than automatically creating separate modules.

## Proposed shared foundation

- Request and structured investigation session.
- Inventory and dependency topology.
- Controlled collection with validated inputs, timeouts, and limits.
- Evidence store with scope, provenance, timestamps, and gaps.
- Orchestrator for module routing, evidence reuse, and bounded expansion.
- Hypothesis testing, timeline/cross-layer correlation, and explainable scoring.
- Standalone reporting; future UI, AI synthesis, and MCP integration outside core diagnostic logic.

## Specific coverage questions resolved in discussion

### UNDO

- Explicit coverage spans Storage & Capacity, Blocking & Transactions, Database Health, and Query Tuner.
- Include space pressure, consuming transactions, retention/configuration evidence, and read-consistency failures such as ORA-01555.
- Do not automatically infer that increasing UNDO is the fix. Research and test the relevant hypotheses.

### Row lock contention

- Core Blocking & Transactions responsibility, invoked by Query Tuner as needed.
- Assistant proposed basic row-lock investigation in the demo; deeper concurrency analysis expands later.
- Identify waiting sessions, root blocking transaction, chains across RAC, incident overlap, and object/row evidence where available.
- Current blocker SQL may differ from the statement that acquired the lock.
- Historical reconstruction is limited by retained evidence. No automatic session killing, commit, or rollback.

### Wait-event routing and coverage

- Proposed central routing catalog maps events/symptoms to hypotheses, evidence requirements, and responsible capabilities.
- Events can route to multiple modules; errors, metrics, plans, and configuration can also activate investigation.
- Discover all exposed event definitions from V$EVENT_NAME rather than hard-code an assumed count.
- Distinguish recognition of all exposed events, generic contextual analysis, and researched/tested specialist diagnosis.
- A wait class is a starting direction, not proof of root cause. Unknown events must remain visible with a diagnostic coverage gap.
- Maintain a coverage matrix for recognition, routing, hypotheses, and tests. The initial version cannot honestly promise specialist diagnosis for every event.
- Oracle sources consulted: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-EVENT_NAME.html and https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/oracle-wait-events.html

## Broader incident coverage discussed

The module set aims to cover common database and related infrastructure incidents. Useful results include establishing a cause, localizing the failing layer, or narrowing alternatives. External application, storage-array, network, and platform telemetry may be needed to establish an infrastructure cause. A causal chain can include a trigger, underlying weakness, and amplifying behavior.

No extra module expansion is required before starting the Query Tuner design. Diagnostic depth, known-cause tests, false-conclusion measurement, and transparent unresolved cases are more important than just listing categories.

## Manager-facing image

- User requested a single-page design image, then corrected the name to OraProbe and requested the end product instead of demo phases.
- Current deliverable: OraProbe-Management-Design.png, labeled TARGET END PRODUCT, showing workspace, orchestration, deterministic engine, AI synthesis, reporting, 12 modules, shared foundation, and controlled integrations.
- Current generation prompt: OraProbe-Management-Design-prompt.txt.
- Previous image was replaced. OraProble-Management-Design-prompt.txt is an obsolete prompt retained on disk, not the current design.

## Next deliverable

Prepare the focused shared-core/Query Tuner design and source-backed diagnostic hypothesis catalog for review. Define the first implementation slice and its meaningful tests. Do not treat the high-level diagram as a completed detailed design, a claim of working software, or authorization to skip the agreed design review.
