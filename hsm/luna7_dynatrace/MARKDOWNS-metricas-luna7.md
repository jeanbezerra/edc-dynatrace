# Luna 7 — Markdown abaixo das métricas

**Legenda:** normal <85% | **SEV2: ≥85% e ≤95%** | **SEV3: >95%** | **SEV4: gargalo comprovado** | **SEV5: indisponibilidade confirmada no escopo afetado**.

## Severidade por escopo

Apresenta a classificação operacional já avaliada pelo processo de incidentes, separando serviço, partição e equipamento para não transformar automaticamente a falha de um membro redundante em queda do serviço. **Máximo: SEV5**; **SEV1** fica reservado a acompanhamento informativo, como proposta, sem marcar operação normal como incidente; **SEV2 ≥85% até 95%**, **SEV3 >95%**, **SEV4 gargalo comprovado** e **SEV5 indisponibilidade confirmada**. O cartão mostra o último bucket do período selecionado; ausência de amostra é **SEM DADOS**, nunca normal.

## Disponibilidade funcional · 0/1

Mostra o resultado de um teste funcional autorizado no caminho real da aplicação, sem tratar resposta a ping ou SNMP como prova suficiente de operação criptográfica. **Máximo: 1 = teste bem-sucedido**; **0 = falha a confirmar e correlacionar**; indisponibilidade confirmada do serviço, da partição ou do equipamento é **SEV5 no respectivo escopo**. **85%/95% não se aplicam ao estado binário**; sem amostra ou sem execução do teste, mostrar **SEM DADOS**, e não concluir que o HSM caiu.

## HA · membros disponíveis / esperados

Compara os membros disponíveis com o inventário esperado de cada grupo HA, observado no cliente que utiliza o serviço. **Máximo: quantidade esperada, não um número fixo**; menos membros disponíveis significa perda de redundância, mas não prova interrupção do serviço; zero membros exige confirmação funcional para **SEV5 do serviço**. A indisponibilidade de um membro é **SEV5 daquele equipamento**; sobrecarga ou filas nos sobreviventes podem caracterizar **SEV4**. **85%/95% não são thresholds de saúde de HA**.

## Idade da última coleta válida · segundos

Indica há quanto tempo chegou a última coleta válida, evitando que um valor antigo permaneça com aparência de saudável. **Não há máximo físico**; adotar inicialmente **180 s para uma coleta a cada 60 s**, como parâmetro operacional proposto, e ajustar ao intervalo efetivo; acima dessa janela, sinalizar **TELEMETRIA DESATUALIZADA**. **85%/95% não se aplicam** e ausência de coleta não é, isoladamente, **SEV5 do HSM**; verificar coletor, caminho de rede, autenticação e o teste funcional independente.

## Utilização criptográfica real · %

Acompanha a utilização real do motor criptográfico somente quando a origem expõe um percentual de ocupação com semântica comprovada; **hsmPerformance indica nível de desempenho e não deve alimentar este gráfico**. **Máximo: 100% de ocupação**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Elevar para **SEV4** somente com evidência de gargalo, como latência fora do objetivo acompanhada de fila; indisponibilidade confirmada é **SEV5**. Sem a métrica real, manter **NÃO COLETADO**, em vez de inferir uso a partir de TPS sem capacidade homologada.

## Armazenamento ocupado por partição · %

Mostra o espaço ocupado na partição, calculado por **bytes em uso ÷ capacidade total da própria partição ×100**, sem confundir esse armazenamento com RAM do appliance. **Máximo: 100% da capacidade total reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Conferir também bytes livres e tendência de crescimento; **SEV4** exige restrição efetiva à operação e **SEV5**, indisponibilidade confirmada no escopo afetado. Não excluir chaves ou objetos como ação automática para liberar espaço.

## Armazenamento alocado no HSM · %

Mostra a parcela do armazenamento global alocada no HSM, usando **bytes alocados ÷ bytes totais ×100**, como visão de planejamento de capacidade. **Máximo: 100% do total reportado**; **SEV2 ≥85% até 95%** e **SEV3 >95%**, com revisão de aplicabilidade quando a alocação integral for intencional. **Alocação global não equivale automaticamente a partições cheias nem a falta de espaço para novas chaves**; correlacionar o espaço livre dentro de cada partição antes de declarar gargalo **SEV4** ou indisponibilidade **SEV5**.

## Sessões utilizadas / limite aplicável · %

Apresenta **sessões simultâneas em uso ÷ limite efetivo do mesmo escopo ×100**, mantendo visíveis cliente e partição para localizar concentração ou vazamento de sessões. **Máximo: limite confirmado para esse pool, cliente ou partição**, sem adotar um valor universal para Luna 7; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Espera por sessão, esgotamento do pool ou aumento de latência podem confirmar **SEV4**; falha funcional que torne o serviço indisponível é **SEV5**. Sem limite conhecido, mostrar somente a contagem bruta e não fabricar um percentual.

## CPU do appliance · %

Exibe o maior percentual de CPU do appliance observado em cada minuto para destacar picos sem os diluir na média entre equipamentos. **Máximo: 100% para a utilização normalizada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. CPU elevada deve ser correlacionada com latência, filas e atividade do appliance antes de ser classificada como gargalo **SEV4**; isoladamente não confirma indisponibilidade **SEV5**. Não somar percentuais de múltiplos núcleos como se o resultado ainda tivesse máximo de 100%.

