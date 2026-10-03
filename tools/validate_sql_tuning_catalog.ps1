param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot '..\knowledge\sql_tuning_catalog_v3.yaml'),
    [switch]$SkipBaselineHash,
    [string]$SourceManifestPath = (Join-Path $PSScriptRoot '..\knowledge\sql_tuning_sources_19c.json')
)
$ErrorActionPreference = 'Stop'
$script:issues = [System.Collections.Generic.List[string]]::new()
function Fail([string]$message) { $script:issues.Add($message) }
function Fields($object, [string[]]$names, [string]$context) {
    foreach ($name in $names) {
        if ($null -eq $object -or $object.PSObject.Properties.Name -notcontains $name) { Fail "$context missing $name" }
    }
}
function Index($items, [string]$key, [string]$context) {
    $result = @{}
    foreach ($item in $items) {
        $id = [string]$item.$key
        if ([string]::IsNullOrWhiteSpace($id)) { Fail "$context empty $key"; continue }
        if ($result.ContainsKey($id)) { Fail "$context duplicate $id" } else { $result[$id] = $item }
    }
    return $result
}
function Ref([hashtable]$map, [string]$id, [string]$context) {
    if (-not $map.ContainsKey($id)) { Fail "$context undefined reference $id" }
}
function Expression($node, [string]$context, [switch]$AllowField) {
    if ($null -eq $node) { Fail "$context null expression"; return }
    $keys = @($node.PSObject.Properties.Name)
    if ($keys.Count -eq 1 -and ($keys[0] -in @('all','any'))) {
        if (@($node.($keys[0])).Count -eq 0) { Fail "$context empty boolean tree" }
        foreach ($child in $node.($keys[0])) { Expression $child $context -AllowField:$AllowField }
        return
    }
    if ($keys.Count -eq 1 -and $keys[0] -eq 'not') { Expression $node.not $context -AllowField:$AllowField; return }
    Fields $node @('op','left','right') $context
    if ($node.op -notin @('eq','ne','gt','ge','lt','le','in')) { Fail "$context invalid comparison operator $($node.op)" }
    foreach ($operand in @($node.left, $node.right)) {
        if ($null -eq $operand) { Fail "$context missing operand"; continue }
        $okeys = @($operand.PSObject.Properties.Name)
        if ($okeys.Count -ne 1) { Fail "$context operand must have one typed key"; continue }
        switch ($okeys[0]) {
            'metric' { Ref $script:metrics $operand.metric $context }
            'threshold' { Ref $script:thresholds $operand.threshold $context }
            'evidence' { Ref $script:evidence $operand.evidence $context }
            'literal' { if ($operand.literal -is [pscustomobject]) { Fail "$context object literal is not supported" } }
            'field' { if (-not $AllowField) { Fail "$context row field outside metric filter" } }
            default { Fail "$context unknown operand $($okeys[0])" }
        }
    }
    if ($node.left.metric -and $node.right.threshold -and $script:metrics.ContainsKey($node.left.metric) -and $script:thresholds.ContainsKey($node.right.threshold)) {
        $actual = $script:metrics[$node.left.metric].unit
        $expected = $script:thresholds[$node.right.threshold].unit
        if ($actual -ne $expected -and $expected -ne 'native_unit') { Fail "$context incompatible units $actual / $expected" }
    }
}
function Visit([string]$id, [hashtable]$graph, [hashtable]$colors, [string]$context) {
    if ($colors[$id] -eq 1) { Fail "$context cycle at $id"; return }
    if ($colors[$id] -eq 2) { return }
    $colors[$id] = 1
    foreach ($next in @($graph[$id])) { if ($next) { Visit $next $graph $colors $context } }
    $colors[$id] = 2
}
try {
    $resolved = (Resolve-Path -LiteralPath $CatalogPath).Path
    # JSON is an intentional YAML 1.2 subset: standard-library offline parsing.
    $catalog = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    Fields $catalog @('catalog_version','baseline','taxonomy','contract','operators','sources','evidence','metrics','thresholds','rules','causal_edges','confidence_policy','cross_module_requests','acceptance_cases','outcomes','hypothesis_gates','feature_requirements') 'catalog'
    if ($catalog.catalog_version -ne '3.0') { Fail 'Unsupported catalog version' }
    $domains = Index $catalog.taxonomy.domains 'code' 'domains'
    $sources = Index $catalog.sources 'id' 'sources'
    $script:evidence = Index $catalog.evidence 'id' 'evidence'
    $script:metrics = Index $catalog.metrics 'id' 'metrics'
    $script:thresholds = Index $catalog.thresholds 'id' 'thresholds'
    $rules = Index $catalog.rules 'id' 'rules'
    $edges = Index $catalog.causal_edges 'id' 'causal_edges'
    $requests = Index $catalog.cross_module_requests 'id' 'cross_module_requests'
    $cases = Index $catalog.acceptance_cases 'id' 'acceptance_cases'
    $manifest = Get-Content -LiteralPath $SourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $auditedSources = Index $manifest.sources 'id' 'audited sources'
    foreach ($source in $catalog.sources) {
        Fields $source @('name','kind','columns','grain','unit_policy','licensing','reference','limitations','fallbacks','audit') "source $($source.id)"
        if ($source.kind -notin @('oracle_view','oracle_api','external_evidence')) { Fail "Invalid source kind $($source.id)" }
        if ($source.kind -ne 'external_evidence') {
            Ref $auditedSources $source.id 'Oracle source allowlist'
            if ($auditedSources.ContainsKey($source.id)) {
                $audited = $auditedSources[$source.id]
                if ($source.name -ne $audited.name -or $source.kind -ne $audited.kind) { Fail "Oracle source definition changed $($source.id)" }
                foreach ($column in $source.columns) { if ($audited.columns -notcontains $column) { Fail "Unaudited Oracle column $($source.id).$column" } }
                foreach ($pack in $audited.requires_all) { if ($source.licensing.requires_all -notcontains $pack) { Fail "Audited licensing gate removed $($source.id)" } }
            }
        }
        if ($source.licensing.category -notin @('base','diagnostics_pack','tuning_pack','external','optional_feature','feature_dependent')) { Fail "Invalid license $($source.id)" }
        foreach ($pack in $source.licensing.requires_all) { if ($pack -notin @('diagnostics_pack','tuning_pack')) { Fail "Invalid pack $pack" } }
        if ($source.licensing.category -eq 'tuning_pack' -and ($source.licensing.requires_all -notcontains 'diagnostics_pack' -or $source.licensing.requires_all -notcontains 'tuning_pack')) { Fail "Tuning dependency missing $($source.id)" }
        if ($source.kind -eq 'oracle_view' -and $source.name -notmatch '^(V\$[A-Z0-9_]+|DBA_[A-Z0-9_]+)$') { Fail "Invalid Oracle source name $($source.name)" }
        if ($source.id -match 'ACTIVE_SESSION_HISTORY|DBA_HIST_(SQL|ACTIVE)' -and $source.licensing.requires_all -notcontains 'diagnostics_pack') { Fail "Diagnostics gate missing $($source.id)" }
        if ($source.id -match 'SQL_(PLAN_)?MONITOR' -and $source.licensing.requires_all -notcontains 'tuning_pack') { Fail "Tuning gate missing $($source.id)" }
        foreach ($fallback in $source.fallbacks) { Ref $sources $fallback "source fallback $($source.id)" }
        if ($source.rac_name -and $source.rac_name -ne $source.name.Replace('V$','GV$')) { Fail "Invalid RAC equivalent $($source.id)" }
    }
    foreach ($item in $catalog.evidence) {
        Fields $item @('type','fields','bindings','normalization','quality') "evidence $($item.id)"
        $fieldIndex = Index $item.fields 'name' "evidence fields $($item.id)"
        foreach ($field in $item.fields) {
            Fields $field @('name','type','unit') "field $($item.id).$($field.name)"
            if ($field.type -notin @('number','string','boolean')) { Fail "Invalid evidence type $($item.id).$($field.name)" }
        }
        if (@($item.bindings).Count -eq 0) { Fail "Unreachable evidence $($item.id)" }
        foreach ($binding in $item.bindings) {
            Ref $sources $binding.source_id "evidence $($item.id)"
            if ($sources.ContainsKey($binding.source_id)) {
                foreach ($column in $binding.columns) { if ($sources[$binding.source_id].columns -notcontains $column) { Fail "Unknown source column $($binding.source_id).$column" } }
            }
        }
    }
    $metricGraph = @{}
    foreach ($metric in $catalog.metrics) {
        Fields $metric @('operator','inputs','unit','parameters','group_by','null_zero_policy','quality') "metric $($metric.id)"
        if ($catalog.operators.PSObject.Properties.Name -notcontains $metric.operator) { Fail "Undefined metric operator $($metric.operator)" }
        $metricGraph[$metric.id] = @()
        foreach ($inputId in $metric.inputs) {
            if ($script:metrics.ContainsKey($inputId)) { $metricGraph[$metric.id] += $inputId; continue }
            $parts = $inputId.Split('.')
            Ref $script:evidence $parts[0] "metric $($metric.id)"
            if ($parts.Count -gt 1 -and $script:evidence.ContainsKey($parts[0]) -and $script:evidence[$parts[0]].fields.name -notcontains $parts[1]) { Fail "Unknown input field $inputId" }
        }
        if ($metric.parameters.filter) { Expression $metric.parameters.filter "metric filter $($metric.id)" -AllowField }
        foreach ($parameter in $metric.parameters.PSObject.Properties) {
            if ($parameter.Name -match '_threshold$' -and $parameter.Value) { Ref $script:thresholds $parameter.Value "metric parameter $($metric.id)" }
            if ($parameter.Name -in @('numerator_add','denominator_add') -and $parameter.Value -is [string] -and $parameter.Value.Contains('.')) {
                $parts = $parameter.Value.Split('.')
                Ref $script:evidence $parts[0] "metric addition $($metric.id)"
                if ($script:evidence.ContainsKey($parts[0]) -and $script:evidence[$parts[0]].fields.name -notcontains $parts[1]) { Fail "Unknown added field $($parameter.Value)" }
            }
        }
    }
    $colors = @{}
    foreach ($id in $metricGraph.Keys) { Visit $id $metricGraph $colors 'metric dependency' }
    foreach ($threshold in $catalog.thresholds) {
        Fields $threshold @('type','unit','value','configuration','oracle_universal') "threshold $($threshold.id)"
        if ($threshold.type -notin @('absolute','ratio','percentage','baseline_relative','historical_deviation','peer_comparison','per_execution','concurrency_adjusted','workload_specific','configurable','evidence_pattern')) { Fail "Invalid threshold type $($threshold.id)" }
        if ($null -ne $threshold.value -and $threshold.value -isnot [ValueType]) { Fail "Invalid threshold value $($threshold.id)" }
    }
    $fingerprints = @{}
    foreach ($rule in $catalog.rules) {
        Ref $domains $rule.domain "rule $($rule.id)"
        if ($rule.id -notmatch ('^' + [regex]::Escape($rule.domain) + '-\d{3}$')) { Fail "Invalid rule ID $($rule.id)" }
        if ($rule.alias_of) {
            Ref $rules $rule.alias_of "alias $($rule.id)"
            if ($rule.alias_of -eq $rule.id -or $rules[$rule.alias_of].alias_of) { Fail "Cyclic/chained alias $($rule.id)" }
            continue
        }
        Fields $rule @('name','diagnostic_class','hypothesis','oracle_versions','scope','observations','required_evidence','optional_evidence','derived_metrics','prerequisites','decision','decision_binding','counter_tests','supporting_tests','confidence_policy','conclusion','roles','recommendation','safety_risk','causal_parents','causal_children','reinforcing_hypotheses','contradictory_hypotheses','licensing_requirements','cross_module_requests','references') "rule $($rule.id)"
        if ($rule.diagnostic_class -notin @('observation','derived_fact','symptom','optimization_opportunity','candidate_contributor','supported_cause','unresolved_hypothesis','no_material_degradation')) { Fail "Invalid class $($rule.id)" }
        if ($rule.confidence_policy -ne $catalog.confidence_policy.id) { Fail "Undefined confidence policy $($rule.id)" }
        if ($rule.safety_risk -notin @('low','moderate','high')) { Fail "Invalid safety risk $($rule.id)" }
        foreach ($id in @($rule.required_evidence) + @($rule.optional_evidence)) { Ref $script:evidence $id "rule evidence $($rule.id)" }
        foreach ($id in $rule.derived_metrics) { Ref $script:metrics $id "rule metric $($rule.id)" }
        foreach ($id in @($rule.causal_parents) + @($rule.causal_children) + @($rule.reinforcing_hypotheses) + @($rule.contradictory_hypotheses)) { Ref $rules $id "rule relationship $($rule.id)" }
        foreach ($id in $rule.cross_module_requests) { Ref $requests $id "module request $($rule.id)" }
        Expression $rule.decision "rule decision $($rule.id)"
        foreach ($test in @($rule.counter_tests) + @($rule.supporting_tests)) { Expression $test.test "rule test $($rule.id)" }
        if (@($rule.counter_tests).Count -eq 0) { Fail "Missing counter-evidence $($rule.id)" }
        foreach ($role in $rule.roles) {
            if ($catalog.contract.roles -notcontains $role.role) { Fail "Invalid role $($rule.id)" }
            if ($role.test) { Expression $role.test "role test $($rule.id)" }
        }
        Fields $rule.recommendation @('evidence_bindings','next_test','expected_result','validation','safety','rollback','withhold') "recommendation $($rule.id)"
        foreach ($id in $rule.recommendation.evidence_bindings) { Ref $script:metrics $id "recommendation evidence $($rule.id)" }
        $fingerprint = $rule.decision | ConvertTo-Json -Depth 100 -Compress
        if ($fingerprints.ContainsKey($fingerprint)) { Fail "Duplicate decisions $($rule.id) and $($fingerprints[$fingerprint])" } else { $fingerprints[$fingerprint] = $rule.id }
    }
    $graph = @{}
    foreach ($id in $rules.Keys) { $graph[$id] = @() }
    foreach ($edge in $catalog.causal_edges) {
        Fields $edge @('parent','child','mechanism','scope','required_evidence','test','temporal','status','counter_test','missing') "edge $($edge.id)"
        Ref $rules $edge.parent "edge $($edge.id)"
        Ref $rules $edge.child "edge $($edge.id)"
        foreach ($id in $edge.required_evidence) { Ref $script:evidence $id "edge evidence $($edge.id)" }
        Expression $edge.test "edge test $($edge.id)"
        Expression $edge.counter_test.test "edge counter $($edge.id)"
        $graph[$edge.parent] += $edge.child
        if ($rules.ContainsKey($edge.parent) -and $rules[$edge.parent].causal_children -notcontains $edge.child) { Fail "Edge child list mismatch $($edge.id)" }
        if ($rules.ContainsKey($edge.child) -and $rules[$edge.child].causal_parents -notcontains $edge.parent) { Fail "Edge parent list mismatch $($edge.id)" }
    }
    $colors = @{}
    foreach ($id in $graph.Keys) { Visit $id $graph $colors 'causal' }
    foreach ($request in $catalog.cross_module_requests) {
        Fields $request @('owner','purpose','evidence_ids','request_keys','response','unavailable','production_execution') "request $($request.id)"
        foreach ($id in $request.evidence_ids) { Ref $script:evidence $id "request $($request.id)" }
    }
    foreach ($case in $catalog.acceptance_cases) {
        if (@($case.facts).Count -eq 0 -or @($case.negative_perturbations).Count -eq 0) { Fail "Incomplete acceptance $($case.id)" }
        foreach ($fact in $case.facts) {
            Fields $fact @('fact','evidence','metrics','rules','causal_edges','expected') "acceptance $($case.id)"
            foreach ($id in $fact.evidence) { Ref $script:evidence $id "acceptance evidence $($case.id)" }
            foreach ($id in $fact.metrics) { Ref $script:metrics $id "acceptance metric $($case.id)" }
            foreach ($id in $fact.rules) { Ref $rules $id "acceptance rule $($case.id)" }
            foreach ($id in $fact.causal_edges) { Ref $edges $id "acceptance edge $($case.id)" }
        }
    }
    foreach ($gate in $catalog.hypothesis_gates.PSObject.Properties) { if ($gate.Value.test) { Expression $gate.Value.test "gate $($gate.Name)" } }
    Ref $rules $catalog.outcomes.healthy_rule 'healthy outcome'
    $repoRoot = Split-Path -Parent (Split-Path -Parent $resolved)
    $baselinePath = Join-Path $repoRoot $catalog.baseline.path
    if (-not $SkipBaselineHash) {
        if (-not (Test-Path -LiteralPath $baselinePath)) { Fail 'V2 baseline missing' }
        elseif ((Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $catalog.baseline.sha256) { Fail 'V2 baseline hash changed' }
    }
    if (Test-Path -LiteralPath $baselinePath) {
        $raw = Get-Content -LiteralPath $baselinePath -Raw
        $oldIds = [regex]::Matches($raw, '(?m)^  - id: ([A-Z]+-\d{3})') | ForEach-Object { $_.Groups[1].Value }
        if (@($oldIds).Count -ne $catalog.baseline.rule_count) { Fail 'Baseline rule count mismatch' }
        foreach ($id in $oldIds) { Ref $rules $id 'V2 ID preservation' }
    }
    if ($script:issues.Count) { foreach ($issue in $script:issues) { Write-Output "ERROR: $issue" }; exit 1 }
    Write-Output "PASS: $($rules.Count) IDs, $(@($catalog.rules | Where-Object { -not $_.alias_of }).Count) canonical rules, $($domains.Count) domains, $($sources.Count) sources, $($script:metrics.Count) metrics, $($edges.Count) acyclic causal edges; V2 preserved."
    Write-Output 'Specification validation only; Oracle collection and diagnostic decisions were not executed.'
    exit 0
} catch { Write-Output "ERROR: $($_.Exception.Message)"; exit 1 }
