# RUM Diagnostic Explorer

Dashboard técnico para diagnosticar RUM Agentless em uma aplicação AngularJS acessada por um HUB, usando apenas dados disponíveis no Dynatrace.

## Artefatos

- `rum-diagnostic-explorer.content.json`: importe pela interface do Dashboards.
- `rum-diagnostic-explorer.document.json`: envelope de documento para `dtctl apply`.
- `queries/*.dql`: uma cópia legível de cada consulta de tile.
- `build-dashboard.ps1`: fonte determinística que regenera os dois JSONs e as consultas.
- `validate-dashboard.ps1`: valida JSON, paridade entre formatos, layouts, variáveis e arquivos DQL.
- `validate-dql.ps1`: executa todas as consultas em um tenant autenticado, substituindo as variáveis por valores reais.

## Importação

### Interface do Dashboards

Importe `rum-diagnostic-explorer.content.json` em **Dashboards → Import dashboard**.

### dtctl

Não aplique diretamente o arquivo versionado: em caso de sucesso, `dtctl apply` pode remover o arquivo de entrada. Use uma cópia temporária.

```powershell
$deployFile = Join-Path ([System.IO.Path]::GetTempPath()) "rum-diagnostic-explorer.document.json"
Copy-Item .\rum-diagnostic-explorer.document.json $deployFile
dtctl apply -f $deployFile -o yaml --dry-run
dtctl apply -f $deployFile -o yaml
```

## Configuração inicial

1. Selecione `frontend_hub` e `frontend_application`. Os dois seletores usam a mesma lista de `frontend.name`; troque o placeholder `(Select frontend)` e confirme que não ficaram com o mesmo valor.
2. Informe `hub_url` e `application_url` com um fragmento estável, como domínio ou prefixo de caminho. Não use `*`.
3. Comece com o timeframe global em 15 ou 30 minutos. Amplie para 1 hora quando o volume for insuficiente.
4. Deixe `session_id` e `request_url` vazios e mantenha `service_name` em `(All services)` no primeiro diagnóstico.
5. Para um drill-down, copie uma session ID ou fragmento de endpoint dos próprios resultados e selecione o serviço na lista.

Todos os tiles herdam o timeframe global. Não há `from:`, `to:` ou `timeframe:` fixo nas DQLs. As consultas detalhadas têm `limit`, e cada tile possui scan limit padrão de 100 GB para evitar varreduras sem limite quando alguém ampliar demais a janela.

## Variáveis

| Variável | Tipo | Uso |
|---|---|---|
| `frontend_hub` | query, seleção única | Frontend Dynatrace do HUB. |
| `frontend_application` | query, seleção única | Frontend Dynatrace do AngularJS. |
| `hub_url` | texto | Fragmento da URL/domínio do HUB. Necessário para os checks de mapping. |
| `application_url` | texto | Fragmento da URL/domínio AngularJS. Necessário para os checks de mapping. |
| `session_id` | texto opcional | Ativa a timeline de uma sessão. |
| `request_url` | texto opcional | Restringe requests RUM e spans por URL/rota/endpoint. |
| `service_name` | query, seleção única | `(All services)` não filtra spans; um serviço específico habilita a topologia Smartscape de um hop. |

## Ordem dos tiles

