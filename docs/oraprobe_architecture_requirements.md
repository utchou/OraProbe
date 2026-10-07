# OraProbe architecture requirements

Status: **authoritative** platform architecture and product requirements register. It was recorded on 2026-10-06, and the decisions on conflicts C-1 and C-2 and architecture decisions D-1 to D-6 were approved the same day. D-1 is the pre-engine design gate; D-2 is in AR-01; D-3 and D-4 are under the design-impact candidates; D-5 is AR-12; D-6 is AR-13. Requirements capture only: nothing here is implemented.

## Document map

| Document | Holds |
| --- | --- |
| [PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md) | Original project bootstrap context. §33 is a short summary that points here. |
| This document | Platform requirements AR-01..AR-13, gaps against V3.2, resolved conflicts, future work. **Authoritative where it differs from PROJECT_CONTEXT.md.** |
| [QUERY_TUNER_REQUIREMENTS.md](../QUERY_TUNER_REQUIREMENTS.md) | Query Tuner requirements, including AR-03 plan comparison in full. |
| [DEMO_SCOPE.md](../DEMO_SCOPE.md) | Demo-specific scope, including the AR-06/AR-11 demo interface. |
| [implementation_readiness_v3_2.md](implementation_readiness_v3_2.md) | V3.2 readiness and engine design-note items. |
| [reference/capstone_architecture_reference.md](reference/capstone_architecture_reference.md) | Enterprise GenAI platform (Capstone) integration-boundary principles; non-authoritative and sanitized for public use. |
| [oraprobe_industry_failure_mode_review.md](oraprobe_industry_failure_mode_review.md) | AR-09 failure-mode / best-practice architecture review: traceability, classified actions, potential V3.2 impacts. |
| `OraProbe-Management-Design-prompt.txt` / `OraProbe-Management-Design.png` | Manager-facing image. The prompt was updated to AR-08 on 2026-10-06. **The PNG is outdated/superseded** (it shows MCP on the evidence-collection side) and needs regeneration once the architecture is stable. |

## Frozen baseline

The SQL Tuner V3.2 knowledge baseline (commit `e4b5fe4`) is frozen:
- `knowledge/sql_tuning_catalog_v3_2.yaml`
- `knowledge/sql_tuning_sources_19c_v3_2.json`
- `knowledge/threshold_profiles/v3_2/template.json`

