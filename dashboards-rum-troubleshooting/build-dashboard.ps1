$ErrorActionPreference = "Stop"

$outputDirectory = $PSScriptRoot
$queriesDirectory = Join-Path $outputDirectory "queries"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $queriesDirectory | Out-Null
Get-ChildItem -LiteralPath $queriesDirectory -Filter "*.dql" -File | Remove-Item -Force

$querySettings = [ordered]@{
    maxResultRecords = 500
    defaultScanLimitGbytes = 2
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
        @([string][char]0x2192, "->"),
        @([string][char]0x2212, "-"),
        @([string][char]0x2264, "<="),
        @([string][char]0x2265, ">=")
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
        [Parameter(Mandatory)][string]$Visualization,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $visualizationSettings = [ordered]@{ autoSelectVisualization = $false }
    if ($Visualization -eq "table") {
        $visualizationSettings["table"] = [ordered]@{
            rowDensity = "condensed"
            columnWidthStrategy = "content"
            enableSparklines = $false
            linewrapEnabled = $true
        }
    }

    $asciiQuery = ConvertTo-AsciiText -Text ($Query.Trim())
    $tiles[$Id] = [ordered]@{
        type = "data"
        title = ConvertTo-AsciiText -Text $Title
        description = ConvertTo-AsciiText -Text $Description
        query = $asciiQuery
        visualization = $Visualization
        visualizationSettings = $visualizationSettings
        querySettings = [ordered]@{
            maxResultRecords = $querySettings.maxResultRecords
            defaultScanLimitGbytes = $querySettings.defaultScanLimitGbytes
            maxResultMegaBytes = $querySettings.maxResultMegaBytes
            defaultSamplingRatio = $querySettings.defaultSamplingRatio
            enableSampling = $querySettings.enableSampling
        }
    }
    $layouts[$Id] = [ordered]@{ x = $X; y = $Y; w = $Width; h = $Height }

    $queryPath = Join-Path $queriesDirectory "$Id.dql"
    [System.IO.File]::WriteAllText($queryPath, $asciiQuery + "`n", $utf8NoBom)
}

Add-MarkdownTile -Id "intro" -X 0 -Y 0 -Width 24 -Height 5 -Content @'
# RUM Agentless Pair Diagnostic

**Build: 2026-09-28-r5 - cross-environment ownership**

Compare any two web frontends in a chained navigation: **upstream -> target**. The dashboard now also exposes homologation and production domains that report through the same instrumentation ID, including URLs assigned to an unrelated frontend.

> Cost guard: every telemetry query ignores a larger global timeframe and is capped by `analysis_window_minutes` at 15, 30, or 60 minutes. Default: 15 minutes.
'@

Add-MarkdownTile -Id "configuration" -X 0 -Y 5 -Width 24 -Height 4 -Content @'
### Required setup

Select `frontend_upstream` and `frontend_target` from the automatic catalog. Use a stable `target_url` fragment shared by homologation and production when you need to expose both domains. Keep RUM enabled on the Apache process group for frontend/backend correlation; suppress only automatic JavaScript injection with an application-level `DoNotInject` rule when the page already contains the Agentless/manual tag. Use `session_id`, `request_url`, and `trace_id` only for drill-down.
'@

Add-MarkdownTile -Id "section_status" -X 0 -Y 9 -Width 24 -Height 2 -Content @'
## 01 - Agentless state and diagnostic matrix

Checks whether the upstream frontend is still collecting, whether the target is collecting, whether the target URL was assigned to upstream or any unrelated frontend, instrumentation cardinality, request production, and trace coverage.
'@

Add-DataTile -Id "diagnostic_matrix" -Title "Agentless checks - Status - Evidence" -Description "One bounded user.events scan consolidates the core checks for the selected frontend pair." -Visualization "table" -X 0 -Y 11 -Width 24 -Height 10 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| fieldsAdd observed_url = coalesce(page.url.full, view.url.full, url.full)
| filter in(frontend.name, array($frontend_upstream, $frontend_target))
    or (stringLength($upstream_url) > 0 and contains(observed_url, $upstream_url:triplequote, caseSensitive: false))
    or (stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false))
