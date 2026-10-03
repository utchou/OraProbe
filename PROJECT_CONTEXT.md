MASTER PROJECT CONTEXT — ORACLE AI PERFORMANCE & TROUBLESHOOTING TOOL
You are helping me design and develop an enterprise-grade Oracle database performance and troubleshooting platform.

Treat everything in this prompt as persistent project context. Do not redesign the architecture casually. If you recommend changing an architectural decision, explain clearly why before changing it.

1. PROJECT OBJECTIVE
Build an intelligent Oracle troubleshooting platform capable of investigating production issues across:

Oracle Database
SQL performance
Oracle RAC
Data Guard
RMAN / backup / restore
Linux OS
ASM / storage
Network
Noisy-neighbor/resource contention
Cross-database and cross-node infrastructure issues
The system should help junior DBAs troubleshoot with the depth and discipline of a highly experienced Oracle performance engineer.

The goal is NOT simply to create a chatbot that asks an LLM what might be wrong.

The system itself must perform evidence collection, analysis, hypothesis testing, elimination, correlation and root-cause ranking.

AI/LLM is primarily the final reasoning, synthesis and interaction layer.

2. CORE ARCHITECTURAL PRINCIPLE
DETERMINISTIC FIRST — LLM LAST
This is the most important design principle.

The majority of troubleshooting intelligence must exist in deterministic Python modules.

The desired pipeline is:

User Request
↓
Structured Investigation Request
↓
Inventory / Topology Resolution
↓
Deterministic Evidence Collection
↓
Deterministic Analysis
↓
Hypothesis Generation
↓
Hypothesis Testing / Elimination
↓
Cross-Layer Correlation
↓
Confidence Scoring
↓
Structured Findings
↓
LLM
↓
Human-readable RCA / explanation / recommendations

The LLM should NOT receive thousands of raw SQL rows, AWR sections, alert logs or shell-command outputs and be expected to discover everything itself.

The deterministic engine should reduce those into high-value structured evidence.

The LLM receives information such as:

symptoms
evidence
anomalies
tested hypotheses
rejected hypotheses
correlations
timelines
confidence scores
unresolved questions
recommended next tests
The LLM then performs higher-level synthesis and explanation.

3. IMPORTANT SAFETY PRINCIPLE
The system is initially READ-ONLY.

It must:

OBSERVE → COLLECT → CORRELATE → TEST → REASON → RECOMMEND

It must NOT automatically modify production databases or servers.

The LLM must never be allowed to freely generate arbitrary SQL or shell commands and execute them against production.

All production access should eventually happen through controlled, predefined capabilities/tools.

Future remediation automation can be considered separately with approvals, validation and rollback mechanisms.

4. TARGET ENVIRONMENT
The production environment is broadly:

Oracle Database 19c
Oracle RAC
RHEL 8
Five-node RAC/Grid clusters
Multiple databases sharing the same RAC infrastructure
Databases may run as 1-, 2-, 3-, 4- or 5-node RAC databases
ASM
Shared storage
Multiple databases share infrastructure
Data Guard
Physical standby databases
GoldenGate exists for some workloads
Instance caging using CPU_COUNT
Separate public, RAC interconnect and storage networks
Central database inventory exists
Inventory maps databases to hosts/topology
All Oracle databases may run under the same Unix oracle account
Because databases share hosts and infrastructure, noisy-neighbor analysis is critical.

A problem reported against one database may actually originate from another database, another RAC instance, another host, storage, network, backup activity or shared infrastructure.

Never assume:

“DB X is slow → DB X itself is the problem.”

5. DEMO ENVIRONMENT
The first demo should stay deliberately small.

Demo scope:

One selected database
3-node RAC primary
3-node RAC physical standby
Oracle 19c
Linux
Local execution
Python available
No dependency on internet access from the database server
No dependency on an LLM API initially
Database inventory can initially come from an Excel/CSV-style mapping
Development happens outside/within the restricted environment as appropriate, but once substantial code enters the restricted corporate environment it may be difficult to move it back out.

Therefore code quality and testing before deployment are extremely important.

6. CORPORATE CONSTRAINTS
Assume an enterprise environment with restrictions.

Do NOT build the core diagnostic engine around libraries that may not be approved.

Prefer:

Python standard library
simple dependencies
modular code
portable interfaces
Some environments may allow LangChain or similar libraries, but core Oracle diagnostic logic must NOT depend on them.

LLM API availability is not guaranteed until architecture/design approval.

MCP implementation used during development may also differ from the eventual company-standard MCP implementation.

Therefore:

Oracle diagnostic logic must remain independent from MCP, LangChain and the selected LLM.

7. PROJECT ARCHITECTURE
Use approximately this separation:

oracle_ai_tool/

    main.py

    core/
        config.py
        evidence.py
        findings.py
        executor.py
        inventory.py
        session.py

    modules/

        sql_tuner/
            collectors.py
            analyzer.py
            rules.py
            hypotheses.py

        os/
            collectors.py
            analyzer.py
            rules.py
            hypotheses.py

        rac/
            collectors.py
            analyzer.py
            rules.py
            hypotheses.py

        dataguard/
            collectors.py
            analyzer.py
            rules.py
            hypotheses.py

        rman/
            collectors.py
            analyzer.py
            rules.py
            hypotheses.py

        storage/
        network/

    correlation/
        engine.py
        timeline.py
        hypotheses.py

    reporting/
        html_report.py

    ai/
        agent.py
        context_builder.py
        prompts.py

    mcp/
        server.py
        tools/

    ui/

    tests/
Do not over-engineer the folder structure prematurely.

Start with the shared core and one module, then expand.

8. MODULE DEVELOPMENT ORDER
Recommended development sequence:

Shared core
SQL Tuner
OS / noisy-neighbor analysis
RAC
Data Guard
RMAN
Storage/network correlation
Cross-domain correlation engine
UI
AI integration
MCP integration
Earlier modules may evolve as later requirements become clear.

Do not attempt to build everything simultaneously.

9. MODULE DESIGN PATTERN
Each diagnostic module should follow approximately:

COLLECT
↓
NORMALIZE
↓
ANALYZE
↓
GENERATE HYPOTHESES
↓
TEST HYPOTHESES
↓
ELIMINATE / SUPPORT
↓
SCORE
↓
RETURN STRUCTURED FINDINGS

Example:

SQL Tuner
    collectors
    metrics
    plan analysis
    rules
    hypothesis engine
    recommendations

RAC
    cluster collectors
    instance collectors
    GC analysis
    interconnect analysis
    service analysis
    hypothesis engine

OS
    CPU
    memory
    IO
    process state
    load
    network
    noisy-neighbor analysis
    hypothesis engine
Modules should return structured evidence/findings rather than prose wherever possible.

10. SHARED EVIDENCE MODEL
All modules should ultimately produce a common evidence representation.

Conceptually an evidence object should contain fields such as:

timestamp
database
instance
host
source
metric
value
baseline
severity
observation
hypothesis
confidence
supporting_evidence
contradicting_evidence
recommended_test
Exact implementation can evolve.

The important requirement is that evidence from different modules can be correlated.

For example:

Database latency spike
+
OS IO latency spike
+
RMAN backup running
+
multiple DBs affected
+
storage latency simultaneously elevated

should allow the correlation engine to reason that this may be infrastructure contention rather than an isolated database problem.

11. SQL TUNER PHILOSOPHY
The SQL Tuner must NOT simply send SQL text and an execution plan to an LLM.

It should behave like a deterministic Oracle performance expert.

It should investigate major SQL-performance families including, where relevant:

elapsed time
DB CPU
buffer gets
physical reads
executions
rows processed
parse activity
plan changes
cardinality estimation
optimizer statistics
access paths
full table scans
index access
join methods
join order
nested loops
hash joins
sort operations
temporary-space usage
PGA pressure
bind variables
bind sensitivity
bind-aware behavior
child cursors
hard parsing
library cache effects
partition pruning
predicate behavior
stale/missing statistics
histograms
skew
SQL plan instability
wait events
concurrency effects
RAC/global-cache implications
IO versus CPU-bound behavior
Do not rely on a handful of simplistic thresholds.

Build hypothesis trees.

Example:

High Buffer Gets

Possible causes:

High buffer gets
├── large number of rows scanned
│   ├── missing/selectivity issue
│   ├── poor access path
│   └── partition pruning failure
├── inefficient nested loops
│   ├── inner operation executed excessively
│   └── poor join cardinality
├── cardinality estimation problem
│   ├── stale stats
│   ├── missing histogram
│   └── correlated columns
├── execution-count issue
└── plan regression

