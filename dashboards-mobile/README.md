# Dashboard Mobile RUM & Experience Vitals

Use o arquivo conforme o método de instalação:

- **Importação pela interface do Dashboards:** `mobile-rum-experience-vitals.content.json`
- **Publicação como documento com `dtctl apply`:** `mobile-rum-experience-vitals.document.json`

O arquivo `.content.json` começa diretamente por `version`, `variables`, `tiles` e `layouts`. O arquivo `.document.json` contém o envelope `name`, `type` e `content` exigido pelo fluxo de documentos do `dtctl`.

Antes de publicar em outro tenant, valide as consultas e os valores das variáveis com dados reais desse ambiente.

O seletor **Frontend** é preenchido somente com aplicações mobile que publicaram a métrica de app start nos últimos 30 dias. Ele é de seleção única e carrega de forma independente dos filtros **Plataforma** e **TipoUsuario**; depois da escolha, todos os tiles usam o frontend selecionado. **Plataforma** continua permitindo Android, iOS ou ambos.
