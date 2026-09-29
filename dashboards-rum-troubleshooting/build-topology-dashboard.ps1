$ErrorActionPreference = "Stop"

$outputDirectory = $PSScriptRoot
$queriesDirectory = Join-Path $outputDirectory "topology-queries"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $queriesDirectory | Out-Null
Get-ChildItem -LiteralPath $queriesDirectory -Filter "*.dql" -File | Remove-Item -Force

$querySettings = [ordered]@{
    maxResultRecords = 500
    defaultScanLimitGbytes = 1
    maxResultMegaBytes = 5
    defaultSamplingRatio = 1
    enableSampling = $false
}

$tiles = [ordered]@{}
$layouts = [ordered]@{}

function ConvertTo-AsciiText {
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)][string]$Text
    )

    $mapped = $Text
    $replacements = @(
        @([string][char]0x00A0, " "),
        @([string][char]0x00B7, "-"),
        @([string][char]0x00D7, "x"),
        @([string][char]0x2011, "-"),
        @([string][char]0x2013, "-"),
        @([string][char]0x2014, "-"),
        @([string][char]0x2018, "'"),
        @([string][char]0x2019, "'"),
        @([string][char]0x201C, '"'),
        @([string][char]0x201D, '"'),
        @([string][char]0x2026, "..."),
        @([string][char]0x202F, " "),
        @([string][char]0x2192, "->")
    )

    foreach ($replacement in $replacements) {
        $mapped = $mapped.Replace($replacement[0], $replacement[1])
    }

    $normalized = $mapped.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new($normalized.Length)
    foreach ($character in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($category -in @(
                [System.Globalization.UnicodeCategory]::NonSpacingMark,
                [System.Globalization.UnicodeCategory]::SpacingCombiningMark,
                [System.Globalization.UnicodeCategory]::EnclosingMark
            )) {
            continue
        }

        if ([int]$character -le 0x7F) {
            [void]$builder.Append($character)
        }
    }

    return $builder.ToString()
}

function Add-MarkdownTile {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $tiles[$Id] = [ordered]@{
        type = "markdown"
        content = ConvertTo-AsciiText -Text $Content
    }
    $layouts[$Id] = [ordered]@{ x = $X; y = $Y; w = $Width; h = $Height }
}

function Add-DataTile {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $asciiQuery = ConvertTo-AsciiText -Text ($Query.Trim())
    $tiles[$Id] = [ordered]@{
        type = "data"
        title = ConvertTo-AsciiText -Text $Title
        description = ConvertTo-AsciiText -Text $Description
        query = $asciiQuery
        visualization = "table"
        visualizationSettings = [ordered]@{
            autoSelectVisualization = $false
            table = [ordered]@{
                rowDensity = "condensed"
                columnWidthStrategy = "content"
                enableSparklines = $false
                linewrapEnabled = $true
            }
        }
        querySettings = [ordered]@{
            maxResultRecords = $querySettings.maxResultRecords
            defaultScanLimitGbytes = $querySettings.defaultScanLimitGbytes
            maxResultMegaBytes = $querySettings.maxResultMegaBytes
            defaultSamplingRatio = $querySettings.defaultSamplingRatio
            enableSampling = $querySettings.enableSampling
        }
    }
    $layouts[$Id] = [ordered]@{ x = $X; y = $Y; w = $Width; h = $Height }

    [System.IO.File]::WriteAllText(
        (Join-Path $queriesDirectory "$Id.dql"),
        $asciiQuery + "`n",
        $utf8NoBom
    )
}

Add-MarkdownTile -Id "intro" -X 0 -Y 0 -Width 24 -Height 5 -Content @'
# RUM Application Topology Comparison

**Build: 2026-09-28-r6 - Agentless web-tier correlation**

Read each layer from left to right: **UPSTREAM** on the left and **TARGET / DOWNSTREAM** on the right. The dashboard uses only the current Smartscape catalog and Dynatrace entity taxonomy; it does not scan user events, spans, logs, or metrics.

The public Smartscape model guarantees `FRONTEND -> SERVICE`, but it does not guarantee a direct `FRONTEND -> HOST` relation. Section 03 therefore shows tenant-specific direct edges when they exist and never labels API dependency hosts as frontend hosting hosts. Use the diagnostic dashboard with an exact correlated page-load trace to prove the Apache process and host.
'@

