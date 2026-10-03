<#
Builds the V3.1 SQL tuning knowledge catalog from the unchanged V3 checkpoint.
Applies only the P1-P8 decisions recorded in docs/sql_tuning_v3_1_change_proposals.md.
Outputs (V2 and V3 files are read, never written):
  knowledge/sql_tuning_catalog_v3_1.yaml          (YAML 1.2, JSON subset)
  knowledge/sql_tuning_sources_19c_v3_1.json      (source allowlist for V3.1)
  knowledge/threshold_profiles/template.json      (P8 profile template, all values null)
  docs/sql_tuning_v3_1_rule_stage_map.md          (generated per-rule stage partition)
Knowledge-only: no collector, engine or database access.
#>
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

$v3Path = Join-Path $Root 'knowledge\sql_tuning_catalog_v3.yaml'
$manifestPath = Join-Path $Root 'knowledge\sql_tuning_sources_19c.json'
$outCatalog = Join-Path $Root 'knowledge\sql_tuning_catalog_v3_1.yaml'
$outManifest = Join-Path $Root 'knowledge\sql_tuning_sources_19c_v3_1.json'
$outProfileDir = Join-Path $Root 'knowledge\threshold_profiles'
$outStageMap = Join-Path $Root 'docs\sql_tuning_v3_1_rule_stage_map.md'
$AuditDate = '2026-10-03'