Each hypothesis should determine what evidence is needed to support or reject it.

12. RESEARCH BEFORE CODING
This requirement is mandatory.

Before implementing a major diagnostic module, research the troubleshooting domain comprehensively.

Priority:

Official Oracle 19c documentation
Oracle performance tuning guides
Oracle RAC documentation
Data Guard documentation
RMAN documentation
Oracle support concepts where publicly documented
Linux/RHEL documentation
credible Oracle engineering sources
For each module build a knowledge/hypothesis catalog before encoding rules.

Research should answer:

What failure/performance patterns exist?
What symptoms do they create?
What evidence confirms them?
What evidence contradicts them?
What other problems look similar?
Which metrics should be collected?
Which Oracle views should be queried?
Which OS commands are needed?
What thresholds are absolute versus workload-dependent?
What correlations are meaningful?
What next diagnostic test should be run?
What remediation is normally recommended?
Do NOT begin writing hundreds of rules before building this catalog.

13. RAC REQUIREMENT
RAC troubleshooting must consider the entire cluster.

The infrastructure has five-node grids.

Even if the investigated database runs on only three nodes, infrastructure effects from other nodes/databases may matter.

Potential areas include:

GC waits
interconnect
LMS activity
instance CPU
CPU_COUNT / instance caging
load imbalance
service placement
blocking
cluster wait events
ASM
storage
host load
network
other databases sharing nodes
noisy neighbors
Do not troubleshoot a RAC database as if each instance exists independently.

14. OS / NOISY-NEIGHBOR REQUIREMENT
This is a major capability.

Because many Oracle databases run under the same Unix account, process ownership alone cannot identify which database consumes resources.

The tool must eventually correlate Oracle processes/PIDs/instances/databases with OS consumption.

Questions it should answer include:

Which DB is the largest CPU consumer?
Which DB is the largest IO consumer?
Which instance is responsible?
Which host is saturated?
Is the investigated DB actually responsible?
Is another DB affecting it?
Is backup software affecting the host/storage?
Are processes stuck in D state?
Is CPU high or merely load average high?
Is IO wait elevated?
Is storage latency elevated?
Is memory pressure involved?
Are multiple DBs showing symptoms simultaneously?
Noisy-neighbor analysis should work across all relevant RAC nodes.

15. DATA GUARD MODULE
The Data Guard module should eventually investigate:

transport lag
apply lag
redo generation rate
redo transport
archive destinations
network throughput
RFS
MRP
standby redo logs
apply throughput
archive gaps
recovery waits
IO bottlenecks
CPU constraints
network constraints
RAC-specific considerations
configuration abnormalities
It should correlate primary and standby evidence over the same time window.

16. RMAN MODULE
RMAN troubleshooting must investigate more than the RMAN log.

For slow backup/restore/duplicate, investigate:

RMAN channels
channel utilization
throughput
waits
source database
target/auxiliary database
storage
ASM
network
CPU
IO
backup software
controlfile/catalog effects where relevant
encryption/TDE where relevant
RAC nodes involved
A recent real-world slow standby creation / RMAN restore investigation should be treated as an important future acceptance scenario.

The system should be capable of collecting synchronized evidence from primary and standby and distinguishing between:

source-side bottleneck
destination-side bottleneck
network bottleneck
storage bottleneck
channel/configuration limitation
infrastructure contention
17. CROSS-DOMAIN CORRELATION
This is ultimately one of the most valuable parts of the product.

Individual modules should not operate as isolated silos.

Example:

User reports:

“Database connections were dropping.”

Evidence:

Oracle:
ORA-609

OS:
high load average

CPU:
mostly idle

Processes:
multiple D-state processes

Backup:
NetBackup running

Storage:
latency increased

Timeline:
events overlap

The engine should correlate these facts instead of concluding:

“High load average means CPU saturation.”

The system must distinguish correlation from causation and test competing hypotheses.

18. CONFIDENCE MODEL
Findings should have confidence.

For example:

Hypothesis:
Storage contention caused database response-time degradation.

Supporting evidence:
+ IO latency increased during incident
+ D-state processes increased
+ multiple databases affected
+ backup activity overlapped
+ CPU remained mostly idle

Contradicting evidence:
- no SAN-level telemetry currently available