| summarize {
    upstream_events = countIf(frontend.name == $frontend_upstream),
    target_events = countIf(frontend.name == $frontend_target),
    unknown_url_events = countIf(isNull(frontend.name)),
    upstream_last_seen = max(if(frontend.name == $frontend_upstream, start_time)),
    target_last_seen = max(if(frontend.name == $frontend_target, start_time)),
    upstream_id_count = countDistinctExact(if(frontend.name == $frontend_upstream, dt.rum.instrumentation.id)),
    target_id_count = countDistinctExact(if(frontend.name == $frontend_target, dt.rum.instrumentation.id)),
    target_url_events = countIf(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false)),
    target_url_in_upstream = countIf(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false) and frontend.name == $frontend_upstream),
    target_url_in_target = countIf(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false) and frontend.name == $frontend_target),
    target_url_in_other = countIf(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false) and isNotNull(frontend.name) and frontend.name != $frontend_upstream and frontend.name != $frontend_target),
    unexpected_target_frontends = collectDistinct(if(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false) and isNotNull(frontend.name) and frontend.name != $frontend_upstream and frontend.name != $frontend_target, frontend.name)),
    target_requests = countIf(frontend.name == $frontend_target and characteristics.has_request),
    traced_target_requests = countIf(frontend.name == $frontend_target and characteristics.has_request and isNotNull(trace.id))
  }
| fieldsAdd
    target_mapping_pct = if(target_url_events > 0, 100.0 * target_url_in_target / target_url_events),
    trace_coverage_pct = if(target_requests > 0, 100.0 * traced_target_requests / target_requests)
| fieldsAdd checks = array(
    record(
        Check = "Upstream RUM state",
        Status = if($upstream_rum_expected == "DISABLED",
            if(upstream_events == 0, "OK", else: "CRITICAL"),
            else: if(upstream_events > 0, "OK", else: "WARNING")),
        Evidence = concat("expected=", $upstream_rum_expected, "; events=", toString(upstream_events), "; last=", coalesce(toString(upstream_last_seen), "none"))),
    record(
        Check = "Target RUM detected",
        Status = if(target_events > 0, "OK", else: "CRITICAL"),
        Evidence = concat(toString(target_events), " events; last=", coalesce(toString(target_last_seen), "none"))),
    record(
        Check = "Target URL assigned to target frontend",
        Status = if(stringLength($target_url) == 0, "NOT_CONFIGURED",
            else: if(target_url_events == 0, "WARNING",
            else: if(target_url_in_upstream > 0 or target_url_in_other > 0, "CRITICAL",
            else: if(target_url_in_target > 0, "OK", else: "WARNING")))),
        Evidence = concat(toString(target_url_in_target), "/", toString(target_url_events), " in target; ", toString(target_url_in_upstream), " in upstream; ", toString(target_url_in_other), " in unrelated frontends ", toString(unexpected_target_frontends))),
    record(
        Check = "Upstream instrumentation IDs",
        Status = if($upstream_rum_expected == "DISABLED" and upstream_id_count == 0, "OK",
            else: if(upstream_id_count <= 1, "OK", else: "WARNING")),
        Evidence = concat(toString(upstream_id_count), " IDs")),
    record(
        Check = "Target instrumentation IDs",
        Status = if(target_id_count == 1, "OK", else: if(target_id_count == 0, "CRITICAL", else: "WARNING")),
        Evidence = concat(toString(target_id_count), " IDs")),
    record(
        Check = "Target requests detected",
        Status = if(target_requests > 0, "OK", else: "WARNING"),
        Evidence = concat(toString(target_requests), " requests")),
    record(
        Check = "Frontend trace context coverage",
        Status = if(target_requests == 0, "NO_DATA",
            else: if(trace_coverage_pct >= 80, "OK",
            else: if(trace_coverage_pct >= 50, "WARNING", else: "CRITICAL"))),
        Evidence = concat(toString(traced_target_requests), "/", toString(target_requests), " requests with trace.id")),
    record(
        Check = "Configured URLs without frontend",
        Status = if(unknown_url_events == 0, "OK", else: "WARNING"),
        Evidence = concat(toString(unknown_url_events), " URL-matched events without frontend"))
  )
