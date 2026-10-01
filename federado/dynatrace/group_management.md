# Gerenciamento de grupos

## Convencao de nomes

Formato: `PTO-DT-<AMBIENTE>-<PAPEL>-<ESCOPO>`.

- `PTO`: Porto.
- `DT`: Dynatrace.
- `PRD`: producao.
- nomes sem acentos evitam divergencias entre IdP, SAML, SCIM, API e automacao.

## Catalogo

### `PTO-DT-PRD-ADMINS`

Administradores tecnicos do ambiente Dynatrace de producao.

- Acesso: administracao completa de Platform Services, ingestao/configuracao de dados e leitura de todo o Grail.
- Policies: `Admin User`, `Data Processing and Storage`, `All Grail data read access`.
- Boundary: nenhum.
- Owner sugerido: Observabilidade Corporativa.
- Aprovacao: owner da plataforma e Seguranca.
- Recertificacao: mensal.

Este grupo administra o ambiente, mas nao deve conceder automaticamente acesso a faturamento, gestao de pessoas ou configuracao da conta. Quando isso for necessario, use separadamente o grupo padrao `Account Admins` e limite-o a poucos responsaveis.

### `PTO-DT-PRD-SRE-CORPORATIVO`

SREs responsaveis pela operacao transversal.

- Acesso: leitura de observabilidade de todas as verticais, recursos de analise e leitura de Settings.
- Policies: `PTO - PROD - SRE Base`, `PTO - PROD - Observability Data Read`, `Settings Reader`.
- Boundary: nenhum.
- Nao inclui: alteracao de Settings, OpenPipeline, buckets, extensoes, credenciais, usuarios ou policies.
- Owner sugerido: SRE Corporativo.
- Recertificacao: trimestral.

### Grupos SRE de vertical

Os quatro grupos usam as mesmas duas policies. Somente os boundaries mudam.

| Grupo | Management Zone | `dt.security_context` |
|---|---|---|
| `PTO-DT-PRD-SRE-PORTO-SEGUROS` | `PROD - Porto Seguros` | `porto/prod/seguros` |
| `PTO-DT-PRD-SRE-PORTO-SAUDE` | `PROD - Porto Saude` | `porto/prod/saude` |
| `PTO-DT-PRD-SRE-PORTO-SERVICOS` | `PROD - Porto Servicos` | `porto/prod/servicos` |
| `PTO-DT-PRD-SRE-PORTO-BANK` | `PROD - Porto Bank` | `porto/prod/bank` |

Cada grupo recebe:

- `PTO - PROD - SRE Base`, restringida pelo boundary de Management Zone da vertical;
- `PTO - PROD - Observability Data Read`, restringida pelo boundary de Grail da vertical.

Nao associar as duas restrictions a policies diferentes em uma unica operacao sem visualizar a policy efetiva. Uma condition nao suportada por uma permission pode deixar essa permission sem filtro. O template separa o boundary Classic do boundary Grail para tornar esse comportamento explicito.

### `PTO-DT-PRD-AUTORES-DOCUMENTOS`

Entitlement aditivo para autoria e colaboracao em Dashboards e Notebooks.

- Pode criar, ler, atualizar e excluir os proprios documentos.
- Pode compartilhar por ambiente ou diretamente e participar de documentos com `Can edit`.
- Pode restaurar ou remover os proprios documentos da lixeira.
- Nao recebe `document:documents:admin` e nao administra documentos de outros owners.
- Nao concede acesso a dados. O usuario tambem precisa pertencer ao grupo SRE adequado.
- Owner sugerido: Observabilidade Corporativa.
- Recertificacao: trimestral.

O owner de um dashboard ou notebook pode habilitar **Allow editors to share**. Sem essa opcao, um colaborador com `Can edit` edita o documento, mas somente o owner altera o compartilhamento.

## Composicao permitida

| Perfil da pessoa | Grupos |
|---|---|
| Administrador do ambiente | `PTO-DT-PRD-ADMINS` e, somente se necessario, `Account Admins` |
| SRE corporativo leitor | `PTO-DT-PRD-SRE-CORPORATIVO` |
| SRE corporativo autor | `PTO-DT-PRD-SRE-CORPORATIVO` + `PTO-DT-PRD-AUTORES-DOCUMENTOS` |
| SRE de vertical leitor | exatamente um grupo SRE de vertical |
| SRE de vertical autor | grupo SRE da vertical + `PTO-DT-PRD-AUTORES-DOCUMENTOS` |

Uma pessoa que atua em duas verticais pode receber os dois grupos correspondentes. Nao a mova para o grupo corporativo apenas para simplificar a atribuicao.

## Combinacoes proibidas ou sujeitas a excecao

- SRE de vertical + `PTO-DT-PRD-SRE-CORPORATIVO`: o acesso amplo vence na pratica porque policies `ALLOW` sao cumulativas.
- SRE de vertical + qualquer grupo padrao com leitura irrestrita do Grail.
- SRE de vertical + policy `All Grail data read access`.
- Usuario humano em grupos de service users ou automacoes.
- Uso de `DENY` condicional para tentar corrigir um `ALLOW` amplo: no Grail, alguns `DENY` condicionais sao executados como incondicionais.

## Matriz de homologacao

Execute com identidades de teste sem outras associacoes de grupo.

| Teste | Admin | SRE corp. | SRE da vertical | Autor sem grupo SRE |
|---|---:|---:|---:|---:|
| Entrar no ambiente PRD | Sim | Sim | Sim | Somente apps/documentos |
| Consultar dados da propria vertical | Sim | Sim | Sim | Nao |
| Consultar dados de outra vertical | Sim | Sim | Nao | Nao |
| Consultar registro sem `dt.security_context` | Sim | Sim | Nao | Nao |
| Alterar Settings | Sim | Nao | Nao | Nao |
| Criar dashboard/notebook | Sim | Com grupo Autor | Com grupo Autor | Sim, mas sem dados |
| Editar documento compartilhado com `Can edit` | Sim | Com grupo Autor | Com grupo Autor | Sim |
| Administrar documento de outro owner sem compartilhamento | Sim | Nao | Nao | Nao |

Para cada SRE de vertical, teste DQL nas tabelas `logs`, `metrics`, `events`, `spans`, `entities`, `smartscape`, `application.snapshots`, `user.events` e `user.sessions`. Um dashboard compartilhado nunca amplia o acesso aos dados: as queries sao executadas com as permissoes de quem o abre.

## Operacao

- Definir um owner e um substituto por grupo.
- Usar solicitacao formal para `ADMINS` e `SRE-CORPORATIVO`.
- Configurar expiracao para terceiros e acessos temporarios no IdP.
- Revisar as **Effective policies** depois de toda alteracao.
- Exportar mensalmente associacoes e comparar com o inventario aprovado.
- Remover o acesso no IdP; nao manter associacoes locais paralelas sem owner.
