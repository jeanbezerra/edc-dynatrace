[CmdletBinding()]
param(
    [ValidateSet("15", "30", "60")]
    [string]$AnalysisWindowMinutes = "15",

    [Parameter(Mandatory)][string]$FrontendUpstream,
    [Parameter(Mandatory)][string]$FrontendTarget,

    [ValidateSet("DISABLED", "ENABLED")]
    [string]$UpstreamRumExpected = "DISABLED",

    [string]$UpstreamUrl = "",
    [string]$TargetUrl = "",
    [string]$SessionId = "",
    [string]$RequestUrl = "",
    [string]$TraceId = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command dtctl -ErrorAction SilentlyContinue)) {
    throw "dtctl was not found. Install and authenticate dtctl before running tenant validation."
}

$values = [ordered]@{
    analysis_window_minutes = $AnalysisWindowMinutes
    frontend_upstream = $FrontendUpstream
    frontend_target = $FrontendTarget
    upstream_rum_expected = $UpstreamRumExpected
    upstream_url = $UpstreamUrl
    target_url = $TargetUrl
    session_id = $SessionId
    request_url = $RequestUrl
    trace_id = $TraceId
}

function ConvertTo-DqlStringLiteral {
    param([AllowEmptyString()][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function Expand-DashboardVariables {
    param([Parameter(Mandatory)][string]$Query)

    $expanded = $Query
    foreach ($entry in $values.GetEnumerator()) {
        $literal = ConvertTo-DqlStringLiteral $entry.Value
        $replacements = @(
            [pscustomobject]@{ Token = "`$$($entry.Key):noquote"; Value = [string]$entry.Value },
            [pscustomobject]@{ Token = "`$$($entry.Key):triplequote"; Value = $literal },
            [pscustomobject]@{ Token = "`$$($entry.Key)"; Value = $literal }
        )

        foreach ($replacement in $replacements) {
            $pattern = [regex]::Escape($replacement.Token)
            $replacementValue = $replacement.Value
            $expanded = [regex]::Replace($expanded, $pattern, { param($match) $replacementValue })
        }
    }
    return $expanded
}

$documentPath = Join-Path $PSScriptRoot "rum-diagnostic-explorer.document.json"
$document = Get-Content -Raw -Encoding utf8 $documentPath | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$validated = 0

foreach ($variable in @($document.content.variables | Where-Object { $_.type -eq "query" })) {
    Write-Host "Validating variable query: $($variable.key)"
    $expandedVariableQuery = Expand-DashboardVariables $variable.input
    if ($expandedVariableQuery -match '\$(analysis_window_minutes|frontend_upstream|frontend_target|upstream_rum_expected|upstream_url|target_url|session_id|request_url|trace_id)(?::\w+)?') {
        $failures.Add("variable:$($variable.key)`nUnexpanded dashboard variable remains in query.")
        continue
    }
    if ($expandedVariableQuery -match '""\s*(?:==|!=)\s*""') {
        $failures.Add("variable:$($variable.key)`nVariable expansion created a constant empty-string comparison.")
        continue
    }

    $output = & dtctl query $expandedVariableQuery --plain 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("variable:$($variable.key)`n$($output -join [Environment]::NewLine)")
    }
    else {
        $validated++
    }
}

foreach ($tileProperty in @($document.content.tiles.psobject.Properties | Where-Object { $_.Value.type -eq "data" })) {
    Write-Host "Validating tile query: $($tileProperty.Name)"
    $expandedQuery = Expand-DashboardVariables $tileProperty.Value.query
    if ($expandedQuery -match '\$(analysis_window_minutes|frontend_upstream|frontend_target|upstream_rum_expected|upstream_url|target_url|session_id|request_url|trace_id)(?::\w+)?') {
        $failures.Add("tile:$($tileProperty.Name)`nUnexpanded dashboard variable remains in query.")
        continue
    }
    if ($expandedQuery -match '""\s*(?:==|!=)\s*""') {
        $failures.Add("tile:$($tileProperty.Name)`nVariable expansion created a constant empty-string comparison.")
        continue
    }

    $output = & dtctl query $expandedQuery --plain 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("tile:$($tileProperty.Name)`n$($output -join [Environment]::NewLine)")
    }
    else {
        $validated++
    }
}

if ($failures.Count -gt 0) {
    Write-Error "$($failures.Count) DQL validation(s) failed."
    $failures | ForEach-Object { Write-Host "`n$_" }
    exit 1
}

Write-Host "Tenant validation OK: $validated queries executed successfully."
