# Dashboard operacional — Luna 7 / Dynatrace

**Revisão:** 9 de setembro de 2026  
**Destino:** aplicativo Dashboards com DQL/Grail, no formato Document Store; não é um dashboard Classic.  
**Escopo assumido:** Luna Network HSM 7. Métricas de appliance, disco e interfaces precisam ser revistas se o produto for PCIe/USB ou outra modalidade.  
**Estado da entrega:** modelo parametrizável. O JSON entregue contém 18 cartões de indicadores com `SEM MAPEAMENTO`, sem valores simulados, e 25 blocos Markdown. Não houve consulta, implantação nem teste de execução no tenant do usuário.

## 1. O que está pronto e o que depende do ambiente

O layout, os textos abaixo das métricas, a escala de severidades, as definições de thresholds e os modelos de consultas estão no pacote. O gerador usa o formato exemplificado no repositório oficial da Dynatrace [D1–D3]. O conteúdo do tenant — nomes reais das métricas, dimensões, unidades, topologia, origem dos percentis e limites de capacidade — não foi fornecido e não é presumido. Assim, um cartão só passa a consultar uma métrica após o mapeamento. Os thresholds são aplicados pelo gerador aos cartões mapeados; nos cartões pendentes, a tabela de aviso e o Markdown continuam visíveis.

A documentação pública principal da Thales não pôde ser acessada nesta pesquisa. Foi possível consultar uma cópia preservada da documentação do fabricante para Luna 7.2 [T1], que descreve alguns campos da SAFENET-HSM-MIB. Essa referência histórica não comprova todos os campos, limites ou comportamentos da revisão instalada. Nenhum máximo universal de sessões, TPS, temperatura ou quantidade de partições foi inventado.

## 2. Política de severidade

| Classificação | Critério | Observação |
|---|---|---|
| NORMAL | Utilização válida abaixo de 85%, sem evidência de incidente | Operação normal não deve virar SEV1. |
| SEV1 | Acompanhamento informativo | Proposta para preencher a escala; nenhum threshold numérico foi definido pelo usuário. |
| SEV2 | Utilização ≥85% e ≤95% | Aplicável somente a percentuais de capacidade com denominador válido. |
| SEV3 | Utilização >95% | 95,000% permanece SEV2. 100% de uso, isoladamente, não é SEV5. |
| SEV4 | Gargalo confirmado | Contenção com evidência de degradação; não é apenas um percentual alto. |
| SEV5 | Indisponibilidade confirmada | Maior criticidade. Indicar se o escopo é equipamento, partição ou serviço. |

**Precedência no mesmo escopo:** SEV5 > SEV4 > SEV3 > SEV2 > SEV1. Uma condição SEV5 em um equipamento não implica automaticamente SEV5 no serviço HA que permanece disponível. Não inverter a escala para a convenção usual de SEV1 crítico.

**Cores propostas:** normal verde; SEV1 azul; SEV2 amarelo; SEV3 laranja; SEV4 vermelho; SEV5 vinho. O texto da severidade permanece obrigatório: a cor não é a única forma de leitura. Cores de alertas térmicos, falhas físicas ou orçamento de erro não atribuem, por si, uma severidade de incidente; a classificação depende do escopo e da avaliação operacional.

Os limites de 85% e 95% são a política operacional solicitada pelo usuário, não uma alegação de recomendação universal da Thales. Eles não se aplicam indiscriminadamente a temperatura em Celsius, RPM, estado binário, taxa de erro, HA, latência ou throughput bruto.

## 3. Organização visual

| Faixa | Indicadores | Visualização após mapeamento |
|---|---|---|
| Situação operacional | Severidade por escopo; disponibilidade funcional; HA; idade da telemetria | Tabelas de estado e série de idade da coleta |
| Capacidade do HSM | Ocupação criptográfica real; armazenamento por partição; alocação global; sessões | Séries por recurso com SEV2 ≥85% e SEV3 >95% |
| Appliance e rede | CPU; RAM; filesystem; rede por direção | Séries por equipamento, filesystem e interface |
| Desempenho | Latência p95; operações/s; fila; taxa de erro | Séries para correlação entre demanda, espera e falha |
| Saúde física | Temperaturas; fontes e ventiladores | Séries por sensor e tabela por componente |

