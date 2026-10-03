<#
Negative regression tests for validate_sql_tuning_catalog.ps1.
Each case mutates a temporary copy of a catalog or threshold profile and asserts the
validator rejects it with the expected message. P1-P8 invariants run against both V3.1
and V3.2; V3.2-specific invariants (V32-01..V32-10, proposal V32-10 dependency grades, lab verification registry,
predecessor hash chain) run against V3.2. Unmodified V3, V3.1 and V3.2 must pass.
Knowledge-only; no database access.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate_sql_tuning_catalog.ps1'
$k = Join-Path $root 'knowledge'
$targets = @(
    [pscustomobject]@{ Version = '3.1'; Catalog = (Join-Path $k 'sql_tuning_catalog_v3_1.yaml'); Manifest = (Join-Path $k 'sql_tuning_sources_19c_v3_1.json'); Template = (Join-Path $k 'threshold_profiles\template.json') }
    [pscustomobject]@{ Version = '3.2'; Catalog = (Join-Path $k 'sql_tuning_catalog_v3_2.yaml'); Manifest = (Join-Path $k 'sql_tuning_sources_19c_v3_2.json'); Template = (Join-Path $k 'threshold_profiles\v3_2\template.json') }
)
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('oraprobe_validator_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$failures = 0

function Load([string]$path) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save($obj, [string]$path) { [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false)) }
function Rule($catalog, [string]$id) { $catalog.rules | Where-Object { $_.id -eq $id } }
function Invoke-Validator([hashtable]$arguments) {
    $out = & $validator @arguments
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}
function Run($target, [string]$catalogFile, [string]$profiles) {
    return Invoke-Validator @{ CatalogPath = $catalogFile; SourceManifestPath = $target.Manifest; ThresholdProfileDir = $profiles; SkipBaselineHash = $true; SkipPredecessorHash = $true }
}
function Expect-Pass([string]$name, $result) {
    if ($result.Code -eq 0) { Write-Output "ok   $name" } else { $script:failures++; Write-Output "FAIL $name (expected pass)`n$($result.Text)" }
}
function Expect-Fail([string]$name, $result, [string]$pattern) {
    if ($result.Code -ne 0 -and $result.Text -match $pattern) { Write-Output "ok   $name" }
    else { $script:failures++; Write-Output "FAIL $name (expected failure matching '$pattern'; exit $($result.Code))`n$($result.Text)" }
}
function Mutate($target, [string]$name, [string]$pattern, [scriptblock]$change) {
    $c = Load $target.Catalog
    & $change $c
    $file = Join-Path $work (($target.Version + '_' + ($name -replace '[^A-Za-z0-9]', '_')) + '.yaml')
    Save $c $file
    Expect-Fail "[$($target.Version)] $name" (Run $target $file $target.Profiles) $pattern
}

