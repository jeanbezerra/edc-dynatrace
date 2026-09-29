$ErrorActionPreference = "Stop"

$documentPath = Join-Path $PSScriptRoot "rum-topology-comparison.document.json"
$contentPath = Join-Path $PSScriptRoot "rum-topology-comparison.content.json"
$queriesDirectory = Join-Path $PSScriptRoot "topology-queries"
$errors = [System.Collections.Generic.List[string]]::new()

function Add-ValidationError {
    param([Parameter(Mandatory)][string]$Message)
    $errors.Add($Message)
}

if (-not (Test-Path -LiteralPath $documentPath)) {
    throw "Missing generated document: $documentPath"
}
if (-not (Test-Path -LiteralPath $contentPath)) {
    throw "Missing generated content: $contentPath"
}

$document = Get-Content -LiteralPath $documentPath -Raw -Encoding utf8 | ConvertFrom-Json
$content = $document.content

if ($document.name -ne "RUM Application Topology Comparison - build 2026-09-28-r5") {
    Add-ValidationError "Unexpected dashboard name: $($document.name)"
}
if ($document.type -ne "dashboard" -or $content.version -ne 21) {
    Add-ValidationError "Expected dashboard document type and content version 21."
}
if ($content.settings.gridLayout.columnsCount -ne 24) {
    Add-ValidationError "Expected a 24-column grid."
}

$variables = @($content.variables)
if ($variables.Count -ne 2) {
    Add-ValidationError "Expected exactly two frontend variables, found $($variables.Count)."
}

foreach ($key in @("frontend_upstream", "frontend_target")) {
    $variable = @($variables | Where-Object { $_.key -eq $key })
    if ($variable.Count -ne 1 -or $variable[0].type -ne "query" -or $variable[0].multiple -ne $false) {
        Add-ValidationError "$key must be an automatic single-select query variable."
        continue
    }
    if ($variable[0].input -notmatch '(?im)^\s*smartscapeNodes\s+"FRONTEND"\s*$') {
        Add-ValidationError "$key must read FRONTEND nodes from Smartscape."
    }
    if ($variable[0].input -match '(?im)^\s*(fetch|timeseries)\s+') {
        Add-ValidationError "$key must not scan telemetry."
    }
}

$targetVariable = @($variables | Where-Object { $_.key -eq "frontend_target" })
if ($targetVariable.Count -eq 1 -and $targetVariable[0].input -notmatch 'name\s*!=\s*\$frontend_upstream') {
    Add-ValidationError "frontend_target must exclude frontend_upstream."
}

$tileProperties = @($content.tiles.psobject.Properties)
$layoutProperties = @($content.layouts.psobject.Properties)
$dataTiles = @($tileProperties | Where-Object { $_.Value.type -eq "data" })
$markdownTiles = @($tileProperties | Where-Object { $_.Value.type -eq "markdown" })

if ($tileProperties.Count -ne 22 -or $dataTiles.Count -ne 14 -or $markdownTiles.Count -ne 8) {
    Add-ValidationError "Expected 22 tiles: 14 data and 8 markdown; found $($tileProperties.Count), $($dataTiles.Count), $($markdownTiles.Count)."
}
if ($layoutProperties.Count -ne $tileProperties.Count) {
    Add-ValidationError "Every tile must have one layout."
}

$requiredDataTiles = @(
    "upstream_configuration", "target_configuration",
    "upstream_applications", "target_applications",
    "upstream_application_hosts", "target_application_hosts",
    "upstream_hosts", "target_hosts",
    "upstream_process_groups", "target_process_groups",
    "upstream_processes", "target_processes",
    "upstream_services", "target_services"
)

