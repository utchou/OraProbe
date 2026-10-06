# OraProbe industry failure-mode and best-practice architecture review

**Status:** design review, 2026-10-06. This is the first pass of AR-09 in [oraprobe_architecture_requirements.md](oraprobe_architecture_requirements.md). It is not an exhaustive industry survey.

**Scope of change:** nothing was implemented, and the frozen V3.2 baseline (commit `e4b5fe4`) is unchanged. Items that may affect V3.2 are listed under [Potential V3.2 impacts](#potential-v32-impacts-approval-required) for approval.

**Purpose:** learn from known failure modes before core implementation, without adding features for feature count. Every proposed action prefers a deterministic, explainable mechanism and preserves:
- deterministic-first / LLM-last;
- explicit UNKNOWN;
- provenance and bounds;
- a topology-independent core;
- evidence-driven cross-module investigation;
- LLM independence;
- a headless core.

## How to read this

**Basis tags** separate the kinds of claim:
- **[P]** established engineering practice, with a cited source where one exists;
- **[D]** documented product behavior, quoted from vendor documentation (Oracle only; no claims are made about other vendors' products);
- **[I]** OraProbe design inference or proposal.

**Classes:**
- **A** — already adequately addressed in design. Engine fixtures must still prove it; "A" never means tested.
- **B** — strengthen before core implementation (the design or contract must exist before engine code).
- **C** — required before production.
- **D** — module-specific future requirement.
- **E** — desirable future enhancement.
- **F** — explicit accepted limitation.

**Severity:** H = can produce a wrong or unsafe conclusion, or forces data-model rework if added late. M = weakens trust or operability. L = quality improvement.

**Timing values:**
- *Before core* — the engine design note or contracts, before engine code.
- *With collectors* — the provider/executor design.
- *With report* — first report implementation.
- *Before production*.
- *With module X*.
- *With AI layer*.
- *Later*.

**Not marked solved because a requirement mentions it.** "A" requires an encoded, validator-enforced V3.2 mechanism or an equivalent concrete contract.

## Summary

| ID | Failure mode / lesson | Class | Sev | Timing |
| --- | --- | --- | --- | --- |
| R-01 | Correlation or coincidental timing taken as causation | A | H | engine fixtures |
| R-02 | Symptom reported as cause | A | H | engine fixtures |
| R-03 | Contributor/victim confusion | A (+F) | H | engine fixtures |
| R-04 | Multiple / interacting causes collapsed into one | **B** | H | before core |
| R-05 | Confidence inflation; ranking shown as probability | **B** (+F) | H | before core |
| R-06 | Forced answer under insufficient evidence | A | H | engine fixtures |
| R-07 | Anchoring on the user's suspected cause | **B** | M | before core |
| R-08 | Sampling / top-N / monitor-eligibility bias | A | H | engine fixtures |
| R-09 | "Not observed" read as "did not happen" | A | H | engine fixtures |
| R-10 | Collector failure or truncation read as complete data | **B** | H | before core |
| R-11 | Observer effect: OraProbe's own load in the evidence | **B** | M | before core |
| R-12 | Hypothesis-driven blindness to uncatalogued causes | **B** | H | before core |
| R-13 | Single-SQL / single-database tunnel vision | A (design) / D | H | planner, modules |
| R-14 | Missing change awareness | **B** (+PV-06) | H | before core |
| R-15 | No incident phase model (onset, peak, recovery) | **B** (+PV-02) | H | before core |
| R-16 | Clock skew and snapshot-boundary errors | **B** | M | before core |
| R-17 | Unbounded causal lag | **B** (+PV-03) | M | before core |
| R-18 | Topology/workload changes during the incident | D | M | RAC/DG modules |
| R-19 | Static universal thresholds | A | H | — |
| R-20 | Baselines blind to business cycles (e.g. month-end) | **B** (+PV-04) | H | before core |
| R-21 | Contaminated or stale baselines and profiles | **B** / C | M | before core / production |
| R-22 | Cluster averages hiding hotspots (aggregation errors) | **B** | H | before core |
| R-23 | Topology independence becoming topology ignorance | **B** | M | before core |
| R-24 | RAC / Data Guard distributed-effect misattribution | D | M | RAC/DG modules |
| R-25 | PLAN_HASH_VALUE / COST overreliance | A (reqs) / D | H | plan comparison |
| R-26 | Plan-line runtime evidence usually unavailable | F | M | — |
| R-27 | Diagnosis not reproducible by another engineer | **B** | H | before core |
| R-28 | Collector parsing errors (NLS, NULL, truncation) | **B** | H | with collectors (design before core) |
| R-29 | Diagnostic query overhead on production | **B** (+PV-01) | H | before collectors |
| R-30 | Collecting from an already-saturated system | **B** | M | before collectors |
| R-31 | Runaway or cyclic investigation loops | **B** | M | planner design |
| R-32 | Volatile evidence lost during investigation | **B** (+PV-01) | H | planner/collector design |
| R-33 | Correct diagnosis, dangerous recommendation | **B** + C (+PV-07) | H | contract before core; review before production |
| R-34 | Rule conflicts and mixed-quality evidence composition | **B** | H | before core |
| R-35 | Cross-module conclusions conflict | D / C | M | correlation engine |
| R-36 | Diagnosis drift after catalog/profile/collector changes | **B** | H | before core |
| R-37 | AI hallucination or override of deterministic truth | C (+B for IDs) | H | AI layer; IDs before core |
| R-38 | Prompt injection through diagnostic text | C | H | AI layer |
| R-39 | Report/portal injection (HTML escaping of SQL text) | C | M | with report |
| R-40 | AI unavailable | A | M | — |
| R-41 | OraProbe not operable or auditable itself | **B** / C | H | run log before core; rest before production |
| R-42 | Partial, cancelled or retried investigations | C | M | before production |
| R-43 | Configuration drift and self-check | C | M | before production |
| R-44 | Evidence-bundle and contract compatibility over upgrades | C | M | before production |
| R-45 | Privilege overreach (SYSDBA) and executor allowlist | **B** + C | H | allowlist before core; least privilege before production |
| R-46 | Sensitive data in SQL text, binds and reports | C (+PV-05) | H | before production |
| R-47 | Credentials, multi-team access, audit | C | H | before production |
| R-48 | No ground-truth scenario corpus or accuracy measurement | **B** | H | before core |
| R-49 | Rules without positive/negative/UNKNOWN fixtures | **B** | H | before core |
| R-50 | No per-investigation coverage statement ("what was not checked") | **B** | H | before core |
| R-51 | Explanation chain ("why" / "why not") not in the result contract | **B** | M | before core |
| R-52 | No operator-asserted evidence or feedback loop | E | M | later |
| R-53 | Duplicate concurrent investigations of one incident | E | L | later |
| R-54 | Multitenant (PDB) noisy neighbors | D | M | AR-05 / OS module |
| R-55 | Accepted structural limitations | F | — | — |

## Top weaknesses

1. **Hypothesis-driven blindness (R-12).** AR-01 collects only what can resolve an active UNKNOWN or hypothesis. A cause outside the catalog then never raises a hypothesis and is never examined. Practice is to sweep resources systematically so that unchecked areas become visible "known unknowns" (USE method [P]).
2. **No result/composition contract (R-04, R-34, R-50, R-51).** V3.2 defines evidence, rules, gates and CP-01. Several things are still undefined:
   - how multiple supported, interacting or conflicting findings combine into one investigation result;
   - how "not checked" is stated;
   - how "why / why not" is presented.
3. **No investigation manifest or replay bundle (R-27, R-36, R-41).** Nothing yet defines the run record (catalog hash, profile version, collector/query versions, engine version, raw evidence) that lets another engineer reproduce a diagnosis or detect drift.
4. **Collector safety and fidelity are unspecified (R-10, R-28, R-29, R-30, R-32).** The design has no:
   - cost classes;
   - volatility ordering;
   - row/time caps, or completeness reporting of collector results;
   - NLS-safe parsing.
5. **Temporal model gaps (R-15, R-16, R-17, R-20).** The model lacks:
   - incident phases, including recovery as a counter-test;
   - a defined clock-offset measurement;
   - bounded causal lag;
   - business-cycle-aware baselines. The October incident is month-end.
6. **Change awareness (R-14).** Read-only in-database change history (optimizer statistics history, patch history) is not used, so TIME-001-style triggers depend on an unavailable external change log.
7. **No ground-truth corpus (R-48, R-49).** One acceptance incident cannot measure wrong-cause or UNKNOWN rates.

## Strengthen before core implementation

**Decision D-1 (2026-10-06):** accepted as the pre-engine design gate in [oraprobe_architecture_requirements.md](oraprobe_architecture_requirements.md#pre-engine-design-gate-decision-d-1-2026-10-06). That document is authoritative for the scope; the list below is the original proposal.

These are design artifacts, not features. They are proposed as additions to the already-planned engine design note and the contract designs (G-01, G-05):

1. **Engine design note, extended scope:**
   - finding composition: multiple and interacting causes, causal chain assembly, conflict presentation, mixed bound-quality evidence (R-04, R-34);
   - CP-01 presentation rules: ranking, never probability (R-05);
   - per-instance-first evaluation (R-22);
   - user-suspected cause handled as a hypothesis (R-07).
2. **Result contract (G-05):**
   - stable finding and evidence IDs;
   - an explanation chain;
   - a coverage statement;
   - diagnosis separated from recommended action (R-33, R-37, R-50, R-51).
3. **Investigation manifest and replay bundle,** plus a run/collection log (R-27, R-36, R-41).
4. **Provider/executor contract:**
   - collector result completeness;
   - self-identification;
   - NLS-safe typed parsing;
   - catalogued-query-only allowlist with typed binds;
   - cost classes, caps and budgets;
   - volatility ordering;
   - degraded-mode collection (R-10, R-11, R-28, R-29, R-30, R-32, R-45).
5. **Planner design inputs:**
   - bounded situational survey;
   - termination guarantees;
   - change-evidence pass (R-12, R-14, R-31).
6. **Temporal contract:**
   - phase windows;
   - clock-offset capture;
   - lag bounds;
   - calendar-aware baseline selection (R-15, R-16, R-17, R-20, R-21).
7. **Topology object** in request/evidence (R-23).
8. **Testing architecture:**
   - ground-truth scenario corpus;
   - per-rule TRUE/FALSE/UNKNOWN fixtures;
   - October as a golden regression (R-48, R-49).

## Detailed register

### 1. False RCA / overconfidence

**R-01 Correlation or coincidental timing taken as causation** — A · H · engine fixtures
- **Lesson [P]:** co-occurrence in an incident window is the classic false-RCA source. PROJECT_CONTEXT §17 already demands this distinction.
- **Relevance:** month-end incidents have many simultaneous anomalies.
- **Existing mitigation:**
  - `supported_cause` requires all five `contract.causal_gate` items (`measured_degradation`, `mechanism_link`, `compatible_temporal_order`, `counter_search_complete`, `comparable_control`);
  - detection or observation alone cannot satisfy `mechanism_link`;
  - CP-01 caps at 40 when the counter-search or timeline is UNKNOWN.
- **Gap:** none in design; unproven until the engine exists.
- **Action:** none beyond fixtures.
- **Test:** perturbation where an unrelated anomaly overlaps the window with no mechanism edge. Expected: never `supported_cause`.

**R-02 Symptom reported as cause** — A · H · engine fixtures
- **Lesson [D]:** Oracle ADDM types its findings as "Problem findings describe the root cause…", "Symptom findings contain information that often lead to one or more problem findings", plus Information and Warning findings. Warning findings cover problems affecting completeness, "such as missing data in AWR". [P] The Google SRE book separates "what's broken" (symptom) from "why" (cause).
- **Existing mitigation:**
  - conclusion classes `observation`, `symptom`, `candidate_contributor`, `supported_cause` and others;
  - stage ladder: detection is not attribution.
- **Gap:** none in design.
- **Test:** a wait-event-only finding (e.g. `resmgr:cpu quantum`) never exceeds `symptom` without an attribution stage.

**R-03 Contributor/victim confusion** — A, with an F part · H · engine fixtures
- **Existing mitigation:**
  - `roles` (trigger, primary/secondary contributor, amplifier, victim, bystander, unresolved);
  - `role_policy` ("waiting is not consumption"; primary requires a measured resource share);
  - V3.2 bound rules forbid "bystander" from incomplete coverage.
- **Accepted limitation (F):** the victim *population* cannot be proven from sampled evidence (October walkthrough).
- **Test:** existing October perturbations.

**R-04 Multiple or interacting causes collapsed into one** — **B** · H · before core
- **Lesson [P]:** real incidents are often chains (trigger + latent weakness + amplifier) or conjunctions (A harmful only with B). Tools that output one "root cause" mislead. DISCUSSION_RECORD already notes that a causal chain can include a trigger, an underlying weakness and amplifying behavior.
- **Existing mitigation:**
  - CP-01 `double_count_policy`: "coexisting causes do not exclude one another";
  - `outcomes.supported`: rank coexisting explanations without categorical exclusion;
  - roles include trigger and amplifier;
  - 16 causal edges.
- **Gap:** no defined algorithm or result shape for:
  - assembling supported findings into causal chains along causal edges;
  - presenting coexisting causes with each one's share or role;
  - interaction effects where neither cause alone is supported.
- **Action:** add "finding composition" to the engine design note:
  - chain assembly along existing `causal_edges`;
  - per-role ranking;
  - how an interaction hypothesis is represented. Default: a composite stays `unresolved` unless an edge or rule encodes the interaction.
- **Test:** a fixture with trigger + amplifier must report a chain, not two unrelated top-ranked causes. A fixture with two independent supported causes reports both.

**R-05 Confidence inflation; ranking shown as probability** — **B** (+F) · H · before core
- **Lesson [P]:** uncalibrated scores displayed as percentages are read as probabilities. Independent-looking evidence is often one mechanism counted twice.
- **Existing mitigation:**
  - CP-01 is "Ranking weights, not calibrated probabilities";
  - support is capped at two independent groups;
  - caps of 40;
  - independence groups on tests;
  - shared-detection dedupe.
- **Gap:**
  - the PROJECT_CONTEXT §18 example shows "Confidence: 82%". No presentation contract forbids probability-like display or requires the score basis to be shown.
  - independence-group accounting is still policy text (already a pending engine-design item).
- **Action:**
  - result contract: present CP-01 as a rank and band with the contributing groups listed; never as "%" or "probability";
  - finish the independence-group algorithm in the engine design note.
- **Accepted limitation (F):** calibrated probabilities need a labeled incident corpus that does not exist (see R-48).
- **Test:** report rendering never emits "%" for confidence. Duplicated evidence through two rules scores once.

**R-06 Forced answer under insufficient evidence** — A · H · engine fixtures
- **Existing mitigation:**
  - three-valued logic: "Missing required evidence prevents evaluation";
  - outcomes `insufficient_evidence`, `historical_telemetry_unavailable`, `configuration_required`;
  - P6 fixed wording;
  - HEALTH rules require exact or bounded inputs.
- **Test:** an empty-evidence fixture yields UNKNOWN or insufficient evidence, never health or a cause.

**R-07 Anchoring on the user's suspected cause** — **B** · M · before core
- **Lesson [P]:** confirmation bias. Investigators, human or tool, chase the reported hypothesis. The October narrative is an example.
- **Existing mitigation:**
  - the October walkthrough treats the narrative as an untested hypothesis;
  - `counter_search_complete` gate.
- **Gap:** the request contract does not say how a user-supplied suspicion enters the system.
- **Action:**
  - request contract: a suspected cause is a *hypothesis seed* with no prior weight, never evidence;
  - the planner must still run the counter-search for competing hypotheses.
- **Test:** a request naming a wrong suspect yields the evidence-supported cause, or UNKNOWN, with the suspect explicitly not supported.

### 2. Incomplete or biased observability

**R-08 Sampling, top-N and monitor-eligibility bias** — A · H · engine fixtures
- **Lesson [D]:** Oracle documents:
  - SQL Monitor monitors automatically when a statement "has consumed at least 5 seconds of CPU or I/O time in a single execution", executes in parallel, or is hinted/forced;
  - AWR captures top SQL by criteria;
  - persisted ASH is "a portion" of samples.
- **Existing mitigation:**
  - P3 `historical_execution_policy`;
  - `capture_bias_policy` (`not_captured`);
  - `bound_policy`;
  - `monitor_policy` ("absence never means zero rows, no spill or no problem");
  - capability `gap_reasons`.
- **Test:** existing October perturbations.

**R-09 "Not observed" read as "did not happen"** — A · H · engine fixtures
- **Existing mitigation:**
  - `unknown_policy` ("Absent requires an adequately collected negative search");
  - `not_captured` status;
  - "missing historical SQL never means it did not execute";
  - `negative_test` outcome "never universally eliminated".
- **Test:** existing perturbations.

**R-10 Collector failure or truncation read as complete data** — **B** · H · before core
- **Lesson [P]:** silent partial results (timeouts, row caps, a missing RAC instance, errors swallowed by a parser) are a common source of wrong "healthy" conclusions.
- **Existing mitigation:**
  - statuses `incomplete`, `unavailable`;
  - gap reasons `collector_timeout_or_row_cap`, `instance_not_covered`;
  - capability `rac_topology_and_instance_coverage`.
- **Gap:** no provider result contract stating, per collection call:
  - expected versus covered instances and containers;
  - row-cap hit;
  - truncation;
  - error class.

  Without it the engine cannot set `incomplete` reliably.
- **Action:** provider/executor contract: every result carries a completeness record. Completeness is required for any `absent`, FALSE or HEALTH evaluation.
- **Test:** inject a row-cap hit or a missing instance. Expected: dependent negative or health conclusions become UNKNOWN.

**R-11 Observer effect: OraProbe's own load in the evidence** — **B** · M · before core
- **Lesson [I]:** diagnostic sessions appear in ASH, V$SESSION and top SQL, and can be mistaken for workload, especially during long collections.
- **Existing mitigation:** none.
- **Action:**
  - collectors identify themselves. Approved direction (D-5, AR-12): MODULE/ACTION via `DBMS_APPLICATION_INFO`, subject to lab, security and privilege validation; consistent with non-destructive operation.
  - metric populations exclude OraProbe's own sessions and SQL, and report the exclusion. This is necessary but insufficient: collectors also load shared resources.
  - AR-13 (D-6) therefore also requires bounded, observable collector overhead through the collection log, so that possible observation contamination can be identified.
  - PV-08 is a collector/executor policy (D-3), not SQL diagnostic knowledge.
- **Test:** a fixture containing OraProbe sessions in ASH. Expected: excluded from workload metrics and listed.

### 3. SQL-centric tunnel vision

**R-12 Hypothesis-driven blindness to uncatalogued causes** — **B** · H · before core
- **Lesson [P]:** the USE method's value is that it "transforms unknown gaps in knowledge into documented 'known unknowns'" by checking every resource for utilization, saturation and errors. Hypothesis-only investigation finds only what it already models.
- **Relevance:** AR-01 deliberately restricts collection to what can resolve an active UNKNOWN or hypothesis. That is correct for cost, but blind to causes no rule anticipates.
- **Existing mitigation:**
  - the `counter_search_complete` gate (limited to catalogued alternates);
  - the coverage matrix document (static).
- **Gap:** no bounded, cheap, always-run *situational survey* of in-scope resources, and no report of resources not examined.
- **Decision D-2 (2026-10-06):** recorded in AR-01. The planner combines (A) a bounded baseline survey / anomaly-discovery path with (B) targeted hypothesis-driven resolution. The survey is bounded by applicability, cost, safety and budget, and never becomes "run every collector".
- **Action:**
  - planner design: a mandatory minimal survey per investigation, cost-bounded, whose purpose is coverage and anomaly flagging. For example: database time model breakdown, wait classes, host CPU if available, other active sessions/services, and whether instance or host evidence is available.
  - Anomalies without a catalogued hypothesis are reported as `uncatalogued_anomaly` observations, never causes.
  - The coverage statement (R-50) lists what was not examined.
- **Test:** inject an anomaly outside any rule (for example a sudden redo spike). Expected: reported as an uncatalogued observation; no cause invented; coverage lists it.

**R-13 Single-SQL / single-database tunnel vision** — A in design, D for modules · H
- **Existing mitigation:**
  - SQL families (tiers), FAM-* rules, `demand_policy`, concurrency/TEMP bounds;
  - Resource Manager rules consumed directly;
  - EXT-001..006 counter-hypotheses;
  - AR-01 planner;
  - PROJECT_CONTEXT §21 ("buttons indicate the starting investigation, not a hard boundary").
- **Gap:**
  - OS, storage, network, RAC and other-database evidence depends on future modules (D);
  - until they exist, the result must say these were not evaluated. QUERY_TUNER_REQUIREMENTS already requires that.
- **Test:** October; the external-cause acceptance cases.

**R-14 Missing change awareness** — **B** (+PV-06) · H · before core
- **Lesson [P]:** incident practice puts recent changes first: deployments, optimizer statistics, parameters, patches, plan baselines.
- **Existing mitigation:**
  - TIME-001 and CUR-004;
  - `change_log` (external; unavailable in the demo);
  - `V$RSRC_PLAN_HISTORY`, `DBA_HIST_PARAMETER` (`cpu_count` and `resource_manager_plan` only);
  - `DBA_OBJECTS.LAST_DDL_TIME`;
  - `DBA_SQL_PLAN_BASELINES`.
- **Gap:** read-only in-database change history is not allowlisted. Candidates, subject to source audit: optimizer statistics history and operations views, the SQL patch registry, and wider parameter history. As a result, TIME-001-style triggers are mostly unevaluable without an external log.
- **Action:**
  - planner design: a change-evidence pass per investigation window;
  - source additions need a future catalog version (PV-06).
- **Test:** a statistics gather before onset must surface as a candidate trigger, and is never a cause without its gates.

### 4. Temporal and incident reconstruction

**R-15 No incident phase model** — **B** (+PV-02) · H · before core
- **Lesson [P]:** postmortem timelines distinguish before, onset, peak, recovery and after. Recovery is a strong counter-test: a proposed cause still present after recovery is weakened, and a cause that ended with recovery is strengthened.
- **Existing mitigation:**
  - incident window plus baseline (`baseline_policy`);
  - `compatible_temporal_order`;
  - TIME-001/002.
- **Gap:**
  - `investigation_keys` holds one incident window;
  - no phase windows;
  - no "cause persisted after recovery" counter-test pattern.
- **Action:**
  - temporal contract: optional phase windows (derived from DB time series or user-supplied), each labeled;
  - a recovery-alignment counter-test pattern for causal edges.
- **Potential V3.2 impact:** PV-02.
- **Test:** a fixture where the suspected cause persists after recovery. Expected: weakened.

**R-16 Clock skew and snapshot-boundary errors** — **B** · M · before core
- **Lesson [D]:** Oracle Clusterware documents cluster time-synchronization requirements (CTSS or NTP/chrony) for RAC nodes. [P] Cross-host correlation fails silently under skew.
- **Existing mitigation:**
  - envelope `clock_error_ms`, `original_timezone`;
  - `window_policy` (half-open UTC, never prorate AWR);
  - ASH cross-instance alignment within sample spacing.
- **Gap:** how `clock_error_ms` is obtained is undefined.
- **Action:** capability record: per-instance and per-host offset against the collector clock at collection time (database time versus collector time), plus time-sync status where readable. The offset feeds onset uncertainty.
- **Test:** a fixture with a 90 s skew. Expected: onset ordering becomes UNKNOWN when within the uncertainty.

**R-17 Unbounded causal lag** — **B** (+PV-03) · M · before core
- **Lesson [P]:** "A preceded B" over any interval can be spurious. Some causes have legitimate lags (statistics last night, effect at today's peak).
- **Existing mitigation:** edge `temporal` text ("bounded onset or same execution operator dependency; unknown order cannot establish cause").
- **Gap:** no typed maximum or minimum lag per edge.
- **Action:**
  - design typed lag bounds per edge;
  - values must not become invented universal constants. They are profile/configuration values, so this possibly needs new threshold IDs (PV-03).
- **Test:** the same change 30 days before onset does not satisfy temporal order under the configured bound.

**R-18 Topology or workload changes during the incident** — D · M · RAC/DG modules
- **Existing mitigation:**
  - `startup_epoch`, `counter_policy` resets;
  - Resource Manager `SEQUENCE#` handling;
  - `reset` status.
- **Gap:** service relocation, failover, switchover and instance eviction are not modeled. Module work for RAC and Data Guard.

### 5. Thresholds

**R-19 Static universal thresholds** — A · H
- **Existing mitigation:**
  - P8: all 39 catalog thresholds are null and `oracle_universal: false`;
  - versioned external profiles;
  - `configuration_required`;
  - blocked-decision reports.

**R-20 Baselines blind to business cycles** — **B** (+PV-04) · H · before core
- **Lesson [P]:** comparing month-end to a mid-month baseline manufactures "degradation". Time-of-day, day-of-week and period-end effects dominate many enterprise workloads.
- **Relevance:** the October incident is a month-end case. The default 8-day AWR retention removes the prior month-end (readiness doc).
- **Existing mitigation:** `baseline_policy` matching strata (binds, volume, service, group, instance, concurrency…).
- **Gaps:**
  - no calendar stratum in `baseline_policy`;
  - threshold-profile `scope` covers database, container, SQL family and workload only, not period/calendar, instance count or hardware class;
  - no baseline-retention strategy.
- **Actions:**
  - define calendar-aware baseline selection (same business period first; record when unavailable → `comparable_control` UNKNOWN);
  - extend profile scope dimensions (PV-04);
  - keep the AWR retention/baseline decision open as already recorded.
- **Test:** a month-end fixture with only a mid-month baseline. Expected: `comparable_control` UNKNOWN, not degradation.

**R-21 Contaminated or stale baselines and profiles** — **B** / C · M
- **Lesson [P]:** a baseline window containing an earlier incident hides the regression. Profiles silently go stale as hardware and workload change.
- **Existing mitigation:**
  - profiles record `author`, `approved_by`, `approved_on` and `calibration_refs`;
  - `finding_traceability` records the profile used.
- **Gap:**
  - baseline windows are not screened for known incidents or anomalies;
  - profiles have no review/expiry date.
- **Actions:**
  - (B) a baseline-selection recipe in the per-metric specs that excludes flagged windows and records the exclusion;
  - (C) profile review-by date (PV-04).

### 6. RAC and distributed systems

**R-22 Cluster averages hiding hotspots; aggregation errors** — **B** · H · before core
- **Lesson [P]:** averages hide tails and hotspots. The SRE book warns that a 100 ms mean can coexist with 1% of requests taking 5 s. Pooled ratios can reverse per-group trends (Simpson's paradox). [D] ADDM Database mode "considers DB time as the sum of the database time for all database instances". That is a documented aggregation choice, useful for throughput, but it is not a per-instance view.
- **Existing mitigation:**
  - Resource Manager: "per instance, never pooled";
  - `scope_binding` requires explicit aggregation;
  - `execution_policy` counts QC executions once;
  - RAC-001 imbalance rule.
- **Gap:** "evaluate per instance first; any cluster aggregate is reported with per-instance values and skew" is mandated only for Resource Manager. `metric_input_policy` computes ratios as sum(numerator)/sum(denominator) at the common grouping. That is correct for a pooled ratio but hides per-instance skew.
- **Action:** engine design note: per-instance-first evaluation for every instance-grain metric; the cluster value is never reported without per-instance spread.
- **Test:** a 3-node fixture with one hot node. Expected: hotspot reported; the cluster average not used as evidence of health.

**R-23 Topology independence becoming topology ignorance** — **B** · M · before core
- **Lesson [I]:** a topology-independent core can drift into ignoring topology semantics: instance count, service placement, role, shared hosts.
- **Existing mitigation:**
  - AR-04 ("topology-aware modules");
  - capability record;
  - `topology_id`.
- **Gap:** no minimal topology object that rules and the planner can consult (G-03).
- **Action:** define a minimal topology object in the request/evidence contract: database, instances, hosts, role, services where known, and source (seed or validated). Rich discovery stays future.
- **Test:** the same rule evaluated on 1-node and 3-node fixtures uses the topology object, not assumptions.

**R-24 RAC and Data Guard distributed-effect misattribution** — D · M
- **Examples:** GC waits caused by a remote instance's CPU/IO or LMS starvation; standby apply lag caused by primary redo bursts.
- **Existing mitigation:** EXT-004, RAC-002, cross-module requests.
- **Action:** RAC and Data Guard module research; requires cross-instance timelines.

### 7. Plan analysis

**R-25 PLAN_HASH_VALUE / COST overreliance** — A for requirements, D for capability · H
- **Existing mitigation:**
  - family `plan_hash_rule` (plan hash never merges or splits families);
  - `plan_policy` (A-Rows/Starts, executed adaptive branch);
  - P5 per-plan AWR comparison;
  - the plan-comparison requirements (no COST/PHV inference; same PHV is not health; estimates-only means UNKNOWN).
- **Gap:** G-02 (plan alignment and per-difference attribution) is module design work.
- **Test:** the `plan_comparison` acceptance scenario in QUERY_TUNER_REQUIREMENTS.md.

**R-26 Plan-line runtime evidence usually unavailable** — F · M
- **Accepted limitation:**
  - with `STATISTICS_LEVEL=TYPICAL` and no monitoring, line-level actuals are absent;
  - historical line actuals depend on LV-05.
  - Plan comparisons will often end as "differences identified, performance attribution UNKNOWN". This is correct behavior, not a defect.

### 8. Data quality, provenance and reproducibility

**R-27 Diagnosis not reproducible by another engineer** — **B** · H · before core
- **Lesson [P]:** W3C PROV defines provenance as information about the entities, activities and people involved in producing data, "which can be used to form assessments about its quality, reliability or trustworthiness".
- **Existing mitigation:**
  - the evidence envelope (source, row key, collected time, window, timezone, clock error, instance, host, units, bounds, provider, provenance, LV refs);
  - `finding_traceability` (profile ID/version/value);
  - a frozen, hash-chained catalog;
  - deterministic generators.
- **Gap:** no investigation manifest or replay bundle. It would record:
  - catalog version and hash;
  - threshold profile ID and version;
  - engine version and OraProbe build;
  - collector query-catalog version and query-text hashes;
  - normalizer version;
  - inventory/topology snapshot;
  - request;
  - raw collected rows (or a hash, if sensitive);
  - the ordered collection log.
- **Action:** define the manifest and bundle in the record/replay design, before the engine, because the engine must emit it.
- **Test:** replaying a bundle on the same versions reproduces the identical result byte-for-byte (excluding timestamps of the replay itself).

**R-28 Collector parsing errors** — **B** · H · executor design before core (collectors not before core, but the parsing contract is)
- **Lesson [P]:** text-based collection (SQL*Plus CSV) is vulnerable to:
  - session NLS settings (decimal separators, date formats, language);
  - NULL versus empty string;
  - truncated LONG/CLOB/LOB columns;
  - embedded delimiters and newlines in SQL text;
  - locale-dependent numbers.
- **Existing mitigation:** `unit_policy` per source; the readiness doc lists "CSV parsing" as an executor safeguard.
- **Gap:** no parsing contract.
- **Action:** executor contract:
  - fixed session NLS settings per collection;
  - explicit formats in queries;
  - typed column schema per catalogued query;
  - CLOB length checks marking truncated text as `incomplete` (text_complete);
  - parse failures giving UNKNOWN with reason `parse_failure` (that reason already exists).
- **Test:** fixtures with comma decimals, embedded newlines and truncated CLOBs.

### 9. Collector safety

**R-29 Diagnostic query overhead on production** — **B** (+PV-01) · H · before collectors
- **Lesson [P]:**
  - broad queries of shared-pool views (V$SQL family) and wide GV$ queries can be expensive and contend with the workload;
  - unbounded DBA_HIST queries (missing snapshot ranges) scan large repositories.
  - This is widely reported in practitioner guidance, but must be lab-measured for OraProbe's own query catalog rather than assumed.
- **Existing mitigation:**
  - predefined read-only collection;
  - gap reason `collector_timeout_or_row_cap`;
  - readiness doc safeguards (timeouts, row caps, bind-only inputs) as unimplemented intentions.
- **Gap:**
  - no cost class per catalogued query or source;
  - no mandatory bounding predicates;
  - no per-investigation budget or concurrency limit.
- **Action:** executor contract:
  - every catalogued query declares a cost class, mandatory bounds (`SQL_ID` / snapshot range / time window), row cap and timeout;
  - the planner budget consumes cost classes;
  - one collector session per target by default.
  - Source/provider cost attributes are PV-01.
- **Test:** the lab measures each query's elapsed time and buffer gets on a loaded system. A query without bounds is rejected by the catalog validator.

**R-30 Collecting from an already-saturated system** — **B** · M · before collectors
- **Lesson [P]:** live incident collection adds load to the system being diagnosed.
- **Gap:** no degraded-mode policy.
- **Action:**
  - when the capability or survey shows host or instance saturation, restrict to the lowest cost classes and prefer already-retained history;
  - record that the investigation ran degraded.
- **Test:** a saturation fixture selects the degraded plan.

**R-31 Runaway or cyclic investigation loops** — **B** · M · planner design
- **Existing mitigation:** AR-01 requires a budget and a depth limit.
- **Gap:** no termination guarantees.
- **Action:** planner design:
  - each (provider, source, scope, window) key is collected at most once per freshness period;
  - monotonically decreasing budget;
  - request-cycle detection;
  - a request is allowed only if it targets a currently UNKNOWN required input;
  - stop when no such input remains.
- **Test:** a cyclic hypothesis fixture terminates within budget with explicit UNKNOWNs.

**R-32 Volatile evidence lost during investigation** — **B** (+PV-01) · H · planner/collector design
- **Lesson [P]:** forensic practice collects evidence in order of volatility (RFC 3227, "Guidelines for Evidence Collection and Archiving"). [D] SQL Monitor live entries age out (V3.2 `monitor_policy`: "after at least one minute"). V$ cursor and session state change continuously.
- **Gap:** no volatility class or ordering.
- **Action:**
  - sources declare a volatility class;
  - for current incidents the planner collects the most volatile evidence first (sessions, ASH in memory, SQL Monitor, cursor state), then retained history.
- **Test:** an ordering assertion in planner unit tests.

### 10. Recommendation safety

**R-33 Correct diagnosis, dangerous recommendation** — **B** (contract) + C (safety review) (+PV-07) · H
- **Lesson [P]:** remediation often has side effects outside the diagnosed scope:
  - an index slows DML and changes other plans;
  - statistics gathering flips unrelated plans;
  - plan forcing or a profile freezes a plan that later turns bad;
  - Resource Manager changes starve other groups;
  - parameters are instance-wide;
  - RAC service moves shift load.

  [D] ADDM attaches an estimated benefit ("an estimate of the portion of DB time that can be saved") to recommendations. Its documentation, as reviewed, does not state a validation requirement. OraProbe should be stricter.
- **Existing mitigation:**
  - production remediation is recommendation-only;
  - per-rule `recommendation` with `next_test`, `validation`, `safety`, `rollback`, `withhold`;
  - `safety_risk` per rule (84 of 86 are "moderate", so it does not discriminate);
  - lab experiments are separate.
- **Gap:**
  - diagnosis and action are not separate result objects;
  - there is no action risk class, blast radius (objects, SQL, instances, other tenants affected), reversibility, preconditions, or approval level;
  - no rule ties recommendation strength to diagnostic stage.
- **Actions:**
  - (B) the result contract separates `finding` from `proposed_action`;
  - an action may cite only findings at or above a stated stage, otherwise it is a "next diagnostic test", not a change;
  - (C) an action-safety catalog (risk class, blast-radius evidence required, rollback, validation plan, approval) reviewed before any production recommendation.
- **Potential V3.2 impact:** PV-07.
- **Test:**
  - an index recommendation for a table with heavy DML requires DML-impact evidence or is withheld;
  - a candidate-stage finding produces no change recommendation.

### 11. Rule conflicts and diagnostic composition

**R-34 Rule conflicts and mixed-quality evidence composition** — **B** · H · before core
- **Existing mitigation:**
  - three-valued logic;
  - CP-01 counter weights;
  - `contradictory_hypotheses` and `reinforcing_hypotheses` on rules;
  - `bound_policy` (a lower bound cannot satisfy `le`);
  - shared-detection dedupe.
- **Gap:**
  - no defined behavior when two supported findings contradict each other;
  - no defined handling of the same quantity measured exactly by one source and as a bound by another (which wins: the tighter interval or the intersection?);
  - no rule that conflicts are surfaced rather than netted out.
- **Action:** engine design note:
  - interval intersection for the same quantity from different sources; an empty intersection is reported as an evidence conflict and the value is UNKNOWN;
  - contradicting supported findings are both reported with a `conflict` marker;
  - scores never cancel silently.
- **Test:**
  - an exact AWR value conflicting with an ASH lower bound above it yields an evidence-conflict finding;
  - two contradicting rules are both listed.

**R-35 Cross-module conclusions conflict** — D / C · M
- **Existing mitigation:**
  - canonical facts owned once (V32-04);
  - RM-002 host counter-test.
- **Gap:** cross-module correlation engine (not ready).
- **Action:** apply R-34 rules across modules when the correlation engine is designed.

### 12. Reproducibility and drift

**R-36 Diagnosis drift after catalog, profile or collector changes** — **B** · H · before core
- **Existing mitigation:**
  - versioned frozen catalogs with a hash chain;
  - catalog-specific profiles;
  - deterministic generators;
  - 71 validator regression tests.
- **Gap:**
  - no requirement that stored investigations are re-evaluable under the version they used and under a newer version, with a diagnosis diff;
  - collector query changes are unversioned.
- **Action:**
  - investigation manifest (R-27);
  - a regression harness that replays stored bundles (October first) against each new catalog/engine version and reports diagnosis diffs for review.
- **Test:** a deliberate catalog change shows up as a reviewed diff on the golden bundles.

### 13. AI-specific failure modes

**R-37 AI hallucination or override of deterministic truth** — C (+B for IDs) · H · AI layer
- **Lesson [D]:** OWASP Top 10 for LLM Applications 2025 recommends defining and validating output formats and using "deterministic code to verify format compliance".
- **Existing mitigation:** AR-02 (the LLM must not create truth, override evidence, change confidence or manufacture evidence).
- **Gap:** no enforcement mechanism.
- **Actions:**
  - (B) stable IDs for findings and evidence in the result contract, so AI text can be checked;
  - (C) the AI output contract cites IDs only; a deterministic checker rejects any claim, cause, confidence or number not present in the result;
  - AI text is stored separately with model/version/prompt version and is never fed back as evidence.
- **Test:** a fabricated cause or number in AI output is rejected.

**R-38 Prompt injection through diagnostic text** — C · H · AI layer
- **Lesson [D]:** OWASP LLM01:2025: "Indirect prompt injections occur when an LLM accepts input from external sources…".
- **Relevance:** SQL text, comments, hints, MODULE/ACTION, object names, bind values, alert-log lines and application messages are untrusted data that OraProbe would pass to an LLM.
- **Action:**
  - all database/OS-derived text is delimited, untrusted data;
  - the LLM holds no execution privilege;
  - AI evidence requests pass deterministic authorization through the planner (catalogued requests only).
- **Test:** a SQL comment containing instructions changes nothing in the outcome.

**R-39 Report and portal injection** — C · M · with report
- **Lesson [P]:** rendering SQL text, MODULE values or object names into HTML or portals without escaping enables script injection.
- **Action:** context-correct escaping in every renderer; the core emits data, never markup (AR-07).
- **Test:** malicious SQL text is rendered inert.

**R-40 AI unavailable** — A · M
- **Existing mitigation:** AR-02 Mode A is complete without an LLM; AR-08 makes MCP/Capstone optional.

### 14. Operability of OraProbe itself

**R-41 OraProbe not operable or auditable itself** — **B** (run log) / C · H
- **Lesson [P]:** a diagnostic tool is a production system. It needs execution IDs, structured logs, health, and an audit of what it ran against which target, on whose behalf.
- **Existing mitigation:** capability record (collection start/end, privileges, connection mode).
- **Gap:** no investigation ID, collection log or audit trail.
- **Actions:**
  - (B) investigation ID plus an ordered collection log in the manifest (R-27): query ID, target, start/end, rows, status, error class;
  - (C) structured logging, health/self-metrics and an audit export.
- **Test:** every collection call appears in the log with its status.

**R-42 Partial, cancelled or retried investigations** — C · M
- **Existing mitigation:** UNKNOWN semantics make a partial result valid.
- **Action:**
  - cancellation and timeout yield a well-formed partial result;
  - retries are idempotent (they reuse the session cache and never double-count evidence);
  - resumable from the bundle.

**R-43 Configuration drift and self-check** — C · M
- **Action:** a self-check that verifies:
  - catalog hash chain (the validator exists);
  - profile validity;
  - Python version;
  - executor availability;
  - privileges;
  - inventory readability.

  It runs before an investigation and its result is recorded in the manifest.

**R-44 Evidence-bundle and contract compatibility over upgrades** — C · M
- **Action:** schema-versioned bundles and result contracts, with a documented compatibility policy.

### 15. Security and enterprise operation

**R-45 Privilege overreach and executor allowlist** — **B** (allowlist) + C (least privilege) · H
- **Existing mitigation:** DEMO_SCOPE: "SYSDBA is privileged access, not a read-only enforcement mechanism. The collector must restrict execution to predefined diagnostic capabilities".
- **Gap:** no enforcement design.
- **Actions:**
  - (B) the executor runs only catalogued query IDs with typed bind values; no text concatenation; no ad-hoc SQL path, including from AI or the UI;
  - (C) production uses a least-privilege account with the exact grants derived from the query catalog; no SYSDBA.
- **Test:** an attempt to run uncatalogued SQL is refused by construction.

**R-46 Sensitive data in SQL text, binds and reports** — C (+PV-05) · H
- **Relevance:**
  - V3.2 collects `V$SQL_BIND_CAPTURE.VALUE_STRING`, full SQL text and literal vectors;
  - these can contain personal or financial data;
  - reports, bundles and LLM context would propagate them.
- **Gap:** no sensitivity classification, redaction or retention policy.
- **Action:**
  - classify evidence fields that carry literal or bind values (PV-05);
  - default redaction in reports and AI context, with explicit opt-in;
  - bundle retention and access policy.
- **Test:** a default report shows no raw bind values.

**R-47 Credentials, multi-team access and audit** — C · H
- **Action:** architectural requirements only:
  - secrets never in configuration files, logs, bundles or LLM context;
  - per-user authorization of which targets may be investigated;
  - evidence and report isolation between teams and environments;
  - an audit trail (R-41).

  Citi-specific implementation is deferred.

### 16. Not yet considered elsewhere

**R-48 No ground-truth scenario corpus or accuracy measurement** — **B** · H · before core
- **Lesson [P]:** diagnostic systems are judged by wrong-cause rate, missed-cause rate and appropriate abstention. These cannot be measured from one incident.
- **Existing mitigation:** QUERY_TUNER_REQUIREMENTS validation expectations; the October acceptance case.
- **Gap:** no scenario corpus, expected-outcome format or metrics.
- **Action:** testing architecture defines a corpus of lab-induced and sanitized real scenarios. Each scenario has an expected outcome, including "must remain UNKNOWN", decoys and healthy controls. Metrics to track:
  - wrong supported cause (target zero);
  - missed supported cause;
  - UNKNOWN rate;
  - coverage.
- **Test:** the corpus runs on every catalog/engine change.

**R-49 Rules without positive, negative and UNKNOWN fixtures** — **B** · H · before core
- **Action:** every implemented rule ships with at least one fixture each for TRUE, FALSE and UNKNOWN (missing evidence, plus `configuration_required`).
- **Test:** CI rejects an implemented rule lacking any of the three.

**R-50 No per-investigation coverage statement** — **B** · H · before core
- **Lesson [D]:** ADDM Warning findings report "problems that may affect the completeness or accuracy of the ADDM analysis (such as missing data in AWR)". [P] USE known-unknowns.
- **Existing mitigation:** blocked-decision report; gap reasons; static coverage matrix.
- **Gap:** no per-investigation summary of what was evaluated, blocked or not examined.
- **Action:** the result contract carries a coverage statement:
  - hypotheses evaluated, blocked (with reason) and not applicable;
  - resources surveyed and not surveyed;
  - modules unavailable.
- **Test:** every report includes it; it is never empty.

**R-51 Explanation chain not in the result contract** — **B** · M · before core
- **Action:** each conclusion carries a machine-readable chain: evidence IDs → metric values with bounds → comparisons and thresholds → stage outcomes → gates. Rejected and unsupported hypotheses carry their "why not". The deterministic report is useful without AI (PROJECT_CONTEXT §26).

**R-52 No operator-asserted evidence or feedback loop** — E · M
- **Action:**
  - DBA-asserted facts (confirmed change, F3 family confirmation, "diagnosis wrong") are stored as evidence with author, time and trust level;
  - they are never silently promoted;
  - they feed the scenario corpus (R-48).

**R-53 Duplicate concurrent investigations of one incident** — E · L
- **Action:** share session evidence for the same target and window, respecting the freshness rules.

**R-54 Multitenant (PDB) noisy neighbors** — D · M
- **Existing mitigation:** `con_id` in the envelope; container identity in the capability record.
- **Action:** CDB-wide versus PDB-scoped evidence rules in the AR-05 capability layer and the OS/Database Health modules.

**R-55 Accepted structural limitations** — F
- No calibrated probabilities (R-05).
- Victim population not provable from sampled evidence (R-03).
- No sub-snapshot granularity for AWR-only history.
- No end-to-end application response time without application telemetry (P6).
- Dictionary state is as of collection time (dependency grades).
- External infrastructure causes cannot be established without external telemetry (demo).
- Plan-line actuals are often unavailable (R-26).

## Potential V3.2 impacts (approval required)

V3.2 was not changed. Each item is a candidate for a future catalog version or for a contract outside the catalog.

**Decisions D-3/D-4 (2026-10-06):**
- these are design-impact candidates, not V3.3 items;
- the initial owner direction per item is in [oraprobe_architecture_requirements.md](oraprobe_architecture_requirements.md#design-impact-candidates-pv-01pv-08-decision-d-3);
- a separate V3.2 impact/design proposal must precede any V3.3;
- the 39-threshold count is a frozen V3.2 invariant, not a permanent constraint;
- for PV-03, the temporal semantics are designed before deciding on threshold IDs.

| PV | Potential impact | Reason | Proposed future investigation |
| --- | --- | --- | --- |
| PV-01 | Source/provider attributes: cost class, volatility class, freshness period | R-29, R-32, G-01 | Decide in planner/executor design whether they live in the catalog (additive) or in a separate query-catalog contract |
| PV-02 | Phase windows beyond the single incident window and baseline in `investigation_keys` / `window_policy` | R-15 | Temporal contract design; check additive compatibility with stage evaluation |
| PV-03 | Typed lag bounds on causal edges; possibly new threshold IDs (would change the validator-enforced 39-threshold invariant) | R-17 | Decide edge-parameter versus threshold-profile representation |
| PV-04 | Threshold-profile scope dimensions (calendar/business period, instance count, hardware class) and review-by date | R-20, R-21 | Profile schema revision, with a catalog-version-specific profile schema |
| PV-05 | Sensitivity classification on evidence fields carrying literals or bind values | R-46 | Security design; additive envelope/field attribute |
| PV-06 | Read-only in-database change-history sources (optimizer statistics history/operations, SQL patch registry, wider parameter history) | R-14 | Source audit against 19c documentation, then a proposal |
| PV-07 | Recommendation block: action risk class, blast radius, reversibility, minimum diagnostic stage — or move actions to a separate action catalog | R-33 | Result/action contract design |
| PV-08 | Population policy excluding OraProbe's own sessions and SQL | R-11 | Policy-text addition in a future version, or engine rule |

## References

| Basis | Source |
| --- | --- |
| [D] | Oracle Database 19c Performance Tuning Guide, "Automatic Performance Diagnostics" (ADDM: DB time, finding types, recommendation benefit, Database mode). https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/automatic-performance-diagnostics.html |
| [D] | Oracle Database 19c SQL Tuning Guide, "Monitoring Database Operations" (automatic monitoring conditions; AWR retention; Tuning Pack). https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/monitoring-database-operations.html |
| [D] | Oracle Clusterware 19c, Introduction to Oracle Clusterware (cluster time synchronization). https://docs.oracle.com/en/database/oracle/oracle-database/19/cwadd/introduction-to-oracle-clusterware.html |
| [D] | OWASP Top 10 for LLM Applications 2025, LLM01 Prompt Injection. https://genai.owasp.org/llmrisk/llm01-prompt-injection/ |
| [P] | Brendan Gregg, The USE Method. https://www.brendangregg.com/usemethod.html |
| [P] | Google, Site Reliability Engineering, "Monitoring Distributed Systems" (symptoms vs causes; golden signals; the tail). https://sre.google/sre-book/monitoring-distributed-systems/ |
| [P] | W3C PROV Overview, Working Group Note, 30 April 2013. https://www.w3.org/TR/prov-overview/ |
| [P] | RFC 3227, Guidelines for Evidence Collection and Archiving (order of volatility). https://www.rfc-editor.org/rfc/rfc3227 |
| Repository | V3.2 catalog contracts cited by name; [implementation_readiness_v3_2.md](implementation_readiness_v3_2.md); [sql_tuning_v3_2_october_walkthrough.md](sql_tuning_v3_2_october_walkthrough.md) |

Statements tagged [P] without a listed source (Simpson's paradox, confirmation bias, change-first incident practice, shared-pool query overhead, NLS parsing hazards) are general engineering knowledge. Where OraProbe depends on them quantitatively, they must be lab-verified.

## Maintenance

- This register is the AR-09 traceability record.
- New failure modes are added as R-xx entries.
- An item moves to class A only when an encoded mechanism and its acceptance test exist.
- The full current industry/research survey remains future work (AR-09).
