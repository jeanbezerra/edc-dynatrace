Crie um dashboard técnico no Dynatrace, utilizando DQL e os recursos atuais da plataforma, com foco em diagnosticar problemas de RUM Agentless em uma aplicação AngularJS que é acessada através de um HUB de aplicações.

## Contexto da arquitetura

O fluxo esperado é:

HUB de aplicações
→ link/redirecionamento
→ Apache HTTP Server
→ balanceamento/proxy
→ WebSphere Application Server (WAS)
→ aplicação AngularJS
→ chamadas XHR/AJAX para backend
→ Dynatrace

Tanto o HUB quanto a aplicação AngularJS possuem RUM habilitado.

O objetivo principal é identificar problemas como:

- aplicação AngularJS sendo atribuída ao frontend RUM incorreto;
- tráfego da aplicação AngularJS sendo capturado pelo RUM do HUB;
- múltiplos instrumentation IDs;
- quebra de sessão entre HUB e AngularJS;
- ausência de RUM na aplicação AngularJS;
- perda de correlação entre frontend e backend;
- requests XHR/AJAX não correlacionados;
- diferenças entre navegação do HUB e navegação da aplicação;
- problemas relacionados a redirecionamento;
- gaps entre RUM, Apache, WAS e distributed tracing;
- requests vistos no browser/RUM mas não encontrados no backend;
- backend observado pelo Dynatrace sem correspondente frontend;
- possível sobreposição de instrumentação RUM.

## Restrições

Não existe acesso:

- ao código-fonte do HUB;
- ao código-fonte da aplicação AngularJS;
- ao navegador dos usuários;
- ao DevTools;
- à configuração direta do Apache;
- à configuração direta do WAS.

Toda a investigação deve ser realizada exclusivamente com os dados disponíveis no Dynatrace.

O dashboard deve funcionar como uma ferramenta operacional de troubleshooting.

## Requisitos gerais

Crie um dashboard chamado:

"RUM Diagnostic Explorer"

Organize o dashboard em seções progressivas, começando por uma visão executiva do problema e permitindo drill-down técnico.

Use DQL sempre que possível.

Evite consultas muito pesadas sem necessidade.

Prefira trabalhar inicialmente com janelas de tempo curtas, como:

- últimos 15 minutos;
- últimos 30 minutos;
- última 1 hora.

Permita alterar o timeframe.

## Variáveis do dashboard

Crie variáveis para:

1. `frontend_hub`
   - nome do frontend Dynatrace correspondente ao HUB.

2. `frontend_application`
   - nome do frontend correspondente à aplicação AngularJS.

3. `hub_url`
   - parte da URL ou domínio do HUB.

4. `application_url`
   - parte da URL ou domínio da aplicação AngularJS.

5. `session_id`
   - opcional, para investigação detalhada de uma sessão.

6. `request_url`
   - opcional, para filtrar uma URL ou endpoint específico.

7. `service_name`
   - opcional, para selecionar um serviço backend relacionado.

As consultas devem utilizar essas variáveis sempre que possível.

---

# SEÇÃO 1 — STATUS GERAL

Crie tiles que mostrem:

- quantidade de eventos RUM do HUB;
- quantidade de eventos RUM da aplicação AngularJS;
- quantidade de sessões únicas do HUB;
- quantidade de sessões únicas da aplicação AngularJS;
- quantidade de instrumentation IDs encontrados no HUB;
- quantidade de instrumentation IDs encontrados na aplicação;
- quantidade de sessões que aparecem nos dois frontends;
- quantidade de requests frontend detectados;
- quantidade de requests com erro;
- quantidade de eventos sem frontend identificado.

Utilize principalmente:

`fetch user.events`

Campos relevantes a considerar:

- `frontend.name`;
- `dt.rum.session.id`;
- `dt.rum.instrumentation.id`;
- `dt.rum.agent.type`;
- `page.url.full`;
- `characteristics.has_request`;
- campos relacionados a request;
- campos relacionados a user action;
- timestamps.

Valide a existência dos campos no schema atual antes de assumir seus nomes.

---

# SEÇÃO 2 — FRONTEND VS INSTRUMENTATION ID

Crie uma tabela:

Frontend | Instrumentation ID | Agent Type | Eventos | Sessões

Objetivo:

identificar se existe mais de um instrumentation ID sendo utilizado para o mesmo frontend.

Destacar situações como:

- HUB com múltiplos IDs;
- AngularJS com múltiplos IDs;
- instrumentation ID aparentemente compartilhado;
- frontend desconhecido;
- mesma URL aparecendo em frontends diferentes.

Exemplo conceitual de DQL:

fetch user.events
| summarize
    eventos = count(),
    sessoes = countDistinct(dt.rum.session.id),
    by: {
        frontend.name,
        dt.rum.instrumentation.id,
        dt.rum.agent.type
    }
| sort eventos desc

Ajuste a query conforme a sintaxe suportada pela versão atual do Dynatrace.

---

# SEÇÃO 3 — URL → FRONTEND

Crie uma tabela:

URL | Frontend | Instrumentation ID | Eventos | Sessões

Filtrar usando as variáveis:

`${hub_url}`

e

`${application_url}`

Objetivo:

descobrir qual frontend está recebendo os eventos de cada URL.

Detectar especialmente:

URL AngularJS
→ frontend.name = HUB

Esse comportamento deve ser tratado como um forte indicador de configuração ou detecção incorreta.

Crie também uma visualização agregada mostrando:

HUB URL
→ frontend HUB

Application URL
→ frontend AngularJS

Quando houver cruzamento, destacar visualmente.

---

# SEÇÃO 4 — SESSÕES QUE ATRAVESSAM HUB E ANGULARJS

Crie uma consulta que agrupe eventos por:

`dt.rum.session.id`

e identifique sessões que possuem eventos provenientes dos dois frontends.

Objetivo:

responder:

"Existem sessões que começam no HUB e continuam na aplicação AngularJS?"

Criar uma tabela:

Session ID | Frontends encontrados | Primeiro evento | Último evento | Eventos | Duração aproximada

Se possível, classificar:

- `CONTINUOUS`
- `HUB_ONLY`
- `APP_ONLY`
- `MULTI_FRONTEND`

Não inferir que uma sessão está quebrada apenas por não aparecer nos dois frontends; tratar como indicador que exige investigação.

---

# SEÇÃO 5 — TIMELINE DE UMA SESSÃO

Utilize a variável:

`${session_id}`

Crie uma tabela ordenada cronologicamente:

Timestamp
Frontend
URL
Tipo de evento
User action
Request URL
Request method
Status code
Instrumentation ID

Objetivo:

reconstruir visualmente uma sessão semelhante a:

HUB
→ click
→ navigation
→ AngularJS
→ user action
→ XHR
→ backend

Permitir observar casos como:

HUB
→ fim da sessão

e depois:

AngularJS
→ nova sessão

Não classificar automaticamente isso como erro sem outras evidências.

---

# SEÇÃO 6 — REQUESTS DO FRONTEND

Utilizar:

`characteristics.has_request == true`

para localizar eventos com requests associados, conforme o modelo atual do Dynatrace.

Criar uma tabela:

Frontend
Request URL
HTTP Method
HTTP Status
Número de chamadas
Erros
Sessões
User Action relacionada

Permitir filtro por:

`${request_url}`

e

`${frontend_application}`

Objetivo:

identificar quais requests a aplicação AngularJS está efetivamente fazendo.

---

# SEÇÃO 7 — REQUESTS COM ERRO

Criar uma visão específica para:

- HTTP 4xx;
- HTTP 5xx;
- requests sem resposta;
- requests cancelados;
- requests lentos, quando essa informação estiver disponível.

Tabela:

Request
Status
Calls
Errors
Frontend
Sessions
p50
p95

Só usar métricas ou campos que existam no ambiente.

Não inventar campos.

---

# SEÇÃO 8 — CORRELAÇÃO FRONTEND → BACKEND

Investigar se requests observados no RUM possuem relação com distributed traces ou spans.

Utilizar:

`fetch spans`

quando aplicável.

Criar visão conceitual:

Frontend Request
→ Service
→ Downstream Service

Para requests selecionadas por `${request_url}`.

Identificar:

- request RUM existe;
- span backend existe;
- service backend identificado;
- trace relacionado encontrado;
- trace backend existe isoladamente;
- ausência aparente de correlação.

Não afirmar automaticamente que a ausência de correspondência significa perda de correlação; apresentar como:

`Correlation not observed`

ou equivalente.

---

# SEÇÃO 9 — BACKEND SERVICES

Criar uma tabela dos serviços associados à aplicação:

Service Name
Requests
Failures
p50
p95
p99
Downstream calls

Use spans, metrics ou Smartscape on Grail conforme adequado.

Permitir filtro por:

`${service_name}`

---

# SEÇÃO 10 — TOPOLOGIA SIMPLIFICADA

Se o dashboard atual suportar visualização adequada, gerar uma visão simplificada:

HUB
→ AngularJS
→ Apache / Web Tier
→ WAS
→ Backend Service
→ Database / External service

Não tentar reproduzir todo o SmartScape.

Mostrar somente dependências relacionadas ao frontend/application/request selecionado.