Confidence:
82%

Next validation:
Check storage-array/ScaleIO latency during 14:05–14:20.
Do not generate arbitrary confidence numbers.

Confidence should eventually derive from weighted evidence.

19. UI / USER INTERACTION
The final product may use a conversational interface, but chat is only an interface.

The troubleshooting engine remains deterministic.

The UI should combine structured controls and natural-language interaction.

Possible screen:

Database: [ PROD01 ▼ ]

Time:
[ Now ] [ Last 15m ] [ Last 1h ] [ Custom ]

Issue:
[ SQL Performance ]
[ DB Slow ]
[ RAC ]
[ Data Guard ]
[ RMAN ]
[ OS / Infrastructure ]

Description:
"Application latency increased around 2 PM."

[ INVESTIGATE ]
Results area:

Investigation Progress

✓ Inventory resolved
✓ Database topology discovered
✓ DB metrics collected
✓ RAC checked
✓ OS checked
✓ Storage checked
✓ Related DB activity checked

Probable Cause
Storage contention during backup activity

Confidence
High

Evidence
...

Timeline
...

Recommendations
...
A conversational panel can allow follow-up questions.

20. NATURAL LANGUAGE CONTROL
Do not give operational control directly to the LLM.

Natural-language input should eventually become a structured request.

Example:

User:

“Why was PAYDB slow yesterday around 3 PM?”

Intent layer produces:

{
  "database": "PAYDB",
  "time_range": "...",
  "symptom": "performance_degradation",
  "scope": "auto"
}
The deterministic orchestrator decides which modules to invoke.

The LLM does NOT independently decide arbitrary production commands.

Structured UI buttons can bypass intent parsing entirely and create the same structured request directly.

21. MODULE ROUTING MUST NOT CREATE SILOS
If a user selects:

“SQL Performance”

that does NOT mean only SQL Tuner may run.

SQL Tuner may discover:

IO latency
RAC GC waits
CPU pressure
storage issue
noisy neighbor
and request evidence from other modules.

Similarly:

RMAN issue → network/storage/OS modules may participate.

Data Guard issue → network/OS/storage/RAC modules may participate.

Buttons indicate the starting investigation, not a hard boundary.

22. INVESTIGATION SESSION
Maintain investigation context.

Example:

Initial request:

“PAYDB was slow at 14:00.”

Later:

“What happened on node 3?”

The system should understand the same:

database
incident
time range
collected evidence
previous hypotheses
without restarting everything.

This context should live in structured session state, not solely in the LLM conversation history.

23. MCP ARCHITECTURE
MCP should be treated as an integration/capability boundary — not where Oracle diagnostic intelligence lives.

Conceptually:

UI
 |
Investigation Orchestrator
 |
Diagnostic Modules
 |
Capability Interface
 |
MCP Adapter
 |
MCP Server
 |
Oracle / Linux / OEM / Inventory
During development we may use FastMCP or another implementation.

Later Citi may provide a company-standard MCP platform.

Changing MCP implementation must NOT require rewriting:

SQL Tuner
RAC logic
Data Guard logic
RMAN logic
OS diagnostic logic
correlation logic
Therefore MCP adapters must remain thin and replaceable.

24. AI / LANGCHAIN ARCHITECTURE
LangChain may be used later for:

LLM integration
tool orchestration
structured outputs
conversational context
agent workflows
But do not put core Oracle diagnostic logic inside LangChain agents.

Conceptually:

Oracle Expertise
    ↓
Deterministic Python Modules

Enterprise Access
    ↓
MCP / Capability Layer

AI Reasoning & Interaction
    ↓
LangChain / LLM

User Experience
    ↓
UI / Chat
These layers should remain replaceable.

25. TOKEN EFFICIENCY
The environment may have limited LLM tokens.

Therefore minimize what is sent to the LLM.

BAD:

Send:

10,000 AWR rows
5,000 alert-log lines
full GV$SESSION
full execution plans
giant shell outputs
GOOD:

Deterministic modules reduce these to:

Incident window: 14:05–14:20

DB response time:
+240%

CPU:
normal

Storage latency:
4 ms → 31 ms

D-state processes:
0 → 17

Backup:
started 14:03

Affected DBs:
4

Primary hypothesis:
shared-storage contention

