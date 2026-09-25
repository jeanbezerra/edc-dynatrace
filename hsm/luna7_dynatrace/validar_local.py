#!/usr/bin/env python3
"""Testes locais estruturais. Não acessa rede e não executa DQL no Dynatrace."""
from pathlib import Path
import json
import tempfile
from gerar_dashboard import CARDS, generate, default_config, severity_percent, validate_layout

base = Path(__file__).parent
checks = []
for value, expected in [(None, 'SEM DADOS'), (-1, 'SEM DADOS'), (0, 'NORMAL'), (84.99, 'NORMAL'), (85, 'SEV2'), (95, 'SEV2'), (95.01, 'SEV3'), (100, 'SEV3')]:
    assert severity_percent(value) == expected, (value, expected)
checks.append('Fronteiras: 84.99 NORMAL; 85 SEV2; 95 SEV2; 95.01 e 100 SEV3; nulo SEM DADOS')
current = json.loads((base / 'dashboard-luna7.document.json').read_text(encoding='utf-8'))
validate_layout(current)
checks.append('IDs correspondentes, grade de 24 colunas e ausência de sobreposição')
manifest = json.loads((base / 'manifesto.json').read_text(encoding='utf-8'))
assert manifest['metric_cards'] == 18 and manifest['tiles'] == 43
assert manifest['mapped_cards'] == 0
for card in manifest['cards']:
    dt = current['content']['layouts'][card['data_tile']]
    md = current['content']['layouts'][card['markdown_tile']]
    assert dt['x'] == md['x'] and dt['w'] == md['w'] and dt['y'] + dt['h'] == md['y']
    text = current['content']['tiles'][card['markdown_tile']]['content']
    assert '\n\n' not in text
    q = current['content']['tiles'][card['data_tile']]['query']
    assert 'SEM MAPEAMENTO' in q and q.startswith('data record(')
checks.append('18 explicações com um parágrafo, imediatamente abaixo dos respectivos indicadores')
checks.append('Entrega padrão sem métricas fictícias: 18 avisos SEM MAPEAMENTO')
# Nomes fictícios abaixo verificam APENAS a substituição de texto, em diretório
# temporário. Nenhuma amostra numérica é produzida e nada é enviado à rede.
with tempfile.TemporaryDirectory(prefix='luna7_schema_test_') as td:
    cfg = default_config()
    cfg['metrics'] = {k: f'test.placeholder.{k}' for k in cfg['metrics']}
    cfg['dimensions'] = {k: f'test.dimension.{k}' for k in cfg['dimensions']}
    mapped = generate(cfg, Path(td))
    assert mapped['mapped_cards'] == 18
    doc = json.loads((Path(td) / 'dashboard-luna7.document.json').read_text(encoding='utf-8'))
    validate_layout(doc)
    for c, entry in zip(CARDS, mapped['cards']):
        tile = doc['content']['tiles'][entry['data_tile']]
        assert '{{metric:' not in tile['query'] and '{{dimension:' not in tile['query']
        if c['kind'] in ('percent', 'ratio'):
            r = tile['visualizationSettings']['thresholds'][0]['rules']
            assert r[1]['comparator'] == '≥' and r[1]['value'] == 85
            assert r[2]['comparator'] == '>' and r[2]['value'] == 95
        if c['kind'] == 'temperature':
            assert 'thresholds' not in tile['visualizationSettings']
    assert doc['content']['variables'][0]['key'] == 'HSM'
checks.append('Substituição isolada de todos os placeholders e habilitação condicional do filtro HSM')
checks.append('Thresholds exatos: SEV2 ≥85; SEV3 >95; temperatura sem máximo presumido')
report = {'status': 'PASSOU_TESTES_LOCAIS', 'checks': checks,
          'not_validated': ['Execução e semântica DQL no tenant', 'Existência real das métricas e dimensões', 'Importação e renderização no app Dynatrace', 'Regras de alerta, persistência e notificações', 'Limites da revisão de hardware e firmware instalada']}
(base / 'validacao_local.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
