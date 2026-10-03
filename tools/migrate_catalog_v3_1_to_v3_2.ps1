<#
Builds the V3.2 SQL tuning knowledge catalog from the unchanged V3.1 checkpoint.
Applies only the V3.2 decisions recorded in docs/sql_tuning_v3_2_proposals.md:
V32-01..V32-10 as accepted (V32-11..14 deferred to backlog), proposal V32-10 graded
dependency evidence (accepted with conditions in the V3.2 correction), plus the
seven-item lab_verification_registry.
Outputs (V2, V3 and V3.1 files are read, never written):
  knowledge/sql_tuning_catalog_v3_2.yaml
  knowledge/sql_tuning_sources_19c_v3_2.json
  knowledge/threshold_profiles/v3_2/template.json
Knowledge-only: no engine, collector, normalizer or database access.
#>
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'catalog_json_helpers.ps1')

$inCatalog = Join-Path $Root 'knowledge\sql_tuning_catalog_v3_1.yaml'
$inManifest = Join-Path $Root 'knowledge\sql_tuning_sources_19c_v3_1.json'
$outCatalog = Join-Path $Root 'knowledge\sql_tuning_catalog_v3_2.yaml'
$outManifest = Join-Path $Root 'knowledge\sql_tuning_sources_19c_v3_2.json'
$outProfileDir = Join-Path $Root 'knowledge\threshold_profiles\v3_2'
$AuditDate = '2026-10-03'
$problems = [System.Collections.Generic.List[string]]::new()

