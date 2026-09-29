# RUM Diagnostic Explorer

## Dashboard adicional: RUM Application Topology Comparison

Este segundo dashboard preserva o diagnostico original e mostra UPSTREAM na esquerda e TARGET na direita em sete camadas: configuracao, Applications/Frontends, hosts que hospedam a aplicacao, hosts de dependencias, Process Groups, Processes e Services.

- `rum-topology-comparison-build-20260928-r3.content.json`: arquivo recomendado para importacao pela interface.
- `rum-topology-comparison-build-20260928-r3.document.json`: envelope versionado para `dtctl apply`.
- `rum-topology-comparison.content.json` e `rum-topology-comparison.document.json`: aliases sem versao.
- `topology-queries/*.dql`: quatorze consultas Smartscape, uma para cada tabela UPSTREAM/TARGET.
- `build-topology-dashboard.ps1`: gera o dashboard adicional.
- `validate-topology-dashboard.ps1`: valida estrutura, simetria, layout, fontes e limites.
- `validate-topology-dql.ps1`: expande as variaveis e valida as quatorze DQLs; com `-RunTenant`, executa no tenant via `dtctl`.

Importe `rum-topology-comparison-build-20260928-r3.content.json` em **Dashboards -> Import dashboard** e confirme no primeiro card o texto `Build: 2026-09-28-r3 - application hosts separated`.

Todas as quatorze tabelas usam somente `smartscapeNodes`, `traverse` e `append`, sem scan de eventos RUM, spans, logs ou metricas. A camada **Application hosting hosts** segue a taxonomia do Dynatrace: `FRONTEND -> SERVICE -> PROCESS -> HOST`, aceitando apenas processos com classificacao em `process.software_technologies.webserver`. Ela tambem exibe a taxonomia do servico, a tecnologia web server, o processo e o Process Group que sustentam a classificacao, sem fixar Apache, NGINX, IIS ou qualquer nome de produto.

A camada **Dependency hosts** combina `FRONTEND -> SERVICE -> HOST` e `FRONTEND -> SERVICE -> PROCESS -> HOST` e inclui APIs, gateways, proxies e demais dependencias. Process Group e apresentado a partir dos campos estaveis `dt.process_group.id` e `dt.process_group.detected_name` dos processos, pois nao existe um no `PROCESS_GROUP` separado no Smartscape on Grail.

Em RUM Agentless nao existe uma relacao nativa de propriedade `FRONTEND -> HOST`. Por isso a secao de hospedagem usa a classificacao tecnologica nativa do processo como criterio taxonomico e deixa toda a cadeia visivel para auditoria. Um servidor sem OneAgent ou sem tecnologia web server detectada nao pode ser associado automaticamente por essa topologia.

```powershell
.\build-topology-dashboard.ps1
.\validate-topology-dashboard.ps1
.\validate-topology-dql.ps1 `
  -FrontendUpstream "Portal frontend" `
  -FrontendTarget "Target frontend"
```

Acrescente `-RunTenant` ao ultimo comando para executar as consultas em um tenant autenticado.

Dashboard técnico para comparar dois frontends web encadeados, independentemente da tecnologia ou do nome das aplicações:

```text
frontend_upstream -> navegação/redirecionamento -> frontend_target -> XHR/fetch -> backend
```

O cenário padrão considera que ambos já utilizaram RUM Agentless, mas a injeção do frontend superior foi desabilitada para evitar que ela sobrescreva ou capture a instrumentação da aplicação alvo.

## Artefatos

- `rum-diagnostic-explorer-build-20260928-r4.content.json`: artefato versionado recomendado para importar pela interface do Dashboards.
- `rum-diagnostic-explorer-build-20260928-r4.document.json`: envelope versionado para `dtctl apply`.
- `rum-diagnostic-explorer.content.json`: alias sem versão para automações existentes.
- `rum-diagnostic-explorer.document.json`: alias sem versão para automações existentes.
- `queries/*.dql`: as oito consultas utilizadas pelos tiles.
- `build-dashboard.ps1`: regenera os JSONs e remove consultas antigas que não pertencem mais ao dashboard.
- `validate-dashboard.ps1`: valida estrutura, layout e limites de custo.
- `validate-dql.ps1`: executa as consultas em um tenant autenticado depois de expandir as variáveis.

