$ErrorActionPreference = "Stop"

$outputDirectory = $PSScriptRoot
$queriesDirectory = Join-Path $outputDirectory "queries"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $queriesDirectory | Out-Null

$querySettings = [ordered]@{
    maxResultRecords = 1000
    defaultScanLimitGbytes = 100
    maxResultMegaBytes = 20
    defaultSamplingRatio = 1
    enableSampling = $false
}

$tiles = [ordered]@{}
$layouts = [ordered]@{}

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
        content = $Content
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

    $tiles[$Id] = [ordered]@{
        type = "data"
        title = $Title
        description = $Description
        query = $Query.Trim()
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
    [System.IO.File]::WriteAllText($queryPath, $Query.Trim() + [Environment]::NewLine, $utf8NoBom)
}

Add-MarkdownTile -Id "intro" -X 0 -Y 0 -Width 24 -Height 5 -Content @'
# RUM Diagnostic Explorer

Troubleshooting técnico de RUM Agentless no fluxo **HUB → Apache/proxy → WAS → AngularJS → XHR/AJAX → backend**. O painel procura evidências de mapeamento incorreto de frontend, sobreposição de instrumentation IDs, continuidade de sessão e lacunas aparentes de correlação frontend/backend.

> Comece com **15–30 minutos** e amplie para **1 hora** somente quando necessário. Todos os tiles herdam o timeframe global. Os estados `WARNING` e `CRITICAL` são hipóteses de triagem, não prova de causalidade.
'@

Add-MarkdownTile -Id "scope_note" -X 0 -Y 5 -Width 24 -Height 4 -Content @'
### Configuração rápida

Selecione `frontend_hub` e `frontend_application`; informe fragmentos estáveis em `hub_url` e `application_url` (domínio ou caminho, sem curingas). `session_id`, `request_url` e `service_name` são opcionais e restringem os drill-downs. URL completa pode estar mascarada; nesse caso use um fragmento preservado ou consulte `page.name`/`view.name` nas alternativas do README.
'@

Add-MarkdownTile -Id "section_01" -X 0 -Y 9 -Width 24 -Height 2 -Content @'
## 01 · Status geral

Confirma volume, sessões, instrumentação e requests antes do drill-down. Ausência de dados pode significar timeframe inadequado, atraso de ingestão ou RUM não observado.
'@

Add-DataTile -Id "status_rum_volume" -Title "Eventos e continuidade por frontend" -Description "Volume do HUB e da aplicação, sessões únicas e interseção de session IDs no período." -Visualization "table" -X 0 -Y 11 -Width 8 -Height 7 -Query @'
fetch user.events
| filter in(frontend.name, array($frontend_hub, $frontend_application))
| filter isNotNull(dt.rum.session.id)
| summarize {
    hub_events = countIf(frontend.name == $frontend_hub),
    application_events = countIf(frontend.name == $frontend_application)
  }, by: {dt.rum.session.id}
| summarize {
    `HUB events` = sum(hub_events),
    `Application events` = sum(application_events),
    `HUB sessions` = countIf(hub_events > 0),
    `Application sessions` = countIf(application_events > 0),
    `Shared sessions` = countIf(hub_events > 0 and application_events > 0)
  }
'@

Add-DataTile -Id "status_instrumentation" -Title "Instrumentation IDs e frontend desconhecido" -Description "Conta IDs distintos por frontend e eventos sem frontend identificado." -Visualization "table" -X 8 -Y 11 -Width 8 -Height 7 -Query @'
fetch user.events
| summarize {
    `HUB instrumentation IDs` = countDistinctExact(if(frontend.name == $frontend_hub, dt.rum.instrumentation.id)),
    `Application instrumentation IDs` = countDistinctExact(if(frontend.name == $frontend_application, dt.rum.instrumentation.id)),
    `Events without frontend` = countIf(isNull(frontend.name) or frontend.name == "")
  }
'@

Add-DataTile -Id "status_requests" -Title "Requests RUM da aplicação" -Description "Requests, falhas, endpoints e sessões afetadas do frontend AngularJS selecionado." -Visualization "table" -X 16 -Y 11 -Width 8 -Height 7 -Query @'
fetch user.events
| summarize {
    `Frontend requests` = countIf(frontend.name == $frontend_application and characteristics.has_request),
    `Failed requests` = countIf(frontend.name == $frontend_application and characteristics.has_failed_request),
    `Distinct request URLs` = countDistinct(if(frontend.name == $frontend_application and characteristics.has_request, url.full)),
    `Request sessions` = countDistinct(if(frontend.name == $frontend_application and characteristics.has_request, dt.rum.session.id))
  }
'@

Add-MarkdownTile -Id "section_02" -X 0 -Y 18 -Width 24 -Height 2 -Content @'
## 02 · Frontend × instrumentation ID

Mais de um ID no mesmo frontend ou um ID compartilhado entre HUB e AngularJS é evidência para revisar regras de detecção e método de injeção.
'@