try {
    foreach ($t in $targets) {
        $dir = Join-Path $work ('profiles_' + $t.Version.Replace('.', '_')); New-Item -ItemType Directory -Path $dir | Out-Null
        Copy-Item -LiteralPath $t.Template -Destination (Join-Path $dir 'template.json')
        $t | Add-Member -NotePropertyName Profiles -NotePropertyValue $dir
    }
    Expect-Pass 'unmodified V3.2 catalog (default)' (Invoke-Validator @{})
    Expect-Pass 'unmodified V3.1 checkpoint' (Invoke-Validator @{ CatalogPath = $targets[0].Catalog })
    Expect-Pass 'unmodified V3 checkpoint' (Invoke-Validator @{ CatalogPath = (Join-Path $k 'sql_tuning_catalog_v3.yaml') })

    # ---------------------------------------------------------------- P1-P8 invariants on V3.1 and V3.2
    foreach ($t in $targets) {
        Mutate $t 'P1 trial metric in detection' 'P1: trial metric access_gain outside validation' {
            param($c) $r = Rule $c 'AP-001'; $r.stages.detection.decision = $r.stages.validation.test }
        Mutate $t 'P1 trials evidence in attribution' 'P1: trials evidence outside validation' {
            param($c) $r = Rule $c 'JOIN-001'; $r.stages.attribution.evidence = @('sql', 'trials') }
        Mutate $t 'P1 trial metric in edge attribution' 'P1: trial metric statistics_gain in edge attribution' {
            param($c) $e = $c.causal_edges | Where-Object { $_.id -eq 'CE-01' }; $e.attribution_test = $e.validation_test }
        Mutate $t 'P1 lab-only rule given detection' 'Lab-only rule has detection IDX-001' {
            param($c) $r = Rule $c 'IDX-001'; $r.stages.detection = (Rule $c 'AP-001').stages.detection }
        Mutate $t 'P1 missing detection stage' 'Missing detection stage CARD-005' {
            param($c) (Rule $c 'CARD-005').stages.detection = $null }
        Mutate $t 'P1 stage concluding supported_cause' 'cannot conclude supported_cause' {
            param($c) (Rule $c 'JOIN-001').stages.attribution.conclusion = 'supported_cause' }
        Mutate $t 'P1 undeclared stage metric' 'not declared in derived_metrics TEMP-003' {
            param($c) $r = Rule $c 'TEMP-003'; $r.derived_metrics = @($r.derived_metrics | Where-Object { $_ -ne 'max_workarea_passes' }) }
        Mutate $t 'P2 plan statistics binding removed' 'V\$SQL_PLAN_STATISTICS_ALL binding must be retained' {
            param($c) $e = $c.evidence | Where-Object { $_.id -eq 'plan' }; $e.bindings = @($e.bindings | Where-Object { $_.source_id -ne 'V$SQL_PLAN_STATISTICS_ALL' }) }
        Mutate $t 'P2 SQL Monitor tuning gate removed' 'Tuning gate missing V\$SQL_PLAN_MONITOR' {
            param($c) $s = $c.sources | Where-Object { $_.id -eq 'V$SQL_PLAN_MONITOR' }; $s.licensing.requires_all = @('diagnostics_pack') }
        Mutate $t 'P3 estimate_kind removed' 'P3 estimate_kind missing' {
            param($c) $e = $c.evidence | Where-Object { $_.id -eq 'executions' }; $e.fields = @($e.fields | Where-Object { $_.name -ne 'estimate_kind' }) }
        Mutate $t 'P3 AWR report tuning gate removed' 'SQL Monitor report tuning gate missing DBA_HIST_REPORTS' {
            param($c) $s = $c.sources | Where-Object { $_.id -eq 'DBA_HIST_REPORTS' }; $s.licensing.category = 'diagnostics_pack'; $s.licensing.requires_all = @('diagnostics_pack') }
        Mutate $t 'P4 undefined predicate pattern set' 'Undefined predicate pattern set' {
            param($c) ($c.metrics | Where-Object { $_.id -eq 'plan_conversion_candidates' }).parameters.pattern_set = 'no_such_set' }
        Mutate $t 'P6 wording changed' 'P6 conclusion wording changed' {
            param($c) $c.contract.database_side_policy.conclusion_text = 'Problem is outside the database.' }
        Mutate $t 'P6 preconditions removed' 'HEALTH-002 preconditions missing' {
            param($c) (Rule $c 'HEALTH-002').preconditions = @() }
        Mutate $t 'P7 capability evidence removed' 'P7 capability evidence missing' {
            param($c) $c.evidence = @($c.evidence | Where-Object { $_.id -ne 'capability' }) }
        Mutate $t 'P8 catalog threshold given a value' 'P8: catalog threshold must remain null material_deviation' {
            param($c) ($c.thresholds | Where-Object { $_.id -eq 'material_deviation' }).value = 1.5 }
        Mutate $t 'Unaudited Oracle column' 'Unaudited Oracle column V\$SQL_MONITOR.NOT_A_COLUMN' {
            param($c) $s = $c.sources | Where-Object { $_.id -eq 'V$SQL_MONITOR' }; $s.columns = @($s.columns) + @('NOT_A_COLUMN') }

        foreach ($case in @(
            @{ Name = 'P8 profile value without rationale or approval'; Pattern = 'value without rationale material_deviation'; Change = { param($p) $p.values.material_deviation.value = 2 } }
            @{ Name = 'P8 profile unit mismatch'; Pattern = 'unit mismatch material_deviation'; Change = { param($p) $p.values.material_deviation.unit = 'seconds' } }
            @{ Name = 'P8 profile missing threshold'; Pattern = 'missing threshold minimum_samples'; Change = { param($p) $p.values.PSObject.Properties.Remove('minimum_samples') } }
        )) {
            $p = Load $t.Template; & $case.Change $p
            $bad = Join-Path $work ('profile_' + $t.Version.Replace('.', '_') + '_' + ($case.Name -replace '[^A-Za-z0-9]', '_')); New-Item -ItemType Directory -Path $bad | Out-Null; Save $p (Join-Path $bad 'p.json')
            Expect-Fail "[$($t.Version)] $($case.Name)" (Run $t $t.Catalog $bad) $case.Pattern
        }
    }

    # ---------------------------------------------------------------- V3.2-specific invariants
    $v32 = $targets[1]
    Mutate $v32 'V32-01 family tier removed' 'V32-01: family tier F3 missing' {
        param($c) $c.contract.family_policy.tiers.PSObject.Properties.Remove('F3') }
    Mutate $v32 'V32-02 sql_template evidence removed' 'V32-02: sql_template evidence missing' {
        param($c) $c.evidence = @($c.evidence | Where-Object { $_.id -ne 'sql_template' }) }
    Mutate $v32 'V32-03 metric without accepted bound kinds' 'V32-03: metric rows_per_execution lacks value_semantics.accepts' {
        param($c) ($c.metrics | Where-Object { $_.id -eq 'rows_per_execution' }).PSObject.Properties.Remove('value_semantics') }
    Mutate $v32 'V32-03 metric accepting incomplete_unknown' 'V32-03: metric host_busy cannot accept incomplete_unknown' {
        param($c) $m = $c.metrics | Where-Object { $_.id -eq 'host_busy' }; $m.value_semantics.accepts = @($m.value_semantics.accepts) + @('incomplete_unknown') }
    Mutate $v32 'V32-03 required bound kind removed' 'V32-03: bound kind sampled_estimate missing' {
        param($c) $c.contract.bound_policy.bound_kinds.PSObject.Properties.Remove('sampled_estimate') }
    Mutate $v32 'V32-04 source owned by two providers' 'V32-04: source V\$SQL assigned to 2 providers' {
        param($c) $p = $c.contract.provider_policy.providers | Where-Object { $_.id -eq 'sql_history' }; $p.sources = @($p.sources) + @('V$SQL') }
    Mutate $v32 'V32-04 provider holding rules' 'V32-04: provider ash must not hold rules or thresholds' {
        param($c) ($c.contract.provider_policy.providers | Where-Object { $_.id -eq 'ash' }).holds_rules_or_thresholds = $true }
    Mutate $v32 'V32-04 RM rule owned by Query Tuner' 'V32-04: RM rule RM-002 must be owned by database_health' {
        param($c) (Rule $c 'RM-002').knowledge_owner = 'query_tuner' }
    Mutate $v32 'V32-04 duplicated RM rule inside Query Tuner' 'Duplicate staged decisions CUR-011 and RM-001' {
        param($c) $copy = (Rule $c 'RM-001') | ConvertTo-Json -Depth 100 | ConvertFrom-Json; $copy.id = 'CUR-011'; $copy.domain = 'CUR'; $copy.knowledge_owner = 'query_tuner'; $copy.consumers = @('query_tuner'); $c.rules = @($c.rules) + @($copy) }
    Mutate $v32 'V32-04 fulfilment from wrong provider' 'V32-04: provider oracle_host does not serve system for DB-RESOURCE' {
        param($c) $r = $c.cross_module_requests | Where-Object { $_.id -eq 'DB-RESOURCE' }; ($r.provider_fulfillment | Where-Object { $_.provider -eq 'instance_runtime' }).provider = 'oracle_host' }
    Mutate $v32 'V32-04 evidence flow principle changed' 'V32-04: evidence flow principle changed' {
        param($c) $c.contract.evidence_flow_policy.principle = 'Query Tuner collects what it needs.' }
    Mutate $v32 'LV registry item removed' 'Lab verification item LV-03 missing' {
        param($c) $c.lab_verification_registry = @($c.lab_verification_registry | Where-Object { $_.id -ne 'LV-03' }) }
    Mutate $v32 'LV registry item without lab test' 'lab verification LV-01 missing lab_test' {
        param($c) ($c.lab_verification_registry | Where-Object { $_.id -eq 'LV-01' }).PSObject.Properties.Remove('lab_test') }
    Mutate $v32 'LV reference to unknown item' 'undefined reference LV-99' {
        param($c) $e = $c.evidence | Where-Object { $_.id -eq ('r' + 'm') }; ($e.bindings | Where-Object { $_.source_id -eq 'DBA_HIST_RSRC_CONSUMER_GROUP' }).lab_verification_required[0].item = 'LV-99' }
    Mutate $v32 'LV column not collected' 'lab verification column NOT_COLLECTED not collected' {
        param($c) ($c.sources | Where-Object { $_.id -eq 'DBA_HIST_OSSTAT' }).lab_verification_required[0].column = 'NOT_COLLECTED' }
    Mutate $v32 'Backlog item not deferred' 'backlog BL-01 must be deferred' {
        param($c) ($c.backlog | Where-Object { $_.id -eq 'BL-01' }).status = 'accepted' }
    Mutate $v32 'not_captured status removed' 'Status not_captured missing' {
        param($c) $c.contract.statuses = @($c.contract.statuses | Where-Object { $_ -ne 'not_captured' }) }
    Mutate $v32 'V32-04 consumers serialized as a scalar' 'V32-04: consumers must be a list FAM-004' {
        param($c) (Rule $c 'FAM-004').consumers = 'query_tuner' }
    Mutate $v32 'V32-10 coincidence grade counted as dependency' 'V32-10: dependency grade D3 cannot count as common dependency' {
        param($c) $c.contract.dependency_evidence_policy.grades.D3.counts_as_common_dependency = $true }
    Mutate $v32 'V32-10 lab-gated grade used in production' 'V32-10: dependency grade D1 must be lab_verification_required while LV-03 is open' {
        param($c) $c.contract.dependency_evidence_policy.grades.D1.production_use = 'allowed' }
    Mutate $v32 'V32-10 causation limit removed' 'V32-10: dependency limit object_caused_degradation missing' {
        param($c) $c.contract.dependency_evidence_policy.cannot_establish.PSObject.Properties.Remove('object_caused_degradation') }
    Mutate $v32 'V32-10 dependency raising family tier' 'V32-10: dependency evidence must not affect family tier' {
        param($c) $c.contract.dependency_evidence_policy.family_tier_effect = 'corroborates_F2' }
    Mutate $v32 'V32-10 coincidence grade as FAM-004 minimum' 'V32-10: common_dependency_count minimum grade must be D1 or D2' {
        param($c) ($c.metrics | Where-Object { $_.id -eq 'common_dependency_count' }).parameters.minimum_grade = 'D3' }
    Mutate $v32 'V32-10 LV-03 gate removed from V$OBJECT_DEPENDENCY' 'V32-10: V\$OBJECT_DEPENDENCY must carry LV-03 while open' {
        param($c) ($c.sources | Where-Object { $_.id -eq 'V$OBJECT_DEPENDENCY' }).lab_verification_required = @() }

    # ---------------------------------------------------------------- predecessor chain on a mirrored repository
    $mirror = Join-Path $work 'repo'; $mk = Join-Path $mirror 'knowledge'; New-Item -ItemType Directory -Path $mk | Out-Null
    foreach ($f in @('sql_tuning_catalog.yaml', 'sql_tuning_catalog_v3.yaml', 'sql_tuning_catalog_v3_1.yaml', 'sql_tuning_catalog_v3_2.yaml', 'sql_tuning_sources_19c.json', 'sql_tuning_sources_19c_v3_1.json', 'sql_tuning_sources_19c_v3_2.json')) { Copy-Item -LiteralPath (Join-Path $k $f) -Destination (Join-Path $mk $f) }
    $mirrorArgs = @{ CatalogPath = (Join-Path $mk 'sql_tuning_catalog_v3_2.yaml'); ThresholdProfileDir = $v32.Profiles }
    Expect-Pass '[3.2] mirrored repository with intact chain' (Invoke-Validator $mirrorArgs)
    Add-Content -LiteralPath (Join-Path $mk 'sql_tuning_catalog_v3.yaml') -Value ' '
    Expect-Fail '[3.2] V3 checkpoint tampered (chain)' (Invoke-Validator $mirrorArgs) 'predecessor 3.0 hash changed'
    Copy-Item -LiteralPath (Join-Path $k 'sql_tuning_catalog_v3.yaml') -Destination (Join-Path $mk 'sql_tuning_catalog_v3.yaml') -Force
    Add-Content -LiteralPath (Join-Path $mk 'sql_tuning_catalog_v3_1.yaml') -Value ' '
    Expect-Fail '[3.2] V3.1 checkpoint tampered' (Invoke-Validator $mirrorArgs) 'predecessor 3.1 hash changed'
    Copy-Item -LiteralPath (Join-Path $k 'sql_tuning_catalog_v3_1.yaml') -Destination (Join-Path $mk 'sql_tuning_catalog_v3_1.yaml') -Force
    $c = Load (Join-Path $k 'sql_tuning_catalog_v3_2.yaml')
    $extra = ($c.thresholds | Where-Object { $_.id -eq 'minimum_samples' }) | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $extra.id = 'invented_threshold'
    $c.thresholds = @($c.thresholds) + @($extra); Save $c (Join-Path $mk 'sql_tuning_catalog_v3_2.yaml')
    Expect-Fail '[3.2] threshold added beyond the 39' (Invoke-Validator $mirrorArgs) 'Threshold count changed \(39 -> 40\)'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
if ($failures) { Write-Output "$failures validator test(s) failed"; exit 1 }
Write-Output 'All validator tests passed.'
exit 0
