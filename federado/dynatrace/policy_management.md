# Gerenciamento de policies e boundaries

## Principios

- Policies definem capacidades; boundaries definem o escopo.
- Criar as policies customizadas no nivel da conta e vincula-las somente ao ambiente de producao.
- Preferir `ALLOW` explicito e menor privilegio.
- Nao usar `DENY` para compensar grupos excessivamente amplos.
- Nao conceder dados de Security, Session Replay, BizEvents, system tables ou dados sensiveis sem uma aprovacao separada.
- Revisar custom policies quando o Dynatrace adicionar ou descontinuar permissions.

## Policy `PTO - PROD - SRE Base`

Capacidades minimas para abrir Dashboards/Notebooks, executar consultas e usar analises. Ela nao concede acesso aos registros de observabilidade; isso pertence a policy seguinte.

```text
// Executar apps, funcoes e consultas de Dashboards/Notebooks
ALLOW app-engine:apps:run, app-engine:functions:run, app-engine:edge-connects:read;
ALLOW hub:catalog:read;
ALLOW unified-analysis:screen-definition:read;

// Preferencias do usuario nos apps
ALLOW state:user-app-states:read, state:user-app-states:write, state:user-app-states:delete;

// Abrir documentos proprios ou compartilhados; autoria e compartilhamento ficam em outra policy
ALLOW document:documents:read, document:environment-shares:read, document:direct-shares:read;

// Analises usadas por Dashboards e Notebooks
ALLOW davis:analyzers:read, davis:analyzers:execute;

// Catalogos sem acesso ao conteudo das tabelas
ALLOW storage:bucket-definitions:read, storage:fieldset-definitions:read, storage:filter-segments:read;

// Acesso ao ambiente Classic; aplicar boundary de Management Zone para verticais
ALLOW environment:roles:viewer, environment:roles:logviewer;

// Permissoes auxiliares da UI
ALLOW platform-management:effective-permissions:resolve, platform-management:environments:read;
```

O desenho usa uma policy customizada em vez de `Standard User` para nao conceder implicitamente workflows, vulnerabilidades, SLOs, configuracoes e outros recursos que nao foram solicitados. Se a organizacao preferir a policy padrao para reduzir manutencao, substitua esta policy por `Standard User`, faca uma analise de risco das permissoes adicionais e repita os testes negativos.

## Policy `PTO - PROD - Observability Data Read`

Leitura operacional sem Security Events, BizEvents, Session Replay, system tables e arquivos lookup.

```text
// Bucket discovery e leitura ficam limitados as tabelas de observabilidade aprovadas
ALLOW storage:buckets:read
WHERE storage:table-name IN (
  "logs",
  "metrics",
  "events",
  "spans",
  "application.snapshots",
  "user.events",
  "user.sessions"
);

// Para grupos de vertical, o boundary adiciona storage:dt.security_context
ALLOW storage:logs:read;
ALLOW storage:metrics:read;
ALLOW storage:events:read;
ALLOW storage:spans:read;
ALLOW storage:application.snapshots:read;
ALLOW storage:entities:read;
ALLOW storage:smartscape:read;
ALLOW storage:user.events:read;
ALLOW storage:user.sessions:read;
```

`storage:buckets:read` permite descobrir os buckets das tabelas indicadas, mas nao permite ler seus registros sozinho. As permissions de tabela recebem o boundary `storage:dt.security_context` nos grupos de vertical.

## Policy `PTO - PROD - Document Author`

Perfil aditivo para criacao e colaboracao em dashboards e notebooks modernos.

```text
// Aplicacoes Dashboards e Notebooks
ALLOW app-engine:apps:run, app-engine:functions:run, app-engine:edge-connects:read;
ALLOW hub:catalog:read;
ALLOW state:user-app-states:read, state:user-app-states:write, state:user-app-states:delete;
ALLOW davis:analyzers:read, davis:analyzers:execute;

// Ciclo de vida dos documentos do usuario
ALLOW document:documents:read, document:documents:write, document:documents:delete;
ALLOW document:trash.documents:read, document:trash.documents:restore, document:trash.documents:delete;

// Compartilhamento para o ambiente e diretamente com pessoas/grupos
ALLOW document:environment-shares:read, document:environment-shares:write,
      document:environment-shares:claim, document:environment-shares:delete;
ALLOW document:direct-shares:read, document:direct-shares:write, document:direct-shares:delete;
```

