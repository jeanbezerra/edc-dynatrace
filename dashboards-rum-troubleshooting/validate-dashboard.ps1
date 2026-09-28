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
    $document = Get-Content -Raw -Encoding utf8 $documentPath | ConvertFrom-Json
    $content = Get-Content -Raw -Encoding utf8 $contentPath | ConvertFrom-Json
}
catch {
    throw "JSON parsing failed: $($_.Exception.Message)"
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
    elseif ((Get-Content -Raw -Encoding utf8 $queryFile).Trim() -ne $tile.query.Trim()) {
        Add-ValidationError "Query file differs from tile query for '$($property.Name)'."
    }

    if ($tile.query -match '(?im)(^|[,\s])(?:from|to|timeframe)\s*:') {
        Add-ValidationError "Tile '$($property.Name)' contains a fixed timeframe."
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

$allQueries = @($dataTiles.Value.query) + @($content.variables | Where-Object { $_.type -eq "query" } | ForEach-Object input)
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
    FixedTimeframes = 0
} | Format-List