$v31 = Load-Json $inCatalog
$manifest = Load-Json $inManifest
if ($v31.catalog_version -ne '3.1') { throw 'Expected V3.1 input' }
$v31Hash = (Get-FileHash -LiteralPath $inCatalog -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestHash = (Get-FileHash -LiteralPath $inManifest -Algorithm SHA256).Hash.ToLowerInvariant()
$ref = 'https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/'
$audit = [ordered]@{ checked_on = $AuditDate; authority = 'Oracle 19c documentation'; status = 'source_definition_reviewed'; column_contract = 'only listed supported columns; live availability and offering remain collection gates' }
$diagLic = [ordered]@{ category = 'diagnostics_pack'; requires_all = @('diagnostics_pack'); feature_gates = @(); offering_check = $true }
$baseLic = [ordered]@{ category = 'base'; requires_all = @(); feature_gates = @(); offering_check = $true }
$q = @('matching_scope', 'matching_window', 'complete_required_inputs')
function Field([string]$n, [string]$t, [string]$u) { [ordered]@{ name = $n; type = $t; unit = $u; added_in = '3.2' } }
function LV([string]$column, [string]$item) { [ordered]@{ column = $column; item = $item } }

# =============================================================== lab verification registry (seven open Oracle facts)
$registry = @(
    [ordered]@{ id = 'LV-01'; status = 'open'; blocks_production_use = $true
        question = 'What unit is DBA_HIST_RSRC_CONSUMER_GROUP.CPU_WAIT_TIME recorded in?'
        affected = [ordered]@{ sources = @('DBA_HIST_RSRC_CONSUMER_GROUP'); metrics = @('rm_group_cpu_wait_interval', 'rm_wait_share'); rules = @('RM-001', 'RM-003', 'FAM-005', 'TIME-002') }
        documentation_gap = 'The 19c Reference documents CONSUMED_CPU_TIME in milliseconds for this view but states no unit for CPU_WAIT_TIME; DBA_HIST_RSRC_METRIC documents its CPU_WAIT_TIME in milliseconds, but that is a different view.'
        lab_test = 'Enable a CPU-managed plan with instance caging, drive CPU contention across two consumer groups, capture V$RSRC_CONSUMER_GROUP.CPU_WAIT_TIME (documented ms) immediately before and after two manual AWR snapshots, and compare with the DBA_HIST_RSRC_CONSUMER_GROUP delta and with ASH resmgr:cpu quantum sample time.'
        consequence_if_unresolved = 'Group-level historical Resource Manager wait share stays lab_verification_required (UNKNOWN in production). Instance-level wait share from DBA_HIST_OSSTAT RSRC_MGR_CPU_WAIT_TIME (documented hundredths of a second) remains usable.' }
    [ordered]@{ id = 'LV-02'; status = 'open'; blocks_production_use = $true
        question = 'Does DBA_HIST_RSRC_METRIC retain 1-minute rows for the full AWR retention, or only for the hour preceding each snapshot?'
        affected = [ordered]@{ sources = @(); metrics = @(); rules = @('TIME-002', 'RM-001') }
        documentation_gap = 'The view intro says "historical Resource Manager metrics for the past hour" while the view carries SNAP_ID and per-minute BEGIN_TIME/END_TIME/INTSIZE_CSEC; retention and completeness per snapshot are not stated.'
        lab_test = 'After more than 24 hours of snapshots, count rows per SNAP_ID and consumer group, compare MIN(BEGIN_TIME) with the oldest retained snapshot, and check for gaps between consecutive END_TIME/BEGIN_TIME.'
        consequence_if_unresolved = 'Source stays out of V3.2 (backlog BL-01). Historical Resource Manager onset ordering is limited to snapshot-interval granularity.' }
    [ordered]@{ id = 'LV-03'; status = 'open'; blocks_production_use = $true
        question = 'Does V$OBJECT_DEPENDENCY list a merged view as a dependency of a cached SQL cursor, and how does FROM_ADDRESS/FROM_HASH join to V$SQL?'
        affected = [ordered]@{ sources = @('V$OBJECT_DEPENDENCY'); metrics = @('common_dependency_count'); rules = @('FAM-004') }
        documentation_gap = 'The Reference states the view displays objects depended on by a package, procedure or cursor loaded in the shared pool and can be used with V$SESSION and V$SQL; it does not state that merged views are listed, does not document that FROM_ADDRESS/FROM_HASH equal V$SQL ADDRESS/HASH_VALUE, and does not document TO_TYPE codes.'
        lab_test = 'Create a view over two tables, run a query whose plan merges the view, then query V$OBJECT_DEPENDENCY for the cursor and verify TO_NAME includes the view; verify the join to V$SQL by ADDRESS/HASH_VALUE.'
        consequence_if_unresolved = 'Dependency grade D1 (recorded cursor dependency) stays lab_verification_required and is excluded from production conclusions. FAM-004 common dependency in production rests on grade D2 (resolved text reference) only.' }
    [ordered]@{ id = 'LV-04'; status = 'open'; blocks_production_use = $true
        question = 'Does DBA_HIST_TBSPC_SPACE_USAGE include temporary tablespaces, and what does TABLESPACE_USEDSIZE mean for TEMP?'
        affected = [ordered]@{ sources = @(); metrics = @(); rules = @('TEMP-004') }
        documentation_gap = 'The Reference describes generic "historical tablespace usage statistics" without stating temporary tablespace coverage.'
        lab_test = 'Join TABLESPACE_ID to the TEMP tablespace, allocate a known amount of TEMP, take a snapshot during allocation, and compare TABLESPACE_USEDSIZE with V$TEMPSEG_USAGE at that moment.'
        consequence_if_unresolved = 'Source stays out (backlog BL-03). Historical TEMP occupancy comes only from ASH lower bounds.' }
    [ordered]@{ id = 'LV-05'; status = 'open'; blocks_production_use = $true
        question = 'What is the XML structure of AWR-captured SQL Monitor reports (DBA_HIST_REPORTS_DETAILS.REPORT), and does it contain signatures, per-plan-line rows/starts and maximum TEMP per line and process?'
        affected = [ordered]@{ sources = @('DBA_HIST_REPORTS', 'DBA_HIST_REPORTS_DETAILS'); metrics = @('report_execution_temp_ub'); rules = @('CARD-005', 'JOIN-001', 'TEMP-001', 'TEMP-002') }
        documentation_gap = 'The Reference documents the REPORT column as the uncompressed XML report but not its schema.'
        lab_test = 'Run monitored parallel and serial statements with known spills, let AWR capture reports, parse the XML, and compare every extracted value with V$SQL_PLAN_MONITOR / V$SQL_MONITOR captured live for the same SQL_EXEC_ID.'
        consequence_if_unresolved = 'Report-derived plan-line actuals and TEMP upper bounds stay lab_verification_required; historical executions without live monitor data keep plan-line facts UNKNOWN.' }
    [ordered]@{ id = 'LV-06'; status = 'open'; blocks_production_use = $false
        question = 'For a persisted ASH sample instant in DBA_HIST_ACTIVE_SESS_HISTORY, are all active sessions sampled at that instant persisted, or only a subset of sessions?'
        affected = [ordered]@{ sources = @('DBA_HIST_ACTIVE_SESS_HISTORY'); metrics = @('ash_concurrent_executions_lb', 'ash_temp_occupancy_lb', 'ash_cluster_temp_occupancy_lb', 'ash_family_temp_lb'); rules = @('FAM-003', 'TEMP-004', 'RM-001') }
        documentation_gap = 'The Performance Tuning Guide states only that "a portion of the session samples is written to disk", without the selection rule.'
        lab_test = 'Hold N sessions continuously active with distinct identifiers, then compare per-SAMPLE_ID session counts in V$ACTIVE_SESSION_HISTORY with DBA_HIST_ACTIVE_SESS_HISTORY for every persisted SAMPLE_ID.'
        consequence_if_unresolved = 'None for safety: per-instant persisted counts are already treated as lower bounds. Verification could only tighten interpretation, never upgrade a peak to exact.' }
    [ordered]@{ id = 'LV-07'; status = 'open'; blocks_production_use = $false
        question = 'Which OS-dependent V$OSSTAT statistics (BUSY_TIME, IDLE_TIME, OS_CPU_WAIT_TIME, LOAD) are populated on the target RHEL 8 hosts, and do they agree with OS tools under virtualization?'
        affected = [ordered]@{ sources = @('DBA_HIST_OSSTAT'); metrics = @('host_busy', 'host_queue'); rules = @('RM-002', 'RM-004') }
        documentation_gap = 'The Reference marks these statistics as OS-dependent; only NUM_CPUS and RSRC_MGR_CPU_WAIT_TIME are documented for all platforms.'
        lab_test = 'On a RHEL 8 lab host, drive known CPU load, take snapshots, and compare DBA_HIST_OSSTAT deltas with sar/mpstat over the same interval, including steal time if virtualized.'
        consequence_if_unresolved = 'Availability is detected at collection time: absent statistics leave host_busy/host_queue unavailable. Populated values are used with interval-average semantics; virtualization accuracy remains a stated limitation.' }
)

$backlog = @(
    [ordered]@{ id = 'BL-01'; origin = 'V32-11'; status = 'deferred'; item = 'DBA_HIST_RSRC_METRIC minute-level Resource Manager history'; lab_verification = @('LV-02'); reason = 'Retention semantics contradictory in documentation.' }
    [ordered]@{ id = 'BL-02'; origin = 'V32-12'; status = 'deferred'; item = 'DBA_HIST_SYSTEM_EVENT resmgr:cpu quantum instance totals; DBA_HIST_COLORED_SQL coverage note'; lab_verification = @(); reason = 'Cross-checks only; not required for the first engine.' }
    [ordered]@{ id = 'BL-03'; origin = 'V32-13'; status = 'deferred'; item = 'DBA_HIST_SQL_BIND_METADATA bind-type vectors; DBA_HIST_TBSPC_SPACE_USAGE TEMP; ORA-1652 alert-log provider'; lab_verification = @('LV-04'); reason = 'Uncertain or external; not production truth until verified.' }
    [ordered]@{ id = 'BL-04'; origin = 'V32-14'; status = 'deferred'; item = 'DBA guidance on AWR capture settings (TOPNSQL, colored SQL, retention)'; lab_verification = @(); reason = 'Configuration advice outside read-only collection; never executed by OraProbe.' }
)

# =============================================================== contract additions
$modules = @('query_tuner', 'database_health', 'os_noisy_neighbors', 'rac_clusterware', 'storage_capacity', 'network', 'data_guard', 'rman_recovery', 'blocking_transactions', 'connectivity_services', 'jobs_changes', 'replication')
$contract = Copy-Ordered $v31.contract
$envelope = [System.Collections.Generic.List[string]]::new(); foreach ($x in $v31.contract.evidence_envelope) { $envelope.Add($x) }
foreach ($x in @('lower_bound', 'upper_bound', 'bound_kind', 'estimate_kind', 'family_tier', 'provider_id', 'provenance', 'lab_verification_refs')) { if (-not $envelope.Contains($x)) { $envelope.Add($x) } }
$contract['evidence_envelope'] = $envelope.ToArray()
$statuses = [System.Collections.Generic.List[string]]::new(); foreach ($x in $v31.contract.statuses) { $statuses.Add($x) }; $statuses.Add('not_captured'); $statuses.Add('lab_verification_required')
$contract['statuses'] = $statuses.ToArray()
$reasons = [System.Collections.Generic.List[string]]::new(); foreach ($x in $v31.contract.unknown_reasons) { $reasons.Add($x) }
foreach ($x in @('not_captured_by_selective_source', 'lab_verification_required', 'bound_not_comparable', 'estimate_not_accepted', 'family_tier_insufficient')) { $reasons.Add($x) }
$contract['unknown_reasons'] = $reasons.ToArray()

$contract['family_policy'] = [ordered]@{
    rule = 'V32-01: a family is a workload-grouping claim at a stated tier, never an assertion of application semantics unless confirmed outside Oracle. Plan hash, module/action/service, shared objects or time co-occurrence form a cohort, never a family.'
    tiers = [ordered]@{
        C = [ordered]@{ name = 'cohort'; requires = 'shared plan hash, module/action/service, objects or time window'; establishes = 'co-occurrence worth examining'; does_not_establish = 'statement identity' }
        F1 = [ordered]@{ name = 'candidate_family'; requires = 'same non-zero FORCE_MATCHING_SIGNATURE from any source, or same loose_template_hash'; establishes = 'lexically similar statements'; does_not_establish = 'same name resolution, semantics, complete membership' }
        F2 = [ordered]@{ name = 'strongly_supported_family'; requires = 'same strict_template_hash for every member from complete text with normalization_status ok; same statement type; same literal-type vector; identical values at semantic-risk literal positions; same PARSING_SCHEMA_NAME (or every identifier resolved to the same dictionary objects); plus at least one corroboration: same non-zero FORCE_MATCHING_SIGNATURE, overlapping executed-plan object set, or same module/action'; establishes = 'same statement template under the same name resolution, differing only in ordinary literal values; valid for aggregating resource demand'; does_not_establish = 'application-level equivalence; equal cost behaviour' }
        F3 = [ordered]@{ name = 'confirmed_family'; requires = 'F2 plus a recorded external confirmation (application equivalence record or DBA confirmation with author and time)'; establishes = 'semantic equivalence for remediation scope'; does_not_establish = 'anything about cost or causation beyond F2' }
    }
    split_rules = @('different parsing schema with different resolved objects', 'different statement type', 'literal-type mismatch at the same position', 'different value at a semantic-risk literal position', 'truncated, unparseable or unsupported text')
    plan_hash_rule = 'Plan hash never merges or splits a family; differing plans inside F2/F3 are recorded as plan strata.'
    unverified_member_rule = 'Members known only by FORCE_MATCHING_SIGNATURE (no complete text) are capped at F1 and reported as unverified_member.'
    selectivity_strata = 'Within F2/F3 stratify by literal value class and observed per-execution cost band; baselines compare like strata.'
    purpose_matrix = [ordered]@{
        fam_001_derived_fact = 'F2'
        family_aggregate_demand_cpu_temp_share = 'F2'
        fam_004_common_dependency = 'F2'
        remediation_scope_all_members = 'F3'
    }
    below_minimum = 'Values are reported as cohort figures; confidence_policy.indirect_family_cap applies; no family-grain TRUE (reason family_tier_insufficient).'
    finding_traceability = 'Every family-grain finding records family_id, family_version, family_tier and the tier basis.'
}
$contract['normalizer_policy'] = [ordered]@{
    rule = 'V32-02: a deterministic lexical normalizer (tokenizer, not a grammar parser) provides candidate grouping and supporting evidence. Normalized text alone never establishes semantic or application equivalence. A full grammar parser is not required for the first engine; AST-based rules remain UNKNOWN until one exists.'
    input = 'Complete text only: V$SQL.SQL_FULLTEXT, DBA_HIST_SQLTEXT.SQL_TEXT, or V$SQL_MONITOR.SQL_TEXT when IS_FULL_SQLTEXT=Y. Incomplete text yields truncated.'
    lexing = 'Oracle lexical rules: text literals with doubled-quote escapes, N-prefixed and q-quote alternative quoting; numeric literals with decimals, exponent and f/F/d/D suffix; DATE/TIMESTAMP/INTERVAL typed literals as single tokens; bind placeholders; quoted identifiers preserved exactly; unquoted words uppercased; whitespace collapsed; non-hint comments removed; optimizer hints kept verbatim as opaque tokens.'
    literal_handling = 'Literals become typed placeholders; the literal vector records position, type, value and context class.'
    semantic_risk_positions = @('ordinal ORDER BY/GROUP BY position', 'ROWNUM comparison', 'FETCH FIRST/NEXT n', 'OFFSET n', 'SAMPLE (n)')
    risk_rule = 'Values at semantic-risk positions stay in the strict template; uncertain context is treated as risk.'
    loose_template = 'Strict template with literal IN-lists collapsed to one placeholder; used only for F1.'
    statuses = @('ok', 'truncated', 'unparseable', 'unsupported_statement_type')
    can_establish = @('identity up to whitespace, unquoted case, non-hint comments and ordinary literal values', 'literal positions and types', 'bind positions', 'identifier tokens present outside literals and comments', 'grouping for statements mixing literals and binds, which FORCE_MATCHING_SIGNATURE does not transform')
    cannot_establish = @('name resolution', 'identifier role (table, view, alias, column, function)', 'equivalence of reordered or rewritten SQL', 'semantics of literals outside the risk list', 'PL/SQL or dynamic SQL provenance', 'view definitions changing over time', 'equality with Oracle signature values')
    implementation_status = 'specified_not_implemented; sql_template evidence is unsupported until a normalizer version exists'
}
$contract['bound_policy'] = [ordered]@{
    rule = 'V32-03: every value carries bound_kind. A comparison never silently treats a bound or estimate as an exact value.'
    bound_kinds = [ordered]@{
        exact = 'Value measured for the stated scope/window.'
        lower_bound = 'True value is at least this value.'
        upper_bound = 'True value is at most this value.'
        bounded_interval = 'True value lies within [lower_bound, upper_bound].'
        sampled_estimate = 'Point estimate from sampled evidence without guaranteed bounds.'
        interval_average = 'Average over a stated interval; never a peak.'
        incomplete_unknown = 'Coverage or semantics insufficient for any comparison.'
    }
    comparison = [ordered]@{
        interval_form = 'Represent values as [L, U]: exact L=U; lower_bound U=+infinity; upper_bound L=-infinity; bounded_interval both.'
        gt = 'TRUE if L > t; FALSE if U <= t; otherwise UNKNOWN.'
        ge = 'TRUE if L >= t; FALSE if U < t; otherwise UNKNOWN.'
        lt = 'TRUE if U < t; FALSE if L >= t; otherwise UNKNOWN.'
        le = 'TRUE if U <= t; FALSE if L > t; otherwise UNKNOWN.'
        eq_ne_in = 'Exact values only; any other bound kind gives UNKNOWN (bound_not_comparable).'
        sampled_estimate = 'Evaluated only when the metric value_semantics.accepts lists sampled_estimate; the result carries quality estimated into every finding. Otherwise UNKNOWN (estimate_not_accepted).'
        interval_average = 'Evaluated only when value_semantics.accepts lists interval_average; the result is labelled with interval granularity and never interpreted as a peak.'
        not_accepted = 'Any bound kind not in value_semantics.accepts gives UNKNOWN (bound_not_comparable).'
        incomplete_unknown = 'Always UNKNOWN.'
    }
    propagation = @(
        'sum or max of lower bounds is a lower bound'
        'ratio with lower-bound numerator and exact denominator is a lower bound'
        'ratio with exact numerator and lower-bound denominator is an upper bound'
        'ratio whose numerator and denominator are bounds in the same direction is incomplete_unknown unless both are bracketed'
        'counts or sums over a population with incomplete coverage are lower bounds'
        'percentiles over incomplete populations are incomplete_unknown (missing members are not random)'
        'baseline_ratio of an incident lower bound over an exact baseline is a lower bound; both sides sampled with the same estimator yields sampled_estimate'
        'any input with status lab_verification_required makes the result lab_verification_required'
    )
    health_rule = 'HEALTH-001/HEALTH-002 require exact or bounded_interval inputs whose upper bounds satisfy the tolerance; lower bounds and estimates can never establish health.'
}
$contract['evidence_flow_policy'] = [ordered]@{
    principle = 'COLLECT ONCE -> NORMALIZE ONCE -> DEFINE CANONICAL FACT/HYPOTHESIS ONCE -> ALLOW MULTIPLE DIAGNOSTIC MODULES TO CONSUME IT.'
    providers = 'Evidence providers in provider_policy are shared core components. They own predefined read-only queries, normalization into catalog evidence, licensing/capability gates, coverage, bound_kind and provenance. They hold no thresholds and no rules. Each source belongs to exactly one provider.'
    session_cache = 'Within one investigation, evidence for a (provider, source, scope, window) key is collected once and reused by every consumer.'
    canonical_facts = 'Each rule is defined once, with one knowledge_owner responsible for maintenance. The shared engine evaluates it once per scope/window; the evaluated finding is a canonical session fact.'
    consumption = 'Any module listed in consumers reads the evaluated finding and its evidence directly. Consumption never requires the owner module to be installed and never re-evaluates or copies the rule.'
    no_duplication = 'No module may define a rule whose staged decisions duplicate another rule; the validator rejects duplicate staged fingerprints.'
}
$contract['knowledge_ownership_policy'] = [ordered]@{
    modules = $modules
    rule = 'knowledge_owner is a maintenance responsibility, not an execution dependency. Resource Manager hypotheses RM-001..RM-006 are owned by database_health and consumed directly by query_tuner.'
}
$contract['capture_bias_policy'] = [ordered]@{
    rule = 'V32-05: missing historical SQL never means the SQL did not execute.'
    selective_sources = [ordered]@{
        DBA_HIST_SQLSTAT = 'Top SQL per snapshot by elapsed, CPU, parse calls, sharable memory and version count (default top 30 at TYPICAL); MAXIMUM or colored SQL still requires presence in the cursor cache at snapshot time.'
        DBA_HIST_SQLTEXT = 'Text only for SQL captured in the repository.'
        DBA_HIST_SQL_PLAN = 'Plans only for captured SQL.'
        DBA_HIST_ACTIVE_SESS_HISTORY = 'Only a portion of in-memory samples is persisted; selection rule undocumented.'
        DBA_HIST_REPORTS = 'Only the most expensive completed monitored statements.'
    }
    absence = 'A SQL_ID, member or execution not found in a selective source has status not_captured, never absent; absent requires a complete search.'
    recorded_settings = 'TOPNSQL (DBA_HIST_WR_CONTROL) and snapshot interval/retention are recorded in capability for every historical investigation.'
}
$contract['family_coverage_policy'] = [ordered]@{
    rule = 'V32-07: coverage quality determines what can be concluded about a family.'
    effects = @(
        'Historically, family aggregates from DBA_HIST_SQLSTAT are lower_bound unless membership completeness is independently established; live aggregates are lower_bound when members may have aged out of the cursor cache.'
        'Only gt/ge comparisons can become TRUE on family aggregates with lower_bound; le/lt/eq comparisons are UNKNOWN.'
        'A family can never be concluded not to be a contributor (bystander or negative) from incomplete coverage.'
        'HEALTH-001/HEALTH-002 cannot be TRUE when any family aggregate feeding them is incomplete.'
        'Every family aggregate is reported with family_ash_member_count, family_sqlstat_capture_share and family_text_capture_share; unknown coverage is stated as unknown.'
        'Members without complete text are capped at F1 and excluded from F2 aggregates.'
    )
}
$contract['historical_resource_manager_policy'] = [ordered]@{
    rule = 'V32-06: only documented 19c semantics participate in production conclusions; undocumented or contradictory unit/retention semantics are lab_verification_required.'
    plan_state = 'DBA_HIST_RSRC_PLAN (START_TIME/END_TIME, CPU_MANAGED, INSTANCE_CAGING) and DBA_HIST_PARAMETER (cpu_count, resource_manager_plan) establish the plan and caging configuration in force per instance.'
    group_intervals = 'DBA_HIST_RSRC_CONSUMER_GROUP cumulative counters differenced between consecutive snapshots of the same DBID/INSTANCE_NUMBER/SEQUENCE# and instance startup. CONSUMED_CPU_TIME is documented in milliseconds. CPU_WAIT_TIME has no documented unit in this view (LV-01) and is lab_verification_required.'
    instance_wait = 'DBA_HIST_OSSTAT RSRC_MGR_CPU_WAIT_TIME (documented hundredths of a second, cumulative, all platforms) gives instance-level Resource Manager CPU wait per snapshot interval.'
    granularity = 'Snapshot interval (default one hour); results are interval_average or interval totals, never peaks.'
    rac = 'All Resource Manager evidence is per instance; plans and CPU_COUNT may differ per instance; cluster views are per-instance results reported side by side, never pooled into one ratio.'
    resets = 'Instance restart or plan change (SEQUENCE# change) makes the spanning interval UNKNOWN.'
    group_mapping = 'DBA_HIST_SQLSTAT carries no consumer group; a family is attributed to a group only through ASH CONSUMER_GROUP_ID samples (family_observed_group_mapping), and only when one group is observed.'
    cannot_establish = @('peaks shorter than the snapshot interval', 'exact CPU per SQL inside a consumer group', 'instantaneous waiting-session counts', 'which other database consumed host CPU')
}
$contract['historical_temp_concurrency_policy'] = [ordered]@{
    rule = 'V32-08/V32-09: historical TEMP and concurrency from ASH are estimates or bounds only and are never reported as exact peaks. Evidence quality is preserved in every finding.'
    temp_per_execution = 'ASH TEMP_SPACE_ALLOCATED summed over the execution sessions (QC and PX via QC identity) per sample instant, maximum over instants: lower_bound. Report-derived per-line maxima summed: upper_bound, lab_verification_required (LV-05). DBA_HIST_SQLSTAT has no TEMP column: unavailable.'
    concurrent_executions = 'Distinct execution keys per persisted ASH sample instant, maximum: lower_bound; executions idle between fetches are invisible. ELAPSED_TIME_DELTA per interval second: interval_average of database time, not an execution count.'
    simultaneous_temp = 'Sum of TEMP_SPACE_ALLOCATED over all sampled sessions per instant per instance; cluster value sums instances at instants aligned within the sample spacing: lower_bound.'
    temp_by_family = 'Per-instant TEMP of tier-qualified member sessions: lower_bound bytes; share of the same-instant total: sampled_estimate. Session TEMP is attributed to the current SQL, which may differ from the allocating cursor; TOP_LEVEL_SQL_ID and IS_SQLID_CURRENT are recorded.'
    projection_rule = 'Per-execution TEMP multiplied by concurrency is a projection and never a measured occupancy.'
}
$contract['host_cpu_policy'] = [ordered]@{
    rule = 'V32-10: Oracle-recorded host CPU (provider oracle_host, DBA_HIST_OSSTAT) distinguishes host saturation from Resource Manager/caging limitation at snapshot-interval granularity.'
    supports = @('host busy fraction from BUSY_TIME/(BUSY_TIME+IDLE_TIME) deltas as interval_average', 'LOAD as a point sample (sampled_estimate) against NUM_CPUS', 'instance-level Resource Manager wait from RSRC_MGR_CPU_WAIT_TIME')
    differentiation = 'High Resource Manager wait while host CPU has spare capacity supports caging or group policy (RM-002/RM-003) over host contention (RM-004); a busy host leaves both open and they may coexist.'
    limits = 'Host CPU alone never eliminates noisy-neighbour or other external contributors: it is host-wide, interval-averaged, OS-dependent (LV-07) and carries no per-database or per-process attribution. OS-CPU counter-search remains partially fulfilled until OS telemetry exists.'
}
$contract['dependency_evidence_policy'] = [ordered]@{
    rule = 'Proposal V32-10 (accepted with conditions; distinct from decision label V32-10 host CPU): graded attribution/supporting evidence that SQL statements or family members depend on or access a common object or view. A dependency link is graded per (member SQL_ID, resolved OBJECT_ID) and never by object name alone.'
    grades = [ordered]@{
        D1 = [ordered]@{ name = 'recorded_cursor_dependency'; requires = 'V$OBJECT_DEPENDENCY row (TO_OWNER, TO_NAME) for a cursor of the member currently loaded in the shared pool, joined FROM_ADDRESS/FROM_HASH to V$SQL ADDRESS/HASH_VALUE within the same instance and CON_ID, resolved to OBJECT_ID through DBA_OBJECTS (TO_TYPE codes are not used)'; establishes = 'the cached cursor recorded a dependency on the object'; does_not_establish = 'that the incident-time cursor had the same dependency when the child was loaded after the window; that the object was accessed at run time or how much work it caused'; counts_as_common_dependency = $true; production_use = 'lab_verification_required'; lab_verification = @('LV-03') }
        D2 = [ordered]@{ name = 'resolved_text_reference'; requires = 'identifier token from sql_template.identifier_set (complete text, normalization_status ok) resolved to exactly one local object: explicit OWNER.NAME, else an object of PARSING_SCHEMA_NAME, else a private synonym of PARSING_SCHEMA_NAME, else a PUBLIC synonym; synonym chains followed through DBA_SYNONYMS to a local object without cycles; same CON_ID'; establishes = 'the statement text names the object under the parsing schema name resolution as of collection time'; does_not_establish = 'identifier role (a column, alias or function may share the name); run-time access; definitions as of the incident when they changed later'; counts_as_common_dependency = $true; production_use = 'allowed'; lab_verification = @() }
        D3 = [ordered]@{ name = 'executed_plan_access_in_closure'; requires = 'plan line OBJECT# (V$SQL_PLAN or DBA_HIST_SQL_PLAN) of the member inside the dependency closure of the object (DBA_DEPENDENCIES walk, depth bounded by threshold dependency_depth)'; establishes = 'the member accessed an object underlying the common object'; does_not_establish = 'that the access went through the common object or view; base objects are often accessed directly'; counts_as_common_dependency = $false; production_use = 'allowed'; lab_verification = @() }
        D4 = [ordered]@{ name = 'coincidence'; requires = 'unresolved or ambiguous identifier match, closure membership without plan access, or a downgraded link'; establishes = 'cohort-level co-occurrence worth examining'; does_not_establish = 'a dependency'; counts_as_common_dependency = $false; production_use = 'allowed'; lab_verification = @() }
    }
    common_dependency = 'Two or more members are linked to the same resolved OBJECT_ID at grade D1 or D2. While LV-03 is open, D1 is lab_verification_required, so production FAM-004 detection rests on D2 only. D3 and D4 are reported as object coincidence (cohort).'
    downgrades = @(
        'plan_contradicts_reference: a captured plan of the same SQL_ID exists and none of its OBJECT# values is the resolved object or in its closure -> D2 becomes D4 (conservative: join elimination can also remove access)'
        'definition_may_have_changed: CREATED or LAST_DDL_TIME of the resolved object, of any synonym on the chain or of any view on the closure path is later than the investigated window start -> D2/D3 become D4 for that window; LAST_DDL_TIME also moves on grants and revokes, so this is conservative'
        'D1 from a child cursor first loaded after the window end is subject to the definition_may_have_changed check'
        'ambiguous: more than one candidate object, an editioned object with more than one edition, or a remote object (DB_LINK or REFERENCED_LINK_NAME not null) -> no D1/D2 link'
    )
    coverage = [ordered]@{
        rule = 'Same principles as contract.capture_bias_policy and contract.family_coverage_policy.'
        ungraded = 'A member with neither a cached cursor nor complete text is ungraded with status not_captured; it is never concluded independent of the object.'
        absence = 'No V$OBJECT_DEPENDENCY row for an aged-out cursor, missing text or missing plan is not_captured, never evidence of non-dependency. Absence of a dependency is never concluded from incomplete evidence.'
        bound = 'common_dependency_count is exact only when every in-scope member is graded; otherwise lower_bound (gt/ge may be TRUE; le/lt/eq UNKNOWN).'
        report = 'Per object: members by grade, ungraded members, downgrade reasons, resolution_as_of and the instance/container of each link.'
        rac = 'Library cache addresses are instance-local; D1 joins never cross INST_ID. Dictionary resolution is database-wide per container.'
    }
    family_tier_effect = 'none'
    family_rule = 'Dependency grades are never a family-tier basis or corroboration and never raise a family tier; the existing executed-plan object-set corroboration in family_policy F2 is unchanged and applies only on top of the F2 template requirements.'
    cannot_establish = [ordered]@{
        semantic_family_equivalence = 'A common dependency never establishes that statements form a family or are semantically equivalent.'
        object_caused_degradation = 'A common dependency never establishes that the object caused degradation; it satisfies no causal gate and no measured_degradation test. FAM-004 remains capped at derived_fact.'
        identical_work_beneath_view = 'A common view never implies the same access path, transformations, row volume or work beneath it; common_path_work is measured per member and plan stratum.'
        causation_from_common_reference = 'The number of statements referencing the same object is never evidence of causation.'
    }
}
$contract['lab_verification_policy'] = [ordered]@{
    rule = 'Values whose source column, metric or semantics reference an open lab_verification_registry item with blocks_production_use=true carry status lab_verification_required and evaluate as UNKNOWN in production conclusions. They may be displayed only as unverified observations in lab mode.'
    resolution = 'An item is resolved only by recorded lab evidence and a subsequent catalog revision; resolution never happens at runtime.'
}
$tp = Copy-Ordered $v31.contract.threshold_profile_policy
$tp['profile_location'] = 'knowledge/threshold_profiles/v3_2/'
$tp['profile_template'] = 'knowledge/threshold_profiles/v3_2/template.json'
$tp['rule'] = $v31.contract.threshold_profile_policy.rule + ' V3.2: profiles are catalog-version specific; V3.2 profiles live under knowledge/threshold_profiles/v3_2/. Thresholds compare against values only under bound_policy.'
$contract['threshold_profile_policy'] = $tp
$cap = Copy-Ordered $v31.contract.capability_policy
$items = [System.Collections.Generic.List[string]]::new(); foreach ($x in $v31.contract.capability_policy.items) { $items.Add($x) }
foreach ($x in @('awr_topnsql_setting', 'historical_resource_plan_and_cpu_count_per_instance', 'oracle_host_stat_availability', 'normalizer_version', 'open_lab_verification_items')) { $items.Add($x) }
$cap['items'] = $items.ToArray()
$contract['capability_policy'] = $cap

# =============================================================== providers (each source exactly once)
$providerDefs = [ordered]@{
    capability       = [ordered]@{ scope = 'Identity, configuration, retention and entitlement record at investigation start'; owner = 'shared_core'; available_in_demo = $true }
    sql_runtime      = [ordered]@{ scope = 'Cursor cache, plans, workareas, binds, SQL Monitor (live)'; owner = 'shared_core'; available_in_demo = $true }
    sql_history      = [ordered]@{ scope = 'AWR SQL statistics, text, plans and SQL Monitor reports'; owner = 'shared_core'; available_in_demo = $true }
    ash              = [ordered]@{ scope = 'In-memory and persisted Active Session History; service names'; owner = 'shared_core'; available_in_demo = $true }
    instance_runtime = [ordered]@{ scope = 'Sessions, waits, system statistics, TEMP/UNDO/segment runtime state'; owner = 'shared_core'; available_in_demo = $true }
    resource_mgr     = [ordered]@{ scope = 'Resource Manager plans, groups, metrics and history; historical parameters'; owner = 'shared_core'; available_in_demo = $true }
    oracle_host      = [ordered]@{ scope = 'Oracle-recorded host OS statistics (DBA_HIST_OSSTAT)'; owner = 'shared_core'; available_in_demo = $true }
    dictionary       = [ordered]@{ scope = 'Data dictionary metadata and statistics'; owner = 'shared_core'; available_in_demo = $true }
    os_telemetry     = [ordered]@{ scope = 'Direct OS telemetry with per-process attribution'; owner = 'os_noisy_neighbors'; available_in_demo = $false }
    storage_telemetry = [ordered]@{ scope = 'Storage/ASM latency and peers'; owner = 'storage_capacity'; available_in_demo = $false }
    network_telemetry = [ordered]@{ scope = 'Interconnect/network evidence'; owner = 'network'; available_in_demo = $false }
    rman_records     = [ordered]@{ scope = 'RMAN job/channel evidence'; owner = 'rman_recovery'; available_in_demo = $false }
    change_records   = [ordered]@{ scope = 'Independently recorded changes'; owner = 'jobs_changes'; available_in_demo = $false }
    application_records = [ordered]@{ scope = 'Application execution, equivalence and trial records'; owner = 'connectivity_services'; available_in_demo = $false }
    snapshot_capture = [ordered]@{ scope = 'OraProbe-captured base-view snapshots'; owner = 'shared_core'; available_in_demo = $true }
}
function Provider-For([string]$id) {
    switch -Regex ($id) {
        '^(V\$INSTANCE|V\$DATABASE|V\$PARAMETER|DBA_HIST_WR_CONTROL|DBA_HIST_SNAPSHOT|license_policy|collector_runtime)$' { return 'capability' }
        '^(V\$RSRC|DBA_RSRC_PLAN_DIRECTIVES$|DBA_HIST_RSRC_|DBA_HIST_PARAMETER$)' { return 'resource_mgr' }
        '^DBA_HIST_OSSTAT$' { return 'oracle_host' }
        '^(V\$ACTIVE_SESSION_HISTORY|DBA_HIST_ACTIVE_SESS_HISTORY|DBA_HIST_SERVICE_NAME)$' { return 'ash' }
        '^(DBA_HIST_SQLSTAT|DBA_HIST_SQLTEXT|DBA_HIST_SQL_PLAN|DBA_HIST_REPORTS|DBA_HIST_REPORTS_DETAILS)$' { return 'sql_history' }
        '^(V\$SQL|V\$PX_SESSION$|V\$PQ_TQSTAT$|V\$OBJECT_DEPENDENCY$|DBMS_XPLAN\.)' { return 'sql_runtime' }
        '^(V\$SESSION|V\$SESSION_EVENT|V\$SYSSTAT|V\$SYS_TIME_MODEL|V\$SYSTEM_EVENT|V\$EVENT_NAME|V\$PGASTAT|V\$TEMPSEG_USAGE|V\$UNDOSTAT|V\$SEGMENT_STATISTICS)$' { return 'instance_runtime' }
        '^DBA_' { return 'dictionary' }
        '^os_cpu_memory$' { return 'os_telemetry' }
        '^storage_io$' { return 'storage_telemetry' }
        '^rac_network$' { return 'network_telemetry' }
        '^rman_activity$' { return 'rman_records' }
        '^change_log$' { return 'change_records' }
        '^application_execution_log$' { return 'application_records' }
        '^captured_base_snapshots$' { return 'snapshot_capture' }
    }
    return $null
}

# =============================================================== sources (V32-05, V32-06, V32-10)
$columnAdds = [ordered]@{
    'V$ACTIVE_SESSION_HISTORY'     = @('FORCE_MATCHING_SIGNATURE', 'TOP_LEVEL_SQL_ID', 'SQL_OPCODE', 'PGA_ALLOCATED')
    'DBA_HIST_ACTIVE_SESS_HISTORY' = @('FORCE_MATCHING_SIGNATURE', 'TOP_LEVEL_SQL_ID', 'SQL_OPCODE', 'MODULE', 'ACTION', 'SERVICE_HASH', 'PGA_ALLOCATED')
    'DBA_HIST_SQLSTAT'             = @('FORCE_MATCHING_SIGNATURE', 'MODULE', 'ACTION', 'PARSING_SCHEMA_NAME', 'PARSE_CALLS_DELTA', 'END_OF_FETCH_COUNT_DELTA', 'PX_SERVERS_EXECS_DELTA', 'CON_ID')
    'V$SQL_MONITOR'                = @('SQL_TEXT', 'IS_FULL_SQLTEXT', 'EXACT_MATCHING_SIGNATURE', 'FORCE_MATCHING_SIGNATURE')
    'V$SQL'                        = @('ADDRESS', 'HASH_VALUE')
    'DBA_HIST_SQL_PLAN'            = @('OBJECT#')
}
$limitationAdds = @{
    'DBA_HIST_SQLSTAT'             = ' V3.2/V32-05: selective capture (contract.capture_bias_policy); no EXACT_MATCHING_SIGNATURE and no SERVICE; a SQL_ID not present is not_captured, never absent.'
    'DBA_HIST_ACTIVE_SESS_HISTORY' = ' V3.2: FORCE_MATCHING_SIGNATURE gives activity-weighted (not top-N) signature evidence; MODULE/ACTION/SERVICE_HASH as sampled; per-instant counts and TEMP are lower bounds (LV-06).'
    'V$ACTIVE_SESSION_HISTORY'     = ' V3.2: TEMP_SPACE_ALLOCATED/PGA_ALLOCATED are per session at the sample instant and attributed to the current SQL.'
    'V$SQL_MONITOR'                = ' V3.2: SQL_TEXT is usable for templates only when IS_FULL_SQLTEXT=Y.'
    'V$SQL'                        = ' V3.2/proposal V32-10: ADDRESS/HASH_VALUE identify the parent cursor for the V$OBJECT_DEPENDENCY join (LV-03); instance-local.'
    'DBA_HIST_SQL_PLAN'            = ' V3.2/proposal V32-10: OBJECT# gives executed-plan object identity for dependency grade D3 (captured plans only; missing plan is not_captured).'
}
$lvSourceColumns = @{ 'V$OBJECT_DEPENDENCY' = @((LV 'FROM_ADDRESS' 'LV-03'), (LV 'FROM_HASH' 'LV-03'), (LV 'TO_NAME' 'LV-03'));'DBA_HIST_RSRC_CONSUMER_GROUP' = @((LV 'CPU_WAIT_TIME' 'LV-01')); 'DBA_HIST_REPORTS_DETAILS' = @((LV 'REPORT' 'LV-05')); 'DBA_HIST_OSSTAT' = @((LV 'VALUE' 'LV-07')) }
$newSources = @(
    [ordered]@{ id = 'DBA_HIST_SQLTEXT'; name = 'DBA_HIST_SQLTEXT'; rac_name = $null; kind = 'oracle_view'; columns = @('DBID', 'SQL_ID', 'SQL_TEXT', 'COMMAND_TYPE', 'CON_DBID', 'CON_ID'); grain = 'captured_parent_cursor'; unit_policy = 'Text retained verbatim; no units.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_SQLTEXT.html'
        limitations = 'V3.2/V32-05: text only for SQL captured in the Workload Repository; missing text is not_captured.'; fallbacks = @('captured_base_snapshots'); audit = $audit; added_in = '3.2' }
    [ordered]@{ id = 'DBA_HIST_SERVICE_NAME'; name = 'DBA_HIST_SERVICE_NAME'; rac_name = $null; kind = 'oracle_view'; columns = @('DBID', 'SERVICE_NAME_HASH', 'SERVICE_NAME', 'CON_DBID', 'CON_ID'); grain = 'service'; unit_policy = 'Identity only.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_SERVICE_NAME.html'
        limitations = 'V3.2: resolves ASH SERVICE_HASH to service names tracked by AWR.'; fallbacks = @(); audit = $audit; added_in = '3.2' }
    [ordered]@{ id = 'DBA_HIST_RSRC_PLAN'; name = 'DBA_HIST_RSRC_PLAN'; rac_name = $null; kind = 'oracle_view'; columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'SEQUENCE#', 'START_TIME', 'END_TIME', 'PLAN_ID', 'PLAN_NAME', 'CPU_MANAGED', 'PARALLEL_EXECUTION_MANAGED', 'INSTANCE_CAGING', 'CON_DBID', 'CON_ID'); grain = 'instance_plan_activation'; unit_policy = 'Dates normalized to UTC with original timezone retained.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_RSRC_PLAN.html'
        limitations = 'V3.2/V32-06: snapshots of V$RSRC_PLAN_HISTORY; SEQUENCE# resets at instance restart; per instance.'; fallbacks = @(); audit = $audit; added_in = '3.2' }
    [ordered]@{ id = 'DBA_HIST_RSRC_CONSUMER_GROUP'; name = 'DBA_HIST_RSRC_CONSUMER_GROUP'; rac_name = $null; kind = 'oracle_view'; columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'SEQUENCE#', 'CONSUMER_GROUP_ID', 'CONSUMER_GROUP_NAME', 'REQUESTS', 'CPU_WAIT_TIME', 'CPU_WAITS', 'CONSUMED_CPU_TIME', 'YIELDS', 'ACTIVE_SESS_LIMIT_HIT', 'QUEUED_TIME', 'CON_DBID', 'CON_ID'); grain = 'instance_group_snapshot_cumulative'; unit_policy = 'CONSUMED_CPU_TIME and QUEUED_TIME documented in milliseconds; CPU_WAIT_TIME unit undocumented (LV-01).'; licensing = $diagLic; reference = $ref + 'DBA_HIST_RSRC_CONSUMER_GROUP.html'
        limitations = 'V3.2/V32-06: snapshots of V$RSRC_CONS_GROUP_HISTORY; cumulative per SEQUENCE# (plan activation); difference only within the same instance startup and SEQUENCE#.'; fallbacks = @(); audit = $audit; lab_verification_required = $lvSourceColumns['DBA_HIST_RSRC_CONSUMER_GROUP']; added_in = '3.2' }
    [ordered]@{ id = 'DBA_HIST_PARAMETER'; name = 'DBA_HIST_PARAMETER'; rac_name = $null; kind = 'oracle_view'; columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'PARAMETER_HASH', 'PARAMETER_NAME', 'VALUE', 'ISDEFAULT', 'ISMODIFIED', 'CON_DBID', 'CON_ID'); grain = 'instance_snapshot'; unit_policy = 'Raw text retained; numeric parsing only for named numeric parameters.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_PARAMETER.html'
        limitations = 'V3.2/V32-06: snapshots of V$SYSTEM_PARAMETER; collected only for cpu_count and resource_manager_plan; values at snapshot instants, changes between snapshots are not timed.'; fallbacks = @(); audit = $audit; added_in = '3.2' }
    [ordered]@{ id = 'DBA_HIST_OSSTAT'; name = 'DBA_HIST_OSSTAT'; rac_name = $null; kind = 'oracle_view'; columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'STAT_ID', 'STAT_NAME', 'VALUE', 'CON_DBID', 'CON_ID'); grain = 'instance_host_snapshot'; unit_policy = 'Time statistics in hundredths of a second (cumulative); LOAD, NUM_CPUS instantaneous; per V$OSSTAT documentation.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_OSSTAT.html'
        limitations = 'V3.2/V32-10: snapshots of V$OSSTAT for the instance host; collected only for NUM_CPUS, BUSY_TIME, IDLE_TIME, OS_CPU_WAIT_TIME, LOAD, RSRC_MGR_CPU_WAIT_TIME. Only NUM_CPUS and RSRC_MGR_CPU_WAIT_TIME are documented for all platforms (LV-07). Host-wide, no per-database attribution.'; fallbacks = @(); audit = $audit; lab_verification_required = $lvSourceColumns['DBA_HIST_OSSTAT']; added_in = '3.2' }
    [ordered]@{ id = 'V$OBJECT_DEPENDENCY'; name = 'V$OBJECT_DEPENDENCY'; rac_name = 'GV$OBJECT_DEPENDENCY'; kind = 'oracle_view'; columns = @('FROM_ADDRESS', 'FROM_HASH', 'TO_OWNER', 'TO_NAME', 'CON_ID'); grain = 'cached_cursor_dependency'; unit_policy = 'Identity only; library cache addresses retained as hexadecimal text.'; licensing = $baseLic; reference = $ref + 'V-OBJECT_DEPENDENCY.html'
        limitations = 'V3.2/proposal V32-10: only packages, procedures and cursors currently loaded in the shared pool; aged-out cursors give not_captured, never absent. Merged-view listing and the join to V$SQL ADDRESS/HASH_VALUE are undocumented (LV-03). TO_TYPE codes are undocumented and not collected; object type comes from DBA_OBJECTS. Addresses are instance-local.'; fallbacks = @(); audit = $audit
        rac_gate = [ordered]@{ feature = 'oracle_rac'; availability = 'GV$ may exist on single instance; cross-instance investigation requires RAC topology'; fallback = 'instance-local V$ evidence with explicit missing-instance coverage' }
        lab_verification_required = $lvSourceColumns['V$OBJECT_DEPENDENCY']; added_in = '3.2' }
    [ordered]@{ id = 'DBA_OBJECTS'; name = 'DBA_OBJECTS'; rac_name = $null; kind = 'oracle_view'; columns = @('OWNER', 'OBJECT_NAME', 'SUBOBJECT_NAME', 'OBJECT_ID', 'OBJECT_TYPE', 'CREATED', 'LAST_DDL_TIME', 'STATUS', 'NAMESPACE', 'EDITION_NAME'); grain = 'dictionary_object'; unit_policy = 'Dates normalized to UTC with original timezone retained.'; licensing = $baseLic; reference = $ref + 'DBA_OBJECTS.html'
        limitations = 'V3.2/proposal V32-10: current dictionary state at collection time, not as of the incident. LAST_DDL_TIME also changes on grants and revokes, so it signals only that a definition may have changed.'; fallbacks = @(); audit = $audit; added_in = '3.2' }
    [ordered]@{ id = 'DBA_SYNONYMS'; name = 'DBA_SYNONYMS'; rac_name = $null; kind = 'oracle_view'; columns = @('OWNER', 'SYNONYM_NAME', 'TABLE_OWNER', 'TABLE_NAME', 'DB_LINK', 'ORIGIN_CON_ID'); grain = 'synonym'; unit_policy = 'Identity only.'; licensing = $baseLic; reference = $ref + 'DBA_SYNONYMS.html'
        limitations = 'V3.2/proposal V32-10: current state at collection time; TABLE_NAME may name another synonym (chains); DB_LINK not null means a remote object that is never resolved.'; fallbacks = @(); audit = $audit; added_in = '3.2' }
)