Add-DataTile -Id "frontend_instrumentation" -Title "Frontend × instrumentation ID × agent" -Description "Inventário de combinações observadas, incluindo eventos sem frontend ou sem instrumentation ID." -Visualization "table" -X 0 -Y 20 -Width 16 -Height 9 -Query @'
fetch user.events
| filter in(frontend.name, array($frontend_hub, $frontend_application)) or isNull(frontend.name)
| fieldsAdd
    Frontend = coalesce(frontend.name, "UNKNOWN_FRONTEND"),
    `Instrumentation ID` = coalesce(dt.rum.instrumentation.id, "NOT_OBSERVED"),
    `Agent type` = coalesce(dt.rum.agent.type, "NOT_OBSERVED")
| summarize Events = count(), Sessions = countDistinct(dt.rum.session.id), by: {Frontend, `Instrumentation ID`, `Agent type`}
| sort Events desc
| limit 100
'@

Add-DataTile -Id "shared_instrumentation" -Title "IDs compartilhados entre frontends" -Description "Mostra somente instrumentation IDs observados em mais de um frontend selecionado." -Visualization "table" -X 16 -Y 20 -Width 8 -Height 9 -Query @'
fetch user.events
| filter in(frontend.name, array($frontend_hub, $frontend_application))
| filter isNotNull(dt.rum.instrumentation.id)
| summarize
    Frontends = collectDistinct(frontend.name),
    Events = count(),
    Sessions = countDistinct(dt.rum.session.id),
    by: {`Instrumentation ID` = dt.rum.instrumentation.id}
| fieldsAdd `Frontend count` = arraySize(Frontends), Status = if(arraySize(Frontends) > 1, "WARNING", else: "OK")
| filter `Frontend count` > 1
| fields `Instrumentation ID`, Frontends = toString(Frontends), Events, Sessions, Status
| sort Events desc
| limit 50
'@

Add-MarkdownTile -Id "section_03" -X 0 -Y 29 -Width 24 -Height 2 -Content @'
## 03 · URL → frontend e navegação

A URL AngularJS atribuída ao HUB é um forte indicador de mapeamento inesperado. Redirecionamentos e navegações são exibidos como evidência; não provam sozinhos erro de sessão.
'@

Add-DataTile -Id "url_frontend_detail" -Title "URL → frontend → instrumentation ID" -Description "Descobre qual frontend recebeu eventos das URLs configuradas e evidencia a mesma URL em frontends diferentes." -Visualization "table" -X 0 -Y 31 -Width 14 -Height 10 -Query @'
fetch user.events
| fieldsAdd `Observed URL` = coalesce(page.url.full, view.url.full, url.full)
| filter isNotNull(`Observed URL`)
| filter
    ($hub_url != "" and contains(`Observed URL`, $hub_url:triplequote, false)) or
    ($application_url != "" and contains(`Observed URL`, $application_url:triplequote, false))
| summarize
    Events = count(),
    Sessions = countDistinct(dt.rum.session.id),
    by: {`Observed URL`, Frontend = frontend.name, `Instrumentation ID` = dt.rum.instrumentation.id}
| sort Events desc
| limit 100
'@

Add-DataTile -Id "url_mapping_status" -Title "Mapeamento esperado × observado" -Description "CRITICAL indica URL do HUB/aplicação recebida por um frontend diferente do configurado." -Visualization "table" -X 14 -Y 31 -Width 10 -Height 10 -Query @'
fetch user.events
| fieldsAdd observed_url = coalesce(page.url.full, view.url.full, url.full)
| filter isNotNull(observed_url)
| filter
    ($hub_url != "" and contains(observed_url, $hub_url:triplequote, false)) or
    ($application_url != "" and contains(observed_url, $application_url:triplequote, false))
| fieldsAdd `URL scope` = if(
    $application_url != "" and contains(observed_url, $application_url:triplequote, false), "APPLICATION_URL",
    else: "HUB_URL")
| fieldsAdd `Expected frontend` = if(`URL scope` == "APPLICATION_URL", $frontend_application, else: $frontend_hub)
| summarize Events = count(), Sessions = countDistinct(dt.rum.session.id), by: {`URL scope`, `Expected frontend`, `Observed frontend` = frontend.name}
| fieldsAdd
    Status = if(`Observed frontend` == `Expected frontend`, "OK", else: "CRITICAL"),
    Severity = if(`Observed frontend` == `Expected frontend`, 0, else: 2)
| sort Severity desc, Events desc
| fieldsRemove Severity
'@

Add-DataTile -Id "navigation_redirects" -Title "Navegações e redirecionamentos observados" -Description "Compara hard/soft navigation, origem e destino entre HUB e AngularJS." -Visualization "table" -X 0 -Y 41 -Width 24 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_navigation
| filter in(frontend.name, array($frontend_hub, $frontend_application))
| fieldsAdd
    Source = coalesce(page.source.url.full, view.source.url.full, view.source.name, "NOT_OBSERVED"),
    Destination = coalesce(page.url.full, view.url.full, page.name, view.name, "NOT_OBSERVED")