| fields checks
| expand checks
| fields Check = checks[Check], Status = checks[Status], Evidence = checks[Evidence]
'@

Add-MarkdownTile -Id "section_mapping" -X 0 -Y 21 -Width 24 -Height 2 -Content @'
## 02 - Instrumentation overlap and URL ownership

The same instrumentation ID across multiple domains exposes homologation/production mixing. A target URL recorded under upstream or any unrelated frontend points to a copied Agentless tag, competing injection, stale HTML/cache, or an auto-injected detection rule with higher precedence.
'@

Add-DataTile -Id "instrumentation_overlap" -Title "Instrumentation IDs across frontends and domains" -Description "CRITICAL means one ID appeared under multiple frontends; WARNING means one ID appeared on multiple domains and requires environment review." -Visualization "table" -X 0 -Y 23 -Width 12 -Height 9 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| fieldsAdd
    observed_url = coalesce(page.url.full, view.url.full, url.full),
    observed_domain = coalesce(page.url.domain, view.url.domain, url.domain)
| filter in(frontend.name, array($frontend_upstream, $frontend_target))
    or (stringLength($upstream_url) > 0 and contains(observed_url, $upstream_url:triplequote, caseSensitive: false))
    or (stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false))
| filter isNotNull(dt.rum.instrumentation.id)
| summarize
    Events = count(),
    Sessions = countDistinct(dt.rum.session.id),
    Frontends = collectDistinct(frontend.name),
    Domains = collectDistinct(observed_domain),
    `Agent types` = collectDistinct(dt.rum.agent.type),
    `First seen` = min(start_time),
    `Last seen` = max(start_time),
    by: {`Instrumentation ID` = dt.rum.instrumentation.id}
| fieldsAdd Status = if(arraySize(Frontends) > 1, "CRITICAL", else: if(arraySize(Domains) > 1, "WARNING", else: "OK"))
| fields Status, `Instrumentation ID`, Frontends, Domains, `Agent types`, Events, Sessions, `First seen`, `Last seen`
| sort Events desc
| limit 100
'@

Add-DataTile -Id "url_ownership" -Title "URL, environment, and frontend ownership" -Description "Reads configured URLs across every frontend, so assignment to an unrelated application is not hidden by the selected pair." -Visualization "table" -X 12 -Y 23 -Width 12 -Height 9 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| fieldsAdd
    observed_url = coalesce(page.url.full, view.url.full, url.full),
    observed_domain = coalesce(page.url.domain, view.url.domain, url.domain, "(unknown)")
| filter isNotNull(observed_url)
    and ((stringLength($upstream_url) > 0 and contains(observed_url, $upstream_url:triplequote, caseSensitive: false))
      or (stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false)))
| fieldsAdd
    `URL scope` = if(stringLength($target_url) > 0 and contains(observed_url, $target_url:triplequote, caseSensitive: false), "TARGET", else: "UPSTREAM"),
    `Observed frontend` = coalesce(frontend.name, "(unknown)")
| fieldsAdd `Expected frontend` = if(`URL scope` == "TARGET", $frontend_target, else: $frontend_upstream)
| summarize
    Events = count(),
    Sessions = countDistinct(dt.rum.session.id),
    `Sample URL` = takeAny(observed_url),
    by: {`URL scope`, `Observed domain` = observed_domain, `Expected frontend`, `Observed frontend`, `Instrumentation ID` = dt.rum.instrumentation.id}
| fieldsAdd Status = if(`Observed frontend` == `Expected frontend`, "OK", else: "CRITICAL")
| fields Status, `URL scope`, `Observed domain`, `Expected frontend`, `Observed frontend`, `Instrumentation ID`, Events, Sessions, `Sample URL`
| sort Events desc
| limit 100
'@

Add-MarkdownTile -Id "section_sessions" -X 0 -Y 32 -Width 24 -Height 2 -Content @'
## 03 - Session continuity and focused timeline

Continuity is evidence, not proof of correctness. The comparison is bounded to at most 60 minutes; use `session_id` for a focused event timeline.
'@

