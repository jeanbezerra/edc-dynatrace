$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$documentPath = Join-Path $root "rum-diagnostic-explorer.document.json"
$contentPath = Join-Path $root "rum-diagnostic-explorer.content.json"
$queriesPath = Join-Path $root "queries"

$errors = [System.Collections.Generic.List[string]]::new()

function Add-ValidationError {
    param([string]$Message)
    $errors.Add($Message)
}

try {
    $documentRaw = Get-Content -Raw -Encoding utf8 $documentPath
    $contentRaw = Get-Content -Raw -Encoding utf8 $contentPath
    $document = $documentRaw | ConvertFrom-Json
    $content = $contentRaw | ConvertFrom-Json
}
catch {
    throw "JSON parsing failed: $($_.Exception.Message)"
}

foreach ($artifact in @(
        [pscustomobject]@{ Name = "document JSON"; Text = $documentRaw },
        [pscustomobject]@{ Name = "content JSON"; Text = $contentRaw }
    )) {
    if ($artifact.Text -match '[^\x00-\x7F]') {
        Add-ValidationError "$($artifact.Name) contains non-ASCII characters that may render incorrectly after import."
    }
}

if ($document.name -ne "RUM Diagnostic Explorer") {
    Add-ValidationError "Unexpected dashboard name: $($document.name)"
}
if ($document.type -ne "dashboard") {
    Add-ValidationError "Unexpected document type: $($document.type)"
}
if ($document.content.version -ne 21 -or $content.version -ne 21) {
    Add-ValidationError "Dashboard schema version must be 21."
}

$documentContentNormalized = $document.content | ConvertTo-Json -Depth 100 -Compress
$contentNormalized = $content | ConvertTo-Json -Depth 100 -Compress
if ($documentContentNormalized -ne $contentNormalized) {
    Add-ValidationError "The .content.json file differs from document.content."
}

$tileProperties = @($content.tiles.psobject.Properties)
$layoutProperties = @($content.layouts.psobject.Properties)
$tileIds = @($tileProperties.Name | Sort-Object)
$layoutIds = @($layoutProperties.Name | Sort-Object)

if (($tileIds -join "|") -ne ($layoutIds -join "|")) {
    Add-ValidationError "Tile IDs and layout IDs differ."
}

$dataTiles = @($tileProperties | Where-Object { $_.Value.type -eq "data" })
$markdownTiles = @($tileProperties | Where-Object { $_.Value.type -eq "markdown" })
$timeGuardPattern = '(?i)from\s*:\s*now\(\)\s*-\s*duration\(toLong\(\$analysis_window_minutes:noquote\),\s*unit\s*:\s*"m"\)'

foreach ($property in $dataTiles) {
    $tile = $property.Value
    foreach ($requiredProperty in @("title", "description", "query", "visualization", "visualizationSettings", "querySettings")) {
        if (-not $tile.psobject.Properties.Name.Contains($requiredProperty)) {
            Add-ValidationError "Data tile '$($property.Name)' misses '$requiredProperty'."
        }
    }

    $queryFile = Join-Path $queriesPath "$($property.Name).dql"
    if (-not (Test-Path -LiteralPath $queryFile)) {
        Add-ValidationError "Missing extracted query file for '$($property.Name)'."
    }
    else {
        $queryFileText = Get-Content -Raw -Encoding utf8 $queryFile
        if ($queryFileText.Trim() -ne $tile.query.Trim()) {
            Add-ValidationError "Query file differs from tile query for '$($property.Name)'."
        }
        if ($queryFileText -match '[^\x00-\x7F]') {
            Add-ValidationError "Query file for '$($property.Name)' contains non-ASCII characters."
        }
    }

    if ($tile.query -match '(?im)(^|[,\s])(?:to|timeframe)\s*:') {
        Add-ValidationError "Tile '$($property.Name)' contains an unsupported to/timeframe override."
    }

    if ($tile.query -match '(?im)^\s*fetch\s+' -and $tile.query -notmatch $timeGuardPattern) {
        Add-ValidationError "Tile '$($property.Name)' fetches telemetry without the bounded analysis window."
    }

    $queryWithoutApprovedGuard = [regex]::Replace($tile.query, $timeGuardPattern, "")
    if ($queryWithoutApprovedGuard -match '(?im)(^|[,\s])from\s*:') {
        Add-ValidationError "Tile '$($property.Name)' contains an unapproved from override."
    }

    if ($tile.querySettings.defaultScanLimitGbytes -gt 2) {
        Add-ValidationError "Tile '$($property.Name)' has a scan limit above 2 GB."
    }
    if ($tile.querySettings.maxResultRecords -gt 500) {
        Add-ValidationError "Tile '$($property.Name)' allows more than 500 result records."
    }

    if ($tile.query -match '(?im)^\s*fetch\s+spans\b' -and
        $tile.query -notmatch 'trace\.id\s*==\s*toUid\(\$trace_id\)') {
        Add-ValidationError "Tile '$($property.Name)' scans spans without an exact trace_id lookup."
    }
}