# =============================================================== evidence (V32-02, V32-05, V32-06, V32-08..10)
function Set-Binding($evidence, [string]$sourceId, [string[]]$addColumns, $lvRefs) {
    $list = [System.Collections.Generic.List[object]]::new(); $found = $false
    foreach ($b in $evidence.bindings) {
        if ($b.source_id -eq $sourceId) {
            $found = $true
            $nb = Copy-Ordered $b
            $cols = [System.Collections.Generic.List[string]]::new(); foreach ($c in $b.columns) { $cols.Add($c) }
            foreach ($c in $addColumns) { if (-not $cols.Contains($c)) { $cols.Add($c) } }
            $nb['columns'] = $cols.ToArray()
            if ($lvRefs) { $nb['lab_verification_required'] = @($lvRefs) }
            $list.Add($nb)
        } else { $list.Add($b) }
    }
    if (-not $found) {
        $nb = [ordered]@{ source_id = $sourceId; columns = $addColumns; added_in = '3.2' }
        if ($lvRefs) { $nb['lab_verification_required'] = @($lvRefs) }
        $list.Add($nb)
    }
    $evidence.bindings = $list.ToArray()
}
function Add-Fields($evidence, [object[]]$fields) {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $evidence.fields) { $list.Add($f) }
    foreach ($f in $fields) { $list.Add($f) }
    $evidence.fields = $list.ToArray()
}
$ev = @{}; foreach ($e in $v31.evidence) { $ev[$e.id] = $e }