Add-MarkdownTile -Id "section_configuration" -X 0 -Y 5 -Width 24 -Height 5 -Content @'
## 01 - FRONTEND CONFIGURATION

For pages that already contain the Agentless/manual JavaScript, keep RUM enabled on the entry Apache process group (`builtin:rum.processgroup`, `enable=true`) and add an application-scoped custom injection rule with `rule=DoNotInject` (`builtin:rum.web.custom-injection-rules`). This prevents a second script while preserving JavaScript delivery, beacon handling, `Server-Timing`, and frontend/backend correlation. Smartscape DQL exposes the frontend catalog state below, but not those Settings 2.0 values; verify both schemas in Settings or through the Settings API.
'@

Add-DataTile -Id "upstream_configuration" -Title "UPSTREAM - Frontend catalog state" -Description "Frontend catalog state only; process-group RUM and custom injection rules require Settings 2.0 validation." -X 0 -Y 10 -Width 12 -Height 9 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| fields
    `Frontend ID` = id,
    `Frontend name` = name,
    `Frontend type` = frontend.type,
    `Frontend RUM enabled (catalog)` = dt.rum.instrumentation.rum.enabled,
    `Instrumentation ID` = dt.rum.instrumentation.id,
    `Deleted at` = frontend.deletion_time,
    `First observed` = getStart(lifetime),
    `Last observed` = getEnd(lifetime)
| sort `Frontend name` asc, `Frontend ID` asc
| limit 20
'@

Add-DataTile -Id "target_configuration" -Title "TARGET - Frontend catalog state" -Description "Frontend catalog state only; process-group RUM and custom injection rules require Settings 2.0 validation." -X 12 -Y 10 -Width 12 -Height 9 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| fields
    `Frontend ID` = id,
    `Frontend name` = name,
    `Frontend type` = frontend.type,
    `Frontend RUM enabled (catalog)` = dt.rum.instrumentation.rum.enabled,
    `Instrumentation ID` = dt.rum.instrumentation.id,
    `Deleted at` = frontend.deletion_time,
    `First observed` = getStart(lifetime),
    `Last observed` = getEnd(lifetime)
| sort `Frontend name` asc, `Frontend ID` asc
| limit 20
'@

Add-MarkdownTile -Id "section_applications" -X 0 -Y 19 -Width 24 -Height 2 -Content @'
## 02 - APPLICATIONS / FRONTENDS

The selected Web Application is represented by a `FRONTEND` node. Both Smartscape and Classic IDs are shown when available.
'@

Add-DataTile -Id "upstream_applications" -Title "UPSTREAM - Applications" -Description "Frontend/Web Application identity selected as upstream." -X 0 -Y 21 -Width 12 -Height 7 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| fields
    `Application ID` = id,
    `Application name` = name,
    `Classic application ID` = id_classic,
    `Entity type` = type
| sort `Application name` asc, `Application ID` asc
| limit 20
'@

Add-DataTile -Id "target_applications" -Title "TARGET - Applications" -Description "Frontend/Web Application identity selected as target." -X 12 -Y 21 -Width 12 -Height 7 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| fields
    `Application ID` = id,
    `Application name` = name,
    `Classic application ID` = id_classic,
    `Entity type` = type
| sort `Application name` asc, `Application ID` asc
| limit 20
'@

Add-MarkdownTile -Id "section_application_hosts" -X 0 -Y 28 -Width 24 -Height 4 -Content @'
## 03 - FRONTEND HOSTS - CORRELATED TOPOLOGY

Tenant-specific direct `FRONTEND <-> HOST` edges, when present. An empty result does not prove that the Angular frontend has no hosting server: the public Smartscape taxonomy documents only `FRONTEND -> SERVICE` and does not guarantee a direct host relation. Disabling RUM on the entry Apache process group also removes the correlation needed to prove the web tier. Re-enable process-group RUM, block only injection with `DoNotInject`, then use an exact page-load trace in the diagnostic dashboard to identify Apache process group and host. Dependency hosts remain separate below.
'@

Add-DataTile -Id "upstream_application_hosts" -Title "UPSTREAM - Correlated frontend hosts" -Description "Best-effort tenant-specific direct Smartscape edges; an empty result requires correlated trace validation." -X 0 -Y 32 -Width 12 -Height 11 -Query @'
smartscapeEdges "*"
| filter source_type == "FRONTEND" and target_type == "HOST"
| filter source_id in [
    smartscapeNodes "FRONTEND"
    | filter name == $frontend_upstream
    | fields id
  ]
