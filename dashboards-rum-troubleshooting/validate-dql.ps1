[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FrontendHub,
    [Parameter(Mandatory)][string]$FrontendApplication,
    [string]$HubUrl = "",
    [string]$ApplicationUrl = "",
    [string]$SessionId = "",
    [string]$RequestUrl = "",
    [string]$ServiceName = "(All services)"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command dtctl -ErrorAction SilentlyContinue)) {
    throw "dtctl was not found. Install and authenticate dtctl before running tenant validation."
}

$values = [ordered]@{
    frontend_hub = $FrontendHub
    frontend_application = $FrontendApplication
    hub_url = $HubUrl
    application_url = $ApplicationUrl
    session_id = $SessionId
    request_url = $RequestUrl
    service_name = $ServiceName
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
        foreach ($token in @("`$$($entry.Key):triplequote", "`$$($entry.Key)")) {
            $pattern = [regex]::Escape($token)
            $expanded = [regex]::Replace($expanded, $pattern, { param($match) $literal })
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
    $output = & dtctl query $variable.input --plain 2>&1
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