$sql = $ev['sql']
Add-Fields $sql @((Field 'module' 'string' 'identity'), (Field 'action' 'string' 'identity'), (Field 'service' 'string' 'identity'), (Field 'capture_status' 'string' 'flag'), (Field 'command_type' 'number' 'identity'))
Set-Binding $sql 'V$SQL' @('MODULE', 'ACTION', 'SERVICE') $null
Set-Binding $sql 'DBA_HIST_SQLSTAT' @('DBID', 'INSTANCE_NUMBER', 'SNAP_ID', 'FORCE_MATCHING_SIGNATURE', 'MODULE', 'ACTION', 'PARSING_SCHEMA_NAME', 'PARSE_CALLS_DELTA', 'END_OF_FETCH_COUNT_DELTA', 'PX_SERVERS_EXECS_DELTA', 'CON_ID') $null
Set-Binding $sql 'DBA_HIST_SQLTEXT' @('SQL_ID', 'SQL_TEXT', 'COMMAND_TYPE', 'CON_ID') $null
$sql.normalization = $sql.normalization + ' V3.2: capture_status is captured or not_captured (contract.capture_bias_policy); DBA_HIST_SQLSTAT has no exact signature or service (null, not empty). Historical aggregates over captured rows are lower_bound for any population that may include uncaptured SQL.'

