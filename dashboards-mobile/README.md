# Dashboard Mobile RUM & Experience Vitals

Use o arquivo conforme o método de instalação:

- **Importação pela interface do Dashboards:** `mobile-rum-experience-vitals.content.json`
- **Publicação como documento com `dtctl apply`:** `mobile-rum-experience-vitals.document.json`

O arquivo `.content.json` começa diretamente por `version`, `variables`, `tiles` e `layouts`. O arquivo `.document.json` contém o envelope `name`, `type` e `content` exigido pelo fluxo de documentos do `dtctl`.

Antes de publicar em outro tenant, valide as consultas e os valores das variáveis com dados reais desse ambiente.
