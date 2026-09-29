[CmdletBinding()]
param(
    [string]$FrontendUpstream = "UPSTREAM FRONTEND",
    [string]$FrontendTarget = "TARGET FRONTEND",
    [switch]$RunTenant
)

$ErrorActionPreference = "Stop"

if ($FrontendUpstream -eq $FrontendTarget) {
    throw "FrontendUpstream and FrontendTarget must be different."
}
if ($RunTenant -and -not (Get-Command dtctl -ErrorAction SilentlyContinue)) {
    throw "dtctl was not found. Install and authenticate dtctl before tenant validation."
}

$documentPath = Join-Path $PSScriptRoot "rum-topology-comparison.document.json"
$document = Get-Content -LiteralPath $documentPath -Raw -Encoding utf8 | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$staticValidated = 0
$tenantValidated = 0

$values = [ordered]@{
    frontend_upstream = $FrontendUpstream
    frontend_target = $FrontendTarget
}

function ConvertTo-DqlStringLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function Expand-DashboardVariables {
    param([Parameter(Mandatory)][string]$Query)

    $expanded = $Query
    foreach ($entry in $values.GetEnumerator()) {
        $token = "`$$($entry.Key)"
        $replacement = ConvertTo-DqlStringLiteral -Value ([string]$entry.Value)
        $expanded = $expanded.Replace($token, $replacement)
    }
    return $expanded
}

function Test-ExpandedQuery {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query
    )

    $expanded = Expand-DashboardVariables -Query $Query
    $queryErrors = [System.Collections.Generic.List[string]]::new()

    if ($expanded -match '\$(frontend_upstream|frontend_target)(?::\w+)?') {
        $queryErrors.Add("Unexpanded dashboard variable remains.")
    }
    if ($expanded -match '""\s*(?:==|!=)\s*""') {
        $queryErrors.Add("Variable expansion created a constant empty-string comparison.")
    }
    if ($expanded -match 'contains\([^\r\n]*,\s*(?:true|false)\s*\)') {
        $queryErrors.Add("contains() uses a positional optional parameter.")
    }
    if ($expanded -match '(?im)^\s*(fetch|timeseries|metrics)\s+') {
        $queryErrors.Add("Topology query scans telemetry.")
    }
    if ($expanded -notmatch '(?im)^smartscapeNodes\s+"FRONTEND"\s*$') {
        $queryErrors.Add("Query does not start from a FRONTEND Smartscape node.")
    }
    if ($expanded -notmatch '(?im)^\s*\|\s*limit\s+\d+\s*$') {
        $queryErrors.Add("Query has no explicit result limit.")
    }

    $openParentheses = ([regex]::Matches($expanded, '\(')).Count
    $closeParentheses = ([regex]::Matches($expanded, '\)')).Count
    $openBraces = ([regex]::Matches($expanded, '\{')).Count
    $closeBraces = ([regex]::Matches($expanded, '\}')).Count
    if ($openParentheses -ne $closeParentheses) {
        $queryErrors.Add("Unbalanced parentheses.")
    }
    if ($openBraces -ne $closeBraces) {
        $queryErrors.Add("Unbalanced braces.")
    }

    if ($queryErrors.Count -gt 0) {
        $failures.Add("$Name`n$($queryErrors -join [Environment]::NewLine)")
        return
    }

    $script:staticValidated++
    if ($RunTenant) {
        $output = & dtctl query $expanded --plain 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("$Name`n$($output -join [Environment]::NewLine)")
        }
        else {
            $script:tenantValidated++
        }
    }
}

foreach ($variable in @($document.content.variables | Where-Object { $_.type -eq "query" })) {
    Test-ExpandedQuery -Name "variable:$($variable.key)" -Query $variable.input
}

foreach ($tileProperty in @($document.content.tiles.psobject.Properties | Where-Object { $_.Value.type -eq "data" })) {
    Test-ExpandedQuery -Name "tile:$($tileProperty.Name)" -Query $tileProperty.Value.query
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "`n$_" }
    Write-Error "$($failures.Count) topology DQL validation(s) failed."
    exit 1
}

[pscustomobject]@{
    Result = "OK"
    StaticQueries = $staticValidated
    TenantQueries = $tenantValidated
    TenantExecution = if ($RunTenant) { "executed" } else { "skipped (use -RunTenant)" }
    FrontendUpstream = $FrontendUpstream
    FrontendTarget = $FrontendTarget
}