$sqlTemplate = [ordered]@{
    id = 'sql_template'; type = 'table'
    fields = @((Field 'sql_id' 'string' 'identity'), (Field 'strict_template_hash' 'string' 'identity'), (Field 'loose_template_hash' 'string' 'identity'), (Field 'literal_vector' 'string' 'text'), (Field 'risk_literal_vector' 'string' 'text'), (Field 'bind_positions' 'string' 'text'), (Field 'identifier_set' 'string' 'text'), (Field 'statement_keyword' 'string' 'identity'), (Field 'normalization_status' 'string' 'flag'), (Field 'normalizer_version' 'string' 'identity'), (Field 'text_source' 'string' 'identity'), (Field 'text_complete' 'boolean' 'flag'), (Field 'parsing_schema' 'string' 'identity'))
    bindings = @(
        [ordered]@{ source_id = 'V$SQL'; columns = @('SQL_ID', 'SQL_FULLTEXT', 'PARSING_SCHEMA_NAME') }
        [ordered]@{ source_id = 'DBA_HIST_SQLTEXT'; columns = @('SQL_ID', 'SQL_TEXT', 'COMMAND_TYPE') }
        [ordered]@{ source_id = 'V$SQL_MONITOR'; columns = @('SQL_ID', 'SQL_TEXT', 'IS_FULL_SQLTEXT') }
    )
    normalization = 'V32-02: produced by the lexical normalizer under contract.normalizer_policy from complete text only, recording normalizer_version. Unsupported until a normalizer version exists. Lists (literal_vector, bind_positions, identifier_set) are canonical serialized strings.'
    quality = @('envelope_complete', 'source_capability_allowed', 'identity_resolved')
    added_in = '3.2'
}

$sessions = $ev['sessions']
Add-Fields $sessions @((Field 'force_signature' 'string' 'identity'), (Field 'top_level_sql_id' 'string' 'identity'), (Field 'sql_opcode' 'number' 'identity'), (Field 'module' 'string' 'identity'), (Field 'action' 'string' 'identity'), (Field 'service_hash' 'string' 'identity'), (Field 'plan_hash' 'string' 'identity'), (Field 'temp_bytes' 'number' 'bytes'), (Field 'pga_bytes' 'number' 'bytes'), (Field 'is_sqlid_current' 'string' 'flag'), (Field 'tm_cpu_s' 'number' 'seconds'), (Field 'tm_time_s' 'number' 'seconds'), (Field 'sample_epoch_s' 'number' 'seconds'))
$ashCols = @('SAMPLE_TIME', 'SAMPLE_TIME_UTC', 'FORCE_MATCHING_SIGNATURE', 'TOP_LEVEL_SQL_ID', 'SQL_OPCODE', 'MODULE', 'ACTION', 'SERVICE_HASH', 'SQL_PLAN_HASH_VALUE', 'IS_SQLID_CURRENT', 'TEMP_SPACE_ALLOCATED', 'PGA_ALLOCATED', 'TM_DELTA_CPU_TIME', 'TM_DELTA_TIME', 'CONSUMER_GROUP_ID', 'CON_ID')
Set-Binding $sessions 'V$ACTIVE_SESSION_HISTORY' $ashCols $null
Set-Binding $sessions 'DBA_HIST_ACTIVE_SESS_HISTORY' (@('DBID', 'INSTANCE_NUMBER', 'SNAP_ID') + $ashCols) $null
Set-Binding $sessions 'DBA_HIST_SERVICE_NAME' @('SERVICE_NAME_HASH', 'SERVICE_NAME') $null
$sessions.normalization = $sessions.normalization + ' V3.2: temp_bytes/pga_bytes are per session at the sample instant and attributed to the current SQL (record top_level_sql_id and is_sqlid_current). Persisted-ASH per-instant aggregates are lower_bound (LV-06). TM_DELTA_* windows from persisted samples do not tile time and are never summed into totals; tm_cpu_s/tm_time_s is a per-sample CPU rate only. Group mapping uses CONSUMER_GROUP_ID.'

$rmId = 'r' + 'm'
$rmEv = $ev[$rmId]
Add-Fields $rmEv @((Field 'cpu_count' 'number' 'count'), (Field 'plan_start_utc' 'string' 'identity'), (Field 'plan_end_utc' 'string' 'identity'), (Field 'cpu_waits' 'number' 'count'), (Field 'yields' 'number' 'count'))
Set-Binding $rmEv 'DBA_HIST_RSRC_PLAN' @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'SEQUENCE#', 'START_TIME', 'END_TIME', 'PLAN_NAME', 'CPU_MANAGED', 'INSTANCE_CAGING', 'CON_ID') $null
Set-Binding $rmEv 'DBA_HIST_RSRC_CONSUMER_GROUP' @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'SEQUENCE#', 'CONSUMER_GROUP_ID', 'CONSUMER_GROUP_NAME', 'CONSUMED_CPU_TIME', 'CPU_WAIT_TIME', 'CPU_WAITS', 'YIELDS', 'CON_ID') @((LV 'CPU_WAIT_TIME' 'LV-01'))
Set-Binding $rmEv 'DBA_HIST_PARAMETER' @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'PARAMETER_NAME', 'VALUE', 'CON_ID') $null
Set-Binding $rmEv 'DBA_HIST_SNAPSHOT' @('DBID', 'INSTANCE_NUMBER', 'SNAP_ID', 'STARTUP_TIME', 'BEGIN_INTERVAL_TIME', 'END_INTERVAL_TIME') $null
$rmEv.normalization = $rmEv.normalization + ' V3.2/V32-06: historical group cpu_s from CONSUMED_CPU_TIME deltas (ms) within the same instance startup and SEQUENCE#; historical wait_s from CPU_WAIT_TIME carries lab_verification_required (LV-01); cpu_count from DBA_HIST_PARAMETER (cpu_count only) per instance and snapshot; plan and caging from DBA_HIST_RSRC_PLAN. Per instance, never pooled.'

$os = $ev['os']
Add-Fields $os @((Field 'provenance' 'string' 'identity'), (Field 'num_cpus' 'number' 'count'), (Field 'rsrc_mgr_cpu_wait_s' 'number' 'seconds'), (Field 'os_cpu_wait_s' 'number' 'seconds'), (Field 'busy_s' 'number' 'seconds'), (Field 'idle_s' 'number' 'seconds'))
Set-Binding $os 'DBA_HIST_OSSTAT' @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'STAT_NAME', 'VALUE', 'CON_ID') @((LV 'VALUE' 'LV-07'))
Set-Binding $os 'DBA_HIST_SNAPSHOT' @('DBID', 'INSTANCE_NUMBER', 'SNAP_ID', 'STARTUP_TIME', 'BEGIN_INTERVAL_TIME', 'END_INTERVAL_TIME') $null
$os.normalization = $os.normalization + ' V3.2/V32-10: provenance oracle_host for DBA_HIST_OSSTAT (host of the instance, snapshot-interval deltas in hundredths of a second /100); busy_fraction = delta BUSY_TIME/(delta BUSY_TIME + delta IDLE_TIME) as interval_average; run_queue from LOAD as a point sample (sampled_estimate); num_cpus from NUM_CPUS. OS-dependent statistics may be absent (LV-07). provenance os_telemetry is reserved for the OS module.'