| Seção | Tiles | Finalidade |
|---|---|---|
| 01 · Status geral | Eventos e continuidade; IDs e frontend desconhecido; Requests RUM | Confirmar se há sinal suficiente antes do drill-down. |
| 02 · Frontend × instrumentation | Inventário por ID/agent; IDs compartilhados | Encontrar múltiplos IDs, sobreposição e frontend desconhecido. |
| 03 · URL → frontend | Detalhe URL; mapping esperado; navegações/redirecionamentos | Responder qual frontend recebe a URL AngularJS. |
| 04 · Sessões | Continuidade por session ID; distribuição | Ver sessões comuns sem declarar automaticamente “broken session”. |
| 05 · Timeline | Timeline técnica | Reconstruir HUB → navegação → AngularJS → XHR. |
| 06 · Requests frontend | Requests observadas; tendência | Inventariar chamadas reais, erros e cobertura de trace. |
| 07 · Erros/lentidão | 4xx/5xx/status ausente; lentas | Priorizar endpoints com falha e cauda de latência. |
| 08 · Frontend → backend | Cobertura; root spans; downstream | Localizar onde a correlação deixa de ser observada. |
| 09 · Backend services | Serviços associados | Requests, falhas, percentis e chamadas downstream. |
| 10 · Topologia | Smartscape calls de um hop | Visualização pequena e filtrada, sem reproduzir todo o Smartscape. |
| 11 · Anomalias | Hipóteses diagnósticas | Reunir sinais de mapping, IDs, continuidade, ausência de RUM e trace. |
| 12 · Matriz | Check / Status / Evidence | Consolidar o diagnóstico e orientar o próximo passo. |

## Tiles essenciais para o diagnóstico inicial

Leia primeiro, nesta ordem:

1. **Mapeamento esperado × observado** — responde qual frontend recebe a URL AngularJS.
2. **Frontend × instrumentation ID × agent** — conta IDs e evidencia sobreposição.
3. **Continuidade por session ID** — mostra sessões comuns, HUB_ONLY e APP_ONLY.
4. **Requests observadas no AngularJS** — confirma produção de XHR/fetch no RUM.
5. **Cobertura de trace por request RUM** — verifica `trace.id` e hints de propagação.
6. **Backend observado para o filtro** — verifica root spans e links RUM no backend.

## Regras visuais e thresholds de triagem

Os estados são calculados na própria DQL e aparecem como `Status` nas tabelas. São heurísticas operacionais, não regras de alerta nem confirmação de causa.

| Check | OK | WARNING | CRITICAL |
|---|---|---|---|
| URL AngularJS no HUB | 0% | >0% e <50% | ≥50% |
| Mapping para frontend esperado | ≥95% | <95% | O tile de mapping marca cada combinação inesperada como CRITICAL. |
| Instrumentation IDs | exatamente 1 por frontend | >1 | — |
| Continuidade | ≥5% do menor conjunto de sessões | <5%, havendo tráfego nos dois frontends | — |
| Cobertura `trace.id` | ≥80% | 50–79,9% | <50% no tile de anomalias |
| Request lenta | abaixo de 2 s | — | listada quando >2 s; compare com o SLA real |
| Backend sem link RUM | há spans ligados | root spans existem, mas nenhum link RUM foi observado | — |

`NO_DATA`, `NOT_CONFIGURED` e `INFO` são estados deliberados. `NO_STATUS_OBSERVED` não é sinônimo de timeout, cancelamento ou ausência de resposta.

## Como interpretar por seção

- **Status geral:** zero pode indicar timeframe curto, atraso de ingestão ou ausência real. Valide primeiro sem filtros de URL.
- **Instrumentation:** mais de um ID exige revisar método de injeção e regras de frontend; ID compartilhado é evidência forte de sobreposição.
- **URL mapping:** URL AngularJS no HUB indica detecção/configuração inesperada; confirme volume e instrumentation ID.
- **Sessões:** `CONTINUOUS` observa o mesmo ID nos dois frontends. `HUB_ONLY`/`APP_ONLY` precisa de contexto de navegação, cookies e timing.
- **Timeline:** use para comparar o fim dos eventos do HUB com o início do AngularJS e localizar a primeira request relevante.
- **Requests:** valide se os endpoints esperados realmente aparecem e se os erros são de rede, 4xx ou 5xx.
- **Correlação:** `trace.id` no RUM e link RUM em spans são sinais complementares. Para prova pontual, abra um trace ID específico no Distributed Tracing.
- **Backend/topologia:** serviço com tráfego sem link RUM pode atender canais não-browser; não classifique isso automaticamente como perda de correlação.
- **Matriz:** use a evidência para escolher o próximo drill-down, não para declarar causa raiz.