foreach ($property in $markdownTiles) {
    if ([string]::IsNullOrWhiteSpace($property.Value.content)) {
        Add-ValidationError "Markdown tile '$($property.Name)' is empty."
    }
}

foreach ($layoutProperty in $layoutProperties) {
    $layout = $layoutProperty.Value
    if ($layout.x -lt 0 -or $layout.y -lt 0 -or $layout.w -le 0 -or $layout.h -le 0 -or ($layout.x + $layout.w) -gt 24) {
        Add-ValidationError "Layout '$($layoutProperty.Name)' is outside the 24-column grid."
    }
}

for ($i = 0; $i -lt $layoutProperties.Count; $i++) {
    $a = $layoutProperties[$i]
    for ($j = $i + 1; $j -lt $layoutProperties.Count; $j++) {
        $b = $layoutProperties[$j]
        $overlapX = $a.Value.x -lt ($b.Value.x + $b.Value.w) -and $b.Value.x -lt ($a.Value.x + $a.Value.w)
        $overlapY = $a.Value.y -lt ($b.Value.y + $b.Value.h) -and $b.Value.y -lt ($a.Value.y + $a.Value.h)
        if ($overlapX -and $overlapY) {
            Add-ValidationError "Layouts '$($a.Name)' and '$($b.Name)' overlap."
        }
    }
}

$allQueries = @($dataTiles | ForEach-Object { $_.Value.query }) + @($content.variables | Where-Object { $_.type -eq "query" } | ForEach-Object input)
$queryText = $allQueries -join "`n"
foreach ($variable in $content.variables) {
    if ($queryText -notmatch [regex]::Escape("$" + $variable.key)) {
        Add-ValidationError "Variable '$($variable.key)' is not referenced by any query."
    }
    if ($variable.type -eq "query") {
        if ($variable.input -match '(?im)(^|[,\s])(?:from|to|timeframe)\s*:') {
            Add-ValidationError "Variable '$($variable.key)' contains a fixed timeframe."
        }
        if ($variable.input -notmatch '(?im)^\s*\|\s*fields\s+[^,\r\n]+\s*$') {
            Add-ValidationError "Query variable '$($variable.key)' must finish with exactly one output field before optional sort."
        }
    }
}

$userEventScans = ([regex]::Matches($queryText, '(?im)^\s*fetch\s+user\.events\b')).Count
$spanScans = ([regex]::Matches($queryText, '(?im)^\s*fetch\s+spans\b')).Count
if ($userEventScans -gt 6) {
    Add-ValidationError "Dashboard contains $userEventScans user.events scans; maximum is 6."
}
if ($spanScans -gt 1) {
    Add-ValidationError "Dashboard contains $spanScans spans scans; maximum is 1."
}
if ($dataTiles.Count -gt 8) {
    Add-ValidationError "Dashboard contains $($dataTiles.Count) data tiles; maximum is 8 for the cost-bounded design."
}

$analysisWindow = @($content.variables | Where-Object { $_.key -eq "analysis_window_minutes" })
if ($analysisWindow.Count -ne 1 -or $analysisWindow[0].type -ne "csv" -or $analysisWindow[0].input -ne "15,30,60") {
    Add-ValidationError "analysis_window_minutes must be the bounded CSV list 15,30,60."
}

$upstreamExpectation = @($content.variables | Where-Object { $_.key -eq "upstream_rum_expected" })
if ($upstreamExpectation.Count -ne 1 -or $upstreamExpectation[0].input -ne "DISABLED,ENABLED") {
    Add-ValidationError "upstream_rum_expected must default to the DISABLED,ENABLED CSV list."
}

$unexpectedQueryFiles = @(Get-ChildItem -LiteralPath $queriesPath -Filter "*.dql" | Where-Object { $_.BaseName -notin $dataTiles.Name })
foreach ($file in $unexpectedQueryFiles) {
    Add-ValidationError "Unexpected query file: $($file.Name)"
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

[pscustomobject]@{
    Result = "OK"
    Dashboard = $document.name
    Variables = @($content.variables).Count
    Tiles = $tileProperties.Count
    DataTiles = $dataTiles.Count
    MarkdownTiles = $markdownTiles.Count
    Queries = @(Get-ChildItem -LiteralPath $queriesPath -Filter "*.dql").Count
    Layout = "24 columns; no overlaps"
    TimeGuard = "15/30/60 minutes; hard cap 60"
    ScanLimitPerTile = "2 GB"
    UserEventScans = $userEventScans
    SpanScans = $spanScans
} | Format-List