$depEv = $ev['dependencies']
Add-Fields $depEv @((Field 'sql_id' 'string' 'identity'), (Field 'resolved_object_id' 'string' 'identity'), (Field 'resolved_object_type' 'string' 'text'), (Field 'dependency_grade' 'string' 'flag'), (Field 'grade_basis' 'string' 'text'), (Field 'synonym_chain' 'string' 'text'), (Field 'closure_depth' 'number' 'count'), (Field 'plan_corroboration' 'string' 'flag'), (Field 'definition_may_have_changed' 'boolean' 'flag'), (Field 'resolution_as_of' 'string' 'identity'), (Field 'inst_id' 'number' 'identity'), (Field 'con_id' 'number' 'identity'))
Set-Binding $depEv 'V$OBJECT_DEPENDENCY' @('FROM_ADDRESS', 'FROM_HASH', 'TO_OWNER', 'TO_NAME', 'CON_ID') @((LV 'FROM_ADDRESS' 'LV-03'), (LV 'FROM_HASH' 'LV-03'), (LV 'TO_NAME' 'LV-03'))
Set-Binding $depEv 'V$SQL' @('SQL_ID', 'CHILD_NUMBER', 'ADDRESS', 'HASH_VALUE', 'PARSING_SCHEMA_NAME', 'FIRST_LOAD_TIME', 'CON_ID') $null
Set-Binding $depEv 'DBA_OBJECTS' @('OWNER', 'OBJECT_NAME', 'SUBOBJECT_NAME', 'OBJECT_ID', 'OBJECT_TYPE', 'CREATED', 'LAST_DDL_TIME', 'STATUS', 'NAMESPACE', 'EDITION_NAME') $null
Set-Binding $depEv 'DBA_SYNONYMS' @('OWNER', 'SYNONYM_NAME', 'TABLE_OWNER', 'TABLE_NAME', 'DB_LINK', 'ORIGIN_CON_ID') $null
Set-Binding $depEv 'V$SQL_PLAN' @('SQL_ID', 'CHILD_NUMBER', 'CON_ID') $null
Set-Binding $depEv 'DBA_HIST_SQL_PLAN' @('DBID', 'SQL_ID', 'PLAN_HASH_VALUE', 'ID', 'OBJECT#') $null
$depEv.normalization = $depEv.normalization + ' V3.2/proposal V32-10: one row per (member sql_id, resolved_object_id) link with dependency_grade D1-D4 per contract.dependency_evidence_policy. D1 rows carry lab_verification_required (LV-03). D2 uses sql_template.identifier_set and parsing schema resolution through DBA_OBJECTS/DBA_SYNONYMS. plan_corroboration is corroborated, contradicted or no_plan. resolution_as_of records the dictionary collection time. Missing cursor, text or plan gives not_captured, never non-dependency.'

$capEv = $ev['capability']
Set-Binding $capEv 'DBA_HIST_PARAMETER' @('SNAP_ID', 'INSTANCE_NUMBER', 'PARAMETER_NAME', 'VALUE') $null
Set-Binding $capEv 'DBA_HIST_RSRC_PLAN' @('SNAP_ID', 'INSTANCE_NUMBER', 'START_TIME', 'END_TIME', 'PLAN_NAME', 'CPU_MANAGED', 'INSTANCE_CAGING') $null

# =============================================================== metrics
$metricOut = [System.Collections.Generic.List[object]]::new()
$metricUpdates = @{
    family_members = @{ inputs_add = @('sql_template.strict_template_hash', 'sql_template.loose_template_hash', 'sql_template.normalization_status', 'sql.schema', 'sql.plan_hash', 'sql.module', 'sql.action', 'sessions.force_signature'); params = [ordered]@{ tiers = 'contract.family_policy.tiers'; tier_output = 'member tier and tier basis per member'; ast_alternative = 'ast inputs remain an optional F2 path when a parser exists' } }
    family_member_count = @{ params = [ordered]@{ membership = 'tier_ge_F2 (contract.family_policy.purpose_matrix)' } }
    family_cpu_share = @{ params = [ordered]@{ numerator_population = 'family_members_tier_ge_F2'; coverage = 'contract.family_coverage_policy' } }
    group_cpu_share = @{ params = [ordered]@{ sql_population = 'family_members_tier_ge_F2_with_single_observed_group'; historical = 'numerator DBA_HIST_SQLSTAT CPU_TIME_DELTA of tier>=F2 members (lower_bound under capture bias); denominator DBA_HIST_RSRC_CONSUMER_GROUP CONSUMED_CPU_TIME delta for the observed group, same instance and interval'; group_mapping_metric = 'family_observed_group_mapping' } }
    common_dependency_count = @{ inputs_replace = @('dependencies.sql_id', 'dependencies.resolved_object_id', 'dependencies.dependency_grade', 'family_members')
        params = [ordered]@{ counted = 'distinct tier>=F2 member SQL_IDs linked to the same resolved OBJECT_ID'; minimum_grade = 'D2'; grade_policy = 'contract.dependency_evidence_policy'; lab_gated_grade = 'D1 counts only when LV-03 is resolved; until then lab mode only'; bound = 'exact only when every in-scope member is graded; otherwise lower_bound'; output = 'per object: members by grade, ungraded members, downgrade reasons'; ast_alternative = 'resolved references from a future parser may supply an additional D2 basis'; not = 'family equivalence, causation or identical work beneath the object' } }
    common_path_work = @{ params = [ordered]@{ population = 'member_execution_common_dependency_leaf_operation_tier_ge_F2'; dependency_grade_min = 'D2 link to the common object (contract.dependency_evidence_policy)'; caution = 'Measured per member and plan stratum; never implies identical work beneath the object.' } }
    family_temp_share = @{ params = [ordered]@{ numerator_population = 'family_members_tier_ge_F2' } }
    cpu_demand_deviation = @{ params = [ordered]@{ match = 'same_family_membership_tier_ge_F2_window_configuration' } }
}
$estimateMetrics = @('host_queue')
$averageMetrics = @('host_busy', 'rm_wait_share', 'group_limit_utilization')
foreach ($m in $v31.metrics) {
    $nm = Copy-Ordered $m
    if ($metricUpdates.ContainsKey($m.id)) {
        $u = $metricUpdates[$m.id]
        if ($u.inputs_replace) { $nm['inputs'] = [string[]]$u.inputs_replace }
        if ($u.inputs_add) { $inp = [System.Collections.Generic.List[string]]::new(); foreach ($x in $m.inputs) { $inp.Add($x) }; foreach ($x in $u.inputs_add) { if (-not $inp.Contains($x)) { $inp.Add($x) } }; $nm['inputs'] = $inp.ToArray() }
        if ($u.params) { $p = Copy-Ordered $m.parameters; foreach ($k in $u.params.Keys) { $p[$k] = $u.params[$k] }; $nm['parameters'] = $p }
        $nm['revised_in'] = '3.2'
    }
    $accepts = [System.Collections.Generic.List[string]]::new(); foreach ($x in @('exact', 'lower_bound', 'upper_bound', 'bounded_interval')) { $accepts.Add($x) }
    if ($m.operator -eq 'weighted_sample_share' -or $estimateMetrics -contains $m.id) { $accepts.Add('sampled_estimate') }
    if ($m.operator -eq 'rate' -or $averageMetrics -contains $m.id) { $accepts.Add('interval_average') }
    $nm['value_semantics'] = [ordered]@{ accepts = $accepts.ToArray(); derivation = 'V3.2 default by operator: rate -> interval_average; weighted_sample_share -> sampled_estimate; explicit metric overrides listed in change record.' }
    $metricOut.Add($nm)
}
function NewMetric([string]$id, [string]$op, [string[]]$inputs, [string]$unit, $params, [string[]]$groupBy, [string[]]$accepts, [string]$change, [string[]]$lv) {
    $m = [ordered]@{ id = $id; operator = $op; inputs = $inputs; unit = $unit; parameters = $params; group_by = $groupBy; null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q
        value_semantics = [ordered]@{ accepts = $accepts; derivation = 'declared in V3.2' }; added_in = '3.2'; change = $change }
    if ($lv) { $m['lab_verification_required'] = $lv }
    return $m
}
$std = @('exact', 'lower_bound', 'upper_bound', 'bounded_interval')
$newMetrics = @(
    (NewMetric 'rm_group_consumed_cpu_interval' 'delta' @('rm.cpu_s') 'seconds' ([ordered]@{ source = 'DBA_HIST_RSRC_CONSUMER_GROUP CONSUMED_CPU_TIME (ms)'; delta_required = $true; same = 'DBID/INSTANCE_NUMBER/instance startup/SEQUENCE#/CONSUMER_GROUP_ID' }) @('inst_id', 'group_id', 'snapshot_interval') $std 'V32-06' $null)
    (NewMetric 'rm_group_cpu_wait_interval' 'delta' @('rm.wait_s') 'seconds' ([ordered]@{ source = 'DBA_HIST_RSRC_CONSUMER_GROUP CPU_WAIT_TIME'; delta_required = $true; unit_status = 'undocumented; LV-01' }) @('inst_id', 'group_id', 'snapshot_interval') $std 'V32-06' @('LV-01'))
    (NewMetric 'rm_instance_wait_share_interval' 'ratio' @('os.rsrc_mgr_cpu_wait_s', 'rm.cpu_s') 'ratio' ([ordered]@{ numerator = 'delta RSRC_MGR_CPU_WAIT_TIME of the instance (DBA_HIST_OSSTAT, hundredths of a second)'; denominator_add = 'os.rsrc_mgr_cpu_wait_s'; denominator = 'sum over groups of rm_group_consumed_cpu_interval plus the numerator, same instance and interval'; grain = 'instance_snapshot_interval'; caution = 'Instance-level only; does not identify which group waited.' }) @('inst_id', 'snapshot_interval') @('exact', 'lower_bound', 'upper_bound', 'bounded_interval', 'interval_average') 'V32-06/V32-10' $null)
    (NewMetric 'caged_capacity_utilization' 'ratio' @('rm.cpu_s', 'rm.cpu_count') 'ratio' ([ordered]@{ numerator = 'sum over groups of rm_group_consumed_cpu_interval'; denominator = 'interval seconds x cpu_count in force (DBA_HIST_PARAMETER), same instance'; require = 'INSTANCE_CAGING=ON for the interval (DBA_HIST_RSRC_PLAN); otherwise UNKNOWN'; caution = 'Foreground consumer-group CPU only; interval average, never a peak.' }) @('inst_id', 'snapshot_interval') @('exact', 'lower_bound', 'upper_bound', 'bounded_interval', 'interval_average') 'V32-06' $null)
    (NewMetric 'family_observed_group_mapping' 'count_distinct' @('sessions.group_id', 'family_members') 'count' ([ordered]@{ population = 'persisted or in-memory ASH samples of tier>=F2 members in the window'; output = 'distinct consumer groups with sample counts'; single_group_required_for = 'group_cpu_share' }) @('family_window', 'inst_id') @('exact', 'lower_bound', 'sampled_estimate') 'V32-06' $null)
    (NewMetric 'family_ash_member_count' 'count_distinct' @('sessions.sql_id', 'family_members') 'count' ([ordered]@{ population = 'members tier>=F1 seen in ASH samples'; bound = 'lower_bound (sampled; short or idle executions may be unsampled)' }) @('family_window') $std 'V32-07' $null)
    (NewMetric 'family_sqlstat_capture_share' 'weighted_sample_share' @('sessions.sample_duration_s', 'sessions.sql_id', 'sql.capture_status') 'ratio' ([ordered]@{ numerator = 'ASH sample duration of family members that have DBA_HIST_SQLSTAT rows in the same snapshot intervals'; denominator = 'ASH sample duration of all family members'; semantics = 'sampled estimate of how much family activity SQLSTAT aggregates cover' }) @('family_window', 'inst_id') @('sampled_estimate') 'V32-07' $null)
    (NewMetric 'family_text_capture_share' 'weighted_sample_share' @('sessions.sample_duration_s', 'sessions.sql_id', 'sql_template.text_complete') 'ratio' ([ordered]@{ numerator = 'ASH sample duration of family members with complete text'; denominator = 'ASH sample duration of all family members'; semantics = 'sampled estimate of how much family activity can reach F2' }) @('family_window', 'inst_id') @('sampled_estimate') 'V32-07' $null)
    (NewMetric 'ash_execution_temp_peak_lb' 'simultaneous_sum' @('sessions.temp_bytes', 'sessions.execution_key', 'sessions.sample_epoch_s') 'bytes' ([ordered]@{ deduplicate = 'session per sample instant'; group = 'QC execution key (QC and PX sessions)'; bound = 'lower_bound' }) @('execution_key') $std 'V32-08' $null)
    (NewMetric 'ash_temp_occupancy_lb' 'simultaneous_sum' @('sessions.temp_bytes', 'sessions.sample_epoch_s') 'bytes' ([ordered]@{ deduplicate = 'session per sample instant'; scope = 'instance'; bound = 'lower_bound' }) @('inst_id', 'window') $std 'V32-08' $null)
    (NewMetric 'ash_cluster_temp_occupancy_lb' 'simultaneous_sum' @('sessions.temp_bytes', 'sessions.sample_epoch_s', 'sessions.inst_id') 'bytes' ([ordered]@{ deduplicate = 'session per sample instant'; time_alignment = 'instants aligned within the observed sample spacing and clock uncertainty'; scope = 'cluster'; bound = 'lower_bound' }) @('window') $std 'V32-08' $null)
    (NewMetric 'ash_family_temp_lb' 'simultaneous_sum' @('sessions.temp_bytes', 'sessions.sample_epoch_s', 'family_members') 'bytes' ([ordered]@{ population = 'sessions of tier>=F2 members (record top_level_sql_id/is_sqlid_current)'; bound = 'lower_bound' }) @('family_window') $std 'V32-08' $null)
    (NewMetric 'ash_family_temp_share' 'ratio' @('sessions.temp_bytes', 'sessions.temp_bytes') 'ratio' ([ordered]@{ numerator_population = 'family_members_tier_ge_F2 sessions at each instant'; denominator_population = 'all sampled sessions at the same instants'; aggregate = 'sum'; semantics = 'sampled_estimate' }) @('family_window') @('sampled_estimate') 'V32-08' $null)
    (NewMetric 'report_execution_temp_ub' 'sum' @('plan.temp_bytes', 'plan.execution_key') 'bytes' ([ordered]@{ source = 'AWR-captured SQL Monitor report per-line, per-process maximum TEMP'; bound = 'upper_bound of the simultaneous execution peak'; caution = 'Maxima need not coincide in time.' }) @('execution_key') @('upper_bound', 'bounded_interval') 'V32-08' @('LV-05'))
    (NewMetric 'ash_concurrent_executions_lb' 'overlap_count' @('sessions.execution_key', 'sessions.sample_epoch_s') 'count' ([ordered]@{ deduplicate = 'qc_execution_key'; mode = 'distinct execution keys per sample instant, maximum over instants'; bound = 'lower_bound; executions idle between fetches are invisible' }) @('sql_or_family_window', 'inst_id') $std 'V32-09' $null)
    (NewMetric 'sql_interval_db_time_rate' 'rate' @('sql.elapsed_s') 'ratio' ([ordered]@{ semantics = 'ELAPSED_TIME_DELTA seconds per interval second (average active database time, including PX)'; not = 'execution count or concurrency peak' }) @('sql_or_family_window', 'snapshot_interval') @('exact', 'lower_bound', 'interval_average') 'V32-09' $null)
)
foreach ($m in $newMetrics) { $metricOut.Add($m) }
$metricById = @{}; foreach ($m in $metricOut) { $metricById[[string]$m.id] = $m }

