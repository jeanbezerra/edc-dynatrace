# Gerenciamento de usuarios e federacao

## Modelo recomendado

Use o IdP corporativo como fonte de verdade. O Dynatrace deve receber a identidade e os grupos; as policies permanecem administradas no Dynatrace.

Claims/grupos sugeridos no IdP:

| Grupo no IdP | Grupo no Dynatrace |
|---|---|
| `PTO-DT-PRD-ADMINS` | `PTO-DT-PRD-ADMINS` |
| `PTO-DT-PRD-SRE-CORPORATIVO` | `PTO-DT-PRD-SRE-CORPORATIVO` |
| `PTO-DT-PRD-SRE-PORTO-SEGUROS` | `PTO-DT-PRD-SRE-PORTO-SEGUROS` |
| `PTO-DT-PRD-SRE-PORTO-SAUDE` | `PTO-DT-PRD-SRE-PORTO-SAUDE` |
| `PTO-DT-PRD-SRE-PORTO-SERVICOS` | `PTO-DT-PRD-SRE-PORTO-SERVICOS` |
| `PTO-DT-PRD-SRE-PORTO-BANK` | `PTO-DT-PRD-SRE-PORTO-BANK` |
| `PTO-DT-PRD-AUTORES-DOCUMENTOS` | `PTO-DT-PRD-AUTORES-DOCUMENTOS` |

## SAML ou SCIM

### SAML com group claims

E a opcao preferida quando compartilhar dashboards/notebooks diretamente com grupos pela interface e um requisito forte.

- Crie primeiro os grupos no Dynatrace.
- Configure o atributo federado da integracao SAML para receber os grupos/roles.
- Em cada grupo, adicione o valor exato do claim em **SAML Group Attribute Value**.
- A associacao e recalculada no login.
- Ao adicionar o primeiro valor SAML a um grupo local, os membros locais existentes sao removidos; teste com um grupo piloto.

Mantenha uma conta de emergencia nao federada ate validar o fluxo em janela anonima.

### SCIM

E a opcao preferida para provisionamento e desprovisionamento continuo de usuarios e grupos.

- O IdP e o owner dos grupos SCIM; nao os altere no Dynatrace.
- As permissions ainda precisam ser vinculadas aos grupos no Dynatrace.
- Restrinja no IdP quais grupos sao sincronizados.
- A remocao ou desativacao no IdP deve desativar o usuario no Dynatrace.

Limitacao relevante: usuarios pertencentes somente a grupos SCIM nao aparecem na interface de compartilhamento de dashboards/notebooks com pessoas ou grupos, a menos que tambem sejam adicionados a um grupo local Dynatrace. Se SCIM for obrigatorio, escolha uma destas estrategias:

1. usar links autenticados de visualizacao/edicao para colaboracoes ad hoc;
2. compartilhar para todo o ambiente somente em modo leitura e apenas para conteudo publicavel;
3. manter grupos locais de colaboracao por automacao, com owner e reconciliacao; ou
4. usar SAML group claims para autorizacao e reservar SCIM ao ciclo de vida, depois de homologar a convivencia dos dois modelos.

Nao crie manualmente grupos locais com o mesmo nome de grupos SCIM sem uma convencao clara; isso favorece atribuicoes ao grupo errado.

## Fluxo de concessao

1. O gestor solicita um papel e informa a vertical.
2. O owner do grupo valida necessidade, ambiente e prazo.
3. Seguranca aprova `ADMINS`, `SRE-CORPORATIVO` e acessos fora da vertical.
4. O IdP adiciona a pessoa ao grupo adequado.
5. A pessoa autentica novamente para atualizar claims SAML, quando aplicavel.
6. O administrador confere **Effective policies**.
7. Um teste positivo e um negativo sao registrados no chamado.

Para autoria, adicionar `PTO-DT-PRD-AUTORES-DOCUMENTOS` sem remover o grupo SRE. Essa associacao e aditiva e nao fornece dados por si so.

## Alteracao de vertical

Ao transferir uma pessoa:

1. remover o grupo da vertical anterior;
2. adicionar o grupo da nova vertical;
3. invalidar sessoes conforme a politica corporativa;
4. confirmar a nova policy efetiva;
5. testar que os dados da vertical anterior deixaram de ser acessiveis.

Evite um periodo de sobreposicao. Se ele for indispensavel, registre prazo e aprovacao.

## Desligamento

- Desabilitar/remover a identidade no IdP.
- Revogar sessoes e tokens pessoais conforme o procedimento corporativo.
- Transferir ownership de dashboards e notebooks operacionais antes de excluir definitivamente a conta.
- Revisar documentos compartilhados por links criados pela pessoa.
- Remover associacoes locais residuais.

Tokens OAuth ou de aplicativo movel podem ter ciclo de vida proprio. O desligamento deve inclui-los explicitamente; nao presuma que remover somente o claim SAML encerra todo acesso ja emitido.

## Contas administrativas de emergencia

- Manter no minimo duas identidades nominais, nao compartilhadas.
- Nao federar essas identidades.
- Exigir MFA, senha no cofre, alerta de uso e revisao mensal.
- Nao usar no dia a dia.
- Testar acesso de forma controlada a cada trimestre.

## Recertificacao

| Grupo | Frequencia | Evidencia minima |
|---|---|---|
| Admins | mensal | owner, justificativa, ultimo uso e MFA |
| SRE Corporativo | trimestral | funcao atual e necessidade transversal |
| SREs de vertical | trimestral | lotacao e vertical correta |
| Autores de documentos | trimestral | necessidade de criacao/edicao |

Na recertificacao, compare IdP, associacoes exibidas no Dynatrace e **Effective policies**. Como permissoes de todos os grupos sao somadas, a revisao deve procurar especialmente grupos amplos herdados.

## Compartilhamento de dashboards e notebooks

- Preferir compartilhamento nominal ou com grupo e `Can view`/`Can edit`.
- Usar **Allow editors to share** somente quando os editores tambem puderem delegar acesso.
- Tratar links `Can edit` como delegacao: qualquer usuario autenticado do ambiente que receber o link obtem o mesmo nivel.
- Um documento compartilhado nao amplia o acesso aos dados. DQL e codigo executam com as permissions de quem abre o documento.
- Codigo de terceiros em dashboards/notebooks executa com a identidade e as permissions do usuario atual; revisar antes de aceitar e executar.
- Antes de transferir ownership, criar copia quando o owner atual precisar manter acesso.

## Referencias oficiais

- [Gerenciamento de grupos](https://docs.dynatrace.com/docs/manage/identity-access-management/user-and-group-management/access-group-management)
- [SAML e autorizacao por grupos](https://docs.dynatrace.com/docs/manage/identity-access-management/user-and-group-management/access-saml)
- [SCIM](https://docs.dynatrace.com/docs/manage/identity-access-management/user-and-group-management/access-scim)
- [Compartilhar documentos](https://docs.dynatrace.com/docs/discover-dynatrace/get-started/dynatrace-ui/share)