O layout usa uma grade de 24 colunas, com dois indicadores por linha. Cada indicador tem um bloco Markdown de um único parágrafo imediatamente abaixo, com a mesma largura; não há sobreposição no JSON gerado. A estrutura segue os exemplos de layout e visualização do repositório oficial Dynatrace [D1–D2].

Configuração inicial sugerida na interface: últimas 2 horas, atualização a cada 1 minuto. Não há intervalo de análise fixado nas consultas: elas respeitam o período do dashboard e usam buckets de 1 minuto. Os cartões de estado mostram o **último bucket do período selecionado**, e não o estado em tempo real quando o usuário seleciona um período passado. Uma visão histórica não substitui detecção contínua de indisponibilidade.

O filtro de texto `HSM` só é criado quando alguma consulta mapeada o utiliza. Vazio significa todos os valores presentes nas séries; preenchido, exige correspondência exata na dimensão mapeada. Para sinais HA ou de serviço, use um identificador de correlação coerente; não force associação a um membro físico quando o sinal representar um grupo lógico.

## 4. Indicadores e parágrafos prontos para os Markdown tiles

Os parágrafos abaixo são os mesmos usados no modelo inicial. Valores opcionais homologados de latência, erro e temperatura podem ser acrescentados pelo gerador quando configurados.

### 01. Severidade por escopo

Apresenta a classificação operacional já avaliada pelo processo de incidentes, separando serviço, partição e equipamento para não transformar automaticamente a falha de um membro redundante em queda do serviço. **Máximo: SEV5**; **SEV1** fica reservado a acompanhamento informativo, como proposta, sem marcar operação normal como incidente; **SEV2 ≥85% até 95%**, **SEV3 >95%**, **SEV4 gargalo comprovado** e **SEV5 indisponibilidade confirmada**. O cartão mostra o último bucket do período selecionado; ausência de amostra é **SEM DADOS**, nunca normal.

### 02. Disponibilidade funcional · 0/1

Mostra o resultado de um teste funcional autorizado no caminho real da aplicação, sem tratar resposta a ping ou SNMP como prova suficiente de operação criptográfica. **Máximo: 1 = teste bem-sucedido**; **0 = falha a confirmar e correlacionar**; indisponibilidade confirmada do serviço, da partição ou do equipamento é **SEV5 no respectivo escopo**. **85%/95% não se aplicam ao estado binário**; sem amostra ou sem execução do teste, mostrar **SEM DADOS**, e não concluir que o HSM caiu.

### 03. HA · membros disponíveis / esperados

Compara os membros disponíveis com o inventário esperado de cada grupo HA, observado no cliente que utiliza o serviço. **Máximo: quantidade esperada, não um número fixo**; menos membros disponíveis significa perda de redundância, mas não prova interrupção do serviço; zero membros exige confirmação funcional para **SEV5 do serviço**. A indisponibilidade de um membro é **SEV5 daquele equipamento**; sobrecarga ou filas nos sobreviventes podem caracterizar **SEV4**. **85%/95% não são thresholds de saúde de HA**.

### 04. Idade da última coleta válida · segundos

Indica há quanto tempo chegou a última coleta válida, evitando que um valor antigo permaneça com aparência de saudável. **Não há máximo físico**; adotar inicialmente **180 s para uma coleta a cada 60 s**, como parâmetro operacional proposto, e ajustar ao intervalo efetivo; acima dessa janela, sinalizar **TELEMETRIA DESATUALIZADA**. **85%/95% não se aplicam** e ausência de coleta não é, isoladamente, **SEV5 do HSM**; verificar coletor, caminho de rede, autenticação e o teste funcional independente.

### 05. Utilização criptográfica real · %

Acompanha a utilização real do motor criptográfico somente quando a origem expõe um percentual de ocupação com semântica comprovada; **hsmPerformance indica nível de desempenho e não deve alimentar este gráfico**. **Máximo: 100% de ocupação**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Elevar para **SEV4** somente com evidência de gargalo, como latência fora do objetivo acompanhada de fila; indisponibilidade confirmada é **SEV5**. Sem a métrica real, manter **NÃO COLETADO**, em vez de inferir uso a partir de TPS sem capacidade homologada.

### 06. Armazenamento ocupado por partição · %