# =============================================================== rules
$ruleChanges = @{
    'RM-001' = @{ detection = (All-Of @((Cmp 'rm_waiter_count' 'gt' 0), (Any-Of @((Cmp 'rm_wait_share' 'gt' 0), (Cmp 'rm_instance_wait_share_interval' 'gt' 0))))); note = 'V32-06: allocation wait may be evidenced by group-level (rm_wait_share) or documented instance-level historical wait.' }
    'RM-002' = @{ attribution = (Any-Of @((Cmp 'rm_wait_share' 'gt' 'rm_pressure_share'), (Cmp 'rm_instance_wait_share_interval' 'gt' 'rm_pressure_share')))
        add_supporting = @([ordered]@{ test = (Cmp 'caged_capacity_utilization' 'gt' 'allocation_utilization_bound'); independence_group = 'capacity_utilization'; effect = 'support_caging_constraint'; stage = 'attribution' })
        add_counter = @([ordered]@{ id = 'RM-002-host-saturated'; effect = 'weaken_caging_as_sole_constraint'; independence_group = 'host_cpu'; stage = 'attribution'; test = (Cmp 'host_busy' 'gt' 'host_busy_bound'); explanation = 'A saturated host means host contention may coexist with caging; caging is not the sole constraint. Never eliminates either.' })
        note = 'V32-06/V32-10: instance-level historical wait share; caged-capacity support; host saturation counter.' }
    'RM-004' = @{ add_counter = @([ordered]@{ id = 'RM-004-host-spare'; effect = 'weaken_host_contention'; independence_group = 'host_cpu'; stage = 'attribution'; test = (Cmp 'host_busy' 'le' 'host_busy_bound'); explanation = 'Interval-average host CPU within tolerance weakens host-wide contention; it cannot exclude sub-interval spikes or per-process noisy neighbours.' }); note = 'V32-10.' }
    'FAM-003' = @{ detection = (All-Of @((Any-Of @((Cmp 'concurrent_execution_count' 'gt' 1), (Cmp 'ash_concurrent_executions_lb' 'gt' 1))), (Cmp 'concurrency_deviation' 'gt' 'concurrency_deviation_bound')))
        attribution = (Any-Of @((Cmp 'peak_temp_occupancy' 'gt' 'temp_budget_bytes'), (Cmp 'ash_cluster_temp_occupancy_lb' 'gt' 'temp_budget_bytes'))); note = 'V32-08/V32-09: ASH lower bounds accepted for gt comparisons only.' }
    'FAM-004' = @{ detection_evidence = @('dependencies'); detection_optional = @('sql_template', 'plan', 'ast'); note = 'Proposal V32-10 (accepted with conditions): detection reads graded dependency evidence (contract.dependency_evidence_policy); D1/D2 links only, D1 lab-gated by LV-03. No parser required. Conclusion ceiling, attribution and causal gates unchanged.' }
    'TEMP-004' = @{ detection = (Any-Of @((Cmp 'peak_temp_occupancy' 'gt' 'temp_budget_bytes'), (Cmp 'ash_cluster_temp_occupancy_lb' 'gt' 'temp_budget_bytes'))); note = 'V32-08: historical occupancy lower bound.' }
}
$rmOwned = @('RM-001', 'RM-002', 'RM-003', 'RM-004', 'RM-005', 'RM-006')
$rulesOut = [System.Collections.Generic.List[object]]::new()
foreach ($r in $v31.rules) {
    if ($r.alias_of) { $rulesOut.Add($r); continue }
    $nr = Copy-Ordered $r
    # Assign in branches: an if-expression would unroll the one-element consumers array.
    if ($rmOwned -contains $r.id) { $nr['knowledge_owner'] = 'database_health'; $nr['consumers'] = [string[]]@('database_health', 'query_tuner') }
    else { $nr['knowledge_owner'] = 'query_tuner'; $nr['consumers'] = [string[]]@('query_tuner') }
    if ($ruleChanges.ContainsKey($r.id)) {
        $ch = $ruleChanges[$r.id]
        $stages = Copy-Ordered $r.stages
        if ($ch.detection) { $d = Copy-Ordered $r.stages.detection; $d['decision'] = $ch.detection; $stages['detection'] = $d }
        if ($ch.detection_evidence) { $d = Copy-Ordered $stages['detection']; $d['evidence'] = [string[]]$ch.detection_evidence; $d['optional_evidence'] = [string[]]$ch.detection_optional; $stages['detection'] = $d }
        if ($ch.attribution) { $a = Copy-Ordered $r.stages.attribution; $a['test'] = $ch.attribution; $stages['attribution'] = $a }
        $nr['stages'] = $stages
        if ($ch.add_supporting) { $l = [System.Collections.Generic.List[object]]::new(); foreach ($t in $r.supporting_tests) { $l.Add($t) }; foreach ($t in $ch.add_supporting) { $l.Add($t) }; $nr['supporting_tests'] = $l.ToArray() }
        if ($ch.add_counter) { $l = [System.Collections.Generic.List[object]]::new(); foreach ($t in $r.counter_tests) { $l.Add($t) }; foreach ($t in $ch.add_counter) { $l.Add($t) }; $nr['counter_tests'] = $l.ToArray() }
        $used = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($s in @($nr['stages'].detection, $nr['stages'].attribution, $nr['stages'].validation)) { if ($s) { foreach ($k in @('decision', 'test', 'disconfirm_test')) { $x = Val-Of $s $k; if ($x) { Collect-Metrics $x $used } } } }
        foreach ($t in @($nr['counter_tests']) + @($nr['supporting_tests'])) { if ($t) { Collect-Metrics (Val-Of $t 'test') $used } }
        $dm = [System.Collections.Generic.List[string]]::new(); foreach ($x in $r.derived_metrics) { $dm.Add($x) }; foreach ($x in $used) { if (-not $dm.Contains($x)) { $dm.Add($x) } }
        $nr['derived_metrics'] = $dm.ToArray()
        foreach ($x in $used) { if (-not $metricById.ContainsKey($x)) { $problems.Add("$($r.id) uses undefined metric $x") } }
        $nr['v3_2_change'] = $ch.note
    }
    $rulesOut.Add($nr)
}

# =============================================================== cross-module requests (V32-04)
$fulfilment = @{
    'DB-RESOURCE' = @(
        [ordered]@{ provider = 'resource_mgr'; evidence_ids = @($rmId); coverage = 'full_for_listed_evidence'; limits = 'Group-level historical wait is lab_verification_required (LV-01).' }
        [ordered]@{ provider = 'instance_runtime'; evidence_ids = @('system'); coverage = 'full_for_listed_evidence'; limits = 'Current instance statistics; historical system statistics are not part of this request.' })
    'OS-CPU' = @([ordered]@{ provider = 'oracle_host'; evidence_ids = @('os'); coverage = 'partial'; limits = 'Host-wide interval averages and point LOAD; no per-database or per-process attribution; cannot eliminate noisy neighbours (contract.host_cpu_policy).' })
}
$requestsOut = [System.Collections.Generic.List[object]]::new()
foreach ($r in $v31.cross_module_requests) {
    $nr = Copy-Ordered $r
    # Assign in branches: an if-expression would unroll the one-element arrays.
    if ($fulfilment.ContainsKey($r.id)) { $nr['provider_fulfillment'] = [object[]]$fulfilment[$r.id] } else { $nr['provider_fulfillment'] = [object[]]@() }
    $nr['owner_module_required'] = $false
    $nr['consumption'] = 'contract.evidence_flow_policy: provider evidence is collected once and evaluated canonical findings are consumed directly; owner module absence only matters for evidence no provider can supply.'
    $requestsOut.Add($nr)
}

# =============================================================== providers assembled
$sourcesOut = [System.Collections.Generic.List[object]]::new()
foreach ($s in $v31.sources) {
    $ns = Copy-Ordered $s
    if ($columnAdds.Contains($s.id)) {
        $cols = [System.Collections.Generic.List[string]]::new(); foreach ($c in $s.columns) { $cols.Add($c) }
        foreach ($c in $columnAdds[$s.id]) { if (-not $cols.Contains($c)) { $cols.Add($c) } }
        $ns['columns'] = $cols.ToArray(); $ns['limitations'] = $s.limitations + $limitationAdds[$s.id]
    }
    if ($lvSourceColumns.ContainsKey($s.id)) { $ns['lab_verification_required'] = $lvSourceColumns[$s.id] }
    $sourcesOut.Add($ns)
}
foreach ($s in $newSources) { $sourcesOut.Add($s) }
$providerSources = [ordered]@{}; foreach ($k in $providerDefs.Keys) { $providerSources[$k] = [System.Collections.Generic.List[string]]::new() }
foreach ($s in $sourcesOut) {
    $p = Provider-For ([string]$s.id)
    if (-not $p) { $problems.Add("No provider for source $($s.id)"); continue }
    $providerSources[$p].Add([string]$s.id)
    $s['provider'] = $p
}
$evidenceOut = [System.Collections.Generic.List[object]]::new(); foreach ($e in $v31.evidence) { $evidenceOut.Add($e) }; $evidenceOut.Add($sqlTemplate)
$providers = [System.Collections.Generic.List[object]]::new()
foreach ($k in $providerDefs.Keys) {
    $srcs = $providerSources[$k].ToArray()
    $eids = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $evidenceOut) { foreach ($b in $e.bindings) { if ($srcs -contains $b.source_id -and -not $eids.Contains([string]$e.id)) { $eids.Add([string]$e.id) } } }
    $d = $providerDefs[$k]
    $providers.Add([ordered]@{ id = $k; scope = $d.scope; owner = $d.owner; available_in_demo = $d.available_in_demo; sources = $srcs; evidence_ids = $eids.ToArray()
        emits = @('evidence envelopes with bound_kind/estimate_kind', 'capability and coverage status', 'provenance and lab_verification_refs'); holds_rules_or_thresholds = $false })
}
$contract['provider_policy'] = [ordered]@{ rule = 'V32-04: each source belongs to exactly one provider; providers are read-only, rule-free and threshold-free.'; providers = $providers.ToArray() }