| fieldsAdd edge_kind = dt.system.edge_kind
| fields
    frontend_id = source_id,
    host_id = target_id,
    relationship_type = type,
    relationship_direction = "FRONTEND -> HOST",
    edge_kind
| append [
    smartscapeEdges "*"
    | filter source_type == "HOST" and target_type == "FRONTEND"
    | filter target_id in [
        smartscapeNodes "FRONTEND"
        | filter name == $frontend_upstream
        | fields id
      ]
    | fieldsAdd edge_kind = dt.system.edge_kind
    | fields
        frontend_id = target_id,
        host_id = source_id,
        relationship_type = type,
        relationship_direction = "HOST -> FRONTEND",
        edge_kind
  ]
| dedup frontend_id, host_id, relationship_type, relationship_direction
| lookup [
    smartscapeNodes "FRONTEND"
    | fields frontend_id = id, frontend_name = name, classic_frontend_id = id_classic
  ], sourceField: frontend_id, lookupField: frontend_id, prefix: "frontend."
| lookup [
    smartscapeNodes "HOST"
    | fields
        host_id = id,
        host_name = name,
        classic_host_id = id_classic,
        host_group = dt.host_group.id,
        os_type = os.type,
        os_name = os.name,
        os_version = os.version,
        ip_addresses = host.ip,
        first_observed = getStart(lifetime),
        last_observed = getEnd(lifetime)
  ], sourceField: host_id, lookupField: host_id, prefix: "host."
| fields
    `Frontend ID` = frontend_id,
    `Frontend name` = frontend.frontend_name,
    `Classic frontend ID` = frontend.classic_frontend_id,
    `Relationship` = relationship_type,
    `Direction` = relationship_direction,
    `Edge kind` = edge_kind,
    `Host ID` = host_id,
    `Host name` = host.host_name,
    `Classic host ID` = host.classic_host_id,
    `Host group` = host.host_group,
    `OS type` = host.os_type,
    `OS name` = host.os_name,
    `OS version` = host.os_version,
    `IP addresses` = host.ip_addresses,
    `First observed` = host.first_observed,
    `Last observed` = host.last_observed
| sort `Host name` asc, `Relationship` asc
| limit 200
'@

Add-DataTile -Id "target_application_hosts" -Title "TARGET - Correlated frontend hosts" -Description "Best-effort tenant-specific direct Smartscape edges; an empty result requires correlated trace validation." -X 12 -Y 32 -Width 12 -Height 11 -Query @'
smartscapeEdges "*"
| filter source_type == "FRONTEND" and target_type == "HOST"
| filter source_id in [
    smartscapeNodes "FRONTEND"
    | filter name == $frontend_target
    | fields id
  ]
| fieldsAdd edge_kind = dt.system.edge_kind
| fields
    frontend_id = source_id,
    host_id = target_id,
    relationship_type = type,
    relationship_direction = "FRONTEND -> HOST",
    edge_kind
| append [
    smartscapeEdges "*"
    | filter source_type == "HOST" and target_type == "FRONTEND"
    | filter target_id in [
        smartscapeNodes "FRONTEND"
        | filter name == $frontend_target
        | fields id
      ]
    | fieldsAdd edge_kind = dt.system.edge_kind
    | fields
        frontend_id = target_id,
        host_id = source_id,
        relationship_type = type,
        relationship_direction = "HOST -> FRONTEND",
        edge_kind
  ]
| dedup frontend_id, host_id, relationship_type, relationship_direction
| lookup [
    smartscapeNodes "FRONTEND"
    | fields frontend_id = id, frontend_name = name, classic_frontend_id = id_classic
  ], sourceField: frontend_id, lookupField: frontend_id, prefix: "frontend."
| lookup [
    smartscapeNodes "HOST"
    | fields
        host_id = id,
        host_name = name,
        classic_host_id = id_classic,
        host_group = dt.host_group.id,
        os_type = os.type,
        os_name = os.name,
        os_version = os.version,
        ip_addresses = host.ip,
        first_observed = getStart(lifetime),
        last_observed = getEnd(lifetime)
  ], sourceField: host_id, lookupField: host_id, prefix: "host."