Mostra o espaço ocupado na partição, calculado por **bytes em uso ÷ capacidade total da própria partição ×100**, sem confundir esse armazenamento com RAM do appliance. **Máximo: 100% da capacidade total reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Conferir também bytes livres e tendência de crescimento; **SEV4** exige restrição efetiva à operação e **SEV5**, indisponibilidade confirmada no escopo afetado. Não excluir chaves ou objetos como ação automática para liberar espaço.

### 07. Armazenamento alocado no HSM · %

Mostra a parcela do armazenamento global alocada no HSM, usando **bytes alocados ÷ bytes totais ×100**, como visão de planejamento de capacidade. **Máximo: 100% do total reportado**; **SEV2 ≥85% até 95%** e **SEV3 >95%**, com revisão de aplicabilidade quando a alocação integral for intencional. **Alocação global não equivale automaticamente a partições cheias nem a falta de espaço para novas chaves**; correlacionar o espaço livre dentro de cada partição antes de declarar gargalo **SEV4** ou indisponibilidade **SEV5**.

### 08. Sessões utilizadas / limite aplicável · %

Apresenta **sessões simultâneas em uso ÷ limite efetivo do mesmo escopo ×100**, mantendo visíveis cliente e partição para localizar concentração ou vazamento de sessões. **Máximo: limite confirmado para esse pool, cliente ou partição**, sem adotar um valor universal para Luna 7; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Espera por sessão, esgotamento do pool ou aumento de latência podem confirmar **SEV4**; falha funcional que torne o serviço indisponível é **SEV5**. Sem limite conhecido, mostrar somente a contagem bruta e não fabricar um percentual.

### 09. CPU do appliance · %

Exibe o maior percentual de CPU do appliance observado em cada minuto para destacar picos sem os diluir na média entre equipamentos. **Máximo: 100% para a utilização normalizada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. CPU elevada deve ser correlacionada com latência, filas e atividade do appliance antes de ser classificada como gargalo **SEV4**; isoladamente não confirma indisponibilidade **SEV5**. Não somar percentuais de múltiplos núcleos como se o resultado ainda tivesse máximo de 100%.

### 10. Memória RAM do appliance · %

Acompanha o percentual de memória RAM efetivamente comprometida conforme a semântica validada do coletor, sem confundir RAM com armazenamento de chaves ou considerar todo cache recuperável como pressão real. **Máximo: 100% da RAM utilizável reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Confirmar pressão efetiva, falhas de alocação e impacto no atendimento antes de declarar gargalo **SEV4**; indisponibilidade comprovada é **SEV5**. Uma origem com apenas memória livre requer validação adicional antes de ativar alertas.

### 11. Filesystem do appliance · %

Mostra a ocupação de cada filesystem relevante do appliance, sem misturar partições distintas em uma média nem confundir o disco do sistema com armazenamento interno de objetos do HSM. **Máximo: 100% da capacidade utilizável informada para o filesystem**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Falhas efetivas de escrita ou restrição ao atendimento podem elevar a **SEV4**; indisponibilidade confirmada é **SEV5**. A equipe deve preservar logs de auditoria e seguir procedimentos aprovados, sem limpeza automática de arquivos.

### 12. Utilização de rede por direção · %

Compara o tráfego por segundo com a velocidade efetiva da interface, separando **recepção e transmissão** para não somar as duas direções de um enlace full-duplex. **Máximo: 100% por direção da capacidade nominal válida**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Perdas, retransmissões ou latência com contenção sustentada podem confirmar gargalo **SEV4**; perda de comunicação que resulte em indisponibilidade é **SEV5 no escopo afetado**. O percentual é inválido quando a velocidade do enlace é desconhecida ou foi coletada incorretamente.

### 13. Latência p95 de origem · ms

Mostra a latência p95 calculada na janela da origem, por cliente, partição e operação, usando o máximo dos valores p95 emitidos em cada minuto; isso **não é o p95 global do período selecionado**. **Não existe máximo universal em milissegundos**: o limite é o **objetivo de latência homologado por operação**, que deve ser configurado antes do alerta. **85%/95% não se aplicam diretamente a milissegundos**; violação sustentada do objetivo acompanhada de contenção pode confirmar **SEV4**, e interrupção funcional confirmada é **SEV5**.

### 14. Throughput por operação · operações/s

