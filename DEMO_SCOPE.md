# Query Tuner demo scope

Product name: OraProbe (user correction). The existing workspace path C:\OraProble is unchanged. OraProbe-Management-Design.png presents the target end product, not only the demo.

User clarification, 2026-10-01. These demo-specific decisions refine PROJECT_CONTEXT.md.

- Develop and repeatedly test on the user's personal machine; transfer code to the company environment and run locally on an OraaS POC database server.
- Initial module: Query Tuner. Keep the shared core limited to its needs.
- Central inventory becomes available after management approval; it is not a demo prerequisite.
- User authorizes local OS-authenticated `/ as sysdba` collection through predefined read-only queries against relevant dictionary and dynamic performance views, including ASH where permitted.
- SYSDBA is privileged access, not a read-only enforcement mechanism. The collector must restrict execution to predefined diagnostic capabilities.
- No representative SQL is currently available. Design a solid initial version, then create controlled degraded-SQL scenarios in the personal lab and test repeatedly.
- Fixtures support early offline testing; live Oracle lab tests are needed to validate collection and actual database behavior. Personal Oracle lab availability/version is not yet established.
- No internet or LLM API dependency at runtime.
- Existing design-before-implementation agreement remains in force.
- Subsequent detailed scope is recorded in QUERY_TUNER_REQUIREMENTS.md: local Excel inventory is a supported input requirement; inventory DB integration and automatic configuration discovery are deferred. Initial inputs are database name, SQL ID, and incident time/window, with optional symptoms.

## Demo interface and offline operation (AR-06, AR-11; recorded 2026-10-06)

Status: requirement only. The CLI is not implemented. Authoritative architecture requirements: docs/oraprobe_architecture_requirements.md.

- The initial demo is fully operable through an interactive Python CLI on the target Unix environment. Conceptually:
  `python3 oraprobe.py` -> select database -> select investigation area -> select investigation/action -> provide SQL ID, time range and other inputs where needed -> invoke the OraProbe core -> terminal result -> optional structured/HTML report.
- The CLI only creates structured requests and renders results. Diagnostic logic never lives in the CLI.
- The demo requires no browser, web server, internet, LLM, MCP or Capstone.
- Deterministic mode uses structured menus/forms. No natural-language keyword parser is built for it.
- Demo inventory (decision C-2): Excel/CSV is the seed inventory. After connecting, the demo may perform bounded runtime validation of the selected target database, topology and capabilities. A mismatch is surfaced as a topology/inventory warning or validation result; it is not a V3.2 diagnostic evidence type. Broader discovery is future work.
- Demo path: CLI -> OraProbe deterministic core -> providers/collectors -> Oracle/OS -> findings/report. Future API, portals, MCP, Capstone and optional LLM assistance are additive. Demo shortcuts must not prevent them.

## Licensing clarification

The user confirms full Oracle licensing for the demo and instructs us to proceed without further licensing clarification. Treat ASH/AWR capabilities as authorized for the demo design. Handle missing or unavailable historical evidence as a data-availability issue; do not require another licensing confirmation.

Source: https://docs.oracle.com/en/database/oracle/oracle-database/19/dblic/Licensing-Information.html