Os artefatos importáveis usam somente caracteres ASCII para evitar mojibake em terminais e importadores legados.

## Proteções de custo

O dashboard foi desenhado para falhar de forma controlada antes de executar uma investigação ampla por engano:

- `analysis_window_minutes` aceita apenas `15`, `30` ou `60`; o padrão é 15 minutos.
- Todos os `fetch user.events` e `fetch spans` possuem esse `from:` explícito. Um timeframe global maior não aumenta a janela lida pelos tiles.
- Cada tile tem scan limit de 2 GB, no máximo 500 registros e 5 MB de resultado.
- A quantidade de tiles de dados caiu de 22 para 8; o tile adicional consulta somente a topologia Smartscape.
- As leituras máximas caíram de 20 scans de `user.events` e 5 de `spans` para 6 e 1, respectivamente.
- O único scan de spans exige um `trace_id` exato; não há inventário amplo de servidores nem join entre `user.events` e `spans`.
- O mapa de serviços consulta relações `calls` atuais do Smartscape, sem abrir outro scan de telemetria.
- Os seletores de frontend são dropdowns automáticos baseados em `smartscapeNodes "FRONTEND"`; eles consultam o catálogo topológico, sem scans de `user.events` ou `spans`.
- Requests são agrupadas por `url.domain` e `url.path`, não por URL completa com query string.

Essas proteções limitam o custo por execução, mas não tornam consultas repetidas gratuitas. Use 15 minutos primeiro e aumente somente quando o volume for insuficiente.

## Variáveis

| Variável | Uso |
|---|---|
| `analysis_window_minutes` | Janela fechada de 15, 30 ou 60 minutos. |
| `frontend_upstream` | Seletor automático do Frontend/Web Application que fica na frente da aplicação alvo. |
| `frontend_target` | Seletor automático do Frontend/Web Application que deve coletar RUM e replay. |
| `upstream_rum_expected` | `DISABLED` no cenário recomendado; use `ENABLED` quando os dois frontends devem coletar. |
| `upstream_url` | Fragmento estável de domínio ou caminho do frontend superior. |
| `target_url` | Fragmento estável de domínio ou caminho da aplicação alvo. |
| `session_id` | Drill-down opcional de uma sessão. |
| `request_url` | Filtro opcional de domínio, caminho ou endpoint. |
| `trace_id` | Trace ID específico copiado do tile de requests. |

Os dois seletores usam nós Smartscape `FRONTEND`. Esse tipo também representa as Web Applications clássicas (`dt.entity.application`), portanto o mesmo dropdown cobre os dois modelos. Como a lista vem do catálogo de entidades, uma aplicação permanece selecionável mesmo quando não produziu eventos RUM recentes. O seletor do alvo exclui automaticamente o frontend superior selecionado.

## Ordem de investigação

1. Selecione dois Frontends/Web Applications diferentes e mantenha a janela em 15 minutos.
2. Use `upstream_rum_expected = DISABLED` se o Agentless superior foi removido.
3. Confira a matriz: nesse modo, qualquer evento recente do frontend superior é `CRITICAL`.
4. Confira se existe exatamente um instrumentation ID no frontend alvo.
5. Preencha as URLs e procure URL `TARGET` atribuída ao frontend superior.
6. Abra uma session ID recente na timeline.
7. Confira requests do frontend alvo e copie um `Sample trace ID`.
8. Compare a tabela de serviços ligados aos dois frontends.
9. Cole o valor em `trace_id` para mapear somente os servidores e processos observados naquele trace.

## Interpretação do cenário Agentless

Quando o RUM superior deveria estar desabilitado:

| Evidência | Interpretação operacional |
|---|---|
| Zero eventos recentes no upstream e eventos no target | Estado esperado após a remoção da instrumentação superior. |
| Eventos continuam chegando no upstream | A alteração não teve efeito completo dentro da janela observada. Investigue cache, páginas antigas abertas, outra origem de injeção e prioridade de regras. |
| Mesmo instrumentation ID aparece nos dois frontends | Forte evidência de sobreposição ou atribuição inconsistente. |
| URL alvo aparece no upstream | Forte evidência de mapping/detection incorreto ou agente superior ainda ativo. |
| Mais de um instrumentation ID no target | Revisar múltiplas formas de injeção, configuração residual e regras concorrentes. |
| Sessões `TARGET_ONLY` | Esperado quando o upstream não coleta mais RUM. |
| Sessões `CONTINUOUS` com upstream desabilitado | Pode indicar clientes/páginas ainda executando a instrumentação superior. Não prova sozinho a origem. |

Eventos dentro da janela podem ter sido produzidos antes de uma mudança recente ou por abas já abertas. Use `Last seen` e repita a análise após o tempo necessário para renovação das páginas.

## Tiles

| Tile | Finalidade |
|---|---|
| Agentless checks - Status - Evidence | Consolida o estado esperado, volume, IDs, mapping, requests e cobertura de trace em um scan. |
| Instrumentation IDs across the frontend pair | Mostra IDs compartilhados entre os dois frontends. |
| Configured URL ownership | Compara frontend esperado e observado para as URLs configuradas. |
| Recent sessions across the frontend pair | Classifica até 100 sessões recentes. |
| Timeline for one session | Reconstrói uma session ID específica. |
| Requests emitted by the target frontend | Consolida chamadas, falhas, latência e exemplos de trace/session ID. |
| Services linked to the selected web applications | Mapeia cada Frontend/Web Application selecionado aos serviços ligados por relações `calls` do Smartscape. |
| Servers observed for the selected trace | Agrupa, por serviço, os hosts e process groups observados somente no trace selecionado. |

## Importação

### Interface

Importe `rum-diagnostic-explorer-build-20260928-r4.content.json` em **Dashboards -> Import dashboard**. Depois de abrir o dashboard importado, confirme no primeiro card o texto `Build: 2026-09-28-r4 - named optional parameters`. O nome novo evita confundir esta importação com uma cópia anterior.

### dtctl

Use uma cópia temporária, pois `dtctl apply` pode remover o arquivo de entrada após sucesso:

```powershell
$deployFile = Join-Path ([System.IO.Path]::GetTempPath()) "rum-diagnostic-explorer.document.json"
Copy-Item .\rum-diagnostic-explorer.document.json $deployFile
dtctl apply -f $deployFile -o yaml --dry-run
dtctl apply -f $deployFile -o yaml
```

## Validação

Validação local:

```powershell
.\build-dashboard.ps1
.\validate-dashboard.ps1
```

Validação das oito DQLs dos tiles e das duas consultas automáticas de variáveis no tenant:

```powershell
.\validate-dql.ps1 `
  -AnalysisWindowMinutes "15" `
  -FrontendUpstream "Portal frontend" `
  -FrontendTarget "Target frontend" `
  -UpstreamRumExpected "DISABLED" `
  -UpstreamUrl "portal.example" `
  -TargetUrl "app.example" `
  -RequestUrl "/api/" `
  -TraceId "<trace-id-opcional>"
```

## Limitações

- O dashboard mostra evidências do Dynatrace; não prova qual componente HTML, proxy ou regra realizou a injeção.
- `dt.rum.instrumentation.id` e `dt.rum.agent.type` dependem da disponibilidade dos campos no tenant.
- URL mascarada pode exigir fragmentos preservados ou comparação por `page.name`/`view.name`.
- Ausência de `trace.id` é `Correlation not observed`; não prova que o backend não processou a request.
- A consulta de spans usa `toUid($trace_id)` e exige que o trace esteja dentro da janela selecionada.
- Frontends não possuem servidor de execução próprio no modelo RUM Agentless. A tabela de servidores mostra hosts backend observados no trace, relacionados aos serviços pelos quais a request passou.
- A relação Frontend/Web Application -> serviço depende da presença e da direção de arestas `calls` no Smartscape do tenant. Nomes duplicados permanecem distinguíveis pelos IDs exibidos.
- Se o scan limit de 2 GB for atingido, reduza a janela ou refine URL/request. Não aumente o limite como primeira ação.