| filter
    ($hub_url == "" and $application_url == "") or
    ($hub_url != "" and (contains(Source, $hub_url:triplequote, false) or contains(Destination, $hub_url:triplequote, false))) or
    ($application_url != "" and (contains(Source, $application_url:triplequote, false) or contains(Destination, $application_url:triplequote, false)))
| summarize Events = count(), Sessions = countDistinct(dt.rum.session.id), by: {Frontend = frontend.name, `Navigation type` = navigation.type, `Performance type` = performance.type, Source, Destination}
| sort Events desc
| limit 50
'@

Add-MarkdownTile -Id "section_04" -X 0 -Y 51 -Width 24 -Height 2 -Content @'
## 04 · Sessões que atravessam HUB e AngularJS

`CONTINUOUS` significa que o mesmo session ID foi observado nos dois frontends. `HUB_ONLY` e `APP_ONLY` são indicadores para investigação, não uma classificação automática de sessão quebrada.
'@

Add-DataTile -Id "session_continuity" -Title "Continuidade por session ID" -Description "Reconstrói o escopo de cada sessão e classifica a presença nos frontends selecionados." -Visualization "table" -X 0 -Y 53 -Width 16 -Height 11 -Query @'
fetch user.events
| filter isNotNull(dt.rum.session.id)
| summarize {
    Frontends = arrayRemoveNulls(collectDistinct(frontend.name)),
    `First event` = min(start_time),
    `Last event` = max(start_time),
    Events = count(),
    hub_events = countIf(frontend.name == $frontend_hub),
    application_events = countIf(frontend.name == $frontend_application)
  }, by: {`Session ID` = dt.rum.session.id}
| filter hub_events > 0 or application_events > 0
| fieldsAdd
    Classification = if(hub_events > 0 and application_events > 0 and arraySize(Frontends) > 2, "MULTI_FRONTEND",
      else: if(hub_events > 0 and application_events > 0, "CONTINUOUS",
      else: if(hub_events > 0, "HUB_ONLY", else: "APP_ONLY"))),
    `Approx. duration` = `Last event` - `First event`
| fields `Session ID`, `Frontends found` = toString(Frontends), Classification, `First event`, `Last event`, Events, `Approx. duration`
| sort `Last event` desc
| limit 100
'@

Add-DataTile -Id "session_classification" -Title "Distribuição das sessões" -Description "Distribuição das classificações sem inferir causa." -Visualization "categoricalBarChart" -X 16 -Y 53 -Width 8 -Height 11 -Query @'
fetch user.events
| filter isNotNull(dt.rum.session.id)
| summarize {
    frontends = arrayRemoveNulls(collectDistinct(frontend.name)),
    hub_events = countIf(frontend.name == $frontend_hub),
    application_events = countIf(frontend.name == $frontend_application)
  }, by: {dt.rum.session.id}
| filter hub_events > 0 or application_events > 0
| fieldsAdd Classification = if(hub_events > 0 and application_events > 0 and arraySize(frontends) > 2, "MULTI_FRONTEND",
    else: if(hub_events > 0 and application_events > 0, "CONTINUOUS",
    else: if(hub_events > 0, "HUB_ONLY", else: "APP_ONLY")))
| summarize Sessions = count(), by: {Classification}
| sort Sessions desc
'@

Add-MarkdownTile -Id "section_05" -X 0 -Y 64 -Width 24 -Height 2 -Content @'
## 05 · Timeline de uma sessão

Preencha `session_id`. A ordem cronológica mostra frontend, URL, navegação, ação, request e instrumentação. Uma nova session ID após a troca de aplicação exige contexto adicional antes de ser tratada como falha.
'@

Add-DataTile -Id "session_timeline" -Title "Timeline técnica da sessão" -Description "Eventos em ordem cronológica para reconstruir HUB → navegação → AngularJS → XHR → backend." -Visualization "table" -X 0 -Y 66 -Width 24 -Height 12 -Query @'
fetch user.events
| filter $session_id != "" and dt.rum.session.id == $session_id
// O tipo é derivado das características; characteristics.classifier não representa toda a combinação do evento.
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
| limit 500
'@

Add-MarkdownTile -Id "section_06" -X 0 -Y 78 -Width 24 -Height 2 -Content @'
## 06 · Requests do frontend

Mostra o que o AngularJS efetivamente chamou. Use `request_url` para restringir domínio, caminho ou endpoint; vazio mantém todas as requests do frontend selecionado.
'@

Add-DataTile -Id "frontend_requests" -Title "Requests observadas no AngularJS" -Description "URL, método, status, volume, falhas, sessões e vínculo de user action quando disponível." -Visualization "table" -X 0 -Y 80 -Width 16 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_request
| filter frontend.name == $frontend_application
| filter $request_url == "" or contains(url.full, $request_url:triplequote, false)
| fieldsAdd `User action` = coalesce(user_action.custom_name, user_action.type, toString(user_action.instance_id), "NOT_OBSERVED")
| summarize
    Calls = count(),
    Errors = countIf(characteristics.has_failed_request or http.response.status_code >= 400),
    Sessions = countDistinct(dt.rum.session.id),
    by: {Frontend = frontend.name, `Request URL` = url.full, `HTTP method` = http.request.method, `HTTP status` = http.response.status_code, `User action`}
