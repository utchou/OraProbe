param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot '..\knowledge\sql_tuning_catalog_v3_2.yaml'),
    [switch]$SkipBaselineHash,
    [switch]$SkipPredecessorHash,
    [string]$SourceManifestPath,
    # Default: 3.1 uses knowledge\threshold_profiles; 3.2+ uses contract.threshold_profile_policy.profile_location.
    [string]$ThresholdProfileDir
)
$ErrorActionPreference = 'Stop'
$script:issues = [System.Collections.Generic.List[string]]::new()
$script:notes = [System.Collections.Generic.List[string]]::new()
function Fail([string]$message) { $script:issues.Add($message) }
function Names($object) { if ($null -eq $object) { return ,@() }; return ,@($object.PSObject.Properties | ForEach-Object { $_.Name }) }
function Fields($object, [string[]]$names, [string]$context) {
    foreach ($name in $names) {
        if ($null -eq $object -or (Names $object) -notcontains $name) { Fail "$context missing $name" }
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
    $keys = Names $node
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
        $okeys = Names $operand
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
function CollectMetrics($node, [System.Collections.Generic.List[string]]$found) {
    if ($null -eq $node) { return }
    $keys = Names $node
    if ($keys.Count -eq 1 -and ($keys[0] -in @('all','any'))) { foreach ($c in $node.($keys[0])) { CollectMetrics $c $found }; return }
    if ($keys.Count -eq 1 -and $keys[0] -eq 'not') { CollectMetrics $node.not $found; return }
    foreach ($o in @($node.left, $node.right)) { if ($o -and $o.metric) { $found.Add([string]$o.metric) } }
}
function MetricsIn($node) {
    $found = [System.Collections.Generic.List[string]]::new()
    CollectMetrics $node $found
    # Unrolled on purpose: callers wrap with @() or iterate.
    return $found.ToArray()
}
function IsTrial([string]$metricId) { return $script:metrics.ContainsKey($metricId) -and $script:metrics[$metricId].operator -eq 'trial_ratio' }
function Visit([string]$id, [hashtable]$graph, [hashtable]$colors, [string]$context) {
    if ($colors[$id] -eq 1) { Fail "$context cycle at $id"; return }
    if ($colors[$id] -eq 2) { return }
    $colors[$id] = 1
    foreach ($next in @($graph[$id])) { if ($next) { Visit $next $graph $colors $context } }
    $colors[$id] = 2
}
try {
    $resolved = (Resolve-Path -LiteralPath $CatalogPath).Path
    $repoRoot = Split-Path -Parent (Split-Path -Parent $resolved)
    # JSON is an intentional YAML 1.2 subset: standard-library offline parsing.
    $catalog = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    $version = [string]$catalog.catalog_version
    if ($version -notin @('3.0', '3.1', '3.2')) { Fail "Unsupported catalog version $version"; throw 'Unsupported catalog version' }
    # 3.2 is a superset of 3.1: every 3.1 invariant (P1-P8) still applies.
    $isV31 = $version -in @('3.1', '3.2')
    $isV32 = $version -eq '3.2'
    $required = @('catalog_version','baseline','taxonomy','contract','operators','sources','evidence','metrics','thresholds','rules','causal_edges','confidence_policy','cross_module_requests','acceptance_cases','outcomes','hypothesis_gates','feature_requirements')
    if ($isV31) { $required += @('predecessor','source_manifest','change_log','plan_predicate_patterns') }
    if ($isV32) { $required += @('lab_verification_registry','backlog') }
    Fields $catalog $required 'catalog'
    if (-not $SourceManifestPath) {
        $SourceManifestPath = if ($isV31) { Join-Path $repoRoot $catalog.source_manifest.path } else { Join-Path $repoRoot 'knowledge\sql_tuning_sources_19c.json' }
    }
    if (-not $ThresholdProfileDir) {
        $ThresholdProfileDir = if ($isV32) { Join-Path $repoRoot $catalog.contract.threshold_profile_policy.profile_location } else { Join-Path $repoRoot 'knowledge\threshold_profiles' }
    }
    $registry = @{}; $boundKinds = @(); $modules = @(); $providers = @{}
    if ($isV32) {
        $registry = Index $catalog.lab_verification_registry 'id' 'lab verification registry'
        # Names already returns a protected array; wrapping in @() would nest it.
        $boundKinds = Names $catalog.contract.bound_policy.bound_kinds
        $modules = @($catalog.contract.knowledge_ownership_policy.modules)
        $providers = Index $catalog.contract.provider_policy.providers 'id' 'providers'
    }
    function LvRefs($refs, [string[]]$columns, [string]$context) {
        foreach ($lv in @($refs)) {
            if ($null -eq $lv) { continue }
            Ref $script:registryRef $lv.item $context
            if ($columns -and $columns -notcontains $lv.column) { Fail "$context lab verification column $($lv.column) not collected" }
        }
    }
    $script:registryRef = $registry
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
        if ($isV31 -and $source.id -match '^DBA_HIST_' -and $catalog.feature_requirements.awr_exceptions -notcontains $source.id -and $source.licensing.requires_all -notcontains 'diagnostics_pack') { Fail "Diagnostics gate missing $($source.id)" }
        if ($isV31 -and $source.id -match '^DBA_HIST_REPORTS' -and $source.licensing.requires_all -notcontains 'tuning_pack') { Fail "SQL Monitor report tuning gate missing $($source.id)" }
        foreach ($fallback in $source.fallbacks) { Ref $sources $fallback "source fallback $($source.id)" }
        if ($source.rac_name -and $source.rac_name -ne $source.name.Replace('V$','GV$')) { Fail "Invalid RAC equivalent $($source.id)" }
        if ($isV32) {
            # V32-04: collect once — every source belongs to exactly one provider.
            Ref $providers $source.provider "source provider $($source.id)"
            $owning = @($catalog.contract.provider_policy.providers | Where-Object { @($_.sources) -contains $source.id })
            if ($owning.Count -ne 1) { Fail "V32-04: source $($source.id) assigned to $($owning.Count) providers" }
            elseif ($owning[0].id -ne $source.provider) { Fail "V32-04: source $($source.id) provider mismatch" }
            LvRefs $source.lab_verification_required @($source.columns) "source $($source.id)"
        }
    }
    if ($isV32) {
        foreach ($p in $catalog.contract.provider_policy.providers) {
            Fields $p @('scope','owner','available_in_demo','sources','evidence_ids','emits','holds_rules_or_thresholds') "provider $($p.id)"
            if ($p.holds_rules_or_thresholds -ne $false) { Fail "V32-04: provider $($p.id) must not hold rules or thresholds" }
            if ($p.owner -ne 'shared_core' -and $modules -notcontains $p.owner) { Fail "Invalid provider owner $($p.id)" }
            foreach ($s in $p.sources) { Ref $sources $s "provider $($p.id)" }
        }
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
            if ($isV32) { LvRefs $binding.lab_verification_required @($binding.columns) "binding $($item.id)/$($binding.source_id)" }
        }
    }
    $metricGraph = @{}
    foreach ($metric in $catalog.metrics) {
        Fields $metric @('operator','inputs','unit','parameters','group_by','null_zero_policy','quality') "metric $($metric.id)"
        if ((Names $catalog.operators) -notcontains $metric.operator) { Fail "Undefined metric operator $($metric.operator)" }
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
        if ($isV31 -and $metric.operator -eq 'plan_predicate_pattern_count') {
            $set = [string]$metric.parameters.pattern_set
            if ((Names $catalog.plan_predicate_patterns) -notcontains $set -or @($catalog.plan_predicate_patterns.$set).Count -eq 0) { Fail "Undefined predicate pattern set $($metric.id).$set" }
            if ($metric.parameters.classification -notin $catalog.contract.predicate_pattern_policy.classifications) { Fail "Invalid predicate classification $($metric.id)" }
        }
        if ($isV32) {
            # V32-03: every metric declares which bound kinds it may be compared with.
            $accepts = @($metric.value_semantics.accepts | Where-Object { $_ })
            if ($accepts.Count -eq 0) { Fail "V32-03: metric $($metric.id) lacks value_semantics.accepts" }
            foreach ($k in $accepts) { if ($boundKinds -notcontains $k) { Fail "V32-03: metric $($metric.id) accepts unknown bound kind $k" } }
            if ($accepts -contains 'incomplete_unknown') { Fail "V32-03: metric $($metric.id) cannot accept incomplete_unknown" }
            foreach ($lv in @($metric.lab_verification_required)) { if ($lv) { Ref $registry $lv "metric $($metric.id) lab verification" } }
        }
    }
    $colors = @{}
    foreach ($id in $metricGraph.Keys) { Visit $id $metricGraph $colors 'metric dependency' }
    foreach ($threshold in $catalog.thresholds) {
        Fields $threshold @('type','unit','value','configuration','oracle_universal') "threshold $($threshold.id)"
        if ($threshold.type -notin @('absolute','ratio','percentage','baseline_relative','historical_deviation','peer_comparison','per_execution','concurrency_adjusted','workload_specific','configurable','evidence_pattern')) { Fail "Invalid threshold type $($threshold.id)" }
        if ($null -ne $threshold.value -and $threshold.value -isnot [ValueType]) { Fail "Invalid threshold value $($threshold.id)" }
        if ($isV31 -and $null -ne $threshold.value) { Fail "P8: catalog threshold must remain null $($threshold.id)" }
    }
    $ruleFieldsV32 = @('knowledge_owner','consumers')

    # ------------------------------------------------------------ rules
    $classes = if ($isV31) { @($catalog.contract.conclusions) } else { @('observation','derived_fact','symptom','optimization_opportunity','candidate_contributor','supported_cause','unresolved_hypothesis','no_material_degradation') }
    $ruleFields = @('name','diagnostic_class','hypothesis','oracle_versions','scope','observations','optional_evidence','derived_metrics','prerequisites','decision_binding','counter_tests','supporting_tests','confidence_policy','conclusion','roles','recommendation','safety_risk','causal_parents','causal_children','reinforcing_hypotheses','contradictory_hypotheses','licensing_requirements','cross_module_requests','references')
    $ruleFields += if ($isV31) { @('lab_only','stages') } else { @('required_evidence','decision') }
    if ($isV32) { $ruleFields += $ruleFieldsV32 }
    $fingerprints = @{}; $detectionPrints = @{}; $sharedDetections = 0; $labOnly = 0; $stageCounts = @{ detection = 0; attribution = 0; validation = 0 }
    foreach ($rule in $catalog.rules) {
        Ref $domains $rule.domain "rule $($rule.id)"
        if ($rule.id -notmatch ('^' + [regex]::Escape($rule.domain) + '-\d{3}$')) { Fail "Invalid rule ID $($rule.id)" }
        if ($rule.alias_of) {
            Ref $rules $rule.alias_of "alias $($rule.id)"
            if ($rule.alias_of -eq $rule.id -or $rules[$rule.alias_of].alias_of) { Fail "Cyclic/chained alias $($rule.id)" }
            continue
        }
        Fields $rule $ruleFields "rule $($rule.id)"
        if ($isV32) {
            # V32-04: one canonical owner per rule; consumers read evaluated facts directly.
            if ($modules -notcontains $rule.knowledge_owner) { Fail "V32-04: invalid knowledge_owner $($rule.id)" }
            if ($rule.consumers -isnot [System.Array]) { Fail "V32-04: consumers must be a list $($rule.id)" }
            if (@($rule.consumers).Count -eq 0) { Fail "V32-04: no consumers $($rule.id)" }
            foreach ($m in @($rule.consumers)) { if ($modules -notcontains $m) { Fail "V32-04: invalid consumer $m in $($rule.id)" } }
            if ($rule.domain -eq 'RM' -and ($rule.knowledge_owner -ne 'database_health' -or @($rule.consumers) -notcontains 'query_tuner')) { Fail "V32-04: RM rule $($rule.id) must be owned by database_health and consumable by query_tuner" }
        }
        if ($rule.diagnostic_class -notin $classes) { Fail "Invalid class $($rule.id)" }
        if ($rule.confidence_policy -ne $catalog.confidence_policy.id) { Fail "Undefined confidence policy $($rule.id)" }
        if ($rule.safety_risk -notin @('low','moderate','high')) { Fail "Invalid safety risk $($rule.id)" }
        foreach ($id in $rule.optional_evidence) { Ref $script:evidence $id "rule evidence $($rule.id)" }
        foreach ($id in $rule.derived_metrics) { Ref $script:metrics $id "rule metric $($rule.id)" }
        foreach ($id in @($rule.causal_parents) + @($rule.causal_children) + @($rule.reinforcing_hypotheses) + @($rule.contradictory_hypotheses)) { Ref $rules $id "rule relationship $($rule.id)" }
        foreach ($id in $rule.cross_module_requests) { Ref $requests $id "module request $($rule.id)" }
        foreach ($test in @($rule.counter_tests) + @($rule.supporting_tests)) { Expression $test.test "rule test $($rule.id)" }
        if (@($rule.counter_tests).Count -eq 0) { Fail "Missing counter-evidence $($rule.id)" }
        foreach ($role in $rule.roles) {
            if ($catalog.contract.roles -notcontains $role.role) { Fail "Invalid role $($rule.id)" }
            if ($role.test) { Expression $role.test "role test $($rule.id)" }
        }
        Fields $rule.recommendation @('evidence_bindings','next_test','expected_result','validation','safety','rollback','withhold') "recommendation $($rule.id)"
        foreach ($id in $rule.recommendation.evidence_bindings) { Ref $script:metrics $id "recommendation evidence $($rule.id)" }
        if (-not $isV31) {
            foreach ($id in @($rule.required_evidence)) { Ref $script:evidence $id "rule evidence $($rule.id)" }
            Expression $rule.decision "rule decision $($rule.id)"
            $fingerprint = $rule.decision | ConvertTo-Json -Depth 100 -Compress
            if ($fingerprints.ContainsKey($fingerprint)) { Fail "Duplicate decisions $($rule.id) and $($fingerprints[$fingerprint])" } else { $fingerprints[$fingerprint] = $rule.id }
            continue
        }
        # ---- V3.1 stage contract (P1)
        $stages = $rule.stages
        Fields $stages @('detection','attribution','validation') "stages $($rule.id)"
        $used = [System.Collections.Generic.List[string]]::new()
        if ($rule.lab_only) {
            $labOnly++
            if ($null -ne $stages.detection) { Fail "Lab-only rule has detection $($rule.id)" }
            if ($null -eq $stages.validation) { Fail "Lab-only rule lacks validation $($rule.id)" }
        } elseif ($null -eq $stages.detection) { Fail "Missing detection stage $($rule.id)" }
        foreach ($stageName in @('detection','attribution','validation')) {
            $stage = $stages.$stageName
            if ($null -eq $stage) { continue }
            $stageCounts[$stageName]++
            $ctx = "stage $($rule.id).$stageName"
            $exprField = if ($stageName -eq 'detection') { 'decision' } else { 'test' }
            Fields $stage @('evidence','optional_evidence',$exprField,'conclusion','meaning') $ctx
            if (@($stage.evidence).Count -eq 0) { Fail "$ctx has no required evidence" }
            foreach ($id in @($stage.evidence) + @($stage.optional_evidence)) { Ref $script:evidence $id $ctx }
            if ($stage.conclusion -notin $classes) { Fail "$ctx invalid conclusion $($stage.conclusion)" }
            if ($stage.conclusion -eq 'supported_cause') { Fail "$ctx stage cannot conclude supported_cause; causal gates required" }
            Expression $stage.$exprField $ctx
            $stageMetrics = @(MetricsIn $stage.$exprField)
            if ($stageName -eq 'validation') {
                Fields $stage @('disconfirm_test','validates','when_missing') $ctx
                Expression $stage.disconfirm_test $ctx
                $stageMetrics += @(MetricsIn $stage.disconfirm_test)
                if ($stage.validates -notin @('mechanism','remediation_gain')) { Fail "$ctx invalid validates" }
                if (@($stage.evidence) -notcontains 'trials') { Fail "$ctx validation without trials evidence" }
            } else {
                foreach ($m in $stageMetrics) { if (IsTrial $m) { Fail "P1: trial metric $m outside validation in $ctx" } }
                if (@($stage.evidence) -contains 'trials') { Fail "P1: trials evidence outside validation in $ctx" }
            }
            if ($stageName -eq 'attribution') {
                Fields $stage @('binds_to','when_unknown') $ctx
                foreach ($ct in @($stage.classification_tests)) { if ($ct) { Expression $ct.test "$ctx classification"; $stageMetrics += @(MetricsIn $ct.test) } }
            }
            foreach ($m in $stageMetrics) { $used.Add($m) }
        }
        foreach ($t in @($rule.counter_tests) + @($rule.supporting_tests)) {
            if ($t.stage -notin @('detection','attribution','validation')) { Fail "Test without valid stage in $($rule.id)" }
            foreach ($m in (MetricsIn $t.test)) { $used.Add($m); if ((IsTrial $m) -and $t.stage -ne 'validation') { Fail "P1: trial metric $m in non-validation test $($rule.id)" } }
        }
        foreach ($m in $used) { if (@($rule.derived_metrics) -notcontains $m) { Fail "Stage metric $m not declared in derived_metrics $($rule.id)" } }
        foreach ($pc in @($rule.preconditions)) {
            if ($null -eq $pc) { continue }
            switch ($pc.kind) {
                'metric_status' { Ref $script:metrics $pc.metric "precondition $($rule.id)" }
                'rule_outcome' { Ref $rules $pc.rule "precondition $($rule.id)" }
                default { Fail "Invalid precondition kind $($rule.id)" }
            }
        }
        $dPrint = if ($stages.detection) { $stages.detection.decision | ConvertTo-Json -Depth 100 -Compress } else { 'lab' }
        $aPrint = if ($stages.attribution) { $stages.attribution.test | ConvertTo-Json -Depth 100 -Compress } else { '-' }
        $vPrint = if ($stages.validation) { $stages.validation.test | ConvertTo-Json -Depth 100 -Compress } else { '-' }
        $fingerprint = "$dPrint|$aPrint|$vPrint"
        if ($fingerprints.ContainsKey($fingerprint)) { Fail "Duplicate staged decisions $($rule.id) and $($fingerprints[$fingerprint])" } else { $fingerprints[$fingerprint] = $rule.id }
        if ($stages.detection) {
            if ($detectionPrints.ContainsKey($dPrint)) { $sharedDetections++; $script:notes.Add("shared detection $($rule.id) = $($detectionPrints[$dPrint])") } else { $detectionPrints[$dPrint] = $rule.id }
        }
    }

    # ------------------------------------------------------------ causal edges
    $graph = @{}
    foreach ($id in $rules.Keys) { $graph[$id] = @() }
    foreach ($edge in $catalog.causal_edges) {
        $edgeFields = if ($isV31) { @('parent','child','mechanism','scope','required_evidence','attribution_test','validation_evidence','validation_test','temporal','status','counter_test','missing') } else { @('parent','child','mechanism','scope','required_evidence','test','temporal','status','counter_test','missing') }
        Fields $edge $edgeFields "edge $($edge.id)"
        Ref $rules $edge.parent "edge $($edge.id)"
        Ref $rules $edge.child "edge $($edge.id)"
        foreach ($id in @($edge.required_evidence) + @($edge.validation_evidence)) { if ($id) { Ref $script:evidence $id "edge evidence $($edge.id)" } }
        if ($isV31) {
            Expression $edge.attribution_test "edge test $($edge.id)"
            foreach ($m in (MetricsIn $edge.attribution_test)) { if (IsTrial $m) { Fail "P1: trial metric $m in edge attribution $($edge.id)" } }
            if (@($edge.required_evidence) -contains 'trials') { Fail "P1: trials in edge required evidence $($edge.id)" }
            if ($null -ne $edge.validation_test) {
                Expression $edge.validation_test "edge validation $($edge.id)"
                Expression $edge.validation_disconfirm_test "edge validation $($edge.id)"
                if (@($edge.validation_evidence) -notcontains 'trials') { Fail "Edge validation without trials evidence $($edge.id)" }
            }
        } else { Expression $edge.test "edge test $($edge.id)" }
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
        if ($isV32) {
            Fields $request @('provider_fulfillment','owner_module_required','consumption') "request $($request.id)"
            foreach ($f in @($request.provider_fulfillment)) {
                if ($null -eq $f) { continue }
                Ref $providers $f.provider "request fulfilment $($request.id)"
                if ($f.coverage -notin @('full_for_listed_evidence','partial')) { Fail "Invalid fulfilment coverage $($request.id)" }
                foreach ($id in @($f.evidence_ids)) {
                    Ref $script:evidence $id "request fulfilment $($request.id)"
                    if ($providers.ContainsKey($f.provider) -and @($providers[$f.provider].evidence_ids) -notcontains $id) { Fail "V32-04: provider $($f.provider) does not serve $id for $($request.id)" }
                }
            }
        }
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

    # ------------------------------------------------------------ V3.1 contract, predecessor and profiles
    $profileCount = 0
    if ($isV31) {
        Fields $catalog.contract @('evidence_stages','stage_policy','monitor_policy','historical_execution_policy','predicate_pattern_policy','awr_plan_policy','database_side_policy','capability_policy','threshold_profile_policy','unknown_reasons') 'contract'
        Fields $catalog.contract.evidence_stages @('detection','attribution','validation') 'contract.evidence_stages'
        if ($catalog.contract.conclusions -notcontains 'no_material_database_side_degradation') { Fail 'P6 conclusion class missing' }
        $p6 = 'No material database-side degradation detected in the investigated evidence/window; end-to-end application/network/client response time was not evaluated.'
        if ($catalog.contract.database_side_policy.conclusion_text -ne $p6) { Fail 'P6 conclusion wording changed' }
        Ref $rules $catalog.outcomes.database_side_rule 'database-side outcome'
        if ($rules.ContainsKey('HEALTH-002') -and @($rules['HEALTH-002'].preconditions).Count -lt 2) { Fail 'HEALTH-002 preconditions missing' }
        if (-not $script:evidence.ContainsKey('capability')) { Fail 'P7 capability evidence missing' }
        if (@($catalog.contract.capability_policy.items).Count -eq 0) { Fail 'P7 capability items missing' }
        if ($script:evidence.ContainsKey('executions') -and $script:evidence['executions'].fields.name -notcontains 'estimate_kind') { Fail 'P3 estimate_kind missing on executions' }
        if ($script:evidence.ContainsKey('plan') -and $script:evidence['plan'].fields.name -notcontains 'actuals_source') { Fail 'P2 actuals_source missing on plan' }
        if (@($script:evidence['plan'].bindings | Where-Object { $_.source_id -eq 'V$SQL_PLAN_STATISTICS_ALL' }).Count -eq 0) { Fail 'P2: V$SQL_PLAN_STATISTICS_ALL binding must be retained' }
        if (-not $SkipPredecessorHash) {
            # Walk the whole predecessor chain (3.2 -> 3.1 -> 3.0) so every frozen checkpoint is verified.
            $link = $catalog; $chain = 0
            while ($link.predecessor -and $chain -lt 5) {
                $chain++
                $predPath = Join-Path $repoRoot $link.predecessor.path
                $label = "predecessor $($link.predecessor.version)"
                if (-not (Test-Path -LiteralPath $predPath)) { Fail "$label missing"; break }
                if ((Get-FileHash -LiteralPath $predPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $link.predecessor.sha256) { Fail "$label hash changed"; break }
                if ($link.source_manifest) {
                    $predManifest = Join-Path $repoRoot $link.source_manifest.predecessor_path
                    if ((Get-FileHash -LiteralPath $predManifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $link.source_manifest.predecessor_sha256) { Fail "$label source manifest hash changed" }
                }
                $pred = Get-Content -LiteralPath $predPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($r in $pred.rules) { Ref $rules $r.id "$label ID preservation" }
                foreach ($m in $pred.metrics) { Ref $script:metrics $m.id "$label metric preservation" }
                if ($chain -eq 1 -and $isV32) {
                    # Thresholds: same IDs and units as the predecessor, all null.
                    $predThresholds = Index $pred.thresholds 'id' 'predecessor thresholds'
                    if ($predThresholds.Count -ne $script:thresholds.Count) { Fail "Threshold count changed ($($predThresholds.Count) -> $($script:thresholds.Count))" }
                    foreach ($k in $predThresholds.Keys) {
                        if (-not $script:thresholds.ContainsKey($k)) { Fail "Threshold removed $k" }
                        elseif ($predThresholds[$k].unit -ne $script:thresholds[$k].unit) { Fail "Threshold unit changed $k" }
                    }
                }
                $link = $pred
            }
        }
        if ($isV32) {
            Fields $catalog.contract @('family_policy','normalizer_policy','bound_policy','evidence_flow_policy','knowledge_ownership_policy','provider_policy','capture_bias_policy','family_coverage_policy','historical_resource_manager_policy','historical_temp_concurrency_policy','host_cpu_policy','lab_verification_policy','dependency_evidence_policy') 'contract'
            foreach ($k in @('exact','lower_bound','upper_bound','sampled_estimate','incomplete_unknown')) { if ($boundKinds -notcontains $k) { Fail "V32-03: bound kind $k missing" } }
            foreach ($k in @('lower_bound','upper_bound','bound_kind','family_tier')) { if ($catalog.contract.evidence_envelope -notcontains $k) { Fail "V32-03: envelope missing $k" } }
            foreach ($k in @('not_captured','lab_verification_required')) { if ($catalog.contract.statuses -notcontains $k) { Fail "Status $k missing" } }
            foreach ($k in @('C','F1','F2','F3')) { if ((Names $catalog.contract.family_policy.tiers) -notcontains $k) { Fail "V32-01: family tier $k missing" } }
            if ($catalog.contract.evidence_flow_policy.principle -ne 'COLLECT ONCE -> NORMALIZE ONCE -> DEFINE CANONICAL FACT/HYPOTHESIS ONCE -> ALLOW MULTIPLE DIAGNOSTIC MODULES TO CONSUME IT.') { Fail 'V32-04: evidence flow principle changed' }
            if (-not $script:evidence.ContainsKey('sql_template')) { Fail 'V32-02: sql_template evidence missing' }
            # Lab verification registry: the seven open Oracle facts, fully specified.
            $expectedLv = @('LV-01','LV-02','LV-03','LV-04','LV-05','LV-06','LV-07')
            foreach ($id in $expectedLv) { if (-not $registry.ContainsKey($id)) { Fail "Lab verification item $id missing" } }
            foreach ($lv in $catalog.lab_verification_registry) {
                Fields $lv @('status','blocks_production_use','question','affected','documentation_gap','lab_test','consequence_if_unresolved') "lab verification $($lv.id)"
                if ($lv.blocks_production_use -isnot [bool]) { Fail "lab verification $($lv.id) blocks_production_use must be boolean" }
                foreach ($s in @($lv.affected.sources)) { if ($s) { Ref $sources $s "lab verification $($lv.id)" } }
                foreach ($m in @($lv.affected.metrics)) { if ($m) { Ref $script:metrics $m "lab verification $($lv.id)" } }
                foreach ($r in @($lv.affected.rules)) { if ($r) { Ref $rules $r "lab verification $($lv.id)" } }
            }
            # Proposal V32-10: graded dependency evidence with fixed limits.
            $dep = $catalog.contract.dependency_evidence_policy
            foreach ($g in @('D1','D2','D3','D4')) {
                $grade = $dep.grades.$g
                if ($null -eq $grade) { Fail "V32-10: dependency grade $g missing"; continue }
                Fields $grade @('name','requires','establishes','does_not_establish','counts_as_common_dependency','production_use','lab_verification') "dependency grade $g"
                if ($g -in @('D3','D4') -and $grade.counts_as_common_dependency -ne $false) { Fail "V32-10: dependency grade $g cannot count as common dependency" }
                foreach ($lv in @($grade.lab_verification)) {
                    if (-not $lv) { continue }
                    Ref $registry $lv "dependency grade $g"
                    if ($registry.ContainsKey($lv) -and $registry[$lv].status -eq 'open' -and $registry[$lv].blocks_production_use -and $grade.production_use -ne 'lab_verification_required') { Fail "V32-10: dependency grade $g must be lab_verification_required while $lv is open" }
                }
            }
            foreach ($k in @('semantic_family_equivalence','object_caused_degradation','identical_work_beneath_view','causation_from_common_reference')) { if ((Names $dep.cannot_establish) -notcontains $k) { Fail "V32-10: dependency limit $k missing" } }
            if ($dep.family_tier_effect -ne 'none') { Fail 'V32-10: dependency evidence must not affect family tier' }
            if ($script:metrics.ContainsKey('common_dependency_count') -and $script:metrics['common_dependency_count'].parameters.minimum_grade -notin @('D1','D2')) { Fail 'V32-10: common_dependency_count minimum grade must be D1 or D2' }
            if ($sources.ContainsKey('V$OBJECT_DEPENDENCY') -and $registry.ContainsKey('LV-03') -and $registry['LV-03'].status -eq 'open' -and @($sources['V$OBJECT_DEPENDENCY'].lab_verification_required | Where-Object { $_.item -eq 'LV-03' }).Count -eq 0) { Fail 'V32-10: V$OBJECT_DEPENDENCY must carry LV-03 while open' }
            foreach ($b in $catalog.backlog) {
                Fields $b @('origin','status','item','lab_verification','reason') "backlog $($b.id)"
                if ($b.status -ne 'deferred') { Fail "backlog $($b.id) must be deferred" }
                foreach ($lv in @($b.lab_verification)) { if ($lv) { Ref $registry $lv "backlog $($b.id)" } }
            }
        }
        # P8 threshold profiles live outside the catalog; validate every profile present.
        if (Test-Path -LiteralPath $ThresholdProfileDir) {
            foreach ($file in Get-ChildItem -LiteralPath $ThresholdProfileDir -Filter '*.json') {
                $profileCount++
                $ctx = "threshold profile $($file.Name)"
                $profileDoc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                Fields $profileDoc @($catalog.contract.threshold_profile_policy.profile_required_fields) $ctx
                if ($profileDoc.catalog_version -ne $version) { Fail "$ctx catalog version mismatch" }
                $keys = Names $profileDoc.values
                foreach ($k in $keys) { if (-not $script:thresholds.ContainsKey($k)) { Fail "$ctx unknown threshold $k" } }
                foreach ($k in $script:thresholds.Keys) { if ($keys -notcontains $k) { Fail "$ctx missing threshold $k" } }
                $configured = 0
                foreach ($k in $keys) {
                    $entry = $profileDoc.values.$k
                    if ($script:thresholds.ContainsKey($k) -and $entry.unit -ne $script:thresholds[$k].unit) { Fail "$ctx unit mismatch $k" }
                    if ($null -ne $entry.value) {
                        $configured++
                        if ($entry.value -isnot [ValueType] -or $entry.value -is [bool]) { Fail "$ctx non-numeric value $k" }
                        if ([string]::IsNullOrWhiteSpace([string]$entry.rationale)) { Fail "$ctx value without rationale $k" }
                    }
                }
                if ($configured -gt 0) {
                    foreach ($f in @('profile_id','profile_version','author','approved_by','approved_on')) { if ([string]::IsNullOrWhiteSpace([string]$profileDoc.$f)) { Fail "$ctx configured values without $f" } }
                }
            }
        }
    }

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
    $canonical = @($catalog.rules | Where-Object { -not $_.alias_of }).Count
    if ($isV31) {
        Write-Output "PASS ($version): $($rules.Count) IDs, $canonical canonical rules ($labOnly lab-only), $($domains.Count) domains, $($sources.Count) sources, $($script:metrics.Count) metrics, $($edges.Count) acyclic causal edges."
        Write-Output "Stages: $($stageCounts.detection) detection, $($stageCounts.attribution) attribution, $($stageCounts.validation) validation; $sharedDetections shared detection decisions (scored once); trial metrics confined to validation."
        Write-Output "Thresholds: $($script:thresholds.Count) defined, all null; $profileCount threshold profile file(s) validated. V2 baseline and predecessor chain preserved."
        if ($isV32) {
            $blocking = @($catalog.lab_verification_registry | Where-Object { $_.blocks_production_use }).Count
            Write-Output "V3.2: $($providers.Count) evidence providers own all $($sources.Count) sources once; every metric declares accepted bound kinds; $($registry.Count) lab-verification items ($blocking block production use); $(@($catalog.backlog).Count) deferred backlog items."
        }
    } else {
        Write-Output "PASS: $($rules.Count) IDs, $canonical canonical rules, $($domains.Count) domains, $($sources.Count) sources, $($script:metrics.Count) metrics, $($edges.Count) acyclic causal edges; V2 preserved."
    }
    foreach ($note in $script:notes) { Write-Output "INFO: $note" }
    Write-Output 'Specification validation only; Oracle collection and diagnostic decisions were not executed.'
    exit 0
} catch { Write-Output "ERROR: $($_.Exception.Message)"; exit 1 }