Confidence:
high
Then provide supporting evidence when the LLM needs deeper detail.

26. REPORTING
Before AI integration, the standalone engine should already be capable of producing a useful report.

Initial output can be HTML.

Report should include:

investigation summary
database/topology
incident time
evidence collected
anomalies
hypotheses tested
supported hypotheses
rejected hypotheses
probable cause
confidence
timeline
recommendations
further tests required
If the deterministic HTML report is already useful to an experienced DBA, the architecture is working.

AI should make it better — not rescue a weak diagnostic engine.

27. TESTING STRATEGY
Every module must have tests.

Separate:

collectors
parsers
rules
hypothesis logic
scoring
correlation
Use stored/sanitized outputs for testing wherever possible.

Example fixtures:

tests/
    fixtures/
        awr/
        sql/
        rac/
        dataguard/
        rman/
        os/
This is especially important because code may become difficult to move back outside the corporate environment after deployment.

28. DEVELOPMENT APPROACH
Do NOT try to generate the complete application immediately.

Build incrementally.

First milestone:

core/
sql_tuner/
tests/
main.py
Make SQL Tuner excellent.

Then introduce OS/noisy-neighbor analysis.

Then RAC.

Then Data Guard.

Then RMAN.

Then cross-domain correlation.

Only after the deterministic engine becomes useful should we heavily integrate:

AI
LangChain
MCP
conversational UX
29. CODING EXPECTATIONS
When generating code:

Explain what component we are building.
Explain where it fits architecturally.
Keep modules small and testable.
Avoid unnecessary dependencies.
Use clear Python.
Separate collection from analysis.
Separate rules from execution.
Separate Oracle logic from AI logic.
Separate Oracle logic from MCP implementation.
Never silently change architecture.
Include tests for meaningful logic.
Prefer deterministic reasoning where possible.
Do not invent Oracle behavior.
Research uncertain Oracle behavior before encoding it.
Design for production safety.
30. WHAT NOT TO DO
Do NOT turn this into:

“Ask ChatGPT why my Oracle database is slow.”

Do NOT build a giant prompt containing Oracle troubleshooting instructions and call that the diagnostic engine.

Do NOT dump all telemetry into an LLM.

Do NOT allow LLM-generated arbitrary production commands.

Do NOT couple Oracle logic tightly to:

OpenAI
Claude
LangChain
FastMCP
any single MCP implementation
Do NOT create isolated modules that cannot share evidence.

Do NOT diagnose based solely on static thresholds.

Do NOT assume high load average means high CPU.

Do NOT assume the database reporting the symptom is necessarily the root cause.

Do NOT optimize for a flashy chatbot before the diagnostic engine works.

31. DEFINITION OF SUCCESS
The tool should eventually behave like an experienced Oracle performance engineer who:

Understands the topology.
Establishes the incident timeline.
Collects relevant evidence.
Looks beyond the reported database.
Forms competing hypotheses.
Tests them.
Eliminates unsupported explanations.
Correlates DB + RAC + OS + storage + network + backup evidence.
Ranks likely causes.
States uncertainty.
Recommends the next diagnostic step.
Produces an explainable RCA.
The ideal outcome is:

The deterministic engine discovers most of the answer.

The LLM then explains:

what happened,
why the evidence supports it,
what remains uncertain,
what should be checked next,
and what the DBA should do.
32. INSTRUCTION TO THE AI ASSISTANT
Whenever I ask you to develop a component:

Do not immediately start coding.

First determine:

Which architectural layer it belongs to.
What evidence it requires.
What Oracle/Linux knowledge must be researched.
What hypotheses the module needs to recognize.
How those hypotheses can be deterministically tested.
What evidence supports/rejects each hypothesis.
What structured output the module should produce.
How it interacts with other modules.
How it will be tested.
Whether the design remains portable across future MCP/LLM implementations.
Then propose the design.

Once we agree on the design, implement it incrementally.

Always preserve the project’s central principle:

DETERMINISTIC-FIRST, LLM-LAST.

The AI is an intelligence and synthesis layer around a strong diagnostic engine — it is not a substitute for that engine.

This is the version I’d use as the project bootstrap prompt when opening a fresh ChatGPT/Claude/Codex session. It captures the important decisions we made through the recent discussions, including the newer UI → structured request → orchestrator → modules → correlation → LLM flow.