Nothing in this document changes it. Where a requirement will need V3.2 to be extended, the gap is listed under [Gaps against V3.2](#gaps-against-v32) as a future design decision.

## Classification

- **CURRENT:** frozen or current repository state.
- **REQ:** architectural or product requirement, binding on future design.
- **DESIGN:** future design work; a reviewed design is required before code.
- **IMPL:** future implementation work; not yet authorized.
- **ACCEPT:** acceptance or testing requirement.

## Requirement register

### AR-01 Evidence-driven cross-module investigation

A major capability. It extends PROJECT_CONTEXT §17, §21 and §22.

- **REQ:** OraProbe uses evidence or findings from one diagnostic area to find what evidence is missing. It resolves which provider/collector of another area can supply it, collects it where permitted, and re-evaluates the hypotheses:
  `observe -> hypothesize -> identify missing evidence -> resolve which provider can supply it -> collect targeted evidence -> test/eliminate hypotheses -> correlate -> repeat when justified -> conclude or explicitly remain UNKNOWN`.
- **REQ:** this is a first-class Evidence Resolution / Investigation Planner capability (or equivalent). Rules and evidence identify what they need; provider ownership/mapping identifies who can supply it.
- **REQ:** it must not become:
  - "run every collector";
  - an enormous hard-coded if/else routing tree;
  - collectors duplicated inside each module. The V3.2 principle applies: collect once, normalize once, define each canonical fact once, multiple consumers.
- **REQ (decision D-2, 2026-10-06):** hypothesis-driven evidence resolution alone is insufficient. A cause for which no rule generates a hypothesis may never be investigated. The planner therefore combines two paths:
  - **A.** a small, bounded, low-cost baseline survey / anomaly-discovery path;
  - **B.** targeted hypothesis-driven evidence resolution.

  The survey never becomes "run every collector". It is bounded by applicability, cost, safety and the investigation budget. Anomalies it finds without a catalogued hypothesis are reported as observations, never as causes. Rationale: review R-12.
- **Example:**
  1. SQL investigation observes `resmgr:cpu quantum`, so Resource Manager evidence is required.
  2. The Database Health / Resource Manager provider supplies it.
  3. Host CPU evidence may then be required, and the OS provider supplies it.
  4. The evidence is correlated and the diagnosis is re-evaluated.
- **REQ safeguards:**
  - do not recollect evidence that is still sufficiently fresh and valid;
  - invoke another provider only when its evidence can materially resolve an active UNKNOWN or hypothesis;
  - check topology and capability applicability, and current versus historical availability;
  - order collection by cost and safety;
  - enforce a collection budget and an investigation depth limit;
  - apply freshness/cache rules;
  - a provider/collector failure, timeout or denial never becomes FALSE evidence;
  - unresolved evidence remains explicit in results.
- **CURRENT:** V3.2 provides part of the substrate, but there is no planner.
  - Staged rules name their required and optional evidence.
  - `contract.provider_policy` assigns every source to exactly one provider and lists the evidence each provider serves.
  - `cross_module_requests` carry `provider_fulfillment` and `owner_module_required: false`.
  - Statuses and UNKNOWN reasons distinguish `unavailable`, `not_captured`, `unlicensed` and `lab_verification_required`.
- **DESIGN:** planner algorithm and data contract (G-01). **IMPL:** the planner.
- **ACCEPT:** a replayed investigation shows:
  - which evidence was requested and why;
  - which was reused or skipped and why;
  - which provider failures occurred;
  - which UNKNOWNs remain.

### AR-02 Two explicit operating modes

Refines PROJECT_CONTEXT §2, §19, §20, §24 and §26.

- **REQ A, Deterministic Analysis.** OraProbe is a complete, useful product without an LLM:
  - `structured request -> collection -> evidence normalization -> deterministic investigation/diagnosis -> correlation -> findings -> confidence/uncertainty -> recommendations / next evidence -> structured/terminal/HTML output`.
  - An LLM, API, MCP or Capstone outage never disables core diagnostic capability.
  - The LLM stage in the PROJECT_CONTEXT §2 pipeline is optional.
- **REQ B, AI-Assisted Analysis.** It uses the same deterministic pipeline and the same diagnostic truth.
  - The optional LLM may:
    - interpret natural-language intent into the same structured request;
    - explain and summarize evidence and findings;
    - converse and ask questions;
    - make controlled requests for additional approved evidence through the planner.
  - The LLM must not:
    - create a competing diagnostic truth;
    - silently override deterministic evidence;
    - silently change confidence;
    - manufacture missing evidence;
    - convert UNKNOWN into TRUE/FALSE without evidence.
- **REQ:** natural-language understanding is an optional AI-interface capability. Deterministic operation does not need it.
- **DESIGN:** how AI-mode evidence requests enter the planner, and how LLM text stays distinguishable from deterministic findings. **IMPL:** the AI layer (later).
- **ACCEPT:**
  - the same structured request yields identical deterministic findings and confidence with AI assistance on or off;
  - AI output cannot alter findings, confidence or UNKNOWN states.

### AR-03 SQL execution plan comparison and explanation

Specified in [QUERY_TUNER_REQUIREMENTS.md, "Execution plan comparison"](../QUERY_TUNER_REQUIREMENTS.md): requirements, the V3.2 gap (G-02) and the `plan_comparison` acceptance scenario.

### AR-04 Topology-independent core, topology-aware modules

Refines PROJECT_CONTEXT §4, §5 and §13.

- **REQ:** the diagnostic core assumes no particular topology. Without redesigning the core it must eventually support:
  - single-instance Oracle;
  - RAC with any node count;
  - Data Guard or none;
  - asymmetric primary/standby topology;
  - other Oracle environments and topologies.
- **REQ:** OraaS (Citi Oracle as a Service) is the current environment in which OraProbe may operate. It is an environment OraProbe can diagnose; it does not define OraProbe's architecture. **OraProbe must not be architecturally coupled to OraaS's current topology, deployment model, naming conventions, infrastructure, node count or other environment-specific assumptions.** The five-node OraaS grids and the 3-node demo primary/standby are environment descriptions, never assumptions hard-coded into the core.
- **REQ:** prefer a minimal seed inventory. Conceptually:
  - database identifier/name;
  - one reachable primary instance/host;
  - an optional standby seed.
- **REQ:** OraProbe discovers and validates the actual runtime topology and capabilities. Inventory is not blindly trusted. An inventory-vs-discovery mismatch must be capable of becoming diagnostic evidence rather than being silently overwritten.
- **Demo (decision C-2):**
  - Excel/CSV is the demo seed inventory.
  - The demo may perform bounded runtime validation of the selected target database, topology and capabilities after connecting.
  - A mismatch is surfaced as a topology/inventory warning or validation result. It is **not** a V3.2 diagnostic evidence type.
- **CURRENT:**
  - V3.2 `investigation_keys` include `topology_id`.
  - The V3.2 capability record captures database, container and instance identity, RAC topology and instance coverage at investigation start.
  - Sources carry GV$/RAC gates.
  - There is no inventory model, topology discovery or mismatch-evidence model (G-03).
- **DESIGN:** inventory/topology model, discovery, and formal mismatch-as-diagnostic-evidence (G-03). **IMPL:** topology discovery.
- **ACCEPT:** fixtures for:
  - single instance;
  - 2-node and N-node RAC;
  - no standby;
  - asymmetric standby;
  - an inventory/runtime mismatch, which the demo reports as a warning.

### AR-05 Oracle version / capability adaptability

- **REQ:** one common diagnostic core over a version/capability-aware evidence-source layer, with per-version mappings and collectors: Oracle 19c now, Oracle AI Database 26ai as a target direction.
- **REQ:** runtime version/capability discovery decides which sources, views, columns and features are valid. CDB/PDB/multitenant implications are considered.
- **REQ:** no separate diagnostic products and no duplicated diagnostic core.
- **CURRENT:** V3.2 is primarily 19c-oriented.
  - Every rule declares `oracle_versions: 19c`.
  - The source manifest `sql_tuning_sources_19c_v3_2.json` is audited against 19c documentation.
  - The capability record captures `oracle_version` and container identity.
- **DESIGN:** the capability layer (G-04). V3.2 is not rewritten for this. **IMPL:** 26ai mappings and collectors.
- **ACCEPT:** a source, view or column invalid for the discovered version or capability is reported as unsupported, never as absent data or healthy.

### AR-06 Initial demo interface and offline operation

- **REQ:** an interactive Python CLI on the target Unix environment.
  - The CLI only creates structured requests.
  - No browser, web server, internet, LLM, MCP or Capstone dependency.
  - Structured menus/forms; no natural-language keyword parser in deterministic mode.
- **Details:** [DEMO_SCOPE.md](../DEMO_SCOPE.md).
- **IMPL:** CLI and report generation (later).

### AR-07 Headless, presentation-agnostic core

- **REQ:** diagnostic functionality does not depend on OraProbe owning the UI. The same diagnostic core serves all of these through stable programmatic request/result contracts, without duplicating diagnostic logic:
  - the OraProbe CLI;
  - an OraProbe-owned portal;
  - another team's portal;
  - automation;
  - API consumers;
  - MCP/AI consumers.
- **REQ:** portal-specific presentation never leaks into the deterministic core.
- **REQ:** integrating an arbitrary enterprise portal may depend on that portal exposing a supported integration mechanism and on enterprise security/network policy. That is an integration concern, not a reason to redesign diagnostics.
- **DESIGN:** request/result contract (G-05). **IMPL:** API and portals (later).
- **ACCEPT:** the same structured request submitted through the CLI and through a programmatic call produces identical structured results.

### AR-08 Capstone / MCP boundary

Authoritative (decision C-1). It supersedes the earlier PROJECT_CONTEXT §23 diagram.

- **REQ:** Capstone and MCP are future integration/adapter layers. They are not dependencies of:
  - the deterministic core;
  - the initial demo;
  - collectors/providers;
  - diagnostic modules;
  - the evidence model;
  - the deterministic engine.

  The initial demo excludes them.
- **REQ:** MCP/Capstone never sit on the mandatory data-collection path. Collectors/providers are native OraProbe core capabilities. Canonical direction:

  ```
  Portal / Capstone / LLM
          -> MCP adapter/client boundary where applicable
          -> OraProbe Core
          -> Providers / Collectors
          -> Oracle / OS
  ```

- **REQ:** if a future enterprise integration uses MCP or another mechanism to obtain specific evidence, it is an optional adapter behind the provider/collector abstraction. It never becomes a dependency of the deterministic core.
- **REQ:** there is no second SQL Tuner or diagnostic engine inside MCP. Internal contracts remain naturally exposable through MCP/Capstone without redesigning the diagnostic core.
- **CURRENT:** the Capstone architecture was reviewed separately by the project owner; its source material is not stored in this repository. A sanitized, non-authoritative integration-boundary reference (internal details intentionally omitted) is in [reference/capstone_architecture_reference.md](reference/capstone_architecture_reference.md). No MCP is implemented.
- **IMPL:** MCP adapter and Capstone integration (later).

### AR-09 Industry failure-mode / anti-pattern traceability

Applies to all modules.

- **REQ:** at an appropriate future checkpoint, conduct a current industry/research review of known weaknesses of:
  - database troubleshooting tools;
  - performance diagnostic tools;
  - observability platforms;
  - AIOps/RCA products;
  - AI-assisted diagnostic systems.
- **REQ:** maintain traceability in this form:
  `known failure mode -> OraProbe mitigation/design mechanism -> test/acceptance evidence -> remaining limitation/gap -> required action`.
  Anything not adequately addressed stays an explicit limitation or backlog item and is never assumed solved.
- **Seed failure modes** (from the 2026-10-06 request; not exhaustive):
  - false-positive RCA;
  - symptom vs cause confusion; contributor vs victim confusion; correlation mistaken for causation;
  - single-SQL tunnel vision; failure to correlate SQL families or cascading workloads;
  - missing evidence interpreted as healthy; sampling/capture bias; inappropriate/static thresholds;
  - RAC aggregation errors; topology assumptions; Oracle-version assumptions;
  - current-vs-historical inconsistencies; plan-hash overreliance; weak temporal correlation;
  - incomplete incident evidence; stale inventory;
  - collector overhead; privilege/licensing gaps;
  - unsafe recommendations; conflicting rules; configuration drift;
  - poor explainability; non-reproducible diagnoses;
  - AI hallucination / black-box conclusions.
- **DESIGN:** the full current industry/research survey remains future work. A first-pass review with the traceability register (R-01..R-55, classes A–F, potential V3.2 impacts PV-01..PV-08) is in [oraprobe_industry_failure_mode_review.md](oraprobe_industry_failure_mode_review.md) (2026-10-06).

### AR-10 Production-proven diagnostic SQL as design input

- **CURRENT:** production-proven Oracle diagnostic scripts have been supplied externally. They are **not** repository artifacts and are not to be copied into the repository now.
- **REQ:** they are pending structured assessment during collector/provider design. They are reference inputs and are never copied wholesale. For each relevant script/capability, assess:
  - evidence/metric mapping: what it obtains, which module(s) need it, provider/collector ownership, mapping to V3.2 evidence contracts, duplication with planned collectors;
  - reuse versus adaptation versus exclusion;
  - sensitive or environment-specific content;
  - privileges and licensing;
  - Oracle-version and topology assumptions;
  - runtime overhead and production safety.
- **REQ:** only sanitized, reusable material is considered for repository inclusion, and only after that review.
- **DESIGN:** script assessment and mapping, when collector/provider design starts (G-06).

### AR-11 Demo scope versus production architecture

- **REQ:** demo path:
  `CLI -> OraProbe deterministic core -> providers/collectors -> Oracle/OS -> findings/report`.
- **REQ:** future production integrations are additive, and the demo does not depend on them:
  - API;
  - OraProbe portal and other enterprise portals;
  - MCP and Capstone;
  - optional LLM assistance.
- **REQ:** demo-only shortcuts must not fundamentally prevent them. For example:
  - no diagnostic logic in the CLI;
  - no presentation in the core;
  - no collection that bypasses providers.
- **Details:** [DEMO_SCOPE.md](../DEMO_SCOPE.md).

### AR-12 Non-destructive diagnostic operation and session identification

Decision D-5, 2026-10-06. Refines PROJECT_CONTEXT §3.

- **REQ:** OraProbe's diagnostic operation is **non-destructive**. Normal diagnostic collection must not modify application/business data or database configuration. Safety is not defined solely as "SELECT-only".
- **REQ:** any future state-changing remediation capability requires separate explicit authorization and its own safety controls (see review R-33).
- **REQ (direction):** OraProbe identifies its collection sessions, for example MODULE/ACTION via `DBMS_APPLICATION_INFO`. This sets session metadata only and is consistent with non-destructive operation. It is subject to lab, security and privilege validation.
- **IMPL:** not now.

### AR-13 Observer effect / self-contamination

Decision D-6, 2026-10-06.

- **REQ:** OraProbe accounts for its own observer effect. Excluding OraProbe-identified sessions (AR-12) from evidence is necessary but insufficient. A collector itself consumes CPU, I/O and other resources and can indirectly affect application sessions.
- **REQ:** the investigation record's collection log captures, per collection call:
  - collector/query identifier;
  - start/end time and duration;
  - target instance/host;
  - completion or incomplete status;
  - timeout;
  - relevant cost and row volume where measurable;
  - collection failures and retries.
- **REQ:** collector overhead is bounded (collector/executor safety contract) and observable (collection log). The log supports collector safety, diagnosis reproducibility, and identifying possible observation contamination: OraProbe activity overlapping the evidence window is reported, never silently ignored.
- **DESIGN:** part of the pre-engine design scope (investigation record, collection log, collector/executor safety). Rationale: review R-11, R-27, R-29, R-41.

### Standing acceptance rule

The October production degradation incident remains a permanent acceptance/regression case ([walkthrough](sql_tuning_v3_2_october_walkthrough.md)). Rules or evidence semantics are never changed merely to force OraProbe to reproduce the known RCA when the available evidence does not support it.

## Gaps against V3.2

These are future design decisions; V3.2 is unchanged.

- **G-01 Planner inputs (AR-01).** V3.2 does not declare:
  - per-evidence freshness/validity windows;
  - provider cost/safety classes;
  - a collection budget or investigation depth;
  - explicit links from evidence to the UNKNOWNs it can resolve (derivable from staged rules, but not declared).

  Expected to be additive, either as provider/source attributes or a separate planner contract. Decided in planner design.
- **G-02 Plan comparison (AR-03).** V3.2 has:
  - no request naming two plans;
  - no operator aligning plan lines across plans;
  - no per-difference attribution.

  Details in QUERY_TUNER_REQUIREMENTS.md.
- **G-03 Topology (AR-04).** V3.2 has:
  - one `topology_id` key;
  - a capability record covering only the investigated database's own instances;
  - no inventory model or seed/discovery reconciliation;
  - no standby or multi-database topology;
  - no inventory-mismatch evidence type.

  Demo mismatches are warnings only (C-2).
- **G-04 Version (AR-05).** The catalog and manifest are 19c-specific. 26ai needs:
  - version-keyed source mappings;
  - capability-based source selection.

  V3.2 multitenant handling is limited to `con_id` and container identity.
- **G-05 Request/result contract (AR-07).** V3.2 defines:
  - the evidence envelope;
  - conclusions;
  - blocked-decision reports.

  It has no external request/result schema.
- **G-06 Production scripts (AR-10).** Externally supplied and not in the repository. Pending structured assessment. Any repository inclusion is limited to reviewed, sanitized material.

## Design-impact candidates PV-01..PV-08 (decision D-3)

These come from the [failure-mode review](oraprobe_industry_failure_mode_review.md#potential-v32-impacts-approval-required). They are **not** V3.3 items: no V3.3 is authorized. Each needs proper ownership analysis.

**Required before any V3.3 is authorized:** a separate V3.2 impact/design proposal identifying which changes genuinely require catalog/schema evolution.

Initial architectural direction:

| PV | Candidate | Primary owner (direction) |
| --- | --- | --- |
| PV-01 | Source cost / volatility / freshness | Provider/source capability and collection policy. Catalog metadata may reference it where justified. |
| PV-02 | Incident phases | Investigation/time model. Rules may reference phase-aware evidence where justified. |
| PV-03 | Causal lag | Potential diagnostic/rule semantics. Design the temporal model first, then decide whether a lag bound is a threshold, rule parameter, relationship constraint or profile value. |
| PV-04 | Threshold-profile scope dimensions / review date | Likely future threshold-profile/catalog evolution. |
| PV-05 | Sensitive evidence | Evidence schema / data governance. Source or catalog annotations may be appropriate. |
| PV-06 | Change-history sources | Future evidence-source/catalog extension. |
| PV-07 | Recommendation risk / blast radius | A separate recommendation/action-safety model; not forced into the SQL diagnostic rule catalog. |
| PV-08 | Excluding OraProbe's own sessions | Collector/executor policy (AR-12, AR-13); not SQL diagnostic knowledge. |

**Threshold count (decision D-4).**
- The 39 null thresholds are a frozen V3.2 invariant, not a permanent OraProbe architectural constraint. V3.2 continues to validate unchanged.
- A future approved catalog version may change threshold definitions or counts for a justified design reason. Future schema semantics are not distorted to preserve the number 39.
- For PV-03, the temporal semantics are designed first; only afterwards is it decided whether causal-lag bounds need threshold IDs.

## Resolved conflicts (approved 2026-10-06)

- **C-1 MCP placement: approved with documentation cleanup.**
  - AR-08 is authoritative.
  - The earlier PROJECT_CONTEXT §23 diagram put MCP between the modules' capability interface and Oracle/Linux. It is superseded, and §23/§24 now reflect AR-08.
- **C-2 Demo inventory/discovery: approved with modification.**
  - Excel/CSV remains the demo seed inventory, and the demo may perform bounded runtime validation after connecting.
  - A mismatch is surfaced as a topology/inventory warning or validation result, not as V3.2 diagnostic evidence.
  - Formal mismatch-as-evidence and broader discovery remain future design (G-03).
  - QUERY_TUNER_REQUIREMENTS.md keeps its Excel inventory requirement.

## Pre-engine design gate (decision D-1, 2026-10-06)

The class-B items of the [failure-mode review](oraprobe_industry_failure_mode_review.md) are accepted as required **pre-engine design scope**. Their architecture and contracts must be sufficiently defined before substantial deterministic-engine implementation. This does **not** require all runtime functionality to be implemented before any coding begins.

Scope:
1. Finding composition and conflicting/competing hypotheses (R-04, R-05, R-07, R-22, R-34).
2. Result / explanation / coverage contract (R-33 diagnosis-vs-action separation, R-37 IDs, R-50, R-51).
3. Investigation record / replay contract (R-27, R-36).
4. Collection log (R-41, AR-13).
5. Collector/executor safety contract: completeness, self-identification, parsing, allowlist, cost/caps/budgets, degraded mode, volatility ordering (R-10, R-11, R-28 to R-32, R-45; AR-12, AR-13).
6. Evidence Resolution / Investigation Planner behavior and termination (R-14, R-31; AR-01).
7. Bounded baseline survey / anomaly-discovery path (R-12; AR-01 D-2).
8. Time / incident semantics: phases, clock offset, lag, calendar-aware baselines (R-15 to R-17, R-20, R-21).
9. Minimal topology model (R-23; G-03).
10. Testing/acceptance corpus architecture (R-48, R-49).

The previously pending engine design-note items (stage evaluation order, shared-detection deduplication, independence-group scoring) remain part of this scope.

## Future design and implementation work

None of this is authorized yet.

| Item | Class | Basis |
| --- | --- | --- |
| V3.2 architecture deep-dive / understanding checkpoint | DESIGN | V3.2 baseline |
| Pre-engine design gate (10 items, including the engine design note: stage evaluation order, shared-detection deduplication, independence-group scoring) | DESIGN | [Pre-engine design gate](#pre-engine-design-gate-decision-d-1-2026-10-06); implementation_readiness_v3_2.md |
| V3.2 impact/design proposal for PV-01..PV-08 (prerequisite for any V3.3) | DESIGN | D-3 |
| Deterministic engine | IMPL | PROJECT_CONTEXT §2, §28 |
| Evidence Resolution / Investigation Planner | DESIGN, then IMPL | AR-01 |
| Collector/provider/module contracts | DESIGN | AR-01, AR-07, V3.2 `provider_policy` |
| Assessment/mapping of production SQL scripts to collectors/evidence | DESIGN | AR-10 |
| Testing architecture; record/replay evidence | DESIGN | PROJECT_CONTEXT §27, AR-01 |
| Live Oracle collector validation | IMPL, ACCEPT | DEMO_SCOPE.md |
| SQL plan comparison | DESIGN, then IMPL | AR-03 |
| Topology discovery; mismatch-as-evidence model | DESIGN, then IMPL | AR-04 |
| 19c / 26ai capability layer | DESIGN, then IMPL | AR-05 |
| Demo CLI; report generation | IMPL | AR-06, PROJECT_CONTEXT §26 |
| API; portal/UI; MCP; Capstone; agents/LLM integration | IMPL (later) | AR-02, AR-07, AR-08 |
| V3.2 lab-verification items LV-01..LV-07 | Lab verification | catalog `lab_verification_registry` |
| Industry failure-mode traceability review | DESIGN | AR-09 |

**Order note:** the module order in PROJECT_CONTEXT §8 and §28 is unchanged. AR-01, AR-04, AR-05 and AR-07 constrain the shared-core design from the first implementation slice. They do not require the planner, discovery, 26ai support or an API before that slice; they require only that the first slice does not preclude them.
