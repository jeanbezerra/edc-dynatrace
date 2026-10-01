# Acesso federado ao Dynatrace em producao

Modelo de grupos, policies e boundaries para o ambiente Dynatrace de producao. O desenho separa o que a pessoa pode fazer do conjunto de dados que ela pode consultar.

Validado contra a documentacao publica do Dynatrace em 2026-10-01.

## Decisao adotada

Nao usar um unico grupo para todas as verticais. Isso tornaria Porto Seguros, Porto Saude, Porto Servicos e Porto Bank indistinguiveis para autorizacao e eliminaria o isolamento entre os dados.

O modelo usa:

- duas policies reutilizadas por todos os SREs: recursos basicos e leitura de observabilidade;
- um grupo federado por vertical, com boundaries que limitam Dynatrace Classic pela Management Zone e Grail por `dt.security_context`;
- um grupo corporativo com leitura transversal, mas sem administracao;
- um grupo administrador com acesso completo ao ambiente de producao;
- um grupo aditivo de autoria de documentos para criar, editar e compartilhar dashboards e notebooks.

```text
Identidade no IdP
       |
       +-- ADMIN -----------------> ambiente inteiro + administracao
       |
       +-- SRE CORPORATIVO -------> ambiente inteiro, somente operacao/leitura
       |
       +-- SRE DA VERTICAL --------> mesma funcao SRE
       |                               + Management Zone da vertical
       |                               + dt.security_context da vertical
       |
       +-- AUTOR DE DOCUMENTOS ----> capacidade aditiva de colaborar
```

## Grupos propostos

| Grupo | Escopo | Policies principais |
|---|---|---|
| `PTO-DT-PRD-ADMINS` | Todo o ambiente de producao | `Admin User`, `Data Processing and Storage` e `All Grail data read access` |
| `PTO-DT-PRD-SRE-CORPORATIVO` | Todas as verticais | SRE base, leitura de observabilidade e `Settings Reader` |
| `PTO-DT-PRD-SRE-PORTO-SEGUROS` | Porto Seguros | SRE base e leitura de observabilidade com boundaries |
| `PTO-DT-PRD-SRE-PORTO-SAUDE` | Porto Saude | SRE base e leitura de observabilidade com boundaries |
| `PTO-DT-PRD-SRE-PORTO-SERVICOS` | Porto Servicos | SRE base e leitura de observabilidade com boundaries |
| `PTO-DT-PRD-SRE-PORTO-BANK` | Porto Bank | SRE base e leitura de observabilidade com boundaries |
| `PTO-DT-PRD-AUTORES-DOCUMENTOS` | Aditivo; nao concede dados sozinho | Criacao, edicao e compartilhamento de dashboards e notebooks |

As permissoes de um usuario sao cumulativas. Uma pessoa de vertical adicionada tambem a um grupo amplo pode contornar o boundary da vertical. Por isso, o grupo corporativo e o grupo administrador exigem aprovacao separada e revisao periodica.

## Pre-requisitos obrigatorios

Antes de liberar os grupos de vertical:

1. Criar e validar as quatro Management Zones de producao:
   - `PROD - Porto Seguros`
   - `PROD - Porto Saude`
   - `PROD - Porto Servicos`
   - `PROD - Porto Bank`
2. Garantir que logs, metricas, spans, eventos, entidades, Smartscape e dados de RUM tenham exatamente um dos seguintes valores em `dt.security_context`:
   - `porto/prod/seguros`
   - `porto/prod/saude`
   - `porto/prod/servicos`
   - `porto/prod/bank`
3. Confirmar que dados sem `dt.security_context` nao sao necessarios para os SREs de vertical. Com o menor privilegio adotado, esses registros ficam invisiveis para eles.
4. Manter pelo menos uma conta administrativa de emergencia nao federada, protegida por MFA e armazenada no cofre corporativo.
5. Testar as permissoes efetivas com um usuario positivo e um usuario negativo por vertical antes do rollout.

Management Zones nao protegem automaticamente os registros do Grail. Logs, metricas, traces/spans e eventos precisam receber `dt.security_context` na origem ou no OpenPipeline. Para entidades monitoradas, configure o mapeamento em **Settings > Topology model > Grail Security Context**.

## Arquivos

- [`group_management.md`](group_management.md): catalogo de grupos, associacoes e matriz de testes.
- [`policy_management.md`](policy_management.md): policies, boundaries e justificativas de seguranca.
- [`user_management.md`](user_management.md): federacao, ciclo de vida, aprovacao e recertificacao.
- [`account-management.example.yaml`](account-management.example.yaml): exemplo declarativo para Monaco; substitua o ID do ambiente antes de usar.

## Implantacao resumida

1. Substituir `REPLACE_WITH_PROD_ENVIRONMENT_ID` no YAML pelo ID real do ambiente.
2. Criar/validar as Management Zones e a classificacao `dt.security_context`.
3. Implantar policies, boundaries e grupos em uma conta/ambiente de teste.
4. Configurar os claims SAML ou provisionar os grupos por SCIM conforme [`user_management.md`](user_management.md).
5. Verificar **Effective policies** e executar a matriz de testes de [`group_management.md`](group_management.md).
6. Promover para producao e registrar o owner de cada grupo.

O arquivo YAML e um template: ele nao deve ser aplicado sem preencher o ambiente e validar os nomes das Management Zones existentes.

## Referencias oficiais

- [Conceder acesso ao Dynatrace](https://docs.dynatrace.com/docs/manage/identity-access-management/use-cases/access-platform)
- [Policies padrao do Dynatrace](https://docs.dynatrace.com/docs/manage/identity-access-management/permission-management/default-policies)
- [Policy boundaries](https://docs.dynatrace.com/docs/manage/identity-access-management/permission-management/manage-user-permissions-policies/iam-policy-boundaries)
- [Permissoes no Grail](https://docs.dynatrace.com/docs/platform/grail/organize-data/assign-permissions-in-grail)
- [Compartilhar documentos](https://docs.dynatrace.com/docs/discover-dynatrace/get-started/dynatrace-ui/share)
- [Configuracao de Account Management no Monaco](https://docs.dynatrace.com/docs/deliver/configuration-as-code/monaco/configuration/account-configuration)