Apresenta o volume efetivo de operações por segundo, separado por operação e partição, para correlacionar demanda, latência e utilização do HSM. **O máximo depende de modelo, licença, algoritmo, tamanho da chave, mecanismo e carga homologada**; não adotar um TPS universal nem interpretar pico observado como capacidade certificada. **85%/95% só se aplicam a uma razão com capacidade válida para a mesma carga**; um platô de throughput acompanhado de fila e latência pode confirmar **SEV4**, enquanto volume zero sem demanda não prova indisponibilidade **SEV5**.

### 15. Fila de espera por cliente/pool · operações

Acompanha operações aguardando atendimento no cliente, pool ou aplicação que efetivamente exponha essa fila, indicando o local da medição para não atribuir toda espera ao motor criptográfico. **Máximo: capacidade configurada da fila, quando existir**; sem esse limite, exibir a contagem e não aplicar **85%/95%**. Crescimento sustentado com latência acima do objetivo ou falhas de aquisição de sessão caracteriza evidência de gargalo **SEV4**; interrupção funcional confirmada é **SEV5**. Fila não coletada deve aparecer como **NÃO COLETADO**, e nunca como zero.

### 16. Taxa de erro por operação · %

Mostra **operações falhas ÷ tentativas totais ×100** da mesma janela, distinguindo timeouts, erros de sessão, autenticação e falhas criptográficas na investigação. **Máximo matemático: 100%; alvo operacional: 0% ou orçamento de erro aprovado**, sem usar **85%/95% como faixas aceitáveis de erro**. Falhas que evidenciem contenção e degradação podem compor **SEV4**; indisponibilidade confirmada do escopo é **SEV5**. Sem tentativas, manter o valor indefinido; uma única operação inválida não comprova indisponibilidade de todo o serviço.

### 17. Temperatura por sensor · °C

Exibe a temperatura absoluta de cada sensor, mantendo separado o sensor interno do HSM, o do appliance e a condição ambiental quando disponíveis. **Máximo e thresholds: limites documentados para o sensor e a revisão exata do equipamento**, sem fixar um número não confirmado e sem converter Celsius em percentual de capacidade. **85%/95% não se aplicam**; alarme físico exige atuação de infraestrutura e correlação com impacto, gargalo comprovado é **SEV4** e indisponibilidade confirmada é **SEV5**. Sem limites validados, o gráfico fica sem linhas térmicas automáticas.

### 18. Fontes e ventiladores · estado por componente

Mostra individualmente o estado de cada fonte e ventilador monitorado, com tradução validada dos códigos da origem. **Escala normalizada: 0 = saudável e 1 = falha; não é uma capacidade percentual**, portanto **85%/95% não se aplicam**. Uma falha com redundância preservada exige tratamento conforme o impacto sem presumir queda do serviço; degradação que produza gargalo confirmado é **SEV4**, e indisponibilidade do equipamento é **SEV5**. Não impor um RPM universal nem presumir número fixo de fontes ou ventiladores.

## 5. Campos do fabricante confirmados na referência histórica

| Campo da SAFENET-HSM-MIB | Significado documentado em Luna 7.2 [T1] | Uso no modelo |
|---|---|---|
| `hsmPartitionStorageTotalBytes` | Capacidade total de armazenamento da partição | Denominador da ocupação por partição |
| `hsmPartitionStorageAllocatedBytes` | Bytes alocados/em uso na partição | Numerador da ocupação por partição |
| `hsmPartitionStorageAvailableBytes` | Bytes disponíveis/não utilizados na partição | Conferência de capacidade livre |
| `hsmStorageTotalBytes` | Capacidade total de armazenamento do HSM | Denominador da alocação global |
| `hsmStorageAllocatedBytes` | Bytes alocados no HSM | Numerador da alocação global |
| `hsmStorageAvailableBytes` | Bytes disponíveis no HSM | Conferência da disponibilidade global |
| `hsmMaximumPartitions` | Número máximo permitido de partições | Consultar o valor real; não fixar um máximo para toda a família |
| `hsmPartitionsCreated` | Número de partições criadas | Inventário e eventual cartão adicional de capacidade |
| `hsmPartitionObjectCount` | Quantidade de objetos na partição | Diagnóstico; não é ocupação em bytes |
| `hsmPerformance` | Nível de desempenho do HSM | Não é uso de CPU nem ocupação criptográfica percentual |