| sort Calls desc
| limit 100
'@

Add-DataTile -Id "request_trend" -Title "Requests, falhas e requests com trace" -Description "Tendência de volumes no timeframe global; a distância entre Requests e Traced indica onde medir cobertura." -Visualization "lineChart" -X 16 -Y 80 -Width 8 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_request
| filter frontend.name == $frontend_application
| filter $request_url == "" or contains(url.full, $request_url:triplequote, false)
| makeTimeseries {
    Requests = count(),
    Errors = countIf(characteristics.has_failed_request),
    Traced = countIf(isNotNull(trace.id))
  }
'@

Add-MarkdownTile -Id "section_07" -X 0 -Y 90 -Width 24 -Height 2 -Content @'
## 07 · Requests com erro ou lentidão

`NO_STATUS_OBSERVED` significa apenas que nenhum status HTTP foi capturado. Não equivale automaticamente a timeout, cancelamento ou ausência de resposta. O painel não inventa um campo de cancelamento inexistente no modelo semântico atual.
'@

Add-DataTile -Id "request_errors" -Title "4xx, 5xx e status não observado" -Description "Agrupa requests com falha, status HTTP de erro ou ausência de status; inclui p50 e p95." -Visualization "table" -X 0 -Y 92 -Width 12 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_request
| filter frontend.name == $frontend_application
| filter $request_url == "" or contains(url.full, $request_url:triplequote, false)
| filter characteristics.has_failed_request or http.response.status_code >= 400 or isNull(http.response.status_code)
| fieldsAdd `Status class` = if(http.response.status_code >= 500, "HTTP_5XX",
    else: if(http.response.status_code >= 400, "HTTP_4XX",
    else: if(isNull(http.response.status_code), "NO_STATUS_OBSERVED", else: "OTHER")))
| summarize
    Calls = count(),
    Errors = countIf(characteristics.has_failed_request or http.response.status_code >= 400),
    Sessions = countDistinct(dt.rum.session.id),
    `p50 ms` = percentile(duration, 50) / 1ms,
    `p95 ms` = percentile(duration, 95) / 1ms,
    by: {Request = url.full, Status = http.response.status_code, `Status class`, Frontend = frontend.name}
| sort Errors desc, Calls desc
| limit 100
'@

Add-DataTile -Id "slow_requests" -Title "Requests lentas" -Description "Threshold operacional inicial de 2 s; ajuste a interpretação ao SLA real da aplicação." -Visualization "table" -X 12 -Y 92 -Width 12 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_request
| filter frontend.name == $frontend_application
| filter $request_url == "" or contains(url.full, $request_url:triplequote, false)
| filter duration > 2s
| summarize
    Calls = count(),
    Sessions = countDistinct(dt.rum.session.id),
    `p50 ms` = percentile(duration, 50) / 1ms,
    `p95 ms` = percentile(duration, 95) / 1ms,
    `Max ms` = max(duration) / 1ms,
    by: {Request = url.full, `HTTP method` = http.request.method, `HTTP status` = http.response.status_code}
| sort `p95 ms` desc
| limit 100
'@

Add-MarkdownTile -Id "section_08" -X 0 -Y 102 -Width 24 -Height 2 -Content @'
## 08 · Correlação frontend → backend

`trace.id` no evento RUM prova que contexto de trace foi observado no frontend; spans com link RUM mostram o lado backend. Ausência em qualquer lado deve ser descrita como **Correlation not observed**, nunca como causa definitiva.
'@

Add-DataTile -Id "trace_coverage" -Title "Cobertura de trace por request RUM" -Description "Percentual de requests com trace.id e hints de propagação/Server-Timing." -Visualization "table" -X 0 -Y 104 -Width 8 -Height 10 -Query @'
fetch user.events
| filter characteristics.has_request
| filter frontend.name == $frontend_application
| filter $request_url == "" or contains(url.full, $request_url:triplequote, false)
| summarize
    Requests = count(),
    `Trace ID observed` = countIf(isNotNull(trace.id)),
    `Sampled trace` = countIf(trace.is_sampled == true),
    by: {Request = url.full, `Trace context hint` = request.trace_context_hint, `Server timing hint` = request.server_timing_hint}
| fieldsAdd `Coverage %` = round(100.0 * `Trace ID observed` / Requests, decimals: 1)
| fieldsAdd Status = if(`Coverage %` >= 80, "OK", else: if(`Coverage %` >= 50, "WARNING", else: "CRITICAL"))
| sort Requests desc
| limit 50
'@

