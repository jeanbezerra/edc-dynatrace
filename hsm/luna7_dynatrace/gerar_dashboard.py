#!/usr/bin/env python3
"""Gera um dashboard Dynatrace (Document Store) sem inventar métricas.
Python 3.10+. Sem dependências externas e sem acesso à rede.
Edite mapeamento.json, execute e valide as DQLs no tenant antes de publicar.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

TITLE = "Luna 7 | Operação de HSM | SEV1 → SEV5"
COLORS = {"NORMAL": "#2F6862", "SEV1": "#3F8CFF", "SEV2": "#EEA53C", "SEV3": "#E87D2F", "SEV4": "#C62239", "SEV5": "#7A1030"}
LEGEND = "**Legenda:** normal <85% | **SEV2: ≥85% e ≤95%** | **SEV3: >95%** | **SEV4: gargalo comprovado** | **SEV5: indisponibilidade confirmada no escopo afetado**."
REFS = {
 "D1": "https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/assets/ExampleDashboard.json",
 "D2": "https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/references/tiles.md",
 "D3": "https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-app-dashboards/references/create-update.md",
 "D4": "https://github.com/Dynatrace/dynatrace-for-ai/blob/dc5787dc9c60b3ddbb7455cfcd64e93916767a94/skills/dt-dql-essentials/SKILL.md",
 "T1": "https://github.com/leifj/sunet_pages/blob/f56de75929e379697377bea66326612b6269aad7/007-013576-004_Luna_Network_HSM_Docs_7.2_RevC/snmp_safenet-hsm-mib.htm",
}

# As chaves abaixo são identificadores do modelo, NÃO nomes de métricas Dynatrace.
CARDS = [
 dict(id="severidade", section="01 · Situação operacional", title="Severidade por escopo", kind="severity", metrics=["severidade_operacional"], dims=["hsm", "escopo"], unit="SEV",
 source="Classificador operacional ou integração de incidentes; 0=normal, 1..5=SEV1..SEV5. Não é um campo nativo presumido.",
 text="Apresenta a classificação operacional já avaliada pelo processo de incidentes, separando serviço, partição e equipamento para não transformar automaticamente a falha de um membro redundante em queda do serviço. **Máximo: SEV5**; **SEV1** fica reservado a acompanhamento informativo, como proposta, sem marcar operação normal como incidente; **SEV2 ≥85% até 95%**, **SEV3 >95%**, **SEV4 gargalo comprovado** e **SEV5 indisponibilidade confirmada**. O cartão mostra o último bucket do período selecionado; ausência de amostra é **SEM DADOS**, nunca normal."),
 dict(id="disponibilidade", section="01 · Situação operacional", title="Disponibilidade funcional · 0/1", kind="availability", metrics=["disponibilidade_funcional"], dims=["hsm", "servico"], unit="estado",
 source="Teste funcional autorizado do caminho aplicação → cliente Luna → partição, com operação e chave de teste aprovadas; não usar apenas ICMP/SNMP.",
 text="Mostra o resultado de um teste funcional autorizado no caminho real da aplicação, sem tratar resposta a ping ou SNMP como prova suficiente de operação criptográfica. **Máximo: 1 = teste bem-sucedido**; **0 = falha a confirmar e correlacionar**; indisponibilidade confirmada do serviço, da partição ou do equipamento é **SEV5 no respectivo escopo**. **85%/95% não se aplicam ao estado binário**; sem amostra ou sem execução do teste, mostrar **SEM DADOS**, e não concluir que o HSM caiu."),
 dict(id="ha", section="01 · Situação operacional", title="HA · membros disponíveis / esperados", kind="ha", metrics=["ha_membros_disponiveis", "ha_membros_esperados"], dims=["hsm", "grupo_ha"], unit="membros",
 source="Estado observado pelo cliente Luna/HA e inventário de membros esperados. Dimensão hsm deve identificar o conjunto lógico para esta origem.",
 text="Compara os membros disponíveis com o inventário esperado de cada grupo HA, observado no cliente que utiliza o serviço. **Máximo: quantidade esperada, não um número fixo**; menos membros disponíveis significa perda de redundância, mas não prova interrupção do serviço; zero membros exige confirmação funcional para **SEV5 do serviço**. A indisponibilidade de um membro é **SEV5 daquele equipamento**; sobrecarga ou filas nos sobreviventes podem caracterizar **SEV4**. **85%/95% não são thresholds de saúde de HA**."),
 dict(id="telemetria", section="01 · Situação operacional", title="Idade da última coleta válida · segundos", kind="freshness", metrics=["idade_ultima_coleta_segundos"], dims=["hsm"], unit="s",
 source="Gauge de idade calculada por um observador vivo, em segundos. Deve ser acompanhado de detecção de ausência de dados do próprio observador.",
 text="Indica há quanto tempo chegou a última coleta válida, evitando que um valor antigo permaneça com aparência de saudável. **Não há máximo físico**; adotar inicialmente **180 s para uma coleta a cada 60 s**, como parâmetro operacional proposto, e ajustar ao intervalo efetivo; acima dessa janela, sinalizar **TELEMETRIA DESATUALIZADA**. **85%/95% não se aplicam** e ausência de coleta não é, isoladamente, **SEV5 do HSM**; verificar coletor, caminho de rede, autenticação e o teste funcional independente."),
 dict(id="cripto", section="02 · Capacidade do HSM", title="Utilização criptográfica real · %", kind="percent", metrics=["utilizacao_criptografica_pct"], dims=["hsm"], unit="%",
 source="Percentual real de ocupação/busy do motor, apenas se exposto e documentado pela coleta. hsmPerformance NÃO é esse percentual.",
 text="Acompanha a utilização real do motor criptográfico somente quando a origem expõe um percentual de ocupação com semântica comprovada; **hsmPerformance indica nível de desempenho e não deve alimentar este gráfico**. **Máximo: 100% de ocupação**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Elevar para **SEV4** somente com evidência de gargalo, como latência fora do objetivo acompanhada de fila; indisponibilidade confirmada é **SEV5**. Sem a métrica real, manter **NÃO COLETADO**, em vez de inferir uso a partir de TPS sem capacidade homologada."),
 dict(id="particao", section="02 · Capacidade do HSM", title="Armazenamento ocupado por partição · %", kind="ratio", metrics=["particao_bytes_ocupados", "particao_bytes_totais"], dims=["hsm", "particao"], unit="%",
 source="SAFENET-HSM-MIB: hsmPartitionStorageAllocatedBytes / hsmPartitionStorageTotalBytes × 100; hsmPartitionStorageAvailableBytes como conferência.",
 text="Mostra o espaço ocupado na partição, calculado por **bytes em uso ÷ capacidade total da própria partição ×100**, sem confundir esse armazenamento com RAM do appliance. **Máximo: 100% da capacidade total reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Conferir também bytes livres e tendência de crescimento; **SEV4** exige restrição efetiva à operação e **SEV5**, indisponibilidade confirmada no escopo afetado. Não excluir chaves ou objetos como ação automática para liberar espaço."),
 dict(id="armazenamento_hsm", section="02 · Capacidade do HSM", title="Armazenamento alocado no HSM · %", kind="ratio", metrics=["hsm_bytes_alocados", "hsm_bytes_totais"], dims=["hsm"], unit="%",
 source="SAFENET-HSM-MIB: hsmStorageAllocatedBytes / hsmStorageTotalBytes × 100; interpretar alocação global separadamente de ocupação por objetos.",
 text="Mostra a parcela do armazenamento global alocada no HSM, usando **bytes alocados ÷ bytes totais ×100**, como visão de planejamento de capacidade. **Máximo: 100% do total reportado**; **SEV2 ≥85% até 95%** e **SEV3 >95%**, com revisão de aplicabilidade quando a alocação integral for intencional. **Alocação global não equivale automaticamente a partições cheias nem a falta de espaço para novas chaves**; correlacionar o espaço livre dentro de cada partição antes de declarar gargalo **SEV4** ou indisponibilidade **SEV5**."),
 dict(id="sessoes", section="02 · Capacidade do HSM", title="Sessões utilizadas / limite aplicável · %", kind="ratio", metrics=["sessoes_ativas", "sessoes_limite"], dims=["hsm", "particao", "cliente"], unit="%",
 source="Sessões simultâneas reais e limite efetivo do mesmo pool/cliente/partição. Não substituir por clientes cadastrados ou conexões NTLS.",
 text="Apresenta **sessões simultâneas em uso ÷ limite efetivo do mesmo escopo ×100**, mantendo visíveis cliente e partição para localizar concentração ou vazamento de sessões. **Máximo: limite confirmado para esse pool, cliente ou partição**, sem adotar um valor universal para Luna 7; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Espera por sessão, esgotamento do pool ou aumento de latência podem confirmar **SEV4**; falha funcional que torne o serviço indisponível é **SEV5**. Sem limite conhecido, mostrar somente a contagem bruta e não fabricar um percentual."),
 dict(id="cpu", section="03 · Appliance e rede", title="CPU do appliance · %", kind="percent", metrics=["cpu_appliance_pct"], dims=["hsm"], unit="%",
 source="Utilização de CPU normalizada para 0..100, da coleta suportada do appliance; não confundir com ocupação criptográfica.",
 text="Exibe o maior percentual de CPU do appliance observado em cada minuto para destacar picos sem os diluir na média entre equipamentos. **Máximo: 100% para a utilização normalizada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. CPU elevada deve ser correlacionada com latência, filas e atividade do appliance antes de ser classificada como gargalo **SEV4**; isoladamente não confirma indisponibilidade **SEV5**. Não somar percentuais de múltiplos núcleos como se o resultado ainda tivesse máximo de 100%."),
 dict(id="ram", section="03 · Appliance e rede", title="Memória RAM do appliance · %", kind="percent", metrics=["ram_appliance_pct"], dims=["hsm"], unit="%",
 source="Percentual de RAM segundo semântica documentada da origem; distinguir memória disponível de mera memória livre e de cache recuperável.",
 text="Acompanha o percentual de memória RAM efetivamente comprometida conforme a semântica validada do coletor, sem confundir RAM com armazenamento de chaves ou considerar todo cache recuperável como pressão real. **Máximo: 100% da RAM utilizável reportada**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Confirmar pressão efetiva, falhas de alocação e impacto no atendimento antes de declarar gargalo **SEV4**; indisponibilidade comprovada é **SEV5**. Uma origem com apenas memória livre requer validação adicional antes de ativar alertas."),
 dict(id="disco", section="03 · Appliance e rede", title="Filesystem do appliance · %", kind="percent", metrics=["filesystem_appliance_pct"], dims=["hsm", "filesystem"], unit="%",
 source="Ocupação de cada filesystem relevante suportado pela origem, com denominador e reservas documentados.",
 text="Mostra a ocupação de cada filesystem relevante do appliance, sem misturar partições distintas em uma média nem confundir o disco do sistema com armazenamento interno de objetos do HSM. **Máximo: 100% da capacidade utilizável informada para o filesystem**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Falhas efetivas de escrita ou restrição ao atendimento podem elevar a **SEV4**; indisponibilidade confirmada é **SEV5**. A equipe deve preservar logs de auditoria e seguir procedimentos aprovados, sem limpeza automática de arquivos."),
 dict(id="rede", section="03 · Appliance e rede", title="Utilização de rede por direção · %", kind="percent", metrics=["rede_utilizacao_pct"], dims=["hsm", "interface", "direcao"], unit="%",
 source="100 × bits/s ÷ velocidade efetiva do enlace, separadamente para RX e TX. Taxas calculadas a partir de contadores com tratamento de resets.",
 text="Compara o tráfego por segundo com a velocidade efetiva da interface, separando **recepção e transmissão** para não somar as duas direções de um enlace full-duplex. **Máximo: 100% por direção da capacidade nominal válida**; **SEV2 ≥85% até 95%** e **SEV3 >95%**. Perdas, retransmissões ou latência com contenção sustentada podem confirmar gargalo **SEV4**; perda de comunicação que resulte em indisponibilidade é **SEV5 no escopo afetado**. O percentual é inválido quando a velocidade do enlace é desconhecida ou foi coletada incorretamente."),
 dict(id="latencia", section="04 · Desempenho observado pela aplicação", title="Latência p95 de origem · ms", kind="latency", metrics=["latencia_p95_ms"], dims=["hsm", "particao", "cliente", "operacao"], unit="ms",
 source="p95 em ms calculado pela origem em janelas conhecidas; não calcular média de percentis. Alternativamente, substituir a DQL por percentile de distribuição compatível.",
 text="Mostra a latência p95 calculada na janela da origem, por cliente, partição e operação, usando o máximo dos valores p95 emitidos em cada minuto; isso **não é o p95 global do período selecionado**. **Não existe máximo universal em milissegundos**: o limite é o **objetivo de latência homologado por operação**, que deve ser configurado antes do alerta. **85%/95% não se aplicam diretamente a milissegundos**; violação sustentada do objetivo acompanhada de contenção pode confirmar **SEV4**, e interrupção funcional confirmada é **SEV5**."),
 dict(id="throughput", section="04 · Desempenho observado pela aplicação", title="Throughput por operação · operações/s", kind="throughput", metrics=["operacoes_por_segundo"], dims=["hsm", "particao", "operacao"], unit="op/s",
 source="Gauge de taxa real de operações por segundo, ou DQL adaptada para contador com delta/rate apropriado; distinguir algoritmo, mecanismo e tamanho de chave.",
 text="Apresenta o volume efetivo de operações por segundo, separado por operação e partição, para correlacionar demanda, latência e utilização do HSM. **O máximo depende de modelo, licença, algoritmo, tamanho da chave, mecanismo e carga homologada**; não adotar um TPS universal nem interpretar pico observado como capacidade certificada. **85%/95% só se aplicam a uma razão com capacidade válida para a mesma carga**; um platô de throughput acompanhado de fila e latência pode confirmar **SEV4**, enquanto volume zero sem demanda não prova indisponibilidade **SEV5**."),
 dict(id="fila", section="04 · Desempenho observado pela aplicação", title="Fila de espera por cliente/pool · operações", kind="queue", metrics=["fila_operacoes_pendentes"], dims=["hsm", "particao", "cliente"], unit="operações",
 source="Fila explicitamente medida no cliente, pool ou aplicação; não presumir que uma fila do HSM esteja exposta na MIB.",
 text="Acompanha operações aguardando atendimento no cliente, pool ou aplicação que efetivamente exponha essa fila, indicando o local da medição para não atribuir toda espera ao motor criptográfico. **Máximo: capacidade configurada da fila, quando existir**; sem esse limite, exibir a contagem e não aplicar **85%/95%**. Crescimento sustentado com latência acima do objetivo ou falhas de aquisição de sessão caracteriza evidência de gargalo **SEV4**; interrupção funcional confirmada é **SEV5**. Fila não coletada deve aparecer como **NÃO COLETADO**, e nunca como zero."),
 dict(id="erros", section="04 · Desempenho observado pela aplicação", title="Taxa de erro por operação · %", kind="errors", metrics=["erros_operacoes_pct"], dims=["hsm", "particao", "cliente", "operacao"], unit="%",
 source="100 × operações falhas / tentativas totais da mesma janela, por origem; tentativas=0 deve resultar em nulo, não em sucesso ou falha presumidos.",
 text="Mostra **operações falhas ÷ tentativas totais ×100** da mesma janela, distinguindo timeouts, erros de sessão, autenticação e falhas criptográficas na investigação. **Máximo matemático: 100%; alvo operacional: 0% ou orçamento de erro aprovado**, sem usar **85%/95% como faixas aceitáveis de erro**. Falhas que evidenciem contenção e degradação podem compor **SEV4**; indisponibilidade confirmada do escopo é **SEV5**. Sem tentativas, manter o valor indefinido; uma única operação inválida não comprova indisponibilidade de todo o serviço."),
 dict(id="temperatura", section="05 · Saúde física", title="Temperatura por sensor · °C", kind="temperature", metrics=["temperatura_celsius"], dims=["hsm", "sensor"], unit="°C",
 source="Leitura absoluta por sensor. Limites warning/critical/máximo somente do manual ou configuração aplicável à revisão de hardware/firmware; não presumidos.",
 text="Exibe a temperatura absoluta de cada sensor, mantendo separado o sensor interno do HSM, o do appliance e a condição ambiental quando disponíveis. **Máximo e thresholds: limites documentados para o sensor e a revisão exata do equipamento**, sem fixar um número não confirmado e sem converter Celsius em percentual de capacidade. **85%/95% não se aplicam**; alarme físico exige atuação de infraestrutura e correlação com impacto, gargalo comprovado é **SEV4** e indisponibilidade confirmada é **SEV5**. Sem limites validados, o gráfico fica sem linhas térmicas automáticas."),
 dict(id="hardware", section="05 · Saúde física", title="Fontes e ventiladores · estado por componente", kind="hardware", metrics=["componente_fisico_falha"], dims=["hsm", "componente"], unit="estado",
 source="Estado normalizado de componente: 0=saudável, 1=falha. Traduzir enumerações reais da origem; não presumir seus códigos.",
 text="Mostra individualmente o estado de cada fonte e ventilador monitorado, com tradução validada dos códigos da origem. **Escala normalizada: 0 = saudável e 1 = falha; não é uma capacidade percentual**, portanto **85%/95% não se aplicam**. Uma falha com redundância preservada exige tratamento conforme o impacto sem presumir queda do serviço; degradação que produza gargalo confirmado é **SEV4**, e indisponibilidade do equipamento é **SEV5**. Não impor um RPM universal nem presumir número fixo de fontes ou ventiladores."),
]

DIM_KEYS = sorted({d for c in CARDS for d in c["dims"]})
METRIC_KEYS = sorted({m for c in CARDS for m in c["metrics"]})
TOKEN = re.compile(r"\{\{(metric|dimension):([a-z0-9_]+)\}\}")

def default_config() -> dict[str, Any]:
    return {
      "name": TITLE,
      "notes": "Chaves internas são identificadores do modelo, não nomes reais de métricas. Preencher somente chaves verificadas no tenant. Percentuais são 0..100; não 0..1.",
      "metrics": {m: None for m in METRIC_KEYS},
      "dimensions": {d: None for d in DIM_KEYS},
      "collection_interval_seconds": 60,
      "freshness_limit_seconds": 180,
      "latency_slo_ms": None,
      "error_budget_pct": None,
      "temperature_warning_c": None,
      "temperature_critical_c": None,
      "temperature_limit_source": None,
      "query_overrides": {},
    }

def ident(value: str) -> str:
    if not isinstance(value, str) or not value.strip() or any(ch in value for ch in ('`', '\n', '\r', '\x00')):
        raise ValueError("Nome de métrica/dimensão inválido: deve ser texto não vazio, sem backtick ou quebra de linha.")
    return f"`{value}`"

def metric(key: str) -> str:
    return "{{metric:" + key + "}}"

def dimension(key: str) -> str:
    return "{{dimension:" + key + "}}"

def template_query(c: dict[str, Any]) -> str:
    by = ", ".join(dimension(d) for d in c["dims"])
    selector = f'filter: {{$HSM == "" or {dimension("hsm")} == $HSM}}'
    ms = [metric(m) for m in c["metrics"]]
    kind = c["kind"]
    if kind == "ratio":
        q = f"timeseries {{ocupado = max({ms[0]}), capacidade = min({ms[1]})}}, by: {{{by}}}, interval: 1m, {selector}\n"
        q += "| fieldsAdd valor = if(capacidade[] > 0, 100.0 * ocupado[] / capacidade[], else: null)\n"
        q += f"| fields timeframe, interval, {by}, valor"
        return q
    if kind == "ha":
        q = f"timeseries {{ativos = min({ms[0]}), esperados = max({ms[1]})}}, by: {{{by}}}, interval: 1m, {selector}\n"
        q += "| fieldsAdd Disponiveis = arrayLast(ativos), Esperados = arrayLast(esperados)\n"
        q += "| fieldsAdd Estado = if(isNull(Disponiveis) or isNull(Esperados) or Esperados <= 0, \"SEM DADOS / INVENTARIO INVALIDO\", else: if(Disponiveis == 0, \"NENHUM MEMBRO · VALIDAR SEV5\", else: if(Disponiveis < Esperados, \"REDUNDANCIA DEGRADADA\", else: if(Disponiveis > Esperados, \"REVISAR INVENTARIO\", else: \"MEMBROS ESPERADOS DISPONIVEIS\"))))\n"
        return q + f"| fields {by}, Disponiveis, Esperados, Estado"
    agg = "min" if kind == "availability" else ("avg" if kind == "throughput" else "max")
    q = f"timeseries valor = {agg}({ms[0]}), by: {{{by}}}, interval: 1m, {selector}"
    if kind in ("severity", "availability", "hardware"):
        q += "\n| fieldsAdd Ultimo_bucket = arrayLast(valor)\n"
        if kind == "severity":
            q += "| fieldsAdd Estado = if(isNull(Ultimo_bucket), \"SEM DADOS\", else: if(Ultimo_bucket == 0, \"NORMAL\", else: if(in(Ultimo_bucket, array(1, 2, 3, 4, 5)), concat(\"SEV\", toString(Ultimo_bucket)), else: \"ESTADO INVALIDO\")))\n"
        elif kind == "availability":
            q += "| fieldsAdd Estado = if(isNull(Ultimo_bucket), \"SEM DADOS\", else: if(Ultimo_bucket == 1, \"TESTE OK\", else: if(Ultimo_bucket == 0, \"FALHA FUNCIONAL · VALIDAR SEV5\", else: \"ESTADO INVALIDO\")))\n"
        else:
            q += "| fieldsAdd Estado = if(isNull(Ultimo_bucket), \"SEM DADOS\", else: if(Ultimo_bucket == 0, \"SAUDAVEL\", else: if(Ultimo_bucket == 1, \"FALHA · AVALIAR IMPACTO\", else: \"ESTADO INVALIDO\")))\n"
        q += f"| fields {by}, Ultimo_bucket, Estado"
    return q

def rule(idx: int, value: float, comparator: str, label: str, color: str) -> dict[str, Any]:
    return {"id": idx, "value": value, "comparator": comparator, "label": label, "color": {"Default": color}}

def settings(c: dict[str, Any], cfg: dict[str, Any]) -> dict[str, Any]:
    kind = c["kind"]
    s: dict[str, Any] = {}
    rules: list[dict[str, Any]] = []
    field = "valor"
    if kind in ("severity", "availability", "ha", "hardware"):
        s["table"] = {"rowDensity": "comfortable", "linewrapEnabled": True, "columnWidthStrategy": "content", "enableSparklines": False}
        field = "Ultimo_bucket"
    else:
        s["legend"] = {"showLegend": True, "position": "bottom"}
        s["seriesConfig"] = {"curve": "linear", "pointsDisplay": "auto", "gapPolicy": "gap"}
        s["axes"] = {"yAxis": {"label": c["unit"], "showLabel": True, "scale": "linear", "min": {"mode": "auto"}, "max": {"mode": "auto"}}}
    if kind in ("percent", "ratio"):
        rules = [rule(0, 0, "≥", "NORMAL <85%", COLORS["NORMAL"]), rule(1, 85, "≥", "SEV2 ≥85% até 95%", COLORS["SEV2"]), rule(2, 95, ">", "SEV3 >95%", COLORS["SEV3"])]
    elif kind == "severity":
        rules = [rule(0, 0, "=", "NORMAL", COLORS["NORMAL"])] + [rule(i, i, "=", f"SEV{i}", COLORS[f"SEV{i}"]) for i in range(1, 6)]
    elif kind == "availability":
        rules = [rule(0, 0, "=", "FALHA · VALIDAR SEV5", COLORS["SEV5"]), rule(1, 1, "=", "TESTE OK", COLORS["NORMAL"])]
    elif kind == "hardware":
        rules = [rule(0, 0, "=", "SAUDAVEL", COLORS["NORMAL"]), rule(1, 1, "=", "FALHA · AVALIAR IMPACTO", COLORS["SEV3"])]
    elif kind == "freshness":
        rules = [rule(0, cfg["freshness_limit_seconds"], ">", "TELEMETRIA DESATUALIZADA", COLORS["SEV2"])]
    elif kind == "latency" and cfg.get("latency_slo_ms") is not None:
        rules = [rule(0, cfg["latency_slo_ms"], ">", "SLO VIOLADO · INVESTIGAR GARGALO", COLORS["SEV4"])]
    elif kind == "errors" and cfg.get("error_budget_pct") is not None:
        rules = [rule(0, cfg["error_budget_pct"], ">", "ORCAMENTO DE ERRO VIOLADO", COLORS["SEV3"])]
    elif kind == "temperature":
        for key, label, color in [("temperature_warning_c", "ALERTA TERMICO DO FABRICANTE", COLORS["SEV2"]), ("temperature_critical_c", "LIMITE TERMICO DO FABRICANTE", COLORS["SEV3"])]:
            if cfg.get(key) is not None:
                rules.append(rule(len(rules), cfg[key], "≥", label, color))
    if rules:
        s["thresholds"] = [{"id": 1, "field": field, "title": "Limites operacionais", "isEnabled": True, "rules": rules}]
    return s

def validate_config(cfg: dict[str, Any]) -> None:
    for group in ("metrics", "dimensions", "query_overrides"):
        if not isinstance(cfg.get(group), dict):
            raise ValueError(f"{group} deve ser um objeto JSON.")
    for group in ("metrics", "dimensions"):
        for value in cfg[group].values():
            if value is not None:
                ident(value)
    known = {c["id"] for c in CARDS}
    if set(cfg["query_overrides"]) - known:
        raise ValueError("query_overrides possui identificador de cartão desconhecido.")
    for q in cfg["query_overrides"].values():
        if q is not None and (not isinstance(q, str) or not q.strip()):
            raise ValueError("query_overrides deve conter uma DQL não vazia ou null.")
    for key in ("collection_interval_seconds", "freshness_limit_seconds", "latency_slo_ms", "error_budget_pct", "temperature_warning_c", "temperature_critical_c"):
        val = cfg.get(key)
        if val is not None and (isinstance(val, bool) or not isinstance(val, (int, float)) or not math.isfinite(val)):
            raise ValueError(f"{key}: fornecer número finito ou null.")
    for key in ("collection_interval_seconds", "freshness_limit_seconds"):
        if cfg[key] <= 0:
            raise ValueError(f"{key} deve ser maior que zero.")
    if cfg.get("latency_slo_ms") is not None and cfg["latency_slo_ms"] <= 0:
        raise ValueError("latency_slo_ms deve ser positivo.")
    if cfg.get("error_budget_pct") is not None and not 0 <= cfg["error_budget_pct"] <= 100:
        raise ValueError("error_budget_pct deve estar entre 0 e 100.")
    thermal = [cfg.get("temperature_warning_c"), cfg.get("temperature_critical_c")]
    if any(t is not None for t in thermal) and not cfg.get("temperature_limit_source"):
        raise ValueError("Limites térmicos exigem temperature_limit_source com manual, modelo e revisão aplicáveis.")
    if all(t is not None for t in thermal) and thermal[0] >= thermal[1]:
        raise ValueError("Limite térmico de atenção deve ser menor que o crítico.")

def render_query(c: dict[str, Any], cfg: dict[str, Any]) -> tuple[str | None, list[str]]:
    override = cfg["query_overrides"].get(c["id"])
    if override:
        if TOKEN.search(override):
            raise ValueError(f"Override {c['id']} ainda contém placeholders.")
        return override, []
    missing: list[str] = []
    def sub(m: re.Match[str]) -> str:
        group = "metrics" if m.group(1) == "metric" else "dimensions"
        value = cfg[group].get(m.group(2))
        if value is None:
            missing.append(f"{group}.{m.group(2)}")
            return m.group(0)
        return ident(value)
    query = TOKEN.sub(sub, template_query(c))
    return (None, sorted(set(missing))) if missing else (query, [])

def validate_layout(doc: dict[str, Any]) -> None:
    content = doc["content"]
    if set(content["tiles"]) != set(content["layouts"]):
        raise ValueError("IDs de tiles e layouts não correspondem.")
    positions = list(content["layouts"].items())
    for i, (tid, a) in enumerate(positions):
        if not (0 <= a["x"] < 24 and a["x"] + a["w"] <= 24 and a["h"] > 0):
            raise ValueError(f"Layout inválido: {tid}")
        for other, b in positions[i + 1:]:
            if a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]:
                raise ValueError(f"Sobreposição: {tid} / {other}")

def generate(cfg: dict[str, Any], out: Path) -> dict[str, Any]:
    validate_config(cfg)
    out.mkdir(parents=True, exist_ok=True)
    tiles: dict[str, Any] = {}
    layouts: dict[str, Any] = {}
    manifest: list[dict[str, Any]] = []
    counter = 0
    def tile(data: dict[str, Any], x: int, y: int, w: int, h: int) -> str:
        nonlocal counter
        k = str(counter); counter += 1
        tiles[k] = data; layouts[k] = {"x": x, "y": y, "w": w, "h": h}
        return k
    tile({"type": "markdown", "content": "# HSM Luna 7 · Operação\n\n" + LEGEND + " **SEV5 é a mais crítica. Normal não é SEV1.**\n\n**Escopo assumido: Luna Network HSM 7.** Período sugerido: últimas 2 horas; atualização: 1 minuto. Os cartões de estado representam o último bucket do período selecionado, não necessariamente o instante atual. **SEM MAPEAMENTO / SEM DADOS não significam saudável nem indisponível.**"}, 0, 0, 24, 5)
    y = 5
    for section in dict.fromkeys(c["section"] for c in CARDS):
        tile({"type": "markdown", "content": "## " + section}, 0, y, 24, 2); y += 2
        members = [c for c in CARDS if c["section"] == section]
        for i in range(0, len(members), 2):
            for j, c in enumerate(members[i:i+2]):
                query, missing = render_query(c, cfg)
                x = j * 12
                if query is None:
                    note = "SEM MAPEAMENTO — ver mapeamento.json. Não há dados simulados."
                    query = 'data record(Estado=' + json.dumps(note, ensure_ascii=False) + ', Indicador=' + json.dumps(c["title"], ensure_ascii=False) + ')'
                    viz = "table"
                    vizsettings: dict[str, Any] = {}
                else:
                    viz = "table" if c["kind"] in ("severity", "availability", "ha", "hardware") else "lineChart"
                    vizsettings = settings(c, cfg)
                tid = tile({"type": "data", "title": c["title"], "query": query, "visualization": viz, "visualizationSettings": vizsettings, "querySettings": {}}, x, y, 12, 6)
                text = c["text"]
                if c["kind"] == "freshness":
                    text = text.replace("180 s", f'{cfg["freshness_limit_seconds"]} s').replace("60 s", f'{cfg["collection_interval_seconds"]} s')
                if c["kind"] == "latency" and cfg.get("latency_slo_ms") is not None:
                    text += f' **Objetivo configurado: {cfg["latency_slo_ms"]} ms; validar por operação.**'
                if c["kind"] == "errors" and cfg.get("error_budget_pct") is not None:
                    text += f' **Orçamento configurado: {cfg["error_budget_pct"]}%.**'
                if c["kind"] == "temperature" and cfg.get("temperature_limit_source"):
                    text += f' **Fonte validada dos limites: {cfg["temperature_limit_source"]}.**'
                if "\n\n" in text:
                    raise ValueError("Explicação deve ter apenas um parágrafo.")
                mid = tile({"type": "markdown", "content": text}, x, y + 6, 12, 5)
                manifest.append({"id": c["id"], "title": c["title"], "data_tile": tid, "markdown_tile": mid, "status": "PENDENTE" if missing else "MAPEADO_NAO_EXECUTADO", "missing": missing, "source_contract": c["source"]})
            y += 11
    tile({"type": "markdown", "content": "## Regras de leitura\n\n**Precedência no mesmo escopo:** SEV5 > SEV4 > SEV3 > SEV2 > SEV1. Cruzar 95% não comprova gargalo nem indisponibilidade. Falha de membro e falha do serviço HA são incidentes de escopos diferentes. Os thresholds visuais não criam alertas nem notificações: configurar e homologar separadamente as regras de detecção e o encaminhamento.\n\n**Tratamento de dados:** não preencher ausências com zero, não carregar valores antigos como atuais, não inventar TPS/sessões/temperatura máximos e não interpretar códigos SNMP sem tradução. Ajustar o período e a atualização da interface, e validar todas as DQLs e dimensões no tenant antes de uso operacional.\n\n**Referências:** estrutura de dashboard e visualizações [D1–D4]; campos da SAFENET-HSM-MIB [T1, documentação histórica Luna 7.2]. Referências completas, limitações e checklist no guia do pacote."}, 0, y, 24, 7)
    uses_hsm = any("$HSM" in t.get("query", "") for t in tiles.values())
    variables = [{"version": 2, "key": "HSM", "type": "text", "visible": True, "editable": True, "defaultValue": ""}] if uses_hsm else []
    doc = {"name": cfg.get("name") or TITLE, "type": "dashboard", "content": {"version": 21, "variables": variables, "tiles": tiles, "layouts": layouts}}
    validate_layout(doc)
    (out / "dashboard-luna7.document.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "dashboard-luna7.content.json").write_text(json.dumps(doc["content"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = {"metric_cards": len(CARDS), "tiles": len(tiles), "mapped_cards": sum(not x["missing"] for x in manifest), "runtime_validation": "NAO_EXECUTADA_NO_TENANT", "layout_validation": "OK_SEM_SOBREPOSICOES", "cards": manifest}
    (out / "manifesto.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    qdir = out / "consultas_dql"
    qdir.mkdir(exist_ok=True)
    for c in CARDS:
        q, missing = render_query(c, cfg)
        pre = f'// {c["title"]}\n// {c["source"]}\n// ' + ("MODELO COM PLACEHOLDERS — NÃO EXECUTAR SEM MAPEAR" if missing else "MAPEADO — VALIDAR NO TENANT") + "\n"
        (qdir / f'{c["id"]}.dql').write_text(pre + (q or template_query(c)) + "\n", encoding="utf-8")
    return report

def severity_percent(value: float | None) -> str:
    """Apenas a política de capacidade; não infere SEV4 ou SEV5."""
    if value is None or not math.isfinite(value) or value < 0:
        return "SEM DADOS"
    if value > 95:
        return "SEV3"
    if value >= 85:
        return "SEV2"
    return "NORMAL"

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", type=Path, default=Path(__file__).with_name("mapeamento.json"))
    p.add_argument("--out", type=Path, default=Path(__file__).parent)
    p.add_argument("--init-config", action="store_true", help="Cria configuração vazia; recusa sobrescrever uma existente.")
    args = p.parse_args()
    try:
        if args.init_config:
            args.config.parent.mkdir(parents=True, exist_ok=True)
            with args.config.open("x", encoding="utf-8") as f:
                json.dump(default_config(), f, ensure_ascii=False, indent=2); f.write("\n")
        cfg = json.loads(args.config.read_text(encoding="utf-8"))
        report = generate(cfg, args.out)
    except (OSError, json.JSONDecodeError, ValueError, TypeError, KeyError) as e:
        print(f"ERRO: {e}", file=sys.stderr); return 2
    print(f'{report["mapped_cards"]}/{report["metric_cards"]} cartões mapeados; {report["tiles"]} tiles; layout válido. DQL não executada no tenant.')
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
