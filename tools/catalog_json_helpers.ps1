<#
Shared helpers for catalog generators (dot-source this file).
JSON writer producing the repository's 2-space, LF, UTF-8 (no BOM) format, plus
generic accessors and typed expression builders for catalog decision trees.
tools/migrate_catalog_v3_to_v3_1.ps1 keeps its own frozen copy so V3.1 output stays reproducible.
#>

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
function Load-Json([string]$p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }

function Keys-Of($n) { if ($n -is [System.Collections.IDictionary]) { return ,@($n.Keys) } return ,@($n.PSObject.Properties | ForEach-Object { $_.Name }) }
function Val-Of($n, [string]$k) { if ($n -is [System.Collections.IDictionary]) { return $n[$k] } return $n.$k }
function Copy-Ordered($obj) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Cmp([string]$metric, [string]$op, $right) {
    $r = if ($right -is [string]) { [ordered]@{ threshold = $right } } else { [ordered]@{ literal = $right } }
    return [ordered]@{ op = $op; left = [ordered]@{ metric = $metric }; right = $r }
}
function All-Of([object[]]$items) { if ($items.Count -eq 1) { return $items[0] } return [ordered]@{ all = $items } }
function Any-Of([object[]]$items) { return [ordered]@{ any = $items } }
function Not-Of($item) { return [ordered]@{ not = $item } }
function Collect-Metrics($node, [System.Collections.Generic.HashSet[string]]$set) {
    if ($null -eq $node) { return }
    $keys = Keys-Of $node
    if ($keys.Count -eq 1 -and $keys[0] -in @('all', 'any')) { foreach ($c in @(Val-Of $node $keys[0])) { Collect-Metrics $c $set }; return }
    if ($keys.Count -eq 1 -and $keys[0] -eq 'not') { Collect-Metrics (Val-Of $node 'not') $set; return }
    foreach ($side in @('left', 'right')) { $o = Val-Of $node $side; if ($o -and (Keys-Of $o) -contains 'metric') { [void]$set.Add([string](Val-Of $o 'metric')) } }
}