Esses são nomes de objetos da MIB, **não chaves garantidas de métricas do Dynatrace**. Uma extensão pode usar nomes e dimensões diferentes. Os índices numéricos, os OIDs e a presença dos objetos na versão instalada devem ser confirmados na MIB distribuída com o equipamento; este pacote não fornece OIDs presumidos.

A referência histórica informa cache/atualização de tabelas SNMP a cada 60 segundos [T1]. Isso justifica não presumir detecção subsegundo por essa fonte; confirme o comportamento na versão em produção. A documentação também distingue clientes cadastrados, ativação de partição, objetos e armazenamento: nenhum desses elementos substitui automaticamente sessões simultâneas ou teste de disponibilidade.

## 6. Contrato das métricas e cuidados de cálculo

`mapeamento.json` contém identificadores internos, não nomes de métricas existentes. Cada entrada começa com `null`. Associar um identificador a um nome apenas conecta a consulta; não converte unidade, não cria uma métrica e não implanta um coletor. Os comentários de cada arquivo em `consultas_dql/` e o `manifesto.json` descrevem a origem necessária.

| Família | Contrato exigido |
|---|---|
| Percentuais de CPU, RAM, ocupação criptográfica, filesystem e rede | Gauge já normalizado em 0–100, com semântica validada; não em 0–1. |
| Armazenamento e sessões | Numerador e denominador do mesmo recurso, mesmo escopo, mesma unidade e coleta temporalmente compatível. Capacidade deve ser positiva. |
| Disponibilidade funcional | Gauge binário: 1 teste bem-sucedido, 0 falha. Códigos desconhecidos ou dados ausentes não são sucesso. |
| Severidade operacional | Gauge inteiro: 0 normal, 1–5 SEV1–SEV5; produzido por classificador que já avaliou evidência, persistência e escopo. Não é uma severidade nativa Dynatrace presumida. |
| HA | Quantidade de membros observados disponíveis e inventário esperado, do mesmo grupo lógico. |
| Idade da coleta | Gauge em segundos, produzido por um observador em execução; detecção externa de falta de dados do observador continua necessária. |
| Latência p95 | Gauge em milissegundos de p95 calculado pela origem, em janela conhecida. O gráfico mostra o maior p95 de origem no minuto, não recalcula um percentil global. |
| Throughput | Gauge de taxa em operações por segundo. Um contador acumulado não pode ser ligado diretamente à consulta de gauge. |
| Taxa de erro | Gauge em 0–100: falhas/tentativas da mesma janela; sem tentativas = valor indefinido. |
| Temperatura | Gauge em Celsius por sensor; limites reais e fonte documental obrigatórios para habilitar linhas térmicas. |
| Falha física | Estado normalizado por componente: 0 saudável, 1 falha; traduzir códigos nativos antes do mapeamento. |

As consultas de razão usam `max(numerador)` e `min(denominador)` em cada minuto: são uma visão conservadora com capacidade estável, não uma leitura instantânea sincronizada. Se o limite puder mudar dentro do minuto, ou as séries tiverem cadências/dimensões diferentes, substitua a consulta por uma razão calculada em pares de amostras na origem; não conclua saturação a partir de extremos que nunca coexistiram. Não aplique arredondamento antes de classificar: 95,01% é SEV3, mesmo que a apresentação mostre 95,0%.

Para evitar dupla contagem, preserve dimensões de instância, partição, cliente, pool ou interface que distinguem recursos reais. Se várias séries independentes forem agregadas sem essas dimensões, os extremos poderão se referir a recursos diferentes. Nesse caso, ajuste `query_overrides` em vez de forçar o contrato simplificado.

As séries mantêm lacunas: não usam preenchimento com zero nem interpolação de estado. O último bucket pode estar nulo ou a série pode não existir; ambas as situações exigem leitura de ausência de dados, não de normalidade. Uma consulta sem resultados não consegue inventariar equipamentos que desapareceram: use inventário esperado e detecção de ausência de telemetria fora do dashboard.

Para throughput a partir de contador, fazer conversão correta de delta/taxa no coletor ou substituir a DQL conforme o tipo de métrica ingerida, tratando resets e evitando derivar duas vezes uma taxa já normalizada. Para latência global, usar distribuição/histograma compatível ou eventos individuais; não calcular média de p95s. Para rede full-duplex, separar RX/TX e validar velocidade efetiva. Não limitar artificialmente a exibição em 100% para esconder falhas de unidade ou de denominador.