# =============================================================== acceptance cases
$casesOut = [System.Collections.Generic.List[object]]::new()
foreach ($case in $v31.acceptance_cases) {
    $nc = Copy-Ordered $case
    if ($case.id -eq 'production_family_allocation') {
        $facts = [System.Collections.Generic.List[object]]::new(); foreach ($f in $case.facts) { $facts.Add($f) }
        $facts.Add([ordered]@{ fact = 'Historical family coverage under AWR top-SQL capture bias'; evidence = @('sql', 'sql_template', 'sessions'); metrics = @('family_ash_member_count', 'family_sqlstat_capture_share', 'family_text_capture_share', 'family_member_count'); rules = @('FAM-001', 'CUR-006'); causal_edges = @(); expected = 'Family tier stated per member (F1 for signature-only members); SQLSTAT aggregates reported as lower bounds with capture shares; uncaptured members are not_captured, never absent.' })
        $facts.Add([ordered]@{ fact = 'Historical Resource Manager pressure versus host saturation'; evidence = @($rmId, 'os', 'capability', 'sessions'); metrics = @('rm_instance_wait_share_interval', 'caged_capacity_utilization', 'host_busy', 'rm_group_consumed_cpu_interval', 'family_observed_group_mapping'); rules = @('RM-001', 'RM-002', 'RM-004'); causal_edges = @('CE-11'); expected = 'Plan/caging and cpu_count per instance; interval-level instance wait share and caged utilization; host busy distinguishes caging from host contention at interval granularity without eliminating noisy neighbours; group-level wait remains LV-01.' })
        $facts.Add([ordered]@{ fact = 'Historical TEMP and concurrency bounds'; evidence = @('sessions', 'plan'); metrics = @('ash_execution_temp_peak_lb', 'ash_cluster_temp_occupancy_lb', 'ash_concurrent_executions_lb', 'ash_family_temp_lb', 'ash_family_temp_share'); rules = @('FAM-003', 'TEMP-004'); causal_edges = @('CE-08'); expected = 'Lower bounds and sampled shares only; gt comparisons may become TRUE; occupancy never proven below a budget; report upper bound remains LV-05.' })
        $facts.Add([ordered]@{ fact = 'Graded dependency on PS_C_FEED_DEF_V across family members'; evidence = @('dependencies', 'sql_template', 'plan', 'capability'); metrics = @('common_dependency_count', 'common_path_work'); rules = @('FAM-004'); causal_edges = @(); expected = 'Per-member D1-D4 grades with downgrade reasons and ungraded (not_captured) members; production detection on D2 links only while LV-03 is open; count is a lower bound under incomplete coverage; no family, causation or identical-work claim from the dependency.' })
        $nc['facts'] = $facts.ToArray()
        $neg = [System.Collections.Generic.List[object]]::new(); foreach ($x in $case.negative_perturbations) { $neg.Add($x) }
        $neg.Add([ordered]@{ change = 'A family member SQL_ID is missing from DBA_HIST_SQLSTAT'; expected = 'Member not_captured, never treated as not executed; family aggregates stay lower_bound.' })
        $neg.Add([ordered]@{ change = 'Captured family CPU lower bound is below contributor_share'; expected = 'FAM-005 detection UNKNOWN (lower bound cannot prove le); family never concluded a bystander from incomplete coverage.' })
        $neg.Add([ordered]@{ change = 'Members grouped only by identical normalized text, no corroboration'; expected = 'At most F1 candidate; F2 requires schema/statement-type/literal-type agreement plus corroboration; no application equivalence claimed.' })
        $neg.Add([ordered]@{ change = 'Host busy fraction low while instance Resource Manager wait share high'; expected = 'Supports caging/group policy over host contention (RM-004 weakened); noisy neighbours not eliminated.' })
        $neg.Add([ordered]@{ change = 'Only DBA_HIST_RSRC_CONSUMER_GROUP CPU_WAIT_TIME shows group waits'; expected = 'lab_verification_required (LV-01); group-level wait share UNKNOWN in production.' })
        $neg.Add([ordered]@{ change = 'ASH sample shows an execution session holding 8 GB TEMP'; expected = 'Lower bound of the execution peak; never reported as the exact peak.' })
        $neg.Add([ordered]@{ change = 'Two members contain the token PS_C_FEED_DEF_V but their parsing schemas resolve it to different objects'; expected = 'No common dependency (different OBJECT_ID); the shared token is not a dependency.' })
        $neg.Add([ordered]@{ change = 'Only V$OBJECT_DEPENDENCY rows link the members to the view'; expected = 'D1 lab_verification_required (LV-03); FAM-004 detection UNKNOWN in production unless D2 links exist.' })
        $neg.Add([ordered]@{ change = 'Members share only base tables of the view in their executed plans'; expected = 'D3 object coincidence (cohort); FAM-004 detection not TRUE; no family tier change.' })
        $neg.Add([ordered]@{ change = 'A captured plan of a member accesses nothing in the closure of the resolved view'; expected = 'D2 downgraded to D4 (plan_contradicts_reference) for that member.' })
        $neg.Add([ordered]@{ change = 'LAST_DDL_TIME of the view is later than the incident window start'; expected = 'definition_may_have_changed; links capped at D4 for that window.' })
        $neg.Add([ordered]@{ change = 'A member cursor aged out and its text was not captured'; expected = 'Member ungraded (not_captured); count stays a lower bound; never concluded independent of the view.' })
        $neg.Add([ordered]@{ change = 'Common D2 dependency established for many members while common_path_work is unavailable'; expected = 'FAM-004 detection observation only; attribution UNKNOWN; no claim of family equivalence, identical work beneath the view or causation.' })
        $nc['negative_perturbations'] = $neg.ToArray()
    }
    $casesOut.Add($nc)
}

# =============================================================== assemble
if ($problems.Count) { $problems | ForEach-Object { Write-Output "MIGRATION ERROR: $_" }; exit 1 }
$ops = Copy-Ordered $v31.operators
$ops['family_group'] = 'V3.2: assign each SQL_ID a family tier (C/F1/F2/F3) per contract.family_policy from signatures, sql_template hashes, parsing schema, statement type, literal-type vectors, risk-literal values and corroboration (signature, plan objects, module/action). Plan/object/module similarity alone yields cohort only. Output membership versioned with tier basis; never merges on normalized text alone into F3.'
$changeLog = [System.Collections.Generic.List[object]]::new(); foreach ($x in $v31.change_log) { $changeLog.Add($x) }
foreach ($x in @(
    @('V32-01', 'accepted', 'Family tiers C/F1/F2/F3, split rules, purpose matrix; validated-membership metrics now require tier >= F2.'),
    @('V32-02', 'accepted_with_constraints', 'Lexical normalizer contract and sql_template evidence; grouping and supporting evidence only; no semantic claim; parser not required for first engine.'),
    @('V32-03', 'strongly_accepted', 'bound_kind on every value; interval comparison semantics; metric value_semantics.accepts; no silent bound/threshold comparison.'),
    @('V32-04', 'strongly_accepted_with_architecture_modification', 'Collect once, normalize once, define canonical fact once, many consumers; providers own sources; RM rules owned by database_health and consumed directly by query_tuner.'),
    @('V32-05', 'accepted', 'Historical signature sources; capture-bias policy; not_captured status.'),
    @('V32-06', 'accepted_with_conditions', 'Historical Resource Manager sources; undocumented CPU_WAIT_TIME unit is lab_verification_required.'),
    @('V32-07', 'strongly_accepted', 'Family coverage measures; coverage restricts conclusions.'),
    @('V32-08', 'accepted_as_estimate_bound_only', 'ASH historical TEMP lower bounds/shares; report upper bound lab-gated.'),
    @('V32-09', 'accepted_as_sampled_bound_evidence', 'ASH historical concurrency lower bounds; interval DB-time rate.'),
    @('V32-10', 'accepted', 'Oracle-recorded host CPU for host saturation vs caging differentiation; never eliminates noisy neighbours.'),
    @('V32-10-dependency', 'accepted_with_conditions', 'Proposal V32-10 (numbering correction; formerly backlog BL-05): graded dependency evidence D1-D4 via V$OBJECT_DEPENDENCY (LV-03 gated), DBA_OBJECTS/DBA_SYNONYMS resolution, DBA_HIST_SQL_PLAN.OBJECT#; attribution/supporting evidence only; never family equivalence, object causation, identical work or causation from common reference.')
)) { $changeLog.Add([ordered]@{ id = $x[0]; decision = $x[1]; summary = $x[2] }) }

$catalog = [ordered]@{}
foreach ($p in $v31.PSObject.Properties) {
    switch ($p.Name) {
        'catalog_version' { $catalog['catalog_version'] = '3.2' }
        'catalog_status' { $catalog['catalog_status'] = 'v3.2-reviewable-specification' }
        'predecessor' { $catalog['predecessor'] = [ordered]@{ path = 'knowledge/sql_tuning_catalog_v3_1.yaml'; version = '3.1'; preservation = 'unchanged historical checkpoint'; sha256 = $v31Hash } }
        'source_manifest' { $catalog['source_manifest'] = [ordered]@{ path = 'knowledge/sql_tuning_sources_19c_v3_2.json'; predecessor_path = 'knowledge/sql_tuning_sources_19c_v3_1.json'; predecessor_sha256 = $manifestHash } }
        'change_log' { $catalog['change_log'] = $changeLog.ToArray(); $catalog['lab_verification_registry'] = $registry; $catalog['backlog'] = $backlog }
        'contract' { $catalog['contract'] = $contract }
        'operators' { $catalog['operators'] = $ops }
        'sources' { $catalog['sources'] = $sourcesOut.ToArray() }
        'evidence' { $catalog['evidence'] = $evidenceOut.ToArray() }
        'metrics' { $catalog['metrics'] = $metricOut.ToArray() }
        'rules' { $catalog['rules'] = $rulesOut.ToArray() }
        'cross_module_requests' { $catalog['cross_module_requests'] = $requestsOut.ToArray() }
        'acceptance_cases' { $catalog['acceptance_cases'] = $casesOut.ToArray() }
        default { $catalog[$p.Name] = $p.Value }
    }
}
Save-Json $catalog $outCatalog

$mSources = [System.Collections.Generic.List[object]]::new()
foreach ($s in $manifest.sources) {
    $ns = Copy-Ordered $s
    if ($columnAdds.Contains($s.id)) {
        $cols = [System.Collections.Generic.List[string]]::new(); foreach ($c in $s.columns) { $cols.Add($c) }
        foreach ($c in $columnAdds[$s.id]) { if (-not $cols.Contains($c)) { $cols.Add($c) } }
        $ns['columns'] = $cols.ToArray(); $ns['revised_on'] = $AuditDate
    }
    $mSources.Add($ns)
}
foreach ($s in $newSources) { $mSources.Add([ordered]@{ id = $s.id; name = $s.name; kind = $s.kind; columns = $s.columns; requires_all = $s.licensing.requires_all; reference = $s.reference; added_on = $AuditDate }) }
Save-Json ([ordered]@{ oracle_version = $manifest.oracle_version; reviewed_on = $AuditDate; scope = $manifest.scope; catalog_version = '3.2'; predecessor = [ordered]@{ path = 'knowledge/sql_tuning_sources_19c_v3_1.json'; sha256 = $manifestHash }; sources = $mSources.ToArray() }) $outManifest

New-Item -ItemType Directory -Force -Path $outProfileDir | Out-Null
$values = [ordered]@{}
foreach ($t in $v31.thresholds) { $values[$t.id] = [ordered]@{ value = $null; unit = $t.unit; rationale = $null; calibration_refs = @(); bound_kinds_accepted_note = 'Comparison semantics follow contract.bound_policy' } }
Save-Json ([ordered]@{
    profile_schema_version = '1.0'; profile_id = $null; profile_version = $null; catalog_version = '3.2'
    status = 'template_unconfigured'; author = $null; approved_by = $null; approved_on = $null
    scope = [ordered]@{ database = $null; con_id = $null; sql_family = $null; workload = $null }
    notes = 'Template only. Every value is null by design (P8). No defaults are implied.'
    values = $values
}) (Join-Path $outProfileDir 'template.json')

Write-Output "Wrote $outCatalog"
Write-Output "Wrote $outManifest"
Write-Output "Wrote $(Join-Path $outProfileDir 'template.json')"
Write-Output "Rules: $($rulesOut.Count) IDs; metrics: $($metricOut.Count); sources: $($sourcesOut.Count); evidence: $($evidenceOut.Count); providers: $($providers.Count)"