foreach ($tileId in $requiredDataTiles) {
    $tileProperty = @($dataTiles | Where-Object { $_.Name -eq $tileId })
    if ($tileProperty.Count -ne 1) {
        Add-ValidationError "Missing data tile: $tileId"
        continue
    }

    $tile = $tileProperty[0].Value
    $layout = $content.layouts.$tileId
    $expectedVariable = if ($tileId.StartsWith("upstream_")) { '$frontend_upstream' } else { '$frontend_target' }
    $expectedX = if ($tileId.StartsWith("upstream_")) { 0 } else { 12 }

    if ($tile.visualization -ne "table") {
        Add-ValidationError "$tileId must use table visualization."
    }
    if ($layout.x -ne $expectedX -or $layout.w -ne 12) {
        Add-ValidationError "$tileId must remain in its 12-column comparison side."
    }
    if ($tile.query -notmatch [regex]::Escape($expectedVariable)) {
        Add-ValidationError "$tileId does not use $expectedVariable."
    }
    if ($tileId -in @("upstream_application_hosts", "target_application_hosts")) {
        if ($tile.query -notmatch '(?im)^smartscapeEdges\s+"\*"\s*$') {
            Add-ValidationError "$tileId must start from the complete Smartscape edge catalog."
        }
    }
    elseif ($tile.query -notmatch '(?im)^smartscapeNodes\s+"FRONTEND"\s*$') {
        Add-ValidationError "$tileId must start from a FRONTEND Smartscape node."
    }
    if ($tile.query -match '\bdt\.entity\.') {
        Add-ValidationError "$tileId uses a deprecated dt.entity field."
    }
    if ($tile.query -match '(?im)^\s*fetch\s+(?:user\.events|user\.sessions|spans|logs|events|bizevents)' -or
        $tile.query -match '(?im)^\s*(?:timeseries|metrics)\s+') {
        Add-ValidationError "$tileId must not scan telemetry."
    }
    if ($tile.query -notmatch '(?im)^\s*\|\s*limit\s+\d+\s*$') {
        Add-ValidationError "$tileId must have an explicit result limit."
    }
    if ($tile.querySettings.defaultScanLimitGbytes -gt 1) {
        Add-ValidationError "$tileId scan limit must not exceed 1 GB."
    }
}

foreach ($tileId in @("upstream_configuration", "target_configuration")) {
    $query = $content.tiles.$tileId.query
    foreach ($field in @("dt.rum.instrumentation.rum.enabled", "dt.rum.instrumentation.id", "frontend.type")) {
        if ($query -notmatch [regex]::Escape($field)) {
            Add-ValidationError "$tileId is missing configuration field $field."
        }
    }
}

foreach ($tileId in @("upstream_process_groups", "target_process_groups", "upstream_processes", "target_processes")) {
    $query = $content.tiles.$tileId.query
    if ($query -notmatch 'targetTypes:\s*\{PROCESS\}' -or
        $query -notmatch 'dt\.process_group\.id' -or
        $query -notmatch 'dt\.process_group\.detected_name') {
        Add-ValidationError "$tileId must derive process hierarchy from SERVICE -> PROCESS and expose Process Group ID/name."
    }
}

foreach ($tileId in @("upstream_application_hosts", "target_application_hosts")) {
    $query = $content.tiles.$tileId.query
    if ($query -notmatch 'source_type\s*==\s*"FRONTEND"\s+and\s+target_type\s*==\s*"HOST"' -or
        $query -notmatch 'source_type\s*==\s*"HOST"\s+and\s+target_type\s*==\s*"FRONTEND"' -or
        $query -notmatch 'source_id\s+in\s*\[' -or
        $query -notmatch 'target_id\s+in\s*\[' -or
        $query -notmatch '(?im)^\s*\|\s*append\s*\[' -or
        $query -notmatch 'dt\.system\.edge_kind' -or
        $query -notmatch '(?im)^\s*smartscapeNodes\s+"HOST"\s*$') {
        Add-ValidationError "$tileId must discover direct FRONTEND <-> HOST edges in both directions and enrich the HOST."
    }
    if ($query -match 'targetTypes:\s*\{SERVICE\}' -or $query -match 'targetTypes:\s*\{PROCESS\}') {
        Add-ValidationError "$tileId must not traverse dependency services or processes."
    }
    foreach ($field in @('`Frontend ID`', '`Frontend name`', '`Relationship`', '`Direction`', '`Edge kind`', '`Host ID`', '`Host name`', '`Host group`', '`OS type`', '`IP addresses`', '`Last observed`')) {
        if ($query -notmatch [regex]::Escape($field)) {
            Add-ValidationError "$tileId is missing direct frontend-host evidence field $field."
        }
    }
}