## Campos validados e alternativas

Os nomes principais seguem o Semantic Dictionary atual do New RUM Experience e o modelo de spans atual. Ainda assim, disponibilidade e conteúdo dependem da versão dos agentes, masking e configuração do tenant.

| Campo principal | Alternativa ou tratamento |
|---|---|
| `dt.rum.instrumentation.id` | Se ausente em um tenant em transição, teste `dt.rum.application.id` apenas como fallback; ele é deprecated. |
| `page.url.full`, `view.url.full` | Se mascarados, use `page.name`/`view.name` ou um fragmento preservado em domínio/caminho. |
| `url.full` | Para agrupamento menos sensível, use `url.domain` + `url.path`. |
| `user_action.custom_name` | O dashboard já cai para `user_action.type`, `interaction.type` ou instance ID. |
| `request.is_root_span` | Em traces somente OpenTelemetry, teste `isNull(span.parent_id)` como fallback de root. |
| `dt.service.name` | Se não enriquecido, use `getNodeName(dt.smartscape.service)`. |
| `dt.rum.is_linking_candidate` em spans | O dashboard também considera `dt.rum.session.id`; no frontend, use `trace.id` e os request hints. |
| Smartscape `calls` vazio | Use o tile **Service → downstream observado**, baseado em HTTP client spans. |
| Cancelamento de request | Não há campo semântico genérico assumido. Use `characteristics.has_failed_request`, status HTTP, `performance.incomplete_reason` e evidência específica do tenant. |

## Validação

Validação local, sem acesso a tenant:

```powershell
.\build-dashboard.ps1
.\validate-dashboard.ps1
```

Validação sintática e de execução no tenant (executa 3 queries de variável + 22 queries de tiles):

```powershell
.\validate-dql.ps1 `
  -FrontendHub "HUB frontend" `
  -FrontendApplication "Angular frontend" `
  -HubUrl "hub.exemplo" `
  -ApplicationUrl "app.exemplo" `
  -RequestUrl "/api/" `
  -ServiceName "Meu serviço"
```

O script requer `dtctl` instalado, autenticado e com permissões de leitura de `user.events`, `spans` e Smartscape. Deixe os filtros textuais opcionais vazios e use `-ServiceName "(All services)"` para validar o comportamento sem drill-down de serviço.

## Limitações conhecidas

- Não existe join amplo `user.events` ↔ `spans`: ele é caro e pouco confiável em tenants grandes. O dashboard usa cobertura de `trace.id`, hints, links RUM nos spans e lookup pontual por trace ID.
- Percentis de spans descrevem a amostra observada; contagens usam multiplicidade de sampling/aggregation.
- A lista de frontends depende de dados no timeframe global. Se vier vazia, amplie temporariamente a janela e confirme ingestão/permissões.
- URL masking pode reduzir a precisão dos filtros textuais.
- Tráfego backend sem RUM pode ser legítimo (batch, integrações, mobile, synthetic ou APIs externas).
- O dashboard não substitui regras de detecção de frontend, configurações de CORS/Trace Context nem o Smartscape.

## Regeneração

Edite `build-dashboard.ps1` e execute:

```powershell
.\build-dashboard.ps1
.\validate-dashboard.ps1
```

Os JSONs e os 22 arquivos `.dql` serão atualizados de forma determinística.

## Referências oficiais

- [User events · Semantic Dictionary](https://docs.dynatrace.com/docs/semantic-dictionary/model/rum/user-events)
- [Request user events](https://docs.dynatrace.com/docs/semantic-dictionary/model/rum/user-events/requests)
- [User sessions](https://docs.dynatrace.com/docs/semantic-dictionary/model/rum/user-sessions)
- [Traces · Semantic Dictionary](https://docs.dynatrace.com/docs/semantic-dictionary/model/trace)
- [Estrutura de documentos de dashboard](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/document-api/document-structure-dashboards)
- [Dynatrace Query Language](https://docs.dynatrace.com/docs/platform/grail/dynatrace-query-language)