Add-DataTile -Id "backend_endpoints" -Title "Backend observado para o filtro" -Description "Root spans compatíveis com request_url/service_name. Não é um join amplo com RUM; use trace ID da timeline para confirmação pontual." -Visualization "table" -X 8 -Y 104 -Width 8 -Height 10 -Query @'
fetch spans
| filter request.is_root_span == true
| filter in($service_name, array("", "(All services)")) or dt.service.name == $service_name
| fieldsAdd request_target = coalesce(url.full, url.path, http.route, endpoint.name, "")
| filter $request_url == "" or contains(request_target, $request_url:triplequote, false)
// Multiplicidade corrige ATM/ALR, agregação de spans e read sampling.
| fieldsAdd sampling_probability = (power(2, 56) - coalesce(sampling.threshold, 0)) * power(2, -56)
| fieldsAdd multiplicity = (1 / sampling_probability) * coalesce(aggregation.count, 1) * dt.system.sampling_ratio
| summarize
    Requests = sum(multiplicity),
    Failures = sum(if(request.is_failed == true, multiplicity, else: 0)),
    `p50 ms` = percentile(duration, 50) / 1ms,
    `p95 ms` = percentile(duration, 95) / 1ms,
    `RUM-linked spans` = countIf(isNotNull(dt.rum.session.id) or dt.rum.is_linking_candidate == true),
    by: {Service = dt.service.name, Endpoint = endpoint.name, Route = http.route}
| sort Requests desc
| limit 50
'@

Add-DataTile -Id "observed_dependencies" -Title "Service → downstream observado" -Description "Chamadas HTTP client vistas em spans para localizar onde a cadeia continua após WAS/backend." -Visualization "table" -X 16 -Y 104 -Width 8 -Height 10 -Query @'
fetch spans
| filter span.kind == "client" and isNotNull(http.request.method)
| filter in($service_name, array("", "(All services)")) or dt.service.name == $service_name
| fieldsAdd downstream = coalesce(server.address, url.domain, endpoint.name, "NOT_OBSERVED")
| filter $request_url == "" or contains(coalesce(url.full, url.path, endpoint.name, downstream), $request_url:triplequote, false)
// Multiplicidade corrige contagens; percentis continuam descrevendo spans observados.
| fieldsAdd sampling_probability = (power(2, 56) - coalesce(sampling.threshold, 0)) * power(2, -56)
| fieldsAdd multiplicity = (1 / sampling_probability) * coalesce(aggregation.count, 1) * dt.system.sampling_ratio
| summarize
    Calls = sum(multiplicity),
    Failures = sum(if(request.is_failed == true or http.response.status_code >= 400, multiplicity, else: 0)),
    `p95 ms` = percentile(duration, 95) / 1ms,
    by: {Caller = dt.service.name, Downstream = downstream, Method = http.request.method}
| sort Calls desc
| limit 50
'@

Add-MarkdownTile -Id "section_09" -X 0 -Y 114 -Width 24 -Height 2 -Content @'
## 09 · Backend services

RED e cauda de latência por serviço. Contagens de spans são extrapoladas por sampling/aggregation; percentis descrevem a distribuição observada.
'@

Add-DataTile -Id "backend_services" -Title "Serviços backend associados" -Description "Requests, falhas, p50/p95/p99 e chamadas downstream por serviço." -Visualization "table" -X 0 -Y 116 -Width 24 -Height 10 -Query @'
fetch spans
| filter in($service_name, array("", "(All services)")) or dt.service.name == $service_name
| filter request.is_root_span == true or span.kind == "client"
// A mesma passagem calcula tráfego de entrada e chamadas client do serviço.
| fieldsAdd sampling_probability = (power(2, 56) - coalesce(sampling.threshold, 0)) * power(2, -56)
| fieldsAdd multiplicity = (1 / sampling_probability) * coalesce(aggregation.count, 1) * dt.system.sampling_ratio
| summarize
    Requests = sum(if(request.is_root_span == true, multiplicity, else: 0)),
    Failures = sum(if(request.is_root_span == true and request.is_failed == true, multiplicity, else: 0)),
    `p50 ms` = percentile(if(request.is_root_span == true, duration), 50) / 1ms,
    `p95 ms` = percentile(if(request.is_root_span == true, duration), 95) / 1ms,
    `p99 ms` = percentile(if(request.is_root_span == true, duration), 99) / 1ms,
    `Downstream calls` = sum(if(span.kind == "client", multiplicity, else: 0)),
    by: {`Service name` = dt.service.name}
| filter Requests > 0
| fieldsAdd `Failure rate %` = round(100.0 * Failures / Requests, decimals: 2)
| sort Requests desc
| limit 100
'@

Add-MarkdownTile -Id "section_10" -X 0 -Y 126 -Width 24 -Height 2 -Content @'
## 10 · Topologia simplificada

Informe `service_name` para limitar a travessia. A visão usa somente um hop de `calls`; Apache/WAS aparecem apenas se forem serviços Smartscape relacionados, sem tentar reproduzir todo o Smartscape.
'@

Add-DataTile -Id "smartscape_dependencies" -Title "Smartscape · dependências de 1 hop" -Description "Serviço selecionado e serviços downstream ligados por calls. Vazio até service_name ser informado." -Visualization "table" -X 0 -Y 128 -Width 24 -Height 9 -Query @'
smartscapeNodes "SERVICE"
| filter not in($service_name, array("", "(All services)")) and name == $service_name
| traverse edgeTypes: {calls}, targetTypes: {SERVICE}, direction: forward
| fields
    Source = dt.traverse.history[0][name],
    Relationship = "calls",
    Target = name,
    `Target ID` = id,
    Hop = 1