Nao adicionar `document:documents:admin`. Essa permission permitiria administrar documentos de outros usuarios e pertence somente ao perfil administrador.

## Boundaries Classic

Aplicar exclusivamente a `PTO - PROD - SRE Base` do grupo correspondente.

```text
environment:management-zone = "PROD - Porto Seguros";
environment:management-zone = "PROD - Porto Saude";
environment:management-zone = "PROD - Porto Servicos";
environment:management-zone = "PROD - Porto Bank";
```

Cada linha acima representa um boundary separado, nao um boundary unico.

## Boundaries Grail

Aplicar exclusivamente a `PTO - PROD - Observability Data Read` do grupo correspondente.

```text
storage:dt.security_context = "porto/prod/seguros";
storage:dt.security_context = "porto/prod/saude";
storage:dt.security_context = "porto/prod/servicos";
storage:dt.security_context = "porto/prod/bank";
```

Cada linha acima representa um boundary separado. Use igualdade enquanto houver somente um valor canonico por vertical. Se futuramente surgirem subescopos, padronize valores como `porto/prod/seguros/<time>` e troque conscientemente para `startsWith "porto/prod/seguros/"`.

## Bindings

| Grupo | Policy | Boundary |
|---|---|---|
| Admins | `Admin User` | nenhum |
| Admins | `Data Processing and Storage` | nenhum |
| Admins | `All Grail data read access` | nenhum |
| SRE Corporativo | `PTO - PROD - SRE Base` | nenhum |
| SRE Corporativo | `PTO - PROD - Observability Data Read` | nenhum |
| SRE Corporativo | `Settings Reader` | nenhum |
| SRE de vertical | `PTO - PROD - SRE Base` | Classic da vertical |
| SRE de vertical | `PTO - PROD - Observability Data Read` | Grail da vertical |
| Autores | `PTO - PROD - Document Author` | nenhum |

Todos os bindings devem ser feitos no ID do ambiente de producao. Nao vincule essas policies no nivel da conta, pois isso as propagaria para outros ambientes.

## Dados fora do escopo

Este baseline nao concede aos SREs:

- `storage:security.events:read`;
- `storage:bizevents:read`;
- `storage:system:read`;
- `storage:user.replays:read` ou replay sem mascaramento;
- `storage:files:*`;
- escrita em Settings, OpenPipeline, buckets ou ingestao;
- administracao de documentos de terceiros.

Crie um entitlement adicional, aprovado e auditavel para qualquer uma dessas necessidades. Nao altere silenciosamente a policy base compartilhada.

## Validacao de seguranca

1. Em **Account Management > Identity & access management > Effective policies**, selecione um usuario e o ambiente PRD.
2. Confirme que cada permission `storage:*:read` do SRE de vertical mostra a condition correta.
3. Execute consultas positivas e negativas por tabela.
4. Verifique Classic Problems, Services, Hosts e Logs com a Management Zone.
5. Abra um dashboard de outra vertical: o documento pode ser visivel se foi compartilhado, mas os tiles nao podem retornar dados fora do escopo do usuario.
6. Confirme que o usuario nao consegue alterar Settings nem criar tokens/usuarios/policies.

## Referencias oficiais

- [Sintaxe de policy IAM](https://docs.dynatrace.com/docs/manage/identity-access-management/permission-management/manage-user-permissions-policies/iam-policystatement-syntax)
- [Referencia de permissions IAM](https://docs.dynatrace.com/docs/manage/identity-access-management/permission-management/manage-user-permissions-policies/advanced/iam-policystatements)
- [Policy boundaries](https://docs.dynatrace.com/docs/manage/identity-access-management/permission-management/manage-user-permissions-policies/iam-policy-boundaries)
- [Dashboards: permissions](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/dashboards-new)
- [Notebooks: permissions](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/notebooks)