| fields
    `Frontend ID` = frontend_id,
    `Frontend name` = frontend.frontend_name,
    `Classic frontend ID` = frontend.classic_frontend_id,
    `Relationship` = relationship_type,
    `Direction` = relationship_direction,
    `Edge kind` = edge_kind,
    `Host ID` = host_id,
    `Host name` = host.host_name,
    `Classic host ID` = host.classic_host_id,
    `Host group` = host.host_group,
    `OS type` = host.os_type,
    `OS name` = host.os_name,
    `OS version` = host.os_version,
    `IP addresses` = host.ip_addresses,
    `First observed` = host.first_observed,
    `Last observed` = host.last_observed
| sort `Host name` asc, `Relationship` asc
| limit 200
'@

Add-MarkdownTile -Id "section_dependency_hosts" -X 0 -Y 80 -Width 24 -Height 2 -Content @'
## 07 - DEPENDENCIES - HOSTS

Hosts reached through every service associated with the frontend, including APIs, gateways, proxies, and other downstream dependencies. This layer explains the Sensedia-style hosts and is intentionally separate from the application-hosting evidence above.
'@

Add-DataTile -Id "upstream_hosts" -Title "UPSTREAM - Dependency hosts" -Description "All hosts reached through services associated with the upstream frontend; these are dependencies, not direct frontend-host edges." -X 0 -Y 82 -Width 12 -Height 10 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {HOST}, direction: forward
| append [
    smartscapeNodes "FRONTEND"
    | filter name == $frontend_upstream
    | traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
    | traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
    | traverse edgeTypes: {runs_on}, targetTypes: {HOST}, direction: forward
  ]
| dedup id
| fields
    `Host ID` = id,
    `Host name` = name,
    `Classic host ID` = id_classic,
    `Host group` = dt.host_group.id,
    `OS type` = os.type,
    `OS name` = os.name,
    `OS version` = os.version,
    `IP addresses` = host.ip,
    `First observed` = getStart(lifetime),
    `Last observed` = getEnd(lifetime)
| sort `Host name` asc, `Host ID` asc
| limit 200
'@

Add-DataTile -Id "target_hosts" -Title "TARGET - Dependency hosts" -Description "All hosts reached through services associated with the target frontend; these are dependencies, not direct frontend-host edges." -X 12 -Y 82 -Width 12 -Height 10 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {HOST}, direction: forward
| append [
    smartscapeNodes "FRONTEND"
    | filter name == $frontend_target
    | traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
    | traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
    | traverse edgeTypes: {runs_on}, targetTypes: {HOST}, direction: forward
  ]
| dedup id
| fields
    `Host ID` = id,
    `Host name` = name,
    `Classic host ID` = id_classic,
    `Host group` = dt.host_group.id,
    `OS type` = os.type,
    `OS name` = os.name,
    `OS version` = os.version,
    `IP addresses` = host.ip,
    `First observed` = getStart(lifetime),
    `Last observed` = getEnd(lifetime)
| sort `Host name` asc, `Host ID` asc
| limit 200
'@

Add-MarkdownTile -Id "section_process_groups" -X 0 -Y 43 -Width 24 -Height 2 -Content @'
## 04 - DEPENDENCIES - PROCESS GROUPS

Process Group is a compatibility grouping derived from processes. The table keeps the Dynatrace Process Group ID and detected name visible for human reading.
'@

Add-DataTile -Id "upstream_process_groups" -Title "UPSTREAM - Dependency process groups" -Description "Process groups behind services called by the upstream frontend." -X 0 -Y 45 -Width 12 -Height 9 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
| filter isNotNull(dt.process_group.id) or isNotNull(dt.process_group.detected_name)
| dedup dt.process_group.id, dt.process_group.detected_name
| fields
    `Process Group ID` = dt.process_group.id,
    `Process Group name` = dt.process_group.detected_name
| sort `Process Group name` asc, `Process Group ID` asc
| limit 100
'@

Add-DataTile -Id "target_process_groups" -Title "TARGET - Dependency process groups" -Description "Process groups behind services called by the target frontend." -X 12 -Y 45 -Width 12 -Height 9 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
| filter isNotNull(dt.process_group.id) or isNotNull(dt.process_group.detected_name)
| dedup dt.process_group.id, dt.process_group.detected_name
| fields
    `Process Group ID` = dt.process_group.id,
    `Process Group name` = dt.process_group.detected_name
| sort `Process Group name` asc, `Process Group ID` asc
| limit 100
'@