| limit 100
'@

Add-MarkdownTile -Id "section_11" -X 0 -Y 137 -Width 24 -Height 2 -Content @'
## 11 · Possíveis anomalias de RUM

Os thresholds abaixo são heurísticas de triagem: mapping incorreto ≥50% é `CRITICAL`; mais de um instrumentation ID é `WARNING`; continuidade <5% e cobertura de trace <80% são `WARNING`. Valide sempre a evidência bruta nos tiles anteriores.
'@

Add-DataTile -Id "possible_anomalies" -Title "Hipóteses diagnósticas" -Description "Agregações separadas de RUM, sessões e spans, sem join amplo entre tabelas." -Visualization "table" -X 0 -Y 139 -Width 24 -Height 9 -Query @'
fetch user.events
| fieldsAdd observed_url = coalesce(page.url.full, view.url.full, url.full)
// Uma agregação reúne os sinais RUM para evitar várias varreduras do mesmo período.
| summarize {
    hub_events = countIf(frontend.name == $frontend_hub),
    application_events = countIf(frontend.name == $frontend_application),
    application_url_events = countIf($application_url != "" and contains(observed_url, $application_url:triplequote, false)),
    application_url_in_hub = countIf($application_url != "" and contains(observed_url, $application_url:triplequote, false) and frontend.name == $frontend_hub),
    hub_id_count = countDistinctExact(if(frontend.name == $frontend_hub, dt.rum.instrumentation.id)),
    application_id_count = countDistinctExact(if(frontend.name == $frontend_application, dt.rum.instrumentation.id)),
    application_requests = countIf(frontend.name == $frontend_application and characteristics.has_request),
    traced_application_requests = countIf(frontend.name == $frontend_application and characteristics.has_request and isNotNull(trace.id))
  }
| fieldsAdd
    wrong_mapping_pct = if(application_url_events > 0, 100.0 * application_url_in_hub / application_url_events),
    trace_coverage_pct = if(application_requests > 0, 100.0 * traced_application_requests / application_requests)
| fieldsAdd checks = array(
    record(Check = "Possible wrong frontend mapping", Status = if($application_url == "", "NOT_CONFIGURED", else: if(wrong_mapping_pct >= 50, "CRITICAL", else: if(wrong_mapping_pct > 0, "WARNING", else: "OK"))), Evidence = concat(toString(round(coalesce(wrong_mapping_pct, 0), decimals: 1)), "% of application URL events observed in HUB")),
    record(Check = "Multiple instrumentation IDs", Status = if(hub_id_count > 1 or application_id_count > 1, "WARNING", else: "OK"), Evidence = concat("HUB=", toString(hub_id_count), "; application=", toString(application_id_count))),
    record(Check = "Angular RUM not observed", Status = if($application_url == "", "NOT_CONFIGURED", else: if(application_url_events == 0, "CRITICAL", else: "OK")), Evidence = concat(toString(application_url_events), " events for application_url")),
    record(Check = "Requests without observed backend correlation", Status = if(application_requests == 0, "NO_DATA", else: if(trace_coverage_pct < 50, "CRITICAL", else: if(trace_coverage_pct < 80, "WARNING", else: "OK"))), Evidence = concat(toString(traced_application_requests), "/", toString(application_requests), " requests with trace.id"))
  )
| fields checks
| expand checks
| fields Check = checks[Check], Status = checks[Status], Evidence = checks[Evidence]
| append [
    // Continuidade é calculada por session ID sem materializar arrays de alta cardinalidade.
    fetch user.events
    | filter in(frontend.name, array($frontend_hub, $frontend_application)) and isNotNull(dt.rum.session.id)
    | summarize
        hub_events = countIf(frontend.name == $frontend_hub),
        application_events = countIf(frontend.name == $frontend_application),
        by: {dt.rum.session.id}
    | summarize
        hub_sessions = countIf(hub_events > 0),
        application_sessions = countIf(application_events > 0),
        shared_sessions = countIf(hub_events > 0 and application_events > 0)
    | fieldsAdd smaller_session_set = if(hub_sessions < application_sessions, hub_sessions, else: application_sessions)
    | fieldsAdd continuity_pct = if(smaller_session_set > 0, 100.0 * shared_sessions / smaller_session_set)
    | fields
        Check = "Session continuity not observed",
        Status = if(hub_sessions > 0 and application_sessions > 0 and coalesce(continuity_pct, 0) < 5, "WARNING", else: "OK"),
        Evidence = concat(toString(shared_sessions), " shared sessions; ", toString(round(coalesce(continuity_pct, 0), decimals: 1)), "% of smaller session set")
  ]