Add-DataTile -Id "session_continuity" -Title "Recent sessions across the frontend pair" -Description "Shows up to 100 recent session IDs and classifies their observed presence across upstream and target." -Visualization "table" -X 0 -Y 34 -Width 12 -Height 10 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| filter in(frontend.name, array($frontend_upstream, $frontend_target)) and isNotNull(dt.rum.session.id)
| summarize
    `Upstream events` = countIf(frontend.name == $frontend_upstream),
    `Target events` = countIf(frontend.name == $frontend_target),
    `First event` = min(start_time),
    `Last event` = max(start_time),
    Events = count(),
    by: {`Session ID` = dt.rum.session.id}
| fieldsAdd Classification = if(`Upstream events` > 0 and `Target events` > 0, "CONTINUOUS",
    else: if(`Upstream events` > 0, "UPSTREAM_ONLY", else: "TARGET_ONLY"))
| fieldsAdd `Observed duration` = `Last event` - `First event`
| fields Classification, `Session ID`, `Upstream events`, `Target events`, Events, `First event`, `Last event`, `Observed duration`
| sort `Last event` desc
| limit 100
'@

Add-DataTile -Id "session_timeline" -Title "Timeline for one session" -Description "No useful scan is intended until session_id is filled; results are limited to 300 events." -Visualization "table" -X 12 -Y 34 -Width 12 -Height 10 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| filter dt.rum.session.id == $session_id
| fieldsAdd `Event type` = if(characteristics.is_invalid, "INVALID",
    else: if(characteristics.has_error, "ERROR",
    else: if(characteristics.has_page_summary, "PAGE_SUMMARY",
    else: if(characteristics.has_view_summary, "VIEW_SUMMARY",
    else: if(characteristics.has_user_action, "USER_ACTION",
    else: if(characteristics.has_navigation, "NAVIGATION",
    else: if(characteristics.has_user_interaction, "USER_INTERACTION",
    else: if(characteristics.has_request, "REQUEST", else: "OTHER"))))))))
| fields
    Timestamp = start_time,
    Frontend = frontend.name,
    `Page/View URL` = coalesce(page.url.full, view.url.full),
    `Event type`,
    `User action` = coalesce(user_action.custom_name, user_action.type, interaction.type),
    `Request URL` = url.full,
    `Request method` = http.request.method,
    `Status code` = http.response.status_code,
    `Trace ID` = trace.id,
    `Instrumentation ID` = dt.rum.instrumentation.id
| sort Timestamp asc
| limit 300
'@

Add-MarkdownTile -Id "section_requests" -X 0 -Y 44 -Width 24 -Height 2 -Content @'
## 04 - Target requests and frontend/backend handoff

Requests are grouped by domain and path, not full URL, to avoid query-string cardinality. Copy a sample trace ID into `trace_id` for an exact backend lookup.
'@

Add-DataTile -Id "target_requests" -Title "Requests emitted by the target frontend" -Description "Combines volume, failures, latency, sessions, and trace coverage in one bounded scan." -Visualization "table" -X 0 -Y 46 -Width 24 -Height 10 -Query @'
fetch user.events, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| filter frontend.name == $frontend_target and characteristics.has_request
| fieldsAdd request_target = coalesce(url.full, url.path, "")
| filter contains(request_target, $request_url:triplequote, caseSensitive: false)
| summarize
    Calls = count(),
    Failures = countIf(characteristics.has_failed_request),
    Sessions = countDistinct(dt.rum.session.id),
    Traced = countIf(isNotNull(trace.id)),
    `p50 ms` = percentile(duration, 50) / 1ms,
    `p95 ms` = percentile(duration, 95) / 1ms,
    `Sample trace ID` = takeAny(if(isNotNull(trace.id), toString(trace.id))),
    `Sample session ID` = takeAny(dt.rum.session.id),
    by: {Domain = url.domain, Path = url.path, Method = http.request.method, Status = http.response.status_code}
| fieldsAdd `Trace coverage %` = round(100.0 * Traced / Calls, decimals: 1)
| fields Domain, Path, Method, Status, Calls, Failures, Sessions, Traced, `Trace coverage %`, `p50 ms`, `p95 ms`, `Sample trace ID`, `Sample session ID`
| sort Calls desc
| limit 100
'@

Add-MarkdownTile -Id "section_topology" -X 0 -Y 56 -Width 24 -Height 2 -Content @'
## 05 - Frontend to services and observed servers

