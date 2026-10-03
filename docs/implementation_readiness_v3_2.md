# Implementation readiness after V3.2

Assessment date: 2026-10-03. Basis: V3.2 catalog (including the proposal V32-10 dependency-grade correction), validator and 71 regression cases (all passing), V3.2 change record and October walkthrough. No implementation has started.

## The question

> After V3.2, are the knowledge schema and evidence contracts stable enough that we can implement the deterministic core without expecting major data-model redesign?

**Yes, for the deterministic core and the evidence model.** The structural decisions a core engine depends on are now fixed and validator-enforced:
- the three-stage rule shape;
- true/false/unknown logic with interval bound semantics;
- per-metric accepted bound kinds;
- evidence statuses and UNKNOWN reasons;
- the evidence envelope (bounds, estimate kind, provenance, family tier, lab-verification refs);
- the provider and knowledge-ownership model;
- family tiers;
- the capability record;
- external threshold profiles;
- lab-verification gating.

The remaining open items change **values and coverage, not structure**:
- configuring threshold profiles;
- resolving LV items (a flag flips, or a metric becomes usable);
- adding sources, metrics or rules (additive);
- writing provider queries.

None of them should force a redesign of how evidence, findings, stages or scores are represented.

**Two caveats, stated so they are not mistaken for "no further design work":**
1. **Some metric recipes are still prose** (e.g. `match: contract.baseline_policy`, named populations). Each implemented metric needs a precise implementation spec and fixture tests. That is per-metric engineering inside a fixed contract, not data-model change. The engine should register metric functions by catalog ID so unimplemented metrics stay `unsupported` rather than blocking.
2. **Three engine algorithms exist only as policy text:**
   - shared-detection deduplication;
   - independence-group accounting in CP-01;
   - stage evaluation order and its interaction with preconditions.

   They need a short engine design note before coding. They do not affect the schema.

## Readiness by area

| Area | Rating | Basis | Known limitations / unblock conditions |
| --- | --- | --- | --- |
| **CORE ENGINE** (catalog loader, expression and stage evaluator, bound semantics, CP-01 scoring, causal gates, threshold profiles, blocked-decision reporting, report skeleton) | **READY WITH KNOWN LIMITATIONS** | Every rule element, gate, conclusion ladder and scoring constant is typed and validated. Bound comparison rules are fully specified. Offline fixture testing needs no Oracle. | Engine design note for the three policy-text algorithms. Per-metric implementation specs. **Python 3.8+ is not installed on the development machine.** Target-server Python version still to be confirmed against RHEL 8. |
| **EVIDENCE MODEL** (envelope, statuses, bound/estimate kinds, provenance, capture status, family tier, lab-verification refs, capability record) | **READY** | Every field needed by the October walkthrough is represented. Unknown, absent, not_captured, unlicensed and lab_verification_required are distinguishable. The validator enforces envelope and status completeness. | Fixtures must exercise every status and bound kind; that is testing, not design. |
| **SQL FAMILY NORMALIZER** (lexical tokenizer, templates, tiers) | **READY WITH KNOWN LIMITATIONS** | The contract specifies inputs, lexical rules, risk positions, outputs, statuses and can/cannot lists. No grammar parser is needed. | Needs a fixture corpus: q-quotes, N-literals, typed literals, hints, IN-lists, PL/SQL rejection, PeopleSoft-style SQL. The risk-position heuristics need negative tests. Dependency grade D2 resolution (identifier tokens to dictionary objects) needs fixtures for qualified names, synonym chains, quoted identifiers and name collisions; D1 waits for LV-03. |
| **LIVE COLLECTORS** (SQL*Plus executor, predefined read-only query catalog, V$/GV$ providers) | **NOT READY** | Source columns are audited and the provider ownership is defined. | No 19c lab and no SQL*Plus on the development machine. The predefined query catalog and executor safeguards (timeouts, row caps, CSV parsing, bind-only inputs) are not yet designed. SQL Monitor QC/PX aggregation and `WORKAREA_MAX_TEMPSEG` semantics need lab verification. **Unblock:** lab VM, query-catalog design review, executor design. |
| **HISTORICAL COLLECTORS** (AWR/ASH/RSRC/OSSTAT providers) | **NOT READY** | Sources, capture-bias rules and bounds are defined. | Same environment blockers. LV-01 and LV-05 block key historical values; LV-07 availability is unknown on RHEL 8. The default 8-day AWR retention defeats month-end baselines unless the DBA extends retention or keeps AWR baselines (which needs a further allowlist decision). **Unblock:** lab verification of LV-01/05/07, a retention/baseline decision, query catalog. |
| **CROSS-MODULE CORRELATION** (timeline engine, cross-domain hypotheses, other modules' evidence) | **NOT READY** | The provider/ownership contract and `cross_module_requests` fulfilment are defined. Resource Manager knowledge is consumable without its owner module. | No OS, storage, RAC, change or application providers. There is no correlation/timeline engine design, and onset metrics are coarse (snapshot granularity). This is correctly a later milestone per PROJECT_CONTEXT §28. |

## Recommended next step (when implementation is authorized)

1. **Environment.** Install Python 3.8+ (match the RHEL 8 server's version). Plan a 19c VirtualBox lab.
2. **Engine design note.** Cover:
   - module layout;
   - metric registry by catalog ID;
   - the three policy-text algorithms;
   - the fixture format;
   - the report/JSON output contract.
3. **First slice:** the core engine plus fixture executor, with no Oracle access. Rules whose decisions are mostly literal or evaluable from base/ASH/AWR:
   - HEALTH-001/002 and the `measured_degradation` gate;
   - FAM-001 (with normalizer v1);
   - RM-001 and RM-002;
   - CUR-004 (P5);
   - CARD-005 (zero-estimate branch);
   - TEMP-001/003;
   - EXT-005;
   - WAIT-005.

   Fixtures should encode the October acceptance perturbations as expected outcomes.
4. **Lab track, in parallel:** resolve LV-01, LV-05 and LV-07 first. They unblock the most October reasoning.