## Memória RAM do appliance · %

Acompanha o percentual de memória RAM efetivamente comprometida conforme a semântica validada do coletor, sem confundir RAM com armazenamento de chaves ou considerar todo cache recuperável como pressão real. **Máximo: 100% da RAM utilizável reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Confirmar pressão efetiva, falhas de alocação e impacto no atendimento antes de declarar gargalo **SEV4**; indisponibilidade comprovada é **SEV5**. Uma origem com apenas memória livre requer validação adicional antes de ativar alertas.

## Filesystem do appliance · %

Mostra a ocupação de cada filesystem relevante do appliance, sem misturar partições distintas em uma média nem confundir o disco do sistema com armazenamento interno de objetos do HSM. **Máximo: 100% da capacidade utilizável informada para o filesystem**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Falhas efetivas de escrita ou restrição ao atendimento podem elevar a **SEV4**; indisponibilidade confirmada é **SEV5**. A equipe deve preservar logs de auditoria e seguir procedimentos aprovados, sem limpeza automática de arquivos.

## Utilização de rede por direção · %

Compara o tráfego por segundo com a velocidade efetiva da interface, separando **recepção e transmissão** para não somar as duas direções de um enlace full-duplex. **Máximo: 100% por direção da capacidade nominal válida**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Perdas, retransmissões ou latência com contenção sustentada podem confirmar gargalo **SEV4**; perda de comunicação que resulte em indisponibilidade é **SEV5 no escopo afetado**. O percentual é inválido quando a velocidade do enlace é desconhecida ou foi coletada incorretamente.

## Latência p95 de origem · ms

Mostra a latência p95 calculada na janela da origem, por cliente, partição e operação, usando o máximo dos valores p95 emitidos em cada minuto; isso **não é o p95 global do período selecionado**. **Não existe máximo universal em milissegundos**: o limite é o **objetivo de latência homologado por operação**, que deve ser configurado antes do alerta. **85%/95% não se aplicam diretamente a milissegundos**; violação sustentada do objetivo acompanhada de contenção pode confirmar **SEV4**, e interrupção funcional confirmada é **SEV5**.

## Throughput por operação · operações/s

Apresenta o volume efetivo de operações por segundo, separado por operação e partição, para correlacionar demanda, latência e utilização do HSM. **O máximo depende de modelo, licença, algoritmo, tamanho da chave, mecanismo e carga homologada**; não adotar um TPS universal nem interpretar pico observado como capacidade certificada. **85%/95% só se aplicam a uma razão com capacidade válida para a mesma carga**; um platô de throughput acompanhado de fila e latência pode confirmar **SEV4**, enquanto volume zero sem demanda não prova indisponibilidade **SEV5**.

## Fila de espera por cliente/pool · operações

Acompanha operações aguardando atendimento no cliente, pool ou aplicação que efetivamente exponha essa fila, indicando o local da medição para não atribuir toda espera ao motor criptográfico. **Máximo: capacidade configurada da fila, quando existir**; sem esse limite, exibir a contagem e não aplicar **85%/95%**. Crescimento sustentado com latência acima do objetivo ou falhas de aquisição de sessão caracteriza evidência de gargalo **SEV4**; interrupção funcional confirmada é **SEV5**. Fila não coletada deve aparecer como **NÃO COLETADO**, e nunca como zero.

## Taxa de erro por operação · %

Mostra **operações falhas ÷ tentativas totais ×100** da mesma janela, distinguindo timeouts, erros de sessão, autenticação e falhas criptográficas na investigação. **Máximo matemático: 100%; alvo operacional: 0% ou orçamento de erro aprovado**, sem usar **85%/95% como faixas aceitáveis de erro**. Falhas que evidenciem contenção e degradação podem compor **SEV4**; indisponibilidade confirmada do escopo é **SEV5**. Sem tentativas, manter o valor indefinido; uma única operação inválida não comprova indisponibilidade de todo o serviço.

## Temperatura por sensor · °C

Exibe a temperatura absoluta de cada sensor, mantendo separado o sensor interno do HSM, o do appliance e a condição ambiental quando disponíveis. **Máximo e thresholds: limites documentados para o sensor e a revisão exata do equipamento**, sem fixar um número não confirmado e sem converter Celsius em percentual de capacidade. **85%/95% não se aplicam**; alarme físico exige atuação de infraestrutura e correlação com impacto, gargalo comprovado é **SEV4** e indisponibilidade confirmada é **SEV5**. Sem limites validados, o gráfico fica sem linhas térmicas automáticas.

## Fontes e ventiladores · estado por componente

Mostra individualmente o estado de cada fonte e ventilador monitorado, com tradução validada dos códigos da origem. **Escala normalizada: 0 = saudável e 1 = falha; não é uma capacidade percentual**, portanto **85%/95% não se aplicam**. Uma falha com redundância preservada exige tratamento conforme o impacto sem presumir queda do serviço; degradação que produza gargalo confirmado é **SEV4**, e indisponibilidade do equipamento é **SEV5**. Não impor um RPM universal nem presumir número fixo de fontes ou ventiladores.