The left table uses current Smartscape `calls` relationships for either FRONTEND or Web Application node types. The right table requires one exact `trace_id` and shows only hosts and processes observed in that request; it does not run a broad server inventory.
'@

Add-DataTile -Id "frontend_services" -Title "Services linked to the selected web applications" -Description "Current Smartscape calls relationships. Source type and entity IDs keep the mapping explicit when names are duplicated." -Visualization "table" -X 0 -Y 58 -Width 12 -Height 10 -Query @'
smartscapeEdges "calls"
| filter target_type == "SERVICE"
| fieldsAdd
    `Frontend / Web application` = getNodeName(source_id),
    `Frontend type` = source_type,
    Service = getNodeName(target_id),
    `Edge kind` = dt.system.edge_kind
| filter in(`Frontend / Web application`, array($frontend_upstream, $frontend_target))
| dedup source_id, target_id
| fields
    `Frontend / Web application`,
    `Frontend type`,
    `Frontend ID` = source_id,
    Relation = type,
    Service,
    `Service ID` = target_id,
    `Edge kind`
| sort `Frontend / Web application` asc, Service asc
| limit 100
'@

Add-DataTile -Id "frontend_servers" -Title "Servers observed for the selected trace" -Description "Exact trace lookup grouped by service, host, and process group. This preserves the single bounded spans scan." -Visualization "table" -X 12 -Y 58 -Width 12 -Height 10 -Query @'
fetch spans, from: now() - duration(toLong($analysis_window_minutes:noquote), unit: "m")
| fieldsAdd selected_trace_id = if(stringLength($trace_id) > 0, $trace_id, else: "00000000000000000000000000000000")
| filter trace.id == toUid(selected_trace_id)
| filter isNotNull(dt.smartscape.host)
| summarize
    `Observed spans` = count(),
    `Failed spans` = countIf(request.is_failed == true),
    `First span` = min(start_time),
    `Last span` = max(start_time),
    by:{dt.smartscape.service, dt.smartscape.host, dt.process_group.detected_name}
| fields
    Service = getNodeName(dt.smartscape.service),
    `Service ID` = dt.smartscape.service,
    Server = getNodeName(dt.smartscape.host),
    `Host ID` = dt.smartscape.host,
    `Process group` = dt.process_group.detected_name,
    `Observed spans`,
    `Failed spans`,
    `First span`,
    `Last span`
| sort `Observed spans` desc, Service asc, Server asc
| limit 100
'@

Add-MarkdownTile -Id "footer" -X 0 -Y 68 -Width 24 -Height 5 -Content @'
### Recommended decision order

1. Compare domains listed for each instrumentation ID. 2. Confirm that the target URL maps only to the intended frontend, including rows outside the selected pair. 3. Keep RUM enabled on the Apache process group and use `DoNotInject` to prevent duplicate JavaScript. 4. Inspect a recent session. 5. Inspect target requests. 6. Copy one page-load or request trace ID to prove which service, process group, and host served it. Old browser tabs and cached HTML can continue reporting the previous ID for a while.
'@

$variables = @(
    [ordered]@{
        version = 2
        key = "analysis_window_minutes"
        type = "csv"
        visible = $true
        editable = $true
        input = "15,30,60"
        multiple = $false
    },
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
    },
    [ordered]@{
        version = 2
        key = "upstream_rum_expected"
        type = "csv"
        visible = $true
        editable = $true
        input = "DISABLED,ENABLED"
        multiple = $false
    },
    [ordered]@{ version = 2; key = "upstream_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "target_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "session_id"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "request_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "trace_id"; type = "text"; visible = $true; editable = $true; defaultValue = "" }
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
    name = "RUM Diagnostic Explorer - build 2026-09-28-r5"
    type = "dashboard"
    content = $content
}

$documentJson = ($document | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
$contentJson = ($content | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")

[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer.document.json"), $documentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer.content.json"), $contentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer-build-20260928-r5.document.json"), $documentJson + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer-build-20260928-r5.content.json"), $contentJson + "`n", $utf8NoBom)

Write-Host "Generated cost-bounded dashboard files and $($tiles.Count) tile definitions."