Utilizar Smartscape on Grail quando possível.

Consultas podem considerar:

`smartscapeNodes`

`smartscapeEdges`

relações do tipo:

`calls`

e, quando necessário:

`runs_on`

Evitar carregar milhares de entidades.

Limitar profundidade de dependência a 1 ou 2 hops.

---

# SEÇÃO 11 — POSSÍVEIS ANOMALIAS DE RUM

Criar indicadores derivados dos dados disponíveis.

Mostrar os seguintes cenários:

### Possible wrong frontend mapping

Condição:

URL da aplicação AngularJS aparece predominantemente no frontend HUB.

### Multiple instrumentation IDs

Condição:

mais de um `dt.rum.instrumentation.id` encontrado para o mesmo frontend.

### Session continuity not observed

Condição:

há grande volume de eventos HUB e AngularJS, porém poucas ou nenhuma sessão aparece em ambos.

Não chamar automaticamente de "broken session".

### Angular RUM not observed

Condição:

não existem eventos RUM recentes para a URL configurada da aplicação.

### Requests without observed backend correlation

Condição:

request aparece em `user.events`, mas não foi possível encontrar correlação com spans/service.

### Backend without observed RUM request

Condição:

backend possui tráfego relevante, mas nenhuma request correspondente foi localizada no RUM para o período selecionado.

Todos esses indicadores devem ser tratados como hipóteses diagnósticas, não como causas definitivas.

---

# SEÇÃO 12 — MATRIZ DE DIAGNÓSTICO

Criar uma tabela final:

Check | Status | Evidence

Exemplo:

HUB RUM detected | OK | 18.432 events
Angular RUM detected | OK | 9.821 events
Single HUB instrumentation | OK | 1 ID
Single Angular instrumentation | WARNING | 2 IDs
Angular URL assigned to Angular frontend | OK | 98.7%
Shared sessions observed | WARNING | 3.2%
Frontend requests detected | OK | 41 endpoints
Backend traces observed | OK | 14 services
Frontend/backend correlation | WARNING | 62%
Unexpected frontend mapping | CRITICAL | Angular URL observed in HUB

O dashboard não deve afirmar causalidade apenas com base nesses indicadores.

---

# UX DO DASHBOARD

Utilizar títulos claros e voltados para diagnóstico.

Adicionar blocos Markdown curtos explicando:

- o que cada seção verifica;
- o que significa um resultado anormal;
- qual seria o próximo passo de investigação.

Exemplo:

"Esta tabela mostra qual frontend Dynatrace recebeu os eventos associados às URLs analisadas. A presença da URL AngularJS no frontend HUB pode indicar uma regra de detecção inadequada ou instrumentação inesperada."

Não criar textos longos.

---

# IMPORTANTE SOBRE DQL

Antes de finalizar:

1. valide a sintaxe DQL atual;
2. valide os nomes dos campos;
3. não utilize campos inexistentes;
4. não invente comandos como `event.name` se não fizerem parte desse modelo;
5. prefira campos do Semantic Dictionary atual;
6. comente queries complexas;
7. limite resultados quando necessário;
8. evite consultas caras sobre períodos muito longos;
9. use `fields`, `summarize`, `filter`, `sort` e `limit` para reduzir o volume processado.

Quando uma função não existir na versão atual do DQL, substitua pela implementação suportada.

---

# ENTREGÁVEIS

Produza:

1. definição completa do dashboard;
2. todas as consultas DQL;
3. ordem recomendada dos tiles;
4. variáveis necessárias;
5. títulos dos tiles;
6. descrição curta de cada tile;
7. thresholds/condições visuais;
8. explicação de como interpretar cada seção;
9. indicação de quais tiles são essenciais para o diagnóstico inicial;
10. consultas alternativas caso algum campo não esteja disponível;
11. um README.md explicando como importar, configurar e utilizar o dashboard.

Se o repositório utilizar configuração-as-code para Dynatrace, gerar os arquivos no formato utilizado pelo projeto.

Caso exista Monaco/Dashboards-as-Code ou configuração JSON/YAML no repositório, seguir o padrão já existente.

Não sobrescrever configurações existentes sem necessidade.

## Prioridade

Prioridade máxima para conseguir responder rapidamente:

1. Qual frontend está recebendo a URL AngularJS?
2. Quantos instrumentation IDs existem?
3. Existem sessões que aparecem no HUB e no AngularJS?
4. O AngularJS está produzindo requests RUM?
5. Esses requests possuem backend observado?
6. Onde a correlação aparentemente desaparece?

A primeira versão deve ser operacional e simples. Não tente criar uma plataforma completa de arquitetura ou substituir o SmartScape.