# ---------------------------------------------------------------- JSON output
function Quote-Json([string]$s) {
    $escaped = [regex]::Replace($s, '[\\"\x00-\x1f]', {
        param($m)
        switch ([int][char]$m.Value) {
            34 { '\"' } 92 { '\\' } 10 { '\n' } 13 { '\r' } 9 { '\t' }
            default { '\u{0:x4}' -f [int][char]$m.Value }
        }
    })
    return '"' + $escaped + '"'
}
function Write-JsonValue([System.Text.StringBuilder]$sb, $v, [int]$level) {
    $pad = '  ' * ($level + 1); $end = '  ' * $level
    if ($null -eq $v) { [void]$sb.Append('null'); return }
    if ($v -is [bool]) { [void]$sb.Append($(if ($v) { 'true' } else { 'false' })); return }
    if ($v -is [string]) { [void]$sb.Append((Quote-Json $v)); return }
    if ($v -is [int] -or $v -is [long] -or $v -is [decimal]) { [void]$sb.Append($v.ToString([cultureinfo]::InvariantCulture)); return }
    if ($v -is [double] -or $v -is [single]) { [void]$sb.Append($v.ToString('R', [cultureinfo]::InvariantCulture)); return }
    $names = $null
    if ($v -is [System.Collections.IDictionary]) { $names = @($v.Keys) }
    elseif ($v -is [System.Management.Automation.PSCustomObject]) { $names = @($v.PSObject.Properties | ForEach-Object { $_.Name }) }
    if ($null -ne $names) {
        if ($names.Count -eq 0) { [void]$sb.Append('{}'); return }
        [void]$sb.Append("{`n")
        for ($i = 0; $i -lt $names.Count; $i++) {
            $name = [string]$names[$i]
            # Assign in branches: an if-expression would unroll single-element arrays.
            if ($v -is [System.Collections.IDictionary]) { $value = $v[$name] } else { $value = $v.PSObject.Properties[$name].Value }
            [void]$sb.Append($pad + (Quote-Json $name) + ': ')
            Write-JsonValue $sb $value ($level + 1)
            if ($i -lt $names.Count - 1) { [void]$sb.Append(',') }
            [void]$sb.Append("`n")
        }
        [void]$sb.Append($end + '}'); return
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $items = @($v)
        if ($items.Count -eq 0) { [void]$sb.Append('[]'); return }
        [void]$sb.Append("[`n")
        for ($i = 0; $i -lt $items.Count; $i++) {
            [void]$sb.Append($pad); Write-JsonValue $sb $items[$i] ($level + 1)
            if ($i -lt $items.Count - 1) { [void]$sb.Append(',') }
            [void]$sb.Append("`n")
        }
        [void]$sb.Append($end + ']'); return
    }
    throw "Unsupported JSON value type $($v.GetType().FullName)"
}
function Save-Json($value, [string]$path) {
    $sb = [System.Text.StringBuilder]::new()
    Write-JsonValue $sb $value 0
    [void]$sb.Append("`n")
    [System.IO.File]::WriteAllText($path, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

# ---------------------------------------------------------------- generic access
function Keys-Of($n) { if ($n -is [System.Collections.IDictionary]) { return ,@($n.Keys) } return ,@($n.PSObject.Properties | ForEach-Object { $_.Name }) }
function Val-Of($n, [string]$k) { if ($n -is [System.Collections.IDictionary]) { return $n[$k] } return $n.$k }
function Copy-Ordered($obj) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}
function Load-Json([string]$p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }

# ---------------------------------------------------------------- expression helpers
function Cmp([string]$metric, [string]$op, $right) {
    $r = if ($right -is [string]) { [ordered]@{ threshold = $right } } else { [ordered]@{ literal = $right } }
    return [ordered]@{ op = $op; left = [ordered]@{ metric = $metric }; right = $r }
}
function All-Of([object[]]$items) { if ($items.Count -eq 1) { return $items[0] } return [ordered]@{ all = $items } }
function Any-Of([object[]]$items) { return [ordered]@{ any = $items } }
function Not-Of($item) { return [ordered]@{ not = $item } }
function First-Metric($node) {
    $keys = Keys-Of $node
    if ($keys.Count -eq 1 -and $keys[0] -in @('all', 'any')) { return First-Metric (@(Val-Of $node $keys[0])[0]) }
    if ($keys.Count -eq 1 -and $keys[0] -eq 'not') { return First-Metric (Val-Of $node 'not') }
    foreach ($side in @('left', 'right')) { $o = Val-Of $node $side; if ($o -and (Keys-Of $o) -contains 'metric') { return [string](Val-Of $o 'metric') } }
    throw 'Expression has no metric operand'
}
function Conjuncts($decision) {
    $keys = Keys-Of $decision
    if ($keys.Count -eq 1 -and $keys[0] -eq 'all') { return ,@(Val-Of $decision 'all') }
    return ,@($decision)
}
function Collect-Metrics($node, [System.Collections.Generic.HashSet[string]]$set) {
    if ($null -eq $node) { return }
    $keys = Keys-Of $node
    if ($keys.Count -eq 1 -and $keys[0] -in @('all', 'any')) { foreach ($c in @(Val-Of $node $keys[0])) { Collect-Metrics $c $set }; return }
    if ($keys.Count -eq 1 -and $keys[0] -eq 'not') { Collect-Metrics (Val-Of $node 'not') $set; return }
    foreach ($side in @('left', 'right')) { $o = Val-Of $node $side; if ($o -and (Keys-Of $o) -contains 'metric') { [void]$set.Add([string](Val-Of $o 'metric')) } }
}

# ---------------------------------------------------------------- load inputs
$v3 = Load-Json $v3Path
$manifest = Load-Json $manifestPath
if ($v3.catalog_version -ne '3.0') { throw 'Expected V3.0 input' }
$v3Hash = (Get-FileHash -LiteralPath $v3Path -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$metricOps = @{}; foreach ($m in $v3.metrics) { $metricOps[$m.id] = $m.operator }

# ---------------------------------------------------------------- P1 per-rule stage map
# D/A/V: V3 decision conjuncts (keyed by first metric) assigned to detection / attribution / validation.
# Dover/Aover: replacement expression (P4/P5) that must contain every key listed in Covers.
# AddA: extra attribution conjunct built from existing or P1/P4 metrics. Vm: validation trial metric when V3 decision had none.
# De/Ae: stage-required evidence; Dopt/Aopt: stage-optional evidence. Binds: attribution entity grain.
$FOS = Cmp 'flagged_operation_activity_share' 'gt' 'operation_activity_share'
$opBind = @('operation', 'execution')
$map = [ordered]@{
    'AP-001'    = @{ D = @('full_scans', 'full_scan_options'); V = @('access_gain'); AddA = @($FOS); De = @('plan'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'AP-002'    = @{ D = @('selective_predicates'); V = @('missing_path_gain'); AddA = @($FOS); De = @('ast'); Ae = @('sessions', 'plan'); Binds = @('operation', 'object') }
    'AP-003'    = @{ D = @('visible_valid_indexes'); V = @('unused_index_gain'); AddA = @($FOS); De = @('metadata'); Ae = @('sessions', 'plan'); Binds = @('operation', 'object') }
    'CARD-001'  = @{ D = @('stale_stats'); A = @('estimate_error_ratio'); Vm = 'statistics_gain'; De = @('stats'); Ae = @('plan'); Binds = @('object', 'operation') }
    'CARD-002'  = @{ D = @('histogram_absent', 'distribution_skew'); A = @('estimate_error_ratio'); Vm = 'statistics_gain'; De = @('distribution', 'stats'); Ae = @('plan'); Binds = @('object', 'operation') }
    'CARD-003'  = @{ D = @('distribution_skew'); A = @('estimate_error_ratio'); De = @('distribution'); Ae = @('plan'); Binds = @('object', 'operation') }
    'CARD-004'  = @{ D = @('joint_dependence'); A = @('estimate_error_ratio'); De = @('distribution'); Ae = @('plan'); Binds = @('object', 'operation') }
    'CARD-005'  = @{ D = @('estimate_error_ratio'); De = @('plan') }
    'JOIN-001'  = @{ D = @('nested_loop_operations', 'inner_starts'); A = @('nl_buffers_deviation'); De = @('plan'); Ae = @('sql'); Binds = $opBind }
    'JOIN-002'  = @{ D = @('hash_workareas', 'hash_spills'); De = @('workarea') }
    'JOIN-003'  = @{ D = @('merge_joins', 'merge_sorts'); V = @('merge_gain'); AddA = @($FOS); De = @('plan'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'JOIN-004'  = @{ D = @('cartesian_options'); A = @('cartesian_work_deviation'); De = @('plan'); Ae = @('sql'); Binds = $opBind }
    'JOIN-005'  = @{ D = @('estimate_error_ratio'); V = @('join_order_gain'); De = @('plan') }
    'SORT-001'  = @{ D = @('sort_workareas', 'sort_passes'); De = @('workarea') }
    'SORT-002'  = @{ D = @('aggregate_workareas', 'aggregate_passes'); De = @('workarea') }
    'SORT-003'  = @{ D = @('deduplicate_operations', 'deduplicate_options'); V = @('deduplicate_gain'); AddA = @($FOS); De = @('plan'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'SORT-004'  = @{ D = @('ordering_options'); A = @('ordering_activity_share'); De = @('plan'); Ae = @('sessions'); Binds = $opBind }
    'SUBQ-001'  = @{ D = @('correlated_subqueries'); A = @('subquery_starts'); De = @('ast'); Ae = @('plan'); Binds = $opBind }
    'SUBQ-002'  = @{ D = @('scalar_subqueries'); A = @('subquery_starts'); De = @('ast'); Ae = @('plan'); Binds = $opBind }
    'SUBQ-003'  = @{ D = @('in_exists_subqueries'); V = @('unnesting_gain'); AddA = @((Cmp 'subquery_starts' 'gt' 'starts_bound')); De = @('ast'); Ae = @('plan', 'ast'); Binds = $opBind }
    'SUBQ-004'  = @{ D = @('temp_transformations'); V = @('materialization_gain'); AddA = @($FOS); De = @('plan'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'CUR-001'   = @{ D = @('bind_sensitive_cursors', 'associated_binds'); A = @('bind_stratum_deviation'); De = @('sql', 'binds'); Ae = @('sql'); Binds = @('sql_child', 'bind_stratum') }
    'CUR-002'   = @{ D = @('bind_aware_cursors'); A = @('acs_stratum_deviation'); V = @('acs_gain'); De = @('sql'); Ae = @('sql'); Binds = @('sql_child', 'bind_stratum') }
    'CUR-003'   = @{ D = @('child_count', 'child_bind_mismatch'); A = @('parse_cost_deviation'); De = @('sql', 'cursor'); Ae = @('system'); Binds = @('sql_child', 'instance') }
    'CUR-004'   = @{ D = @('plan_count'); Aover = (Any-Of @((Cmp 'plan_runtime_ratio' 'gt' 'material_deviation'), (Cmp 'awr_plan_elapsed_ratio' 'gt' 'material_deviation'), (Cmp 'awr_plan_buffer_ratio' 'gt' 'material_deviation'))); Covers = @('plan_runtime_ratio'); De = @('sql'); Ae = @('sql'); Aopt = @('executions'); Binds = @('plan_hash', 'execution_or_snapshot_window'); Note = 'P5: plan regression attributable from AWR per-plan aggregates; executions evidence optional.' }
    'CUR-005'   = @{ D = @('disabled_baselines'); A = @('plan_runtime_ratio'); De = @('cursor'); Ae = @('executions'); Binds = @('plan_hash', 'execution') }
    'PAR-001'   = @{ D = @('sample_cpu_share'); De = @('sessions') }
    'PAR-002'   = @{ D = @('sample_io_share'); De = @('sessions') }
    'PAR-003'   = @{ D = @('px_row_skew'); De = @('px') }
    'PAR-004'   = @{ D = @('pga_overallocation', 'workarea_spill_ratio'); De = @('system', 'workarea') }
    'PART-001'  = @{ D = @('requested_partitions', 'unexpected_partitions'); A = @('partition_work_deviation'); De = @('ast', 'plan'); Ae = @('sql'); Binds = @('operation', 'object') }
    'PART-002'  = @{ D = @('unusable_index_partitions'); A = @('partition_index_work_deviation'); De = @('metadata'); Ae = @('sql'); Binds = @('object') }
    'PART-003'  = @{ V = @('partitionwise_gain'); Lab = $true }
    'PART-004'  = @{ D = @('partition_count'); V = @('partition_predicate_gain'); AddA = @($FOS); De = @('metadata'); Ae = @('sessions', 'plan'); Binds = @('operation', 'object') }
    'IDX-001'   = @{ V = @('index_order_gain'); Lab = $true }
    'IDX-002'   = @{ V = @('redundant_index_gain'); Lab = $true }
    'IDX-003'   = @{ D = @('table_by_rowid', 'rowid_options'); V = @('covering_gain'); AddA = @($FOS); De = @('plan'); Ae = @('sessions', 'plan'); Binds = @('operation', 'object') }
    'IDX-004'   = @{ D = @('unusable_indexes'); A = @('index_state_cost_deviation'); De = @('metadata'); Ae = @('sql'); Binds = @('object') }
    'PRED-001'  = @{ D = @('wildcard_predicates'); V = @('wildcard_gain'); AddA = @($FOS); De = @('ast'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'PRED-002'  = @{ D = @('or_predicates'); V = @('or_gain'); AddA = @($FOS); De = @('ast'); Ae = @('sessions', 'plan'); Binds = $opBind }
    'PRED-003'  = @{ Dover = (Any-Of @((Cmp 'function_predicates' 'gt' 0), (Cmp 'plan_function_candidates' 'gt' 0))); Covers = @('function_predicates'); V = @('function_gain'); AddA = @($FOS); De = @('plan'); Dopt = @('ast'); Ae = @('sessions', 'plan'); Binds = $opBind; Note = 'P4: executed-plan predicate candidates detect; parsed AST path retained as alternative.' }
    'PRED-004'  = @{ Dover = (Any-Of @((Cmp 'conversion_predicates' 'gt' 0), (Cmp 'plan_conversion_candidates' 'gt' 0))); Covers = @('conversion_predicates'); V = @('conversion_gain'); Aover = (All-Of @((Cmp 'plan_conversion_verified' 'gt' 0), $FOS)); De = @('plan'); Dopt = @('ast'); Ae = @('plan', 'metadata', 'sessions'); Aopt = @('binds', 'ast'); Binds = @('operation', 'object', 'column'); Classify = @([ordered]@{ id = 'PRED-004-implicit'; test = (Cmp 'plan_conversion_implicit_confirmed' 'gt' 0); label_true = 'implicit_conversion_confirmed'; label_unknown = 'conversion_verified_implicit_unconfirmed'; label_false = 'explicit_conversion_in_source' }); Note = 'P4: predicate text never proves implicit conversion alone; datatype metadata verification is attribution; implicit vs explicit is a separate classification.' }
    'PRED-005'  = @{ D = @('bind_mismatch_reasons', 'associated_binds'); A = @('bind_type_parse_deviation'); De = @('cursor', 'binds'); Ae = @('system'); Binds = @('sql_child', 'bind_position') }
    'DATA-001'  = @{ D = @('pagination_offsets'); V = @('pagination_gain'); De = @('ast') }
    'DATA-002'  = @{ D = @('topn_queries', 'frequency_deviation'); V = @('topn_gain'); De = @('ast', 'sql') }
    'DATA-003'  = @{ D = @('rows_per_execution'); V = @('result_volume_gain'); De = @('sql') }
    'DATA-004'  = @{ D = @('workload_value_bias'); A = @('estimate_error_ratio'); De = @('distribution'); Ae = @('plan'); Binds = @('object', 'operation') }
    'EXT-001'   = @{ D = @('family_cpu_share'); A = @('wall_deviation'); De = @('sql'); Ae = @('executions'); Binds = @('workload', 'resource') }
    'EXT-002'   = @{ D = @('rman_overlap'); A = @('device_latency_deviation'); De = @('rman', 'executions'); Ae = @('storage'); Binds = @('resource', 'shared_device') }
    'EXT-003'   = @{ D = @('physical_read_latency'); A = @('storage_latency_deviation'); De = @('waits'); Ae = @('storage'); Binds = @('resource', 'device') }
    'EXT-004'   = @{ D = @('gc_wait_share'); A = @('interconnect_deviation'); De = @('sessions'); Ae = @('network'); Binds = @('resource', 'instance') }
    'EXT-005'   = @{ D = @('lock_waiters', 'blocking_chain_count'); De = @('sessions') }
    'FAM-001'   = @{ D = @('family_member_count'); De = @('ast', 'sql') }
    'FAM-002'   = @{ D = @('frequency_deviation', 'cpu_demand_deviation'); De = @('sql') }
    'FAM-003'   = @{ D = @('concurrent_execution_count', 'concurrency_deviation'); A = @('peak_temp_occupancy'); De = @('executions'); Ae = @('temp', 'executions'); Binds = @('family', 'resource') }
    'FAM-004'   = @{ D = @('common_dependency_count'); A = @('common_path_work'); De = @('dependencies', 'ast', 'plan'); Ae = @('plan', 'sql'); Binds = @('family', 'object', 'operation') }
    'FAM-005'   = @{ D = @('group_cpu_share'); A = @('rm_wait_share'); De = @('rm', 'sql'); Ae = @('rm'); Binds = @('family', 'resource', 'consumer_group') }
    'FAM-006'   = @{ D = @('cluster_concurrent_execution_count'); A = @('instance_demand_skew'); De = @('executions'); Ae = @('sql', 'rm'); Binds = @('family', 'instance') }
    'RM-001'    = @{ D = @('rm_waiter_count', 'rm_wait_share'); De = @('rm', 'sessions') }
    'RM-002'    = @{ D = @('active_cpu_plan', 'caging_enabled'); A = @('rm_wait_share'); De = @('rm', 'system'); Ae = @('rm'); Binds = @('resource', 'instance') }
    'RM-003'    = @{ D = @('active_cpu_plan', 'group_limit_utilization'); A = @('rm_wait_share'); De = @('rm'); Ae = @('rm'); Binds = @('resource', 'consumer_group') }
    'RM-004'    = @{ D = @('host_busy', 'host_queue'); A = @('wall_deviation'); De = @('os'); Ae = @('executions'); Binds = @('resource', 'host') }
    'RM-005'    = @{ D = @('victim_wait_share'); A = @('victim_cpu_share', 'logical_read_deviation'); De = @('sessions', 'rm'); Ae = @('sql', 'rm'); Binds = @('workload', 'consumer_group') }
    'RM-006'    = @{ D = @('resource_plan_changes'); A = @('rm_wait_share', 'onset_order'); De = @('changes', 'rm'); Ae = @('rm', 'executions', 'changes'); Binds = @('resource', 'change') }
    'TEMP-001'  = @{ D = @('attributed_temp_allocations'); A = @('operation_spill_bytes'); De = @('temp', 'executions'); Ae = @('workarea', 'plan'); Binds = $opBind }
    'TEMP-002'  = @{ D = @('operation_spill_bytes'); A = @('estimate_error_ratio', 'intermediate_row_deviation'); De = @('workarea'); Ae = @('plan'); Binds = $opBind }
    'TEMP-003'  = @{ D = @('max_workarea_passes'); De = @('workarea') }
    'TEMP-004'  = @{ D = @('peak_temp_occupancy'); A = @('cluster_concurrent_execution_count'); De = @('temp', 'executions'); Ae = @('executions'); Binds = @('family', 'resource') }
    'TEMP-005'  = @{ D = @('temp_transformations'); A = @('materialization_work'); De = @('plan'); Ae = @('plan'); Binds = $opBind }
    'TIME-001'  = @{ D = @('frequency_deviation'); A = @('onset_order'); De = @('sql'); Ae = @('changes', 'executions'); Binds = @('change', 'family') }
    'TIME-002'  = @{ D = @('cpu_demand_deviation'); A = @('rm_onset_order', 'victim_onset_order'); De = @('sql'); Ae = @('rm', 'sessions'); Binds = @('family', 'resource', 'workload') }
    'RAC-001'   = @{ D = @('instance_demand_skew'); De = @('sql', 'rm') }
    'RAC-002'   = @{ D = @('gc_wait_share'); A = @('logical_read_deviation'); De = @('sessions'); Ae = @('sql'); Binds = @('sql_or_family', 'instance') }
    'CUR-006'   = @{ D = @('family_member_count'); A = @('hard_parse_rate'); De = @('sql', 'ast'); Ae = @('system'); Binds = @('family', 'instance') }
    'CUR-007'   = @{ D = @('hard_parse_deviation'); A = @('hard_parse_time_share'); De = @('system'); Ae = @('system'); Binds = @('instance') }
    'CUR-008'   = @{ D = @('soft_parse_rate'); A = @('parse_time_share'); De = @('system'); Ae = @('system', 'sql'); Binds = @('instance', 'sql_or_family') }
    'CUR-009'   = @{ D = @('invalidation_rate'); A = @('hard_parse_deviation'); De = @('sql'); Ae = @('system', 'changes'); Binds = @('sql_child', 'change') }
    'CUR-010'   = @{ D = @('library_cache_wait_share'); De = @('sessions') }
    'WAIT-001'  = @{ D = @('commit_wait_share'); De = @('sessions') }
    'WAIT-002'  = @{ D = @('hot_block_wait_share'); A = @('hot_segment_delta'); De = @('sessions'); Ae = @('segments'); Binds = @('object') }
    'WAIT-003'  = @{ D = @('target_snapshot_error'); De = @('undo', 'system') }
    'WAIT-004'  = @{ D = @('fetch_wait_share'); A = @('wall_deviation', 'baseline_deviation_ratio'); De = @('sessions'); Ae = @('executions', 'sql'); Binds = @('execution', 'client_phase') }
    'WAIT-005'  = @{ D = @('unsupported_wait_count'); De = @('events', 'sessions') }
    'EXT-006'   = @{ D = @('paging_deviation'); A = @('wall_deviation'); De = @('os'); Ae = @('executions'); Binds = @('resource', 'host') }
    'HEALTH-001'= @{ D = @('coverage_ratio', 'comparable_baseline_count', 'wall_deviation', 'baseline_deviation_ratio', 'logical_read_deviation', 'read_deviation', 'frequency_deviation', 'concurrency_deviation', 'unresolved_external_count', 'temp_occupancy_deviation'); De = @('coverage', 'executions', 'sql', 'temp') }
}
# Required V3 evidence that P4/P5 deliberately made optional.
$approvedOptionalMoves = @{ 'PRED-003' = @('ast'); 'PRED-004' = @('ast', 'binds'); 'CUR-004' = @('executions') }

# ---------------------------------------------------------------- new metrics (P1, P2, P4, P5, P6)
$q = @('matching_scope', 'matching_window', 'complete_required_inputs')
$newMetrics = @(
    [ordered]@{ id = 'flagged_operation_activity_share'; operator = 'weighted_sample_share'; inputs = @('sessions.sample_duration_s', 'sessions.plan_line_id', 'plan.id'); unit = 'ratio'
        parameters = [ordered]@{ select = 'rule_flagged_operations'; numerator = 'samples whose SQL_PLAN_LINE_ID is an operation flagged by the same rule detection stage, same SQL_ID/plan hash/execution'; denominator = 'same_execution_nonidle_samples'; minimum_sample_threshold = 'minimum_samples'; not = 'exact operation elapsed; ASH plan-line attribution is sampled' }
        group_by = @('sql_id', 'execution_key', 'operation_id', 'inst_id'); null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q; added_in = '3.1'; change = 'P1 attribution metric' }
    [ordered]@{ id = 'monitored_execution_share'; operator = 'ratio'; inputs = @('executions.execution_key', 'executions.execution_key'); unit = 'ratio'
        parameters = [ordered]@{ numerator_population = 'executions with live or AWR-captured SQL Monitor evidence'; denominator_population = 'all executions identified for the SQL/family and window from any source'; aggregate = 'count_distinct'; caution = 'Unmonitored executions have no plan-line actuals from SQL Monitor; absence is never zero rows or no problem.' }
        group_by = @('sql_or_family_window', 'inst_id'); null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q; added_in = '3.1'; change = 'P2 monitoring coverage' }
    [ordered]@{ id = 'plan_conversion_candidates'; operator = 'plan_predicate_pattern_count'; inputs = @('plan.access_predicate', 'plan.filter_predicate', 'plan.id'); unit = 'count'
        parameters = [ordered]@{ pattern_set = 'conversion_wrappers'; column_side_only = $true; classification = 'candidate'; unparseable = 'UNKNOWN' }
        group_by = @('sql_id', 'child', 'plan_hash', 'operation_id'); null_zero_policy = 'UNKNOWN unless documented semantic zero'; quality = $q; added_in = '3.1'; change = 'P4 detection' }
    [ordered]@{ id = 'plan_conversion_verified'; operator = 'plan_predicate_pattern_count'; inputs = @('plan.access_predicate', 'plan.filter_predicate', 'plan.id', 'plan.object_id', 'metadata.object_id', 'metadata.column_name', 'metadata.datatype'); unit = 'count'
        parameters = [ordered]@{ pattern_set = 'conversion_wrappers'; column_side_only = $true; classification = 'datatype_verified'; require = 'wrapped column resolved to the plan-line object and DBA_TAB_COLUMNS.DATA_TYPE differs from the wrapper target type'; ambiguous_wrappers = 'INTERNAL_FUNCTION counts only when the comparison operand type is resolvable and differs from the column type'; unresolved = 'candidate_unverified; contributes UNKNOWN, never zero' }
        group_by = @('sql_id', 'child', 'plan_hash', 'operation_id'); null_zero_policy = 'UNKNOWN unless documented semantic zero'; quality = $q; added_in = '3.1'; change = 'P4 attribution' }
    [ordered]@{ id = 'plan_conversion_implicit_confirmed'; operator = 'plan_predicate_pattern_count'; inputs = @('plan.access_predicate', 'plan.filter_predicate', 'plan.id', 'metadata.datatype', 'ast.pattern', 'ast.column'); unit = 'count'
        parameters = [ordered]@{ pattern_set = 'conversion_wrappers'; column_side_only = $true; classification = 'implicit_confirmed'; require = 'datatype_verified and parsed source shows no explicit conversion at the same column/operator position'; parser_unavailable = 'UNKNOWN (implicit vs explicit undetermined)' }
        group_by = @('sql_id', 'child', 'plan_hash', 'operation_id'); null_zero_policy = 'UNKNOWN unless documented semantic zero'; quality = $q; added_in = '3.1'; change = 'P4 classification' }
    [ordered]@{ id = 'plan_function_candidates'; operator = 'plan_predicate_pattern_count'; inputs = @('plan.access_predicate', 'plan.filter_predicate', 'plan.id'); unit = 'count'
        parameters = [ordered]@{ pattern_set = 'function_wrappers'; column_side_only = $true; classification = 'candidate'; unparseable = 'UNKNOWN' }
        group_by = @('sql_id', 'child', 'plan_hash', 'operation_id'); null_zero_policy = 'UNKNOWN unless documented semantic zero'; quality = $q; added_in = '3.1'; change = 'P4 detection' }
    [ordered]@{ id = 'awr_plan_elapsed_ratio'; operator = 'baseline_ratio'; inputs = @('elapsed_per_execution'); unit = 'ratio'
        parameters = [ordered]@{ match = 'contract.awr_plan_policy'; contrast = 'different_plan_hash_same_sql_id_or_validated_family_member'; source = 'DBA_HIST_SQLSTAT interval deltas joined to DBA_HIST_SNAPSHOT'; minimum_sample_threshold = 'minimum_samples'; minimum_magnitude_threshold = 'minimum_baseline'; caution = 'ELAPSED_TIME_DELTA is DB time including PX workers, not wall response time' }
        group_by = @('sql_id', 'plan_hash', 'inst_id', 'snapshot_window'); null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q; added_in = '3.1'; change = 'P5' }
    [ordered]@{ id = 'awr_plan_buffer_ratio'; operator = 'baseline_ratio'; inputs = @('buffer_gets_per_execution'); unit = 'ratio'
        parameters = [ordered]@{ match = 'contract.awr_plan_policy'; contrast = 'different_plan_hash_same_sql_id_or_validated_family_member'; source = 'DBA_HIST_SQLSTAT interval deltas joined to DBA_HIST_SNAPSHOT'; minimum_sample_threshold = 'minimum_samples'; minimum_magnitude_threshold = 'minimum_baseline' }
        group_by = @('sql_id', 'plan_hash', 'inst_id', 'snapshot_window'); null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q; added_in = '3.1'; change = 'P5' }
    [ordered]@{ id = 'db_time_deviation'; operator = 'baseline_ratio'; inputs = @('elapsed_per_execution'); unit = 'ratio'
        parameters = [ordered]@{ match = 'contract.baseline_policy'; minimum_sample_threshold = 'minimum_samples'; minimum_magnitude_threshold = 'minimum_baseline'; caution = 'Database time per execution, not end-to-end response time; elapsed includes PX worker time.' }
        group_by = @('sql_or_family_window'); null_zero_policy = 'UNKNOWN unless operator explicitly defines zero category'; quality = $q; added_in = '3.1'; change = 'P6 database-side verdict; P5 historical degradation' }
)

# ---------------------------------------------------------------- new / extended sources (P2, P3, P7)
$audit = [ordered]@{ checked_on = $AuditDate; authority = 'Oracle 19c documentation'; status = 'source_definition_reviewed'; column_contract = 'only listed supported columns; live availability and offering remain collection gates' }
$baseLic = [ordered]@{ category = 'base'; requires_all = @(); feature_gates = @(); offering_check = $true }
$diagLic = [ordered]@{ category = 'diagnostics_pack'; requires_all = @('diagnostics_pack'); feature_gates = @(); offering_check = $true }
$tuneLic = [ordered]@{ category = 'tuning_pack'; requires_all = @('diagnostics_pack', 'tuning_pack'); feature_gates = @(); offering_check = $true }
$extLic = [ordered]@{ category = 'external'; requires_all = @(); feature_gates = @(); offering_check = $false }
$ref = 'https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/'
$sourceColumnAdds = [ordered]@{
    'V$SQL_PLAN_MONITOR'           = @('CON_ID', 'KEY', 'STATUS', 'FIRST_REFRESH_TIME', 'LAST_REFRESH_TIME', 'SID', 'PROCESS_NAME', 'SQL_PLAN_HASH_VALUE', 'SQL_CHILD_ADDRESS', 'PLAN_PARENT_ID', 'PLAN_OPERATION', 'PLAN_OPTIONS', 'PLAN_OBJECT_OWNER', 'PLAN_OBJECT_NAME', 'PLAN_CARDINALITY', 'PLAN_PARTITION_START', 'PLAN_PARTITION_STOP', 'WORKAREA_MAX_MEM', 'WORKAREA_MAX_TEMPSEG')
    'V$SQL_MONITOR'                = @('KEY', 'PROCESS_NAME', 'SQL_PLAN_HASH_VALUE', 'SQL_CHILD_ADDRESS', 'FIRST_REFRESH_TIME', 'LAST_REFRESH_TIME', 'PX_SERVER#', 'PX_SERVER_SET', 'PX_SERVER_GROUP', 'PX_IS_CROSS_INSTANCE', 'FETCHES', 'CON_ID')
    'V$ACTIVE_SESSION_HISTORY'     = @('SQL_PLAN_HASH_VALUE', 'IS_SQLID_CURRENT', 'TEMP_SPACE_ALLOCATED', 'TM_DELTA_CPU_TIME', 'TM_DELTA_TIME', 'CON_ID')
    'DBA_HIST_ACTIVE_SESS_HISTORY' = @('SQL_PLAN_HASH_VALUE', 'IS_SQLID_CURRENT', 'TEMP_SPACE_ALLOCATED', 'TM_DELTA_CPU_TIME', 'TM_DELTA_TIME', 'CON_ID')
}
$sourceLimitationAdds = @{
    'V$SQL_PLAN_MONITOR'           = ' V3.1/P2: only monitored executions (>=5 s CPU or I/O in one execution, parallel, MONITOR hint or sql_monitor event) appear; entries persist at least one minute after completion then age out. One V$SQL_MONITOR entry exists for the QC and each PX server sharing the execution key, each with its own plan-line rows: aggregate STARTS/OUTPUT_ROWS per PLAN_LINE_ID across all KEY entries of one execution key (and across instances for cross-instance PX via GV$), verify in lab. OUTPUT_ROWS is cumulative for the execution; divide by STARTS. WORKAREA_TEMPSEG is NULL when not spilled or after completion. Absence of a monitored entry is not zero rows.'
    'V$SQL_MONITOR'                = ' V3.1/P2: QC and each PX server have separate entries sharing SQL_ID/SQL_EXEC_START/SQL_EXEC_ID; count the execution once (QC) and sum worker resource once. Entries retained at least one minute after completion. Unmonitored executions are absent, not fast.'
    'V$ACTIVE_SESSION_HISTORY'     = ' V3.1/P3: execution reconstruction from SQL_EXEC_ID/SQL_EXEC_START is sampled; max(SAMPLE_TIME)-SQL_EXEC_START is a lower bound; executions shorter than the sample spacing can be missed entirely. TEMP_SPACE_ALLOCATED is per session at sample time, not per plan operation.'
    'DBA_HIST_ACTIVE_SESS_HISTORY' = ' V3.1/P3: persisted subset of in-memory samples; derive spacing from USECS_PER_ROW/observed SAMPLE_TIME, never assume a fixed interval. Execution durations/counts reconstructed here are sampled lower bounds and incomplete.'
}
$newSources = @(
    [ordered]@{ id = 'DBA_HIST_REPORTS'; name = 'DBA_HIST_REPORTS'; rac_name = $null; kind = 'oracle_view'
        columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'REPORT_ID', 'COMPONENT_ID', 'SESSION_ID', 'SESSION_SERIAL#', 'PERIOD_START_TIME', 'PERIOD_END_TIME', 'GENERATION_TIME', 'COMPONENT_NAME', 'REPORT_NAME', 'KEY1', 'KEY2', 'KEY3', 'KEY4', 'REPORT_SUMMARY', 'CON_DBID', 'CON_ID')
        grain = 'captured_component_report'; unit_policy = 'Normalize per documented column units; retain raw units.'; licensing = $tuneLic; reference = $ref + 'DBA_HIST_REPORTS.html'
        limitations = 'V3.1/P3: AWR captures SQL Monitor XML reports by default only for the most expensive completed statements by elapsed time since the last capture cycle; COMPONENT_NAME=sqlmonitor, KEY1=SQL_ID, KEY2=SQL_EXEC_ID. Missing report is not evidence of a fast or healthy execution. Retention follows AWR policy. Licensing gated conservatively as Diagnostics+Tuning (DBA_HIST_ prefix plus SQL Monitor content).'
        fallbacks = @('captured_base_snapshots'); audit = $audit; added_in = '3.1' }
    [ordered]@{ id = 'DBA_HIST_REPORTS_DETAILS'; name = 'DBA_HIST_REPORTS_DETAILS'; rac_name = $null; kind = 'oracle_view'
        columns = @('SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'REPORT_ID', 'SESSION_ID', 'SESSION_SERIAL#', 'GENERATION_TIME', 'REPORT', 'CON_DBID', 'CON_ID')
        grain = 'captured_component_report'; unit_policy = 'Report XML values carry their own units; retain raw report.'; licensing = $tuneLic; reference = $ref + 'DBA_HIST_REPORTS_DETAILS.html'
        limitations = 'V3.1/P3: REPORT is the uncompressed XML report. The SQL Monitor XML element structure is not documented in the 19c Reference and must be fixture-verified on a live 19c lab before parsing is trusted; parse failure yields incomplete, never absent.'
        fallbacks = @('captured_base_snapshots'); audit = $audit; added_in = '3.1' }
    [ordered]@{ id = 'DBA_HIST_WR_CONTROL'; name = 'DBA_HIST_WR_CONTROL'; rac_name = $null; kind = 'oracle_view'
        columns = @('DBID', 'SNAP_INTERVAL', 'RETENTION', 'TOPNSQL', 'CON_ID', 'SRC_DBID', 'SRC_DBNAME')
        grain = 'database_configuration'; unit_policy = 'INTERVAL DAY TO SECOND values normalized to seconds; retain raw text.'; licensing = $diagLic; reference = $ref + 'DBA_HIST_WR_CONTROL.html'
        limitations = 'V3.1/P7: configuration of AWR capture; current settings may differ from settings in force during the incident window.'
        fallbacks = @(); audit = $audit; added_in = '3.1' }
    [ordered]@{ id = 'V$INSTANCE'; name = 'V$INSTANCE'; rac_name = 'GV$INSTANCE'; kind = 'oracle_view'
        columns = @('INSTANCE_NUMBER', 'INSTANCE_NAME', 'HOST_NAME', 'VERSION', 'VERSION_FULL', 'STARTUP_TIME', 'STATUS', 'PARALLEL', 'THREAD#', 'INSTANCE_ROLE', 'DATABASE_TYPE', 'CON_ID')
        grain = 'instance'; unit_policy = 'Normalize per documented column units; retain raw units.'; licensing = $baseLic; reference = $ref + 'V-INSTANCE.html'
        limitations = 'V3.1/P7: current state only; STARTUP_TIME defines counter incarnation boundaries.'
        fallbacks = @(); audit = $audit; added_in = '3.1' }
    [ordered]@{ id = 'V$DATABASE'; name = 'V$DATABASE'; rac_name = 'GV$DATABASE'; kind = 'oracle_view'
        columns = @('DBID', 'NAME', 'DB_UNIQUE_NAME', 'DATABASE_ROLE', 'OPEN_MODE', 'CDB', 'CON_ID', 'PLATFORM_NAME')
        grain = 'database'; unit_policy = 'Normalize per documented column units; retain raw units.'; licensing = $baseLic; reference = $ref + 'V-DATABASE.html'
        limitations = 'V3.1/P7: current state only; role at incident time may differ after switchover.'
        fallbacks = @(); audit = $audit; added_in = '3.1' }
    [ordered]@{ id = 'license_policy'; name = 'license_policy'; kind = 'external_evidence'; columns = @()
        grain = 'investigation_configuration'; unit_policy = 'Provider supplies named units and quality'; licensing = $extLic; reference = 'repository:DEMO_SCOPE.md'
        limitations = 'V3.1/P7: configured entitlement statement (who/when/scope). CONTROL_MANAGEMENT_PACK_ACCESS or source existence never substitutes for this record.'
        fallbacks = @(); audit = [ordered]@{ checked_on = $AuditDate; authority = 'repository/provider contract'; status = 'source_definition_reviewed'; column_contract = 'provider schema defined by contract.capability_policy' }; added_in = '3.1' }
    [ordered]@{ id = 'collector_runtime'; name = 'collector_runtime'; kind = 'external_evidence'; columns = @()
        grain = 'investigation_run'; unit_policy = 'Provider supplies named units and quality'; licensing = $extLic; reference = 'repository:QUERY_TUNER_REQUIREMENTS.md'
        limitations = 'V3.1/P7: collector-recorded facts: connection mode/privilege, executor and query-catalog version, per-query start/end UTC, row caps, timeouts and failures. Privilege is reported, not inferred.'
        fallbacks = @(); audit = [ordered]@{ checked_on = $AuditDate; authority = 'repository/provider contract'; status = 'source_definition_reviewed'; column_contract = 'provider schema defined by contract.capability_policy' }; added_in = '3.1' }
)

# ---------------------------------------------------------------- evidence changes
function Add-Binding($evidence, [string]$sourceId, [string[]]$columns) {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($b in $evidence.bindings) { $list.Add($b) }
    $list.Add([ordered]@{ source_id = $sourceId; columns = $columns; added_in = '3.1' })
    $evidence.bindings = $list.ToArray()
}
function Add-Fields($evidence, [object[]]$fields) {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $evidence.fields) { $list.Add($f) }
    foreach ($f in $fields) { $list.Add($f) }
    $evidence.fields = $list.ToArray()
}
function Field([string]$n, [string]$t, [string]$u) { [ordered]@{ name = $n; type = $t; unit = $u; added_in = '3.1' } }
$evidenceById = @{}; foreach ($e in $v3.evidence) { $evidenceById[$e.id] = $e }

$plan = $evidenceById['plan']
Add-Fields $plan @((Field 'actuals_source' 'string' 'identity'), (Field 'execution_key' 'string' 'identity'), (Field 'monitor_status' 'string' 'flag'))
Add-Binding $plan 'V$SQL_PLAN_MONITOR' @('SQL_ID', 'SQL_EXEC_START', 'SQL_EXEC_ID', 'KEY', 'STATUS', 'SQL_PLAN_HASH_VALUE', 'PLAN_LINE_ID', 'PLAN_PARENT_ID', 'PLAN_OPERATION', 'PLAN_OPTIONS', 'PLAN_OBJECT_OWNER', 'PLAN_OBJECT_NAME', 'PLAN_CARDINALITY', 'PLAN_PARTITION_START', 'PLAN_PARTITION_STOP', 'STARTS', 'OUTPUT_ROWS', 'PHYSICAL_READ_BYTES', 'PHYSICAL_WRITE_BYTES', 'WORKAREA_MAX_MEM', 'WORKAREA_MAX_TEMPSEG', 'CON_ID')
Add-Binding $plan 'DBA_HIST_REPORTS' @('REPORT_ID', 'COMPONENT_NAME', 'KEY1', 'KEY2', 'PERIOD_START_TIME', 'PERIOD_END_TIME', 'SNAP_ID', 'DBID', 'INSTANCE_NUMBER', 'CON_ID')
Add-Binding $plan 'DBA_HIST_REPORTS_DETAILS' @('REPORT_ID', 'REPORT', 'DBID', 'INSTANCE_NUMBER', 'CON_ID')
$plan.normalization = $plan.normalization + ' V3.1/P2-P3: actuals come from exactly one source per execution, recorded in actuals_source: plan_statistics_last_execution (V$SQL_PLAN_STATISTICS_ALL LAST_*; populated only with STATISTICS_LEVEL=ALL or statement-level plan statistics; last execution of the child, not necessarily the incident execution), sql_monitor_execution (V$SQL_PLAN_MONITOR for one execution key; STARTS/OUTPUT_ROWS summed across QC/PX KEY entries; OUTPUT_ROWS cumulative so a=OUTPUT_ROWS/STARTS) or awr_sql_monitor_report (DBA_HIST_REPORTS_DETAILS XML for one SQL_EXEC_ID). Never mix sources within one normalized_row_error. V$SQL_PLAN_STATISTICS_ALL remains a valid source and is not replaced. A missing monitored execution leaves a/starts UNKNOWN, never 0.'

$workarea = $evidenceById['workarea']
Add-Binding $workarea 'V$SQL_PLAN_MONITOR' @('SQL_ID', 'SQL_EXEC_START', 'SQL_EXEC_ID', 'KEY', 'STATUS', 'PLAN_LINE_ID', 'PLAN_OPERATION', 'PLAN_OPTIONS', 'WORKAREA_MAX_MEM', 'WORKAREA_MAX_TEMPSEG', 'CON_ID')
$workarea.normalization = $workarea.normalization + ' V3.1/P2: SQL Monitor plan-line workarea values are execution-specific and operation-specific (PLAN_LINE_ID); WORKAREA_TEMPSEG is NULL when not spilled or after completion, so use the maximum column for completed executions and record which column was used. NULL is not 0 unless the execution is monitored, complete and the column semantics are lab-verified.'

$executions = $evidenceById['executions']
Add-Fields $executions @((Field 'plan_hash' 'string' 'identity'), (Field 'estimate_kind' 'string' 'flag'), (Field 'sample_interval_s' 'number' 'seconds'), (Field 'sample_count' 'number' 'count'), (Field 'actuals_source' 'string' 'identity'))
Add-Binding $executions 'V$SQL_MONITOR' @('KEY', 'PROCESS_NAME', 'SQL_PLAN_HASH_VALUE', 'SQL_CHILD_ADDRESS', 'FIRST_REFRESH_TIME', 'LAST_REFRESH_TIME', 'PX_SERVER#', 'PX_SERVER_SET', 'PX_SERVER_GROUP', 'PX_IS_CROSS_INSTANCE', 'FETCHES', 'CON_ID')
Add-Binding $executions 'V$ACTIVE_SESSION_HISTORY' @('SAMPLE_TIME', 'USECS_PER_ROW', 'SESSION_ID', 'SESSION_SERIAL#', 'SQL_ID', 'SQL_EXEC_ID', 'SQL_EXEC_START', 'SQL_PLAN_HASH_VALUE', 'IS_SQLID_CURRENT', 'QC_INSTANCE_ID', 'QC_SESSION_ID', 'QC_SESSION_SERIAL#', 'TEMP_SPACE_ALLOCATED', 'TM_DELTA_CPU_TIME', 'TM_DELTA_TIME', 'CON_ID')
Add-Binding $executions 'DBA_HIST_ACTIVE_SESS_HISTORY' @('DBID', 'INSTANCE_NUMBER', 'SNAP_ID', 'SAMPLE_TIME', 'USECS_PER_ROW', 'SESSION_ID', 'SESSION_SERIAL#', 'SQL_ID', 'SQL_EXEC_ID', 'SQL_EXEC_START', 'SQL_PLAN_HASH_VALUE', 'IS_SQLID_CURRENT', 'QC_INSTANCE_ID', 'QC_SESSION_ID', 'QC_SESSION_SERIAL#', 'TEMP_SPACE_ALLOCATED', 'TM_DELTA_CPU_TIME', 'TM_DELTA_TIME', 'CON_ID')
Add-Binding $executions 'DBA_HIST_REPORTS' @('REPORT_ID', 'COMPONENT_NAME', 'KEY1', 'KEY2', 'PERIOD_START_TIME', 'PERIOD_END_TIME', 'SESSION_ID', 'SESSION_SERIAL#', 'INSTANCE_NUMBER', 'DBID', 'CON_ID')
Add-Binding $executions 'DBA_HIST_REPORTS_DETAILS' @('REPORT_ID', 'REPORT', 'DBID', 'INSTANCE_NUMBER', 'CON_ID')
$executions.normalization = $executions.normalization + ' V3.1/P3: every execution row records estimate_kind from contract.historical_execution_policy. ASH reconstruction groups QC identity + SQL_ID + SQL_EXEC_START + SQL_EXEC_ID with IS_SQLID_CURRENT=Y; wall_s = max(SAMPLE_TIME) - SQL_EXEC_START is a sampled_lower_bound with sample_interval_s from USECS_PER_ROW/observed spacing; executions shorter than spacing are missing, so ASH counts are incomplete lower bounds and complete=0 unless independently established. temp_peak_bytes from ASH TEMP_SPACE_ALLOCATED is a sampled session-level lower bound, never an operation attribution. AWR SQL Monitor reports supply per-execution DB time/elapsed with report_bounded kind. Mixed estimate kinds are never pooled into one percentile.'

$capability = [ordered]@{
    id = 'capability'; type = 'table'
    fields = @((Field 'category' 'string' 'identity'), (Field 'name' 'string' 'identity'), (Field 'value' 'string' 'text'), (Field 'value_number' 'number' 'native_unit'), (Field 'value_unit' 'string' 'identity'), (Field 'observed_at_utc' 'string' 'identity'), (Field 'inst_id' 'number' 'identity'), (Field 'status' 'string' 'flag'))
    bindings = @(
        [ordered]@{ source_id = 'V$INSTANCE'; columns = @('INSTANCE_NUMBER', 'INSTANCE_NAME', 'HOST_NAME', 'VERSION_FULL', 'STARTUP_TIME', 'STATUS', 'PARALLEL', 'THREAD#', 'DATABASE_TYPE', 'CON_ID') }
        [ordered]@{ source_id = 'V$DATABASE'; columns = @('DBID', 'NAME', 'DB_UNIQUE_NAME', 'DATABASE_ROLE', 'OPEN_MODE', 'CDB', 'CON_ID') }
        [ordered]@{ source_id = 'V$PARAMETER'; columns = @('NAME', 'VALUE', 'ISDEFAULT', 'CON_ID') }
        [ordered]@{ source_id = 'V$RSRC_PLAN'; columns = @('NAME', 'IS_TOP_PLAN', 'CPU_MANAGED', 'INSTANCE_CAGING', 'CON_ID') }
        [ordered]@{ source_id = 'DBA_HIST_WR_CONTROL'; columns = @('DBID', 'SNAP_INTERVAL', 'RETENTION', 'TOPNSQL', 'CON_ID') }
        [ordered]@{ source_id = 'DBA_HIST_SNAPSHOT'; columns = @('DBID', 'INSTANCE_NUMBER', 'SNAP_ID', 'STARTUP_TIME', 'BEGIN_INTERVAL_TIME', 'END_INTERVAL_TIME') }
        [ordered]@{ source_id = 'V$ACTIVE_SESSION_HISTORY'; columns = @('SAMPLE_TIME') }
        [ordered]@{ source_id = 'license_policy'; columns = @() }
        [ordered]@{ source_id = 'collector_runtime'; columns = @() }
    )
    normalization = 'V3.1/P7: one row per contract.capability_policy.items entry, per instance where instance-specific, recorded at investigation start before any diagnostic collection. Parameter rows are filtered to the named parameters only. value retains raw text; value_number/value_unit only when the documented unit is unambiguous. Earliest ASH/AWR sample per instance establishes retention coverage. status uses contract.statuses.'
    quality = @('envelope_complete', 'source_capability_allowed', 'identity_resolved')
    added_in = '3.1'
}

# ---------------------------------------------------------------- rule transformation (P1)
$disconfirmText = 'An equivalent mechanism-targeted controlled trial failing to improve cost weakens this mechanism/remediation claim (controlled disconfirmation); the detection finding is retained. Absent/incomparable trial stays validation_pending.'
$ruleById = @{}; foreach ($r in $v3.rules) { $ruleById[$r.id] = $r }
$newRules = [System.Collections.Generic.List[object]]::new()
$stageRows = [System.Collections.Generic.List[object]]::new()
$problems = [System.Collections.Generic.List[string]]::new()

foreach ($rule in $v3.rules) {
    if ($rule.alias_of) { $newRules.Add($rule); continue }
    if (-not $map.Contains($rule.id)) { $problems.Add("No stage map for $($rule.id)"); continue }
    $m = $map[$rule.id]
    $cls = $rule.diagnostic_class
    $conj = Conjuncts $rule.decision
    $byKey = [ordered]@{}
    foreach ($c in $conj) { $k = First-Metric $c; if ($byKey.Contains($k)) { $problems.Add("$($rule.id) ambiguous conjunct key $k") }; $byKey[$k] = $c }
    $D = @($m.D | Where-Object { $_ }); $A = @($m.A | Where-Object { $_ }); $V = @($m.V | Where-Object { $_ }); $covers = @($m.Covers | Where-Object { $_ })
    $assigned = @($D) + @($A) + @($V) + @($covers)
    foreach ($k in $byKey.Keys) { if (@($assigned | Where-Object { $_ -eq $k }).Count -ne 1) { $problems.Add("$($rule.id) V3 conjunct $k assigned $(@($assigned | Where-Object { $_ -eq $k }).Count) times") } }
    foreach ($k in $assigned) { if (-not $byKey.Contains($k)) { $problems.Add("$($rule.id) mapped key $k not in V3 decision") } }
    $hadTrial = $false
    foreach ($k in $byKey.Keys) { if ($metricOps[$k] -eq 'trial_ratio') { $hadTrial = $true; if ($V -notcontains $k) { $problems.Add("$($rule.id) trial conjunct $k not assigned to validation") } } }
    foreach ($k in @($D) + @($A)) { if ($metricOps[$k] -eq 'trial_ratio') { $problems.Add("$($rule.id) trial metric $k outside validation") } }

    # detection
    $detection = $null
    if (-not $m.Lab) {
        $dExpr = if ($m.Dover) { $m.Dover } else { All-Of @($D | ForEach-Object { $byKey[$_] }) }
        $hasAttr = ($A.Count -gt 0) -or $m.AddA -or $m.Aover
        $dConc = if ($hasAttr -or $hadTrial) { if ($cls -in @('symptom')) { 'symptom' } else { 'observation' } } else { $cls }
        $detection = [ordered]@{
            evidence = @($m.De); optional_evidence = @($m.Dopt | Where-Object { $_ })
            decision = $dExpr; conclusion = $dConc
            meaning = 'Condition or relevant observation is present in the collected scope/window. Reported even when attribution or validation is unavailable.'
        }
    } else { $hasAttr = $false }
    if ($covers.Count) {
        $s = [System.Collections.Generic.HashSet[string]]::new()
        if ($m.Dover) { Collect-Metrics $m.Dover $s }; if ($m.Aover) { Collect-Metrics $m.Aover $s }
        foreach ($k in $covers) { if (-not $s.Contains($k)) { $problems.Add("$($rule.id) override does not cover $k") } }
    }
    # attribution
    $attribution = $null
    if ($hasAttr) {
        $aItems = [System.Collections.Generic.List[object]]::new()
        if ($m.Aover) { $aExpr = $m.Aover }
        else {
            foreach ($k in $A) { $aItems.Add($byKey[$k]) }
            foreach ($x in @($m.AddA | Where-Object { $_ })) { $aItems.Add($x) }
            $aExpr = All-Of $aItems.ToArray()
        }
        if ($m.Aover -and $A.Count) { $problems.Add("$($rule.id) has both Aover and A keys") }
        $attribution = [ordered]@{
            evidence = @($m.Ae); optional_evidence = @($m.Aopt | Where-Object { $_ })
            test = $aExpr; binds_to = @($m.Binds)
            conclusion = $cls
            when_unknown = 'attribution_unresolved; detection finding retained with named attribution gap and next test'
            meaning = 'Links the detected condition to a specific operation/object/family/workload/resource under decision_binding identity joins.'
        }
        if ($m.Classify) { $attribution['classification_tests'] = @($m.Classify) }
    }
    # validation
    $validation = $null
    $vMetric = $null
    if ($V.Count -gt 1) { $problems.Add("$($rule.id) multiple validation conjuncts") }
    if ($V.Count -eq 1) { $vMetric = $V[0] }
    elseif ($m.Vm) { $vMetric = $m.Vm }
    elseif (@($rule.counter_tests | Where-Object { $_.independence_group -eq 'controlled_trial' }).Count) { $vMetric = 'controlled_gain' }
    if ($vMetric) {
        $vTest = if ($V.Count -eq 1) { $byKey[$vMetric] } else { Cmp $vMetric 'gt' 'controlled_cost_gain' }
        $validation = [ordered]@{
            evidence = @('trials'); optional_evidence = @()
            test = $vTest; disconfirm_test = (Cmp $vMetric 'le' 'controlled_cost_gain')
            validates = $(if ($hadTrial) { 'remediation_gain' } else { 'mechanism' })
            conclusion = $cls
            when_missing = 'validation_pending; detection and attribution findings retained; controlled lab or separately approved test proposed'
            meaning = 'Controlled, result-equivalent comparison or approved remediation test. Never required to report detection or attribution findings.'
        }
    }
    if ($m.Lab -and -not $validation) { $problems.Add("$($rule.id) lab-only without validation") }

    # evidence accounting (P1: trials move to validation; P4/P5 approved optional moves only)
    $stageReq = @($m.De) + @($m.Ae) + $(if ($validation) { @('trials') } else { @() })
    $stageOpt = @($m.Dopt | Where-Object { $_ }) + @($m.Aopt | Where-Object { $_ })
    $moved = @($rule.required_evidence | Where-Object { $_ -ne 'trials' -and $stageReq -notcontains $_ })
    $expectedMoves = @($approvedOptionalMoves[$rule.id] | Where-Object { $_ })
    foreach ($e in $moved) { if ($expectedMoves -notcontains $e -or $stageOpt -notcontains $e) { $problems.Add("$($rule.id) V3 required evidence $e dropped without approval") } }
    if ($rule.required_evidence -contains 'trials' -and -not $validation) { $problems.Add("$($rule.id) trials dropped") }

    # counter/supporting tests: stage tags; controlled_trial disconfirmation folds into validation.disconfirm_test
    $counters = [System.Collections.Generic.List[object]]::new()
    $movedCounters = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $rule.counter_tests) {
        if ($t.independence_group -eq 'controlled_trial') { $movedCounters.Add($t.id); if ($validation) { $validation['disconfirm_explanation'] = $disconfirmText; $validation['replaces_v3_counter_test'] = $t.id }; continue }
        $ct = Copy-Ordered $t
        $ct['stage'] = $(if ($t.independence_group -eq 'measured_cost') { 'detection' } else { 'attribution' })
        $counters.Add($ct)
    }
    if ($counters.Count -eq 0) { $problems.Add("$($rule.id) no counter tests remain") }
    $supports = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $rule.supporting_tests) { $st = Copy-Ordered $t; $st['stage'] = 'attribution'; $supports.Add($st) }

    # metrics actually used
    $used = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($x in @($detection, $attribution, $validation)) { if ($x) { foreach ($k in @('decision', 'test', 'disconfirm_test')) { if ($x.Contains($k)) { Collect-Metrics $x[$k] $used } }; if ($x.Contains('classification_tests')) { foreach ($ct in $x['classification_tests']) { Collect-Metrics $ct.test $used } } } }
    foreach ($t in $counters) { Collect-Metrics $t.test $used }
    foreach ($t in $supports) { Collect-Metrics $t.test $used }
    $derived = [System.Collections.Generic.List[string]]::new()
    foreach ($x in $rule.derived_metrics) { if (-not $derived.Contains($x)) { $derived.Add($x) } }
    foreach ($x in $used) { if (-not $derived.Contains($x)) { $derived.Add($x) } }

    $optional = [System.Collections.Generic.List[string]]::new()
    foreach ($x in @($rule.optional_evidence) + $stageOpt) { if ($x -and $x -ne 'trials' -and -not $optional.Contains($x) -and $stageReq -notcontains $x) { $optional.Add($x) } }

    $newRule = [ordered]@{}
    foreach ($p in $rule.PSObject.Properties) {
        switch ($p.Name) {
            'required_evidence' {
                $newRule['lab_only'] = [bool]$m.Lab
                $newRule['stages'] = [ordered]@{ detection = $detection; attribution = $attribution; validation = $validation }
            }
            'decision' { }
            'optional_evidence' { $newRule['optional_evidence'] = $optional.ToArray() }
            'derived_metrics' { $newRule['derived_metrics'] = $derived.ToArray() }
            'counter_tests' { $newRule['counter_tests'] = $counters.ToArray() }
            'supporting_tests' { $newRule['supporting_tests'] = $supports.ToArray() }
            'conclusion' {
                $newRule['conclusion'] = [ordered]@{
                    stage_ceiling = $cls
                    when_false = $p.Value.when_false
                    when_unknown = $p.Value.when_unknown
                    when_threshold_unconfigured = 'configuration_required; report per contract.threshold_profile_policy.blocked_decision_report'
                    when_validation_missing = 'validation_pending; earlier stage findings retained'
                    supported_cause_requires = $p.Value.supported_cause_requires
                }
            }
            default { $newRule[$p.Name] = $p.Value }
        }
    }
    $newRule['v3_migration'] = [ordered]@{
        from_version = '3.0'
        detection_conjuncts = @($D); attribution_conjuncts = @($A); validation_conjuncts = @($V)
        replaced_by_override = @($covers)
        added_attribution = @(@($m.AddA | Where-Object { $_ }) | ForEach-Object { First-Metric $_ })
        validation_metric = $vMetric
        moved_counter_tests = $movedCounters.ToArray()
        evidence_made_optional = @($moved)
        note = $(if ($m.Note) { $m.Note } elseif ($m.Lab) { 'P1: V3 decision consisted only of a controlled trial; rule is lab-only and cannot produce a read-only production finding.' } else { 'P1 stage restructuring; V3 non-trial conditions preserved across detection and attribution.' })
    }
    $newRules.Add($newRule)
    $stageRows.Add([pscustomobject]@{ id = $rule.id; cls = $cls; lab = [bool]$m.Lab; D = ($D -join ', '); Dover = [bool]$m.Dover; A = ($A -join ', '); AddA = (@(@($m.AddA | Where-Object { $_ }) | ForEach-Object { First-Metric $_ }) -join ', '); Aover = [bool]$m.Aover; covers = ($covers -join ', '); V = $vMetric; Dc = $(if ($detection) { $detection.conclusion } else { '-' }); Ac = $(if ($attribution) { $attribution.conclusion } else { '-' }); moved = ($movedCounters -join ', '); opt = ($moved -join ', ') })
}

# ---------------------------------------------------------------- P6 HEALTH-002
$h1 = $ruleById['HEALTH-001']
$h2Decision = All-Of @(
    (Cmp 'coverage_ratio' 'ge' 'healthy_coverage'), (Cmp 'comparable_baseline_count' 'gt' 0),
    (Cmp 'db_time_deviation' 'le' 'material_deviation'), (Cmp 'baseline_deviation_ratio' 'le' 'material_deviation'),
    (Cmp 'logical_read_deviation' 'le' 'material_deviation'), (Cmp 'read_deviation' 'le' 'material_deviation'),
    (Cmp 'frequency_deviation' 'le' 'frequency_deviation_bound'), (Cmp 'concurrency_deviation' 'le' 'concurrency_deviation_bound'),
    (Cmp 'temp_occupancy_deviation' 'le' 'material_deviation'))
$h2Metrics = @('coverage_ratio', 'comparable_baseline_count', 'db_time_deviation', 'baseline_deviation_ratio', 'logical_read_deviation', 'read_deviation', 'frequency_deviation', 'concurrency_deviation', 'temp_occupancy_deviation', 'wall_deviation')
$newRules.Add([ordered]@{
    id = 'HEALTH-002'; name = 'No material database-side degradation; end-to-end response time not evaluated'; domain = 'HEALTH'
    diagnostic_class = 'no_material_database_side_degradation'
    hypothesis = 'No material database-side degradation detected in the investigated evidence/window'
    oracle_versions = @('19c'); scope = @('database', 'container', 'instance_or_cluster', 'family_or_sql', 'incident_window')
    baseline_knowledge = $null
    observations = @('coverage_ratio', 'comparable_baseline_count', 'db_time_deviation', 'baseline_deviation_ratio', 'logical_read_deviation', 'read_deviation', 'frequency_deviation', 'concurrency_deviation', 'temp_occupancy_deviation')
    lab_only = $false
    preconditions = @(
        [ordered]@{ kind = 'metric_status'; metric = 'wall_deviation'; status_in = @('unknown'); reason = 'Applies only when end-to-end/wall latency could not be evaluated; a measured wall-latency degradation must not be reported as database-side health.' }
        [ordered]@{ kind = 'rule_outcome'; rule = 'HEALTH-001'; outcome_not_in = @('true'); reason = 'HEALTH-001 is the stronger statement and takes precedence.' }
    )
    stages = [ordered]@{
        detection = [ordered]@{ evidence = @('coverage', 'sql', 'temp', 'executions'); optional_evidence = @(); decision = $h2Decision; conclusion = 'no_material_database_side_degradation'
            meaning = 'Every tracked database-side cost, demand and occupancy measure is within configured tolerance with adequate coverage and a comparable baseline. Sampled execution estimates are allowed for concurrency when estimate kinds match.' }
        attribution = $null; validation = $null
    }
    optional_evidence = @('changes'); derived_metrics = $h2Metrics
    prerequisites = $h1.prerequisites
    decision_binding = $h1.decision_binding
    counter_tests = @([ordered]@{ id = 'HEALTH-002-degraded'; effect = 'prevent_healthy'; independence_group = 'measured_cost'; stage = 'detection'
        test = (Any-Of @((Cmp 'db_time_deviation' 'gt' 'material_deviation'), (Cmp 'logical_read_deviation' 'gt' 'material_deviation'), (Cmp 'frequency_deviation' 'gt' 'frequency_deviation_bound')))
        explanation = 'Any supported material database-side cost/demand deviation prevents this conclusion.' })
    supporting_tests = @(); confidence_policy = 'CP-01'
    conclusion = [ordered]@{ stage_ceiling = 'no_material_database_side_degradation'; fixed_text = 'contract.database_side_policy.conclusion_text'; when_false = 'not_supported_by_collected_evidence'; when_unknown = 'insufficient_evidence (distinct from this conclusion)'; when_threshold_unconfigured = 'configuration_required; report per contract.threshold_profile_policy.blocked_decision_report'; when_validation_missing = 'not_applicable'; supported_cause_requires = 'not_applicable' }
    roles = @([ordered]@{ role = 'unresolved'; when = 'external_and_end_to_end_layers_not_evaluated' })
    recommendation = [ordered]@{
        evidence_bindings = @('coverage_ratio', 'comparable_baseline_count', 'db_time_deviation', 'baseline_deviation_ratio', 'logical_read_deviation', 'read_deviation', 'frequency_deviation', 'concurrency_deviation', 'temp_occupancy_deviation')
        next_test = 'Obtain end-to-end/application or client fetch timing for the same window (APP-NETWORK request) before attributing the reported slowness to any layer; list every unresolved external request.'
        expected_result = 'Database-side scope bounded; end-to-end layers explicitly not evaluated.'
        validation = 'Repeat with application execution timing or wall-latency evidence; HEALTH-001 supersedes when wall latency is available.'
        safety = 'Read-only predefined collection.'
        rollback = 'Not applicable; no change proposed.'
        withhold = @('Do not state or imply that the application, network or client caused the problem.', 'Do not state that no problem exists.')
    }
    safety_risk = 'low'; causal_parents = @(); causal_children = @(); reinforcing_hypotheses = @(); contradictory_hypotheses = @()
    licensing_requirements = $h1.licensing_requirements; cross_module_requests = @('APP-NETWORK')
    references = @('repository:docs/sql_tuning_v3_1_change_proposals.md', 'https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_HIST_SQLSTAT.html', 'https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-ACTIVE_SESSION_HISTORY.html')
    added_in = '3.1'
})

# ---------------------------------------------------------------- causal edges (P1)
$edgeMap = @{ 'CE-01' = @{ A = @('estimate_error_ratio'); V = 'statistics_gain' }; 'CE-02' = @{ A = @('inner_starts'); V = 'join_order_gain' } }
$newEdges = [System.Collections.Generic.List[object]]::new()
foreach ($e in $v3.causal_edges) {
    $conj = Conjuncts $e.test
    $em = $edgeMap[$e.id]
    $attrItems = [System.Collections.Generic.List[object]]::new(); $valNode = $null
    foreach ($c in $conj) {
        $k = First-Metric $c
        if ($metricOps[$k] -eq 'trial_ratio') { if (-not $em -or $em.V -ne $k) { $problems.Add("Edge $($e.id) unmapped trial $k") }; $valNode = $c } else { $attrItems.Add($c) }
    }
    $attrTest = All-Of $attrItems.ToArray()
    $valEvidence = [string[]]@(); $valDisconfirm = $null
    if ($valNode) { $valEvidence = [string[]]@('trials'); $valDisconfirm = Cmp (First-Metric $valNode) 'le' 'controlled_cost_gain' }
    $ne = [ordered]@{
        id = $e.id; parent = $e.parent; child = $e.child; mechanism = $e.mechanism; scope = $e.scope
        required_evidence = @($e.required_evidence | Where-Object { $_ -ne 'trials' })
        attribution_test = $attrTest
        validation_evidence = $valEvidence
        validation_test = $valNode
        validation_disconfirm_test = $valDisconfirm
        temporal = $e.temporal
        status = 'candidate_link_when_attribution_test_true; validation strengthens and satisfies comparable_control; causal gates still required for supported_cause'
        counter_test = [ordered]@{ test = (Not-Of $attrTest); effect = $e.counter_test.effect; note = $e.counter_test.note }
        missing = $e.missing
        v3_migration = [ordered]@{ from_version = '3.0'; validation_conjunct = $(if ($valNode) { First-Metric $valNode } else { $null }) }
    }
    $newEdges.Add($ne)
}

# ---------------------------------------------------------------- contract / policy additions
$contract = Copy-Ordered $v3.contract
$contract['safety'] = $v3.contract.safety
$conclusions = [System.Collections.Generic.List[string]]::new(); foreach ($c in $v3.contract.conclusions) { $conclusions.Add($c) }; $conclusions.Add('no_material_database_side_degradation')
$contract['conclusions'] = $conclusions.ToArray()
$contract['evidence_stages'] = [ordered]@{
    detection = 'Evidence sufficient to establish that an abnormal condition or relevant observation exists.'
    attribution = 'Evidence linking the observed condition to a specific mechanism, SQL family, plan operation, object, workload or resource.'
    validation = 'Evidence from controlled comparison, lab trial, remediation test, or other strong confirmation that validates the causal/remediation hypothesis.'
}
$contract['stage_policy'] = [ordered]@{
    applicability = 'A rule need not use all three stages. attribution or validation null means not applicable for that rule; lab_only rules have no detection stage and never produce read-only production findings.'
    evaluation = 'Stages evaluate independently with three-valued logic over their own required evidence. Detection is evaluated first; attribution and validation are evaluated for every rule whose detection is TRUE, and their absence never erases a TRUE detection finding.'
    conclusion_ladder = 'detection TRUE -> stages.detection.conclusion; plus attribution TRUE -> stages.attribution.conclusion; plus validation TRUE -> stages.validation.conclusion with validates=mechanism|remediation_gain. supported_cause additionally requires all contract.causal_gate items.'
    missing_attribution = 'attribution_unresolved: finding stays at detection conclusion with the named attribution evidence gap and next test.'
    missing_validation = 'validation_pending: no penalty and no confidence cap from absence alone; lab or separately approved test proposed. Production remains read-only.'
    disconfirmed_validation = 'controlled_disconfirmation_weight applies to the mechanism/remediation claim; detection and attribution observations remain reported.'
    stage_outcomes = [ordered]@{
        detection = @('true', 'false', 'unknown', 'configuration_required', 'not_evaluated')
        attribution = @('attributed', 'not_attributed', 'attribution_unresolved', 'not_applicable')
        validation = @('validated', 'disconfirmed', 'validation_pending', 'not_applicable')
    }
    trial_metric_placement = 'trial_ratio metrics may appear only in validation stages and causal-edge validation tests.'
    shared_detection = 'Identical detection decisions in different rules produce one shared observation per scope/window referenced by each rule; it contributes once to scoring (confidence_policy.double_count_policy).'
}
$contract['monitor_policy'] = 'P2: V$SQL_PLAN_MONITOR/GV$SQL_PLAN_MONITOR are additional, not replacement, sources for execution/plan-line runtime evidence. Record per execution whether it was monitored, the eligibility reason if known, licensing status (Diagnostics+Tuning) and retention (live entries age out after at least one minute). QC and PX server entries share the execution key; count the execution once and aggregate plan-line STARTS/OUTPUT_ROWS across its entries, including cross-instance PX via GV$. Executions never monitored, not retained, or not captured to AWR leave monitor evidence absent/unknown; absence never means zero rows, no spill or no problem.'
$contract['historical_execution_policy'] = [ordered]@{
    rule = 'P3: ASH-derived executions are sampled and incomplete; they are never presented as exact durations or counts unless exact reconstruction is independently supported. Historical AWR SQL Monitor report evidence may be stronger where available. Licensing, retention and coverage status are preserved on every row.'
    estimate_kinds = [ordered]@{
        exact_logged = 'Application/execution log with start/end and completion status.'
        monitor_db_time = 'Live SQL Monitor ELAPSED_TIME/CPU_TIME: database time, not wall response.'
        report_bounded = 'AWR-captured SQL Monitor report for one SQL_EXEC_ID; bounded by report period/refresh times.'
        sampled_lower_bound = 'ASH reconstruction: max(SAMPLE_TIME)-SQL_EXEC_START; spacing from USECS_PER_ROW/observed samples; short executions may be absent.'
        polled_censored = 'V$SESSION polling interval; start/end censored by poll spacing.'
    }
    pooling = 'Percentiles, baseline ratios and overlap counts use one estimate kind on both incident and baseline sides; mixed kinds are incomparable.'
}
$contract['predicate_pattern_policy'] = [ordered]@{
    rule = 'P4: executed-plan predicate text identifies candidate column-side function/conversion mechanisms deterministically. Predicate text alone never proves an implicit datatype conversion: it cannot distinguish a conversion written in the SQL from one added by the optimizer, and INTERNAL_FUNCTION is ambiguous.'
    classifications = @('candidate', 'datatype_verified', 'implicit_confirmed', 'candidate_unverified', 'unparseable')
    parser_extension = 'ast evidence and ast_count metrics remain in every affected rule as an alternative detection path and as the implicit/explicit classifier; adding a deterministic SQL parser later requires no rule restructuring.'
    authority = 'engineering_interpretation of Oracle predicate display; requires live 19c fixture verification before production use'
}
$contract['awr_plan_policy'] = 'P5: per-plan historical comparison uses DBA_HIST_SQLSTAT *_DELTA interval values (never re-differenced) joined to DBA_HIST_SNAPSHOT on DBID/INSTANCE_NUMBER/SNAP_ID with a continuous STARTUP_TIME; compares plan hash values of the same SQL_ID (or validated family member) across comparable windows (same instances, service, Resource Manager plan/group, workload stratum and snapshot interval); snapshots below minimum_samples executions are excluded; AWR elapsed is DB time including PX workers; executions spanning snapshot boundaries are flagged and long-running executions require execution-level evidence. Requires Diagnostics Pack entitlement and retained snapshots; otherwise historical_telemetry_unavailable.'
$contract['database_side_policy'] = [ordered]@{
    rule = 'P6: HEALTH-002 is reported only when wall/end-to-end latency could not be evaluated and HEALTH-001 is not TRUE. It is distinct from insufficient database evidence, never states that no problem exists and never attributes the problem to the application, network or client.'
    conclusion_text = 'No material database-side degradation detected in the investigated evidence/window; end-to-end application/network/client response time was not evaluated.'
}
$contract['capability_policy'] = [ordered]@{
    rule = 'P7: record collection/environment settings at investigation start, before diagnostic collection, so every missing or degraded evidence item cites a concrete capability reason. Configuration values never establish licensing entitlement; entitlement comes only from license_policy.'
    items = @('oracle_version', 'database_identity', 'container_identity', 'instance_identity_and_startup', 'rac_topology_and_instance_coverage', 'statistics_level', 'control_management_pack_access', 'configured_license_policy', 'sql_monitor_availability', 'awr_snapshot_interval_and_retention', 'ash_earliest_sample_per_instance', 'awr_earliest_snapshot_per_instance', 'collector_privileges_and_connection_mode', 'resource_manager_plan_and_cpu_count', 'instance_caging_state', 'collection_start_end_utc_and_requested_window')
    entitlement_rule = 'CONTROL_MANAGEMENT_PACK_ACCESS describes enabled features, not entitlement. Source existence does not establish entitlement.'
    gap_reasons = @('statistics_level_typical_no_plan_statistics', 'execution_not_monitored', 'monitor_entry_aged_out', 'awr_report_not_captured', 'pack_access_disabled', 'entitlement_not_configured', 'outside_ash_retention', 'outside_awr_retention', 'instance_not_covered', 'insufficient_privilege', 'collector_timeout_or_row_cap', 'counter_reset_by_restart')
}
$contract['threshold_profile_policy'] = [ordered]@{
    rule = 'P8: catalog thresholds stay null. Values come only from a versioned threshold profile stored outside the catalog (knowledge/threshold_profiles/), validated against the catalog threshold IDs and units. No defaults are invented; with no profile, threshold-dependent comparisons return configuration_required (UNKNOWN in boolean evaluation).'
    profile_location = 'knowledge/threshold_profiles/'
    profile_template = 'knowledge/threshold_profiles/template.json'
    profile_required_fields = @('profile_schema_version', 'profile_id', 'profile_version', 'catalog_version', 'author', 'approved_by', 'approved_on', 'scope', 'values')
    scope_match = 'A profile applies only when its scope (database, container, SQL family/workload) matches the investigation; otherwise configuration_required.'
    blocked_decision_report = @('rule_id', 'stage', 'metric_id', 'measured_value', 'unit', 'scope', 'window_start_utc', 'window_end_utc', 'threshold_id', 'threshold_unit', 'reason')
    finding_traceability = 'Every comparison that used a configured value records profile_id, profile_version and the value used.'
}
$contract['unknown_reasons'] = @('missing_required_evidence', 'configuration_required', 'incomparable', 'unsupported_capability', 'unlicensed_or_unentitled', 'sampled_insufficient', 'outside_retention', 'parse_failure', 'external_module_unavailable')

$cp = Copy-Ordered $v3.confidence_policy
$cp['revision'] = '3.1'
$cp['stage_scoring'] = [ordered]@{
    detection_only = 'Not ranked as a cause; reported with evidence quality and next tests.'
    attribution = 'Candidate ranking uses base_support/independent_support_weight/counter_weight unchanged from V3.'
    validation_true = 'Counts as independence group controlled_trial (within max_independent_support_groups) and may satisfy comparable_control.'
    validation_false = 'controlled_disconfirmation_weight against the mechanism/remediation claim; detection retained.'
    validation_missing = 'No weight, no cap; validation_pending.'
}

$gates = Copy-Ordered $v3.hypothesis_gates
$md = Copy-Ordered $v3.hypothesis_gates.measured_degradation
$mdItems = [System.Collections.Generic.List[object]]::new(); foreach ($x in $v3.hypothesis_gates.measured_degradation.test.any) { $mdItems.Add($x) }; $mdItems.Add((Cmp 'db_time_deviation' 'gt' 'material_deviation'))
$md['test'] = Any-Of $mdItems.ToArray()
$md['meaning'] = $md['meaning'] + ' V3.1: database time per execution (AWR/SQL Monitor) also measures degradation when wall latency is unavailable; it remains database-side only.'
$gates['measured_degradation'] = $md
$ml = Copy-Ordered $v3.hypothesis_gates.mechanism_link; $ml['meaning'] = 'At least one applicable causal edge attribution_test TRUE or a TRUE rule attribution stage binding the mechanism; validation strengthens but is not required. Detection/observation alone cannot satisfy.'; $gates['mechanism_link'] = $ml
$cc = Copy-Ordered $v3.hypothesis_gates.comparable_control; $cc['meaning'] = $cc['meaning'] + ' V3.1: satisfied by a matched baseline under baseline_policy OR a TRUE validation stage.'; $gates['comparable_control'] = $cc

$outcomes = Copy-Ordered $v3.outcomes
$outcomes['database_side_rule'] = 'HEALTH-002'
$outcomes['database_side_no_degradation'] = 'no_material_database_side_degradation; end-to-end not evaluated; never proof that another layer is responsible'
$outcomes['detection_without_attribution'] = 'observation_reported_attribution_unresolved'
$outcomes['detection_without_validation'] = 'finding_reported_validation_pending'
$outcomes['lab_only_rule'] = 'not_evaluable_read_only; lab validation proposed'

$operators = Copy-Ordered $v3.operators
$operators['plan_predicate_pattern_count'] = 'P4: count executed-plan ACCESS/FILTER predicate occurrences matching an allowlisted pattern set from plan_predicate_patterns, after tokenizing Oracle predicate text; wrapped quoted identifier resolved to the plan-line object. Classification parameter selects candidate/datatype_verified/implicit_confirmed. Unparseable text or unresolved objects yield UNKNOWN, never zero.'

$patterns = [ordered]@{
    authority = 'engineering_interpretation; patterns require live 19c fixture verification'
    argument_shape = 'Wrapper applied to a quoted column identifier ("COL" or "ALIAS"."COL") on the column side of a comparison; constant-side wrappers do not count.'
    conversion_wrappers = @(
        [ordered]@{ name = 'TO_NUMBER'; ambiguous = $false; target_type = 'NUMBER' }
        [ordered]@{ name = 'TO_CHAR'; ambiguous = $false; target_type = 'VARCHAR2' }
        [ordered]@{ name = 'TO_DATE'; ambiguous = $false; target_type = 'DATE' }
        [ordered]@{ name = 'TO_TIMESTAMP'; ambiguous = $false; target_type = 'TIMESTAMP' }
        [ordered]@{ name = 'SYS_OP_C2C'; ambiguous = $false; target_type = 'character_set_conversion' }
        [ordered]@{ name = 'INTERNAL_FUNCTION'; ambiguous = $true; target_type = 'unresolved'; note = 'Also appears for non-conversion internal operations; verify operand types before counting.' }
    )
    function_wrappers = @(
        [ordered]@{ name = 'UPPER'; ambiguous = $false }
        [ordered]@{ name = 'LOWER'; ambiguous = $false }
        [ordered]@{ name = 'TRUNC'; ambiguous = $false }
        [ordered]@{ name = 'SUBSTR'; ambiguous = $false }
        [ordered]@{ name = 'NVL'; ambiguous = $false }
    )
}

$fr = Copy-Ordered $v3.feature_requirements
$smon = Copy-Ordered $v3.feature_requirements.sql_monitor
$smon['fallback'] = $smon['fallback'] + '; V3.1: AWR-captured SQL Monitor reports (DBA_HIST_REPORTS/_DETAILS) for historical executions where captured'
$smon['eligibility'] = 'Automatic for >=5 s CPU or I/O in one execution, parallel execution, MONITOR hint or sql_monitor event; requires CONTROL_MANAGEMENT_PACK_ACCESS=DIAGNOSTIC+TUNING and STATISTICS_LEVEL TYPICAL or ALL (configuration, not entitlement).'
$fr['sql_monitor'] = $smon

# ---------------------------------------------------------------- acceptance cases
$cases = [System.Collections.Generic.List[object]]::new()
foreach ($case in $v3.acceptance_cases) {
    $nc = Copy-Ordered $case
    if ($case.id -eq 'production_family_allocation') {
        $neg = [System.Collections.Generic.List[object]]::new(); foreach ($x in $case.negative_perturbations) { $neg.Add($x) }
        $neg.Add([ordered]@{ change = 'All ~1,159 resmgr:cpu quantum waiters treated as CPU consumers'; expected = 'RM-001 symptom only; waiting is not consumption. Contributor roles need measured consumed CPU (FAM-005 detection+attribution); waiters default to RM-005 victim candidates or unresolved.' })
        $neg.Add([ordered]@{ change = 'SQL_IDs grouped only because they share PLAN_HASH_VALUE'; expected = 'FAM-001 detection cannot validate membership without signature/AST evidence; candidate cohort only.' })
        $neg.Add([ordered]@{ change = 'Execution-level TEMP allocation observed without plan-line/workarea evidence'; expected = 'TEMP-001 detection TRUE, attribution_unresolved; JOIN-002/SORT-001/SORT-002 not evaluated; spilling operation not named.' })
        $neg.Add([ordered]@{ change = 'Rollover, demand growth and RM pressure overlap in time with no mechanism test'; expected = 'TIME-001 attribution may show compatible order; trigger role and supported_cause remain blocked by mechanism_link/counter_search/comparable_control gates.' })
        $neg.Add([ordered]@{ change = 'Incident executions not SQL-monitored (serial, <5 s each)'; expected = 'Plan-line actuals UNKNOWN; CARD-005/JOIN-001/TEMP-002 not evaluated; never zero rows or no spill.' })
        $neg.Add([ordered]@{ change = 'No lab trial results available'; expected = 'Detection/attribution findings reported with validation_pending; no rule erased.' })
        $nc['negative_perturbations'] = $neg.ToArray()
    }
    $cases.Add($nc)
}
$cases.Add([ordered]@{
    id = 'database_side_only'; description = 'Historical incident with AWR/ASH only and no application wall timing (P6).'; added_in = '3.1'
    facts = @([ordered]@{ fact = 'Adequate AWR/ASH coverage and matched baseline; no wall-latency evidence'; evidence = @('coverage', 'sql', 'executions', 'temp'); metrics = @('coverage_ratio', 'db_time_deviation', 'baseline_deviation_ratio', 'logical_read_deviation', 'read_deviation', 'frequency_deviation', 'concurrency_deviation', 'temp_occupancy_deviation'); rules = @('HEALTH-002', 'HEALTH-001'); causal_edges = @()
        expected = 'HEALTH-001 unresolved (wall unknown). HEALTH-002 may conclude the fixed database-side text for the stated scope; no external layer is named as responsible.' })
    negative_perturbations = @(
        [ordered]@{ change = 'DB time per execution rises while buffer gets stay flat'; expected = 'HEALTH-002 FALSE; measured_degradation gate TRUE via db_time_deviation; wait/storage hypotheses evaluated.' }
        [ordered]@{ change = 'Wall latency measured and degraded'; expected = 'HEALTH-002 precondition fails and it is not reported; WAIT-004 attribution evaluated.' }
        [ordered]@{ change = 'Baseline missing'; expected = 'insufficient_evidence; never HEALTH-002.' }
    )
})

# ---------------------------------------------------------------- assemble catalog
if ($problems.Count) { $problems | ForEach-Object { Write-Output "MIGRATION ERROR: $_" }; exit 1 }

$metricsOut = [System.Collections.Generic.List[object]]::new(); foreach ($x in $v3.metrics) { $metricsOut.Add($x) }; foreach ($x in $newMetrics) { $metricsOut.Add($x) }
$sourcesOut = [System.Collections.Generic.List[object]]::new()
foreach ($s in $v3.sources) {
    $ns = Copy-Ordered $s
    if ($sourceColumnAdds.Contains($s.id)) {
        $cols = [System.Collections.Generic.List[string]]::new(); foreach ($c in $s.columns) { $cols.Add($c) }
        foreach ($c in $sourceColumnAdds[$s.id]) { if (-not $cols.Contains($c)) { $cols.Add($c) } }
        $ns['columns'] = $cols.ToArray()
        $ns['limitations'] = $s.limitations + $sourceLimitationAdds[$s.id]
    }
    $sourcesOut.Add($ns)
}
foreach ($s in $newSources) { $sourcesOut.Add($s) }
$evidenceOut = [System.Collections.Generic.List[object]]::new(); foreach ($e in $v3.evidence) { $evidenceOut.Add($e) }; $evidenceOut.Add($capability)

$catalog = [ordered]@{}
foreach ($p in $v3.PSObject.Properties) {
    switch ($p.Name) {
        'catalog_version' { $catalog['catalog_version'] = '3.1' }
        'implementation_status' { $catalog['implementation_status'] = 'knowledge-only' }
        'catalog_status' {
            $catalog['catalog_status'] = 'v3.1-reviewable-specification'
            $catalog['predecessor'] = [ordered]@{ path = 'knowledge/sql_tuning_catalog_v3.yaml'; version = '3.0'; preservation = 'unchanged historical checkpoint'; sha256 = $v3Hash }
            $catalog['source_manifest'] = [ordered]@{ path = 'knowledge/sql_tuning_sources_19c_v3_1.json'; predecessor_path = 'knowledge/sql_tuning_sources_19c.json'; predecessor_sha256 = $manifestHash }
            $catalog['change_log'] = @(
                [ordered]@{ id = 'P1'; decision = 'accepted_with_modification'; summary = 'Three evidence stages (detection, attribution, validation); trial metrics only in validation; missing validation never erases detection.' }
                [ordered]@{ id = 'P2'; decision = 'accepted_with_conditions'; summary = 'V$SQL_PLAN_MONITOR added (not replacing V$SQL_PLAN_STATISTICS_ALL) with eligibility, licensing, unmonitored, QC/PX and retention semantics.' }
                [ordered]@{ id = 'P3'; decision = 'accepted_with_strict_limits'; summary = 'Historical executions from ASH as sampled/incomplete evidence and AWR SQL Monitor reports; estimate kinds never pooled.' }
                [ordered]@{ id = 'P4'; decision = 'accepted_with_conditions'; summary = 'Plan-predicate candidate detection with datatype verification as attribution and implicit/explicit classification; parser path retained.' }
                [ordered]@{ id = 'P5'; decision = 'accepted'; summary = 'Plan regression attributable from AWR per-plan aggregates under awr_plan_policy.' }
                [ordered]@{ id = 'P6'; decision = 'accepted_with_wording_change'; summary = 'HEALTH-002 database-side verdict with fixed wording; distinct from insufficient evidence.' }
                [ordered]@{ id = 'P7'; decision = 'strongly_accepted'; summary = 'capability evidence recorded at investigation start; configuration is not entitlement.' }
                [ordered]@{ id = 'P8'; decision = 'strongly_accepted'; summary = 'Thresholds stay null; external versioned threshold profiles; blocked-decision reporting.' }
            )
        }
        'contract' { $catalog['contract'] = $contract }
        'operators' { $catalog['operators'] = $operators; $catalog['plan_predicate_patterns'] = $patterns }
        'confidence_policy' { $catalog['confidence_policy'] = $cp }
        'sources' { $catalog['sources'] = $sourcesOut.ToArray() }
        'evidence' { $catalog['evidence'] = $evidenceOut.ToArray() }
        'metrics' { $catalog['metrics'] = $metricsOut.ToArray() }
        'rules' { $catalog['rules'] = $newRules.ToArray() }
        'causal_edges' { $catalog['causal_edges'] = $newEdges.ToArray() }
        'acceptance_cases' { $catalog['acceptance_cases'] = $cases.ToArray() }
        'outcomes' { $catalog['outcomes'] = $outcomes }
        'hypothesis_gates' { $catalog['hypothesis_gates'] = $gates }
        'feature_requirements' { $catalog['feature_requirements'] = $fr }
        default { $catalog[$p.Name] = $p.Value }
    }
}
Save-Json $catalog $outCatalog

# ---------------------------------------------------------------- V3.1 source allowlist
$mSources = [System.Collections.Generic.List[object]]::new()
foreach ($s in $manifest.sources) {
    $ns = Copy-Ordered $s
    if ($sourceColumnAdds.Contains($s.id)) {
        $cols = [System.Collections.Generic.List[string]]::new(); foreach ($c in $s.columns) { $cols.Add($c) }
        foreach ($c in $sourceColumnAdds[$s.id]) { if (-not $cols.Contains($c)) { $cols.Add($c) } }
        $ns['columns'] = $cols.ToArray(); $ns['revised_on'] = $AuditDate
    }
    $mSources.Add($ns)
}
foreach ($s in $newSources) { if ($s.kind -ne 'external_evidence') { $mSources.Add([ordered]@{ id = $s.id; name = $s.name; kind = $s.kind; columns = $s.columns; requires_all = $s.licensing.requires_all; reference = $s.reference; added_on = $AuditDate }) } }
Save-Json ([ordered]@{ oracle_version = $manifest.oracle_version; reviewed_on = $AuditDate; scope = $manifest.scope; catalog_version = '3.1'; predecessor = [ordered]@{ path = 'knowledge/sql_tuning_sources_19c.json'; sha256 = $manifestHash }; sources = $mSources.ToArray() }) $outManifest

# ---------------------------------------------------------------- P8 threshold profile template
New-Item -ItemType Directory -Force -Path $outProfileDir | Out-Null
$values = [ordered]@{}
foreach ($t in $v3.thresholds) { $values[$t.id] = [ordered]@{ value = $null; unit = $t.unit; rationale = $null; calibration_refs = @() } }
Save-Json ([ordered]@{
    profile_schema_version = '1.0'; profile_id = $null; profile_version = $null; catalog_version = '3.1'
    status = 'template_unconfigured'; author = $null; approved_by = $null; approved_on = $null
    scope = [ordered]@{ database = $null; con_id = $null; sql_family = $null; workload = $null }
    notes = 'Template only. Every value is null by design (P8). Copy, set values from lab/production calibration evidence with rationale, and record approval. No defaults are implied.'
    values = $values
}) (Join-Path $outProfileDir 'template.json')

# ---------------------------------------------------------------- generated stage map document
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# V3.1 rule stage map (generated)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Generated by `tools/migrate_catalog_v3_to_v3_1.ps1` from the unchanged V3 catalog. Do not edit by hand. Each V3 decision conjunct (named by its first metric) appears in exactly one stage; the migration fails otherwise.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Legend: **D** detection, **A** attribution, **V** validation metric. `+` marks an attribution conjunct added in V3.1 from a P1/P4 metric; `override` marks a P4/P5 replacement expression that contains the V3 conjunct. "Moved counter" is the V3 controlled-trial counter test folded into `validation.disconfirm_test`.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Rule | Ceiling class | D (V3 conjuncts) | A (V3 conjuncts / added) | V metric | D concl. | A concl. | Moved counter | Required -> optional |')
[void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
foreach ($r in $stageRows) {
    $d = if ($r.lab) { '*lab-only (no detection)*' } elseif ($r.Dover) { "override (P4) covering $($r.covers)" } else { $r.D }
    $a = @(); if ($r.A) { $a += $r.A }; if ($r.AddA) { $a += "+ $($r.AddA)" }
    if ($r.Aover) { $a = @($(if ($r.Dover) { 'override (P4)' } else { "override (P5) covering $($r.covers)" })) }
    [void]$sb.AppendLine("| $($r.id) | $($r.cls) | $d | $(if ($a.Count) { $a -join '; ' } else { '-' }) | $(if ($r.V) { $r.V } else { '-' }) | $($r.Dc) | $($r.Ac) | $(if ($r.moved) { $r.moved } else { '-' }) | $(if ($r.opt) { $r.opt } else { '-' }) |")
}
[void]$sb.AppendLine('| HEALTH-002 | no_material_database_side_degradation | new rule (P6) | - | - | no_material_database_side_degradation | - | - | - |')
[System.IO.File]::WriteAllText($outStageMap, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

Write-Output "Wrote $outCatalog"
Write-Output "Wrote $outManifest"
Write-Output "Wrote $(Join-Path $outProfileDir 'template.json')"
Write-Output "Wrote $outStageMap"
Write-Output "Rules: $($newRules.Count) IDs; metrics: $($metricsOut.Count); sources: $($sourcesOut.Count); edges: $($newEdges.Count)"