$expectedSectionOrder = [ordered]@{
    section_configuration = 5
    section_applications = 16
    section_application_hosts = 25
    section_process_groups = 38
    section_processes = 49
    section_services = 62
    section_dependency_hosts = 75
}
foreach ($entry in $expectedSectionOrder.GetEnumerator()) {
    $layout = $content.layouts.($entry.Key)
    if ($null -eq $layout -or $layout.y -ne $entry.Value -or $layout.x -ne 0 -or $layout.w -ne 24) {
        Add-ValidationError "$($entry.Key) is missing or outside the restored dependency section order."
    }
}

foreach ($tileId in @("upstream_hosts", "target_hosts")) {
    $query = $content.tiles.$tileId.query
    $hostTraversals = ([regex]::Matches($query, 'targetTypes:\s*\{HOST\}')).Count
    if ($query -notmatch 'edgeTypes:\s*\{calls\}' -or
        $query -notmatch 'targetTypes:\s*\{SERVICE\}' -or
        $query -notmatch 'targetTypes:\s*\{PROCESS\}' -or
        $hostTraversals -lt 2 -or
        $query -notmatch '(?im)^\s*\|\s*append\s*\[') {
        Add-ValidationError "$tileId must combine SERVICE -> HOST and SERVICE -> PROCESS -> HOST paths."
    }
    foreach ($field in @('`Host ID`', '`Host name`', 'dt.host_group.id', 'os.type', 'host.ip', 'getEnd(lifetime)')) {
        if ($query -notmatch [regex]::Escape($field)) {
            Add-ValidationError "$tileId is missing host identity/state field $field."
        }
    }
}

foreach ($tileId in @("upstream_services", "target_services")) {
    $query = $content.tiles.$tileId.query
    if ($query -notmatch 'edgeTypes:\s*\{calls\}' -or $query -notmatch 'targetTypes:\s*\{SERVICE\}') {
        Add-ValidationError "$tileId must map FRONTEND -> SERVICE through calls."
    }
}

for ($i = 0; $i -lt $layoutProperties.Count; $i++) {
    $aName = $layoutProperties[$i].Name
    $a = $layoutProperties[$i].Value
    if ($a.x -lt 0 -or $a.y -lt 0 -or $a.w -le 0 -or $a.h -le 0 -or ($a.x + $a.w) -gt 24) {
        Add-ValidationError "Invalid layout bounds for $aName."
    }
    for ($j = $i + 1; $j -lt $layoutProperties.Count; $j++) {
        $bName = $layoutProperties[$j].Name
        $b = $layoutProperties[$j].Value
        $horizontalOverlap = $a.x -lt ($b.x + $b.w) -and $b.x -lt ($a.x + $a.w)
        $verticalOverlap = $a.y -lt ($b.y + $b.h) -and $b.y -lt ($a.y + $a.h)
        if ($horizontalOverlap -and $verticalOverlap) {
            Add-ValidationError "Layout overlap: $aName and $bName."
        }
    }
}

$queryFiles = @(Get-ChildItem -LiteralPath $queriesDirectory -Filter "*.dql" -File)
if ($queryFiles.Count -ne 14) {
    Add-ValidationError "Expected 14 generated topology queries, found $($queryFiles.Count)."
}

foreach ($path in @($documentPath, $contentPath) + @($queryFiles.FullName)) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-ValidationError "UTF-8 BOM found in $path."
    }
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Select-Object -First 1) {
        Add-ValidationError "Non-ASCII character found in $path."
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "ERROR: $_" }
    Write-Error "$($errors.Count) topology dashboard validation error(s)."
    exit 1
}

[pscustomobject]@{
    Result = "OK"
    Dashboard = $document.name
    Variables = $variables.Count
    Tiles = $tileProperties.Count
    DataTiles = $dataTiles.Count
    MarkdownTiles = $markdownTiles.Count
    Queries = $queryFiles.Count
    Layout = "24 columns; UPSTREAM left; TARGET right; no overlaps"
    DataSources = "Smartscape nodes, edges, and traversal only"
    TelemetryScans = 0
    ScanLimitPerTile = "1 GB"
}
