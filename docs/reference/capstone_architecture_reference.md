# Enterprise GenAI platform (Capstone) — integration boundary reference

**Status:** reference context, sanitized for a public repository (2026-10-07).

**Not an OraProbe authority.** [oraprobe_architecture_requirements.md](../oraprobe_architecture_requirements.md) governs (AR-02, AR-04, AR-07, AR-08, AR-12, AR-13). Nothing here changes OraProbe diagnostic truth or the SQL Tuner V3.2 baseline.

**Scope:** only what is needed to define OraProbe's future integration boundary with an enterprise GenAI/agent platform ("Capstone"). Internal platform documentation was reviewed privately by the project owner on 2026-10-07. Its details, including component names, implementation technologies, models, module status and roadmap, are **intentionally not recorded in this repository**. No internal documents, screenshots or URLs are stored here.

## 1. What OraProbe may assume

Each point was checked against the private review and is stated only generically:
- OraProbe may integrate in future with an enterprise GenAI/agent platform.
- Such a platform may expose capabilities as standardized, MCP-compatible tools. Each tool carries metadata such as a name, a description of its domain, and input and output schemas.
- An enterprise agent may perform intent detection and tool routing. That can include splitting a multi-part request across tools and synthesizing the responses into one answer.

Everything else about the platform is outside this repository's scope and requires internal verification (section 6).

## 2. Integration boundary

```
User / enterprise agent experience
        |
        v
Enterprise agent (intent and tool routing)
        |
        v
OraProbe adapter (e.g. an MCP server)
        |
        v
Stable OraProbe request/result contract   (AR-07; gap G-05)
        |
        v
OraProbe deterministic core
        |
        v
Modules / evidence providers
        |
        v
Native OraProbe collectors
        |
        v
Oracle / OraaS / OS evidence
```

- The OraProbe deterministic core, evidence model, engine, modules, providers, collectors, topology/capability discovery, CLI demo and terminal/HTML reporting are **independent of the enterprise AI platform**. The standalone demo needs no platform, MCP, LLM, browser or internet.
- MCP/LLM layers are **never** the owner of diagnostic truth, evidence semantics, collectors or deterministic reasoning. They are never a mandatory dependency for deterministic execution (AR-08).
- Platform integration and OraaS database access are separate concerns. The evidence path stays core → providers → collectors → Oracle/OraaS/OS (AR-04, AR-08).

## 3. OraProbe integration principles

These were derived from the private review. They are OraProbe design conclusions, not platform facts.

1. **Stable tool contracts.** OraProbe exposes structured request/result contracts through an adapter, with clear tool metadata so an agent can decide when to invoke OraProbe. The agent sees only the contracts OraProbe exposes, never OraProbe internals.
2. **Undecided granularity.** The number of tools, the module-to-tool mapping, granularity and onboarding are future integration design. Collectors are **never** exposed as tools (AR-08; review R-45).
3. **Deterministic payload.** The result returned to an agent is OraProbe's deterministic structured result: findings, evidence IDs, support level, UNKNOWNs, coverage and next evidence (G-05). Agent or LLM synthesis is explanation only and must not override it (AR-02). Further evidence requests go only through OraProbe's planner as catalogued requests (AR-01; review R-37/R-38).
4. **No LLM-generated SQL for diagnostic evidence.** OraProbe must not use LLM-generated SQL to obtain production diagnostic evidence, even through read-only mechanisms (PROJECT_CONTEXT §3; AR-08; review R-45). Platform capabilities that generate queries from natural language are not an OraProbe evidence path.
5. **Own safeguards.** OraProbe enforces its own collection budgets, cost classes, termination and audit, whoever the caller is (AR-01; review R-29, R-31, R-41). Platform-side guardrails, limits or auditing are not assumed to protect OraProbe evidence.
6. **Sensitivity and retention first.** An agent platform may persist, trace or reuse requests and responses. OraProbe results may contain SQL text, bind values, object/schema names, host/database identifiers and operational evidence. Sensitivity classification, redaction and retention must be resolved before any production AI integration (review R-46; PV-05).
7. **AI-explanation reproducibility.** Model choice on an agent platform may not be under OraProbe's control. Deterministic results stay reproducible regardless; AI explanations are recorded separately with whatever model identity is available (review R-37).
8. **Integration mode open.** Whether OraProbe would integrate as its own platform solution or as a tool provider to an existing agent is undecided.
9. **Coordinate scope.** Other enterprise agent initiatives may address database performance analysis. Positioning OraProbe relative to them is an organizational decision, and is not assumed here.

## 4. Future request flow (conceptual)

User: *"Why was database X slow between 10:00 and 10:30?"*

1. The user asks through an enterprise agent experience.
2. The agent detects intent and, using registered tool metadata, selects an OraProbe tool.
3. The agent invokes the OraProbe adapter with a structured request.
4. The adapter calls the **same** deterministic core used by the CLI/API.
5. OraProbe investigates deterministically with native collectors.
6. OraProbe returns structured findings, evidence, support level, UNKNOWNs, coverage and next evidence.
7. The agent may explain the results conversationally. It never replaces or overrides OraProbe's deterministic evidence truth.

Steps 3 to 6 are OraProbe design interpretation. Agent behavior in steps 1, 2 and 7 is generic.

## 5. UI / experience boundary

- **A. OraProbe-owned UI:** calls stable OraProbe interfaces (AR-07).
- **B. Enterprise agent experience:** may consume OraProbe through supported agent/tool integration.
- **C. Any enterprise portal:** consumes OraProbe through supported programmatic interfaces, subject to that portal's mechanisms and policy.

OraProbe diagnostic logic stays presentation-agnostic (AR-07).

## 6. Requires separate internal verification

These are not recorded in this repository and must be verified internally before integration design:
- onboarding/registration of an OraProbe adapter, and tool governance;
- authentication, authorization and propagation of user entitlements (who may investigate which database);
- service identity and secrets management;
- network placement and paths, both platform ↔ OraProbe and OraProbe ↔ Oracle/OraaS;
- protocols, API gateway, request/response size limits, timeouts, and synchronous versus long-running execution (OraProbe investigations may take minutes);
- data handling, persistence, tracing and retention of requests and results;
- model selection/routing for explanations;
- audit requirements;
- HA/scaling;
- UI integration mechanism.

## 7. Related documents

- [oraprobe_architecture_requirements.md](../oraprobe_architecture_requirements.md): authoritative.
- [oraprobe_industry_failure_mode_review.md](../oraprobe_industry_failure_mode_review.md): R-37 to R-40, R-45, R-46.
- [DEMO_SCOPE.md](../../DEMO_SCOPE.md): the demo excludes the platform and MCP.