Add-MarkdownTile -Id "section_processes" -X 0 -Y 54 -Width 24 -Height 2 -Content @'
## 05 - DEPENDENCIES - PROCESSES

Smartscape `PROCESS` nodes on which the directly called services run. The Process Group columns preserve the grouping context.
'@

Add-DataTile -Id "upstream_processes" -Title "UPSTREAM - Dependency processes" -Description "Processes supporting services called by the upstream frontend." -X 0 -Y 56 -Width 12 -Height 11 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
| dedup id
| fields
    `Process ID` = id,
    `Process name` = name,
    `Process Group ID` = dt.process_group.id,
    `Process Group name` = dt.process_group.detected_name,
    `Classic process ID` = id_classic
| sort `Process Group name` asc, `Process name` asc, `Process ID` asc
| limit 200
'@

Add-DataTile -Id "target_processes" -Title "TARGET - Dependency processes" -Description "Processes supporting services called by the target frontend." -X 12 -Y 56 -Width 12 -Height 11 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| traverse edgeTypes: {runs_on}, targetTypes: {PROCESS}, direction: forward
| dedup id
| fields
    `Process ID` = id,
    `Process name` = name,
    `Process Group ID` = dt.process_group.id,
    `Process Group name` = dt.process_group.detected_name,
    `Classic process ID` = id_classic
| sort `Process Group name` asc, `Process name` asc, `Process ID` asc
| limit 200
'@

Add-MarkdownTile -Id "section_services" -X 0 -Y 67 -Width 24 -Height 2 -Content @'
## 06 - DEPENDENCIES - SERVICES

Services directly linked to each frontend by the stable Smartscape `calls` relationship.
'@

Add-DataTile -Id "upstream_services" -Title "UPSTREAM - Dependency services" -Description "Services directly called by the upstream frontend." -X 0 -Y 69 -Width 12 -Height 11 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_upstream
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| dedup id
| fields
    `Service ID` = id,
    `Service name` = name,
    `Classic service ID` = id_classic,
    `Detection version` = dt.service_detection.version,
    `Service type` = dt.service.sdv1_type
| sort `Service name` asc, `Service ID` asc
| limit 200
'@

Add-DataTile -Id "target_services" -Title "TARGET - Dependency services" -Description "Services directly called by the target frontend." -X 12 -Y 69 -Width 12 -Height 11 -Query @'
smartscapeNodes "FRONTEND"
| filter name == $frontend_target
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| dedup id
| fields
    `Service ID` = id,
    `Service name` = name,
    `Classic service ID` = id_classic,
    `Detection version` = dt.service_detection.version,
    `Service type` = dt.service.sdv1_type
| sort `Service name` asc, `Service ID` asc
| limit 200
'@

$variables = @(
    [ordered]@{
        version = 2
        key = "frontend_upstream"
        type = "query"
        visible = $true
        editable = $true
        input = "smartscapeNodes `"FRONTEND`"`n| filter isNotNull(name) and name != `"`"`n| dedup name`n| fields value = name`n| sort value asc`n| limit 500"
        multiple = $false
    },
    [ordered]@{
        version = 2
        key = "frontend_target"
        type = "query"
        visible = $true
        editable = $true
        input = "smartscapeNodes `"FRONTEND`"`n| filter isNotNull(name) and name != `"`" and name != `$frontend_upstream`n| dedup name`n| fields value = name`n| sort value asc`n| limit 500"
        multiple = $false
    }
)

$content = [ordered]@{
    version = 21
    variables = $variables
    tiles = $tiles
    layouts = $layouts
    settings = [ordered]@{
        gridLayout = [ordered]@{ columnsCount = 24 }
    }
    annotations = @()
}

$document = [ordered]@{
    name = "RUM Application Topology Comparison - build 2026-09-28-r6"
    type = "dashboard"
    content = $content
}

$documentJson = ($document | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
$contentJson = ($content | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")

[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-topology-comparison.document.json"), $documentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-topology-comparison.content.json"), $contentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-topology-comparison-build-20260928-r6.document.json"), $documentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-topology-comparison-build-20260928-r6.content.json"), $contentJson + "`n", $utf8NoBom)

Write-Host "Generated side-by-side topology dashboard with $($tiles.Count) tiles and $((Get-ChildItem -LiteralPath $queriesDirectory -Filter '*.dql' -File).Count) queries."