| append [
    // O bloco de spans acrescenta a hipótese backend sem fazer join amplo com user.events.
    fetch spans
    | filter request.is_root_span == true
    | filter in($service_name, array("", "(All services)")) or dt.service.name == $service_name
    | fieldsAdd request_target = coalesce(url.full, url.path, http.route, endpoint.name, "")
    | filter $request_url == "" or contains(request_target, $request_url:triplequote, false)
    | summarize
        backend_requests = count(),
        backend_linked = countIf(isNotNull(dt.rum.session.id) or dt.rum.is_linking_candidate == true)
    | fields
        Check = "Backend without observed RUM request",
        Status = if(backend_requests > 0 and backend_linked == 0, "WARNING", else: "INFO"),
        Evidence = concat(toString(backend_linked), "/", toString(backend_requests), " root spans with RUM link")
  ]
'@

Add-MarkdownTile -Id "section_12" -X 0 -Y 148 -Width 24 -Height 2 -Content @'
## 12 · Matriz de diagnóstico

Resumo final para decidir o próximo passo: regras de frontend/injeção, continuidade de sessão, propagação W3C/Server-Timing ou investigação de serviço/trace. `OK` significa apenas que a evidência esperada foi observada no período.
'@

Add-DataTile -Id "diagnostic_matrix" -Title "Check · Status · Evidence" -Description "Matriz consolidada de RUM e backend; hipóteses, não causas definitivas." -Visualization "table" -X 0 -Y 150 -Width 24 -Height 12 -Query @'
fetch user.events
| fieldsAdd observed_url = coalesce(page.url.full, view.url.full, url.full)
// A matriz calcula todos os checks de frontend em uma única passagem por user.events.
| summarize {
    hub_events = countIf(frontend.name == $frontend_hub),
    application_events = countIf(frontend.name == $frontend_application),
    application_url_events = countIf($application_url != "" and contains(observed_url, $application_url:triplequote, false)),
    application_url_in_hub = countIf($application_url != "" and contains(observed_url, $application_url:triplequote, false) and frontend.name == $frontend_hub),
    application_url_in_application = countIf($application_url != "" and contains(observed_url, $application_url:triplequote, false) and frontend.name == $frontend_application),
    hub_id_count = countDistinctExact(if(frontend.name == $frontend_hub, dt.rum.instrumentation.id)),
    application_id_count = countDistinctExact(if(frontend.name == $frontend_application, dt.rum.instrumentation.id)),
    application_requests = countIf(frontend.name == $frontend_application and characteristics.has_request),
    traced_application_requests = countIf(frontend.name == $frontend_application and characteristics.has_request and isNotNull(trace.id))
  }
| fieldsAdd
    wrong_mapping_pct = if(application_url_events > 0, 100.0 * application_url_in_hub / application_url_events),
    expected_mapping_pct = if(application_url_events > 0, 100.0 * application_url_in_application / application_url_events),
    trace_coverage_pct = if(application_requests > 0, 100.0 * traced_application_requests / application_requests)
| fieldsAdd checks = array(
    record(Check = "HUB RUM detected", Status = if(hub_events > 0, "OK", else: "CRITICAL"), Evidence = concat(toString(hub_events), " events")),
    record(Check = "Angular RUM detected", Status = if(application_events > 0, "OK", else: "CRITICAL"), Evidence = concat(toString(application_events), " events")),
    record(Check = "Single HUB instrumentation", Status = if(hub_id_count == 1, "OK", else: if(hub_id_count == 0, "NO_DATA", else: "WARNING")), Evidence = concat(toString(hub_id_count), " IDs")),
    record(Check = "Single Angular instrumentation", Status = if(application_id_count == 1, "OK", else: if(application_id_count == 0, "NO_DATA", else: "WARNING")), Evidence = concat(toString(application_id_count), " IDs")),
    record(Check = "Angular URL assigned to Angular frontend", Status = if($application_url == "", "NOT_CONFIGURED", else: if(coalesce(expected_mapping_pct, 0) >= 95, "OK", else: "WARNING")), Evidence = concat(toString(round(coalesce(expected_mapping_pct, 0), decimals: 1)), "%")),
    record(Check = "Frontend requests detected", Status = if(application_requests > 0, "OK", else: "WARNING"), Evidence = concat(toString(application_requests), " requests")),
    record(Check = "Frontend/backend correlation", Status = if(application_requests == 0, "NO_DATA", else: if(trace_coverage_pct >= 80, "OK", else: "WARNING")), Evidence = concat(toString(round(coalesce(trace_coverage_pct, 0), decimals: 1)), "% with trace.id")),
    record(Check = "Unexpected frontend mapping", Status = if($application_url == "", "NOT_CONFIGURED", else: if(coalesce(wrong_mapping_pct, 0) >= 50, "CRITICAL", else: if(coalesce(wrong_mapping_pct, 0) > 0, "WARNING", else: "OK"))), Evidence = concat(toString(round(coalesce(wrong_mapping_pct, 0), decimals: 1)), "% application URL in HUB"))
  )