## 7. Como mapear e gerar o dashboard

O gerador é Python 3.10+ puro, sem dependências externas, sem acesso à rede e sem credenciais. Ele não altera o HSM nem publica nada no Dynatrace.

**Primeiro, confirme as métricas reais.** No tenant, obtenha as chaves, dimensões, tipo e unidade de cada métrica que já chega da extensão ou coletor. Não selecione uma chave apenas por semelhança de nome. Mantenha `null` para um indicador não coletado. A pesquisa nesta sessão não disponibilizou uma conexão Dynatrace para inspecionar essas informações.

**Em seguida, preencha `mapeamento.json`.** Para habilitar apenas o armazenamento da partição, por exemplo, mapeie `metrics.particao_bytes_ocupados`, `metrics.particao_bytes_totais`, `dimensions.hsm` e `dimensions.particao` com os nomes verdadeiros. Não copie literalmente os textos abaixo como nomes de métrica:

```json
{
  "metrics": {
    "particao_bytes_ocupados": "<CHAVE_REAL_DOS_BYTES_EM_USO>",
    "particao_bytes_totais": "<CHAVE_REAL_DA_CAPACIDADE_TOTAL>"
  },
  "dimensions": {
    "hsm": "<DIMENSAO_REAL_DO_HSM>",
    "particao": "<DIMENSAO_REAL_DA_PARTICAO>"
  }
}
```

Esse trecho é uma ilustração parcial: edite o arquivo completo fornecido. Uma dimensão também precisa existir nas métricas mapeadas. Para percentuais em 0–1, métricas cumulativas, dimensões diferentes por sinal ou fontes baseadas em eventos, use `query_overrides` com uma DQL validada em vez de fazer um mapeamento semanticamente incorreto. O override deve retornar os campos esperados pela visualização, como `valor`, `timeframe` e `interval` nos gráficos.

**Gere os arquivos em um diretório separado:**

```bash
python gerar_dashboard.py --config mapeamento.json --out ./gerado
```

O comando lista quantos dos 18 indicadores estão mapeados. `manifesto.json` detalha os campos faltantes. Um cartão incompleto continua exibindo `SEM MAPEAMENTO`; um cartão mapeado é marcado como `MAPEADO_NAO_EXECUTADO`, sem alegar validação no tenant. Não existe nenhum conjunto de dados demonstrativo escondido no pacote.

**Valide consultas e artefato no tenant.** O fluxo documentado pela Dynatrace requer explorar campos reais, executar cada consulta e validar antes da publicação [D3]. Substitua `$HSM` por um valor real ou por string vazia ao testar fora do dashboard. Os arquivos DQL ainda contendo `{{metric:...}}` ou `{{dimension:...}}` são modelos e não devem ser executados.

```bash
# Em um ambiente que já tenha dtctl instalado, configurado e autorizado:
dtctl query '<DQL_MATERIALIZADA_COM_VALOR_REAL_DO_FILTRO>' --plain

# Verificação sem persistir, conforme o fluxo oficial consultado:
dtctl apply -f ./gerado/dashboard-luna7.document.json -o yaml --dry-run
```

`dashboard-luna7.document.json` contém o envelope `name`, `type` e `content`, conforme o exemplo oficial de Document Store/dtctl. `dashboard-luna7.content.json` contém apenas o conteúdo interno; ele foi incluído para fluxos que aceitem essa representação, não como garantia de importação pela interface. Não envie nenhum dos dois à API de Dashboards Classic. A importação pela UI e a renderização não foram exercitadas nesta sessão.

**Publicação controlada após homologação:**

```bash
# Preserve uma cópia: a referência oficial informa remoção do arquivo local
# pelo dtctl apply após sucesso. Não use o único exemplar como entrada.
cp ./gerado/dashboard-luna7.document.json ./gerado/dashboard-luna7.publicar.json
dtctl apply -f ./gerado/dashboard-luna7.publicar.json -o yaml
```

O pacote cria um novo documento; não tem ID de dashboard existente. Para atualizar um dashboard já existente, baixe antes o documento atual e preserve as edições e o ID retornado pelo ambiente, conforme o procedimento oficial [D3]. Este gerador não implementa atualização in-place de documento existente.

## 8. Alertas e persistência — configuração separada