| fields checks
| expand checks
| fields Check = checks[Check], Status = checks[Status], Evidence = checks[Evidence]
| append [
    // Sessões são agregadas por ID para evitar arrays grandes no resumo final.
    fetch user.events
    | filter in(frontend.name, array($frontend_hub, $frontend_application)) and isNotNull(dt.rum.session.id)
    | summarize
        hub_events = countIf(frontend.name == $frontend_hub),
        application_events = countIf(frontend.name == $frontend_application),
        by: {dt.rum.session.id}
    | summarize
        hub_sessions = countIf(hub_events > 0),
        application_sessions = countIf(application_events > 0),
        shared_sessions = countIf(hub_events > 0 and application_events > 0)
    | fieldsAdd smaller_session_set = if(hub_sessions < application_sessions, hub_sessions, else: application_sessions)
    | fieldsAdd continuity_pct = if(smaller_session_set > 0, 100.0 * shared_sessions / smaller_session_set)
    | fields
        Check = "Shared sessions observed",
        Status = if(hub_sessions > 0 and application_sessions > 0 and coalesce(continuity_pct, 0) < 5, "WARNING", else: "OK"),
        Evidence = concat(toString(shared_sessions), " sessions; ", toString(round(coalesce(continuity_pct, 0), decimals: 1)), "%")
  ]
| append [
    // Backend é agregado separadamente; ausência de link é somente uma evidência de triagem.
    fetch spans
    | filter request.is_root_span == true
    | filter in($service_name, array("", "(All services)")) or dt.service.name == $service_name
    | fieldsAdd request_target = coalesce(url.full, url.path, http.route, endpoint.name, "")
    | filter $request_url == "" or contains(request_target, $request_url:triplequote, false)
    | summarize
        backend_requests = count(),
        backend_linked = countIf(isNotNull(dt.rum.session.id) or dt.rum.is_linking_candidate == true)
    | fieldsAdd backend_link_pct = if(backend_requests > 0, 100.0 * backend_linked / backend_requests)
    | fieldsAdd checks = array(
        record(Check = "Backend traces observed", Status = if(backend_requests > 0, "OK", else: "WARNING"), Evidence = concat(toString(backend_requests), " root spans")),
        record(Check = "Backend spans with observed RUM link", Status = if(backend_requests == 0, "NO_DATA", else: if(backend_linked > 0, "OK", else: "WARNING")), Evidence = concat(toString(backend_linked), "/", toString(backend_requests), " linked")),
        record(Check = "Backend without observed RUM request", Status = if(backend_requests > 0 and backend_linked == 0, "WARNING", else: "INFO"), Evidence = concat(toString(round(coalesce(backend_link_pct, 0), decimals: 1)), "% root spans with RUM link"))
      )
    | fields checks
    | expand checks
    | fields Check = checks[Check], Status = checks[Status], Evidence = checks[Evidence]
  ]
'@

Add-MarkdownTile -Id "footer" -X 0 -Y 162 -Width 24 -Height 5 -Content @'
### Próximos passos

1. Confirme URL → frontend e instrumentation IDs. 2. Abra uma session ID na timeline. 3. Restrinja `request_url` e compare cobertura/hints. 4. Use um `trace.id` específico no Distributed Tracing. 5. Confirme serviço e dependências Smartscape. Consulte o README para limitações, alternativas de campos e validação no tenant.
'@

$variables = @(
    [ordered]@{
        version = 2
        key = "frontend_hub"
        type = "query"
        visible = $true
        editable = $true
        input = "data record(value = `"(Select frontend)`")`n| append [`n    fetch user.events`n    | filter isNotNull(frontend.name) and frontend.name != `"`"`n    | dedup frontend.name`n    | fields value = frontend.name`n  ]`n| dedup value`n| sort value asc"
        multiple = $false
    },
    [ordered]@{
        version = 2
        key = "frontend_application"
        type = "query"
        visible = $true
        editable = $true
        input = "data record(value = `"(Select frontend)`")`n| append [`n    fetch user.events`n    | filter isNotNull(frontend.name) and frontend.name != `"`"`n    | dedup frontend.name`n    | fields value = frontend.name`n  ]`n| dedup value`n| sort value asc"
        multiple = $false
    },
    [ordered]@{ version = 2; key = "hub_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "application_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "session_id"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{ version = 2; key = "request_url"; type = "text"; visible = $true; editable = $true; defaultValue = "" },
    [ordered]@{
        version = 2
        key = "service_name"
        type = "query"
        visible = $true
        editable = $true
        input = "data record(service_name = `"(All services)`")`n| append [`n    fetch spans`n    | filter request.is_root_span == true and isNotNull(dt.service.name)`n    | dedup dt.service.name`n    | fields service_name = dt.service.name`n    | limit 200`n  ]`n| dedup service_name`n| sort service_name asc"
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
    name = "RUM Diagnostic Explorer"
    type = "dashboard"
    content = $content
}

$documentJson = $document | ConvertTo-Json -Depth 100
$contentJson = $content | ConvertTo-Json -Depth 100

[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer.document.json"), $documentJson + [Environment]::NewLine, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outputDirectory "rum-diagnostic-explorer.content.json"), $contentJson + [Environment]::NewLine, $utf8NoBom)

Write-Host "Generated dashboard files and $($tiles.Count) tile definitions."