Os thresholds de cor são definições de visualização. **O pacote não cria detectores, Problems, Workflows, regras de correlação nem notificações.** A severidade SEV1–SEV5 é a convenção operacional do usuário e deve ser preservada no encaminhamento de incidentes; não é presumida como enumeração nativa de todos os campos de severidade da plataforma.

| Detecção | Regra operacional proposta para homologação | Recuperação proposta |
|---|---|---|
| Capacidade SEV2 | Valor ≥85% e ≤95%, persistindo por 5 min | Abaixo de 80% por 5 min |
| Capacidade SEV3 | Valor >95%, persistindo por 3 min | Abaixo de 90% por 5 min, reavaliando se SEV2 continua aplicável |
| Gargalo SEV4 | Por 5 min, latência acima do SLO homologado **e** evidência de contenção no mesmo caminho: fila crescente, espera por sessão/pool ou recurso saturado | Evidência de contenção e latência recuperadas por 5 min |
| Indisponibilidade SEV5 | Falha funcional confirmada no escopo; como proteção contra transientes, testar inicialmente 2 falhas consecutivas em uma sonda de 30–60 s, sujeito ao SLO | Testes funcionais recuperados e estabilidade confirmada |
| Telemetria ausente/desatualizada | Sem amostras válidas por 3 intervalos de coleta, como ponto de partida | Retorno estável da coleta e teste independente saudável |

Essas janelas são propostas de desenho, não parâmetros solicitados pelo usuário nem recomendações universais da Thales. Indisponibilidade já confirmada por outras evidências não deve esperar uma janela artificial para ser tratada. Configure histerese e deduplicação para não gerar simultaneamente SEV2 e SEV3 para o mesmo recurso; mantenha o maior nível aplicável sem perder o histórico.

A sonda funcional deve usar uma operação de teste autorizada, objeto/chave de teste aprovado e frequência homologada. Não criar ou apagar chaves produtivas, reinicializar o HSM, alterar políticas, habilitar cargas de benchmark ou realizar testes que disputem capacidade sem aprovação. Nenhuma dessas ações é executada pelo pacote.

## 9. Checklist de aceite e validações locais

Antes do uso operacional, confirmar no tenant as chaves e dimensões, unidades, significado de `hsmPerformance`, pares de capacidade, disponibilidade funcional, inventário HA, códigos físicos, limites térmicos e objetivos de latência. Exercitar 84,99%, 85%, 95%, 95,01% e 100%; esperar NORMAL, SEV2, SEV2, SEV3 e SEV3, respectivamente. Exercitar denominador zero, ausência de uma série, coleta interrompida, reset de contador e período histórico. Simular de forma autorizada perda de um membro com HA funcional e indisponibilidade completa; as classificações de componente e serviço não devem ser confundidas.

As verificações locais incluídas no pacote cobrem JSON bem formado, correspondência de IDs, ausência de sobreposição, um único parágrafo por explicação, posicionamento do Markdown imediatamente abaixo do indicador, fronteiras matemáticas de 85/95 e substituição de placeholders com entradas de teste isoladas. Elas **não comprovam** existência das métricas, autorização, disponibilidade de Grail, sintaxe/execução no tenant, compatibilidade da versão do app nem renderização final. O relatório é `validacao_local.json`.

## 10. Referências consultadas

A definição da política de severidade vem da solicitação do usuário. As demais referências abaixo sustentam a estrutura do artefato e os campos históricos citados; não atestam uma integração Luna/Dynatrace específica instalada no ambiente.

**[D1] Dynatrace — exemplo oficial de dashboard, thresholds e envelope JSON.** https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/assets/ExampleDashboard.json

**[D2] Dynatrace — tipos de tiles e campos exigidos por visualização.** https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/references/tiles.md

**[D3] Dynatrace — fluxo de criação, validação e publicação com dtctl.** https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/references/create-update.md

**[D4] Dynatrace — DQL Essentials e manipulação de séries.** https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-dql-essentials/SKILL.md

**[T1] Manual do fabricante Luna Network HSM 7.2 Rev C — SAFENET-HSM-MIB, cópia preservada por terceiro; referência histórica.** https://github.com/leifj/sunet_pages/blob/f56de75929e379697377bea66326612b6269aad7/007-013576-004_Luna_Network_HSM_Docs_7.2_RevC/snmp_safenet-hsm-mib.htm

