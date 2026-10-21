#!/usr/bin/env python3
"""Gera o manifesto do exercicio sem dependencias Python adicionais."""
import argparse
from pathlib import Path
import re
p = argparse.ArgumentParser()
p.add_argument('version', help='v1, v2, v3... ou quebrada (incidente)')
p.add_argument('--replicas', type=int, default=2)
p.add_argument('--output', type=Path, help='Grava YAML em UTF-8')
a = p.parse_args()
if not re.fullmatch(r'v[1-9][0-9]*|quebrada', a.version):
    p.error('Versao invalida')
if not 1 <= a.replicas <= 10:
    p.error('Use 1 a 10 replicas neste laboratorio')
root = Path(__file__).resolve().parents[1]
source = (root / 'k8s/deployment.yaml').read_text(encoding='utf-8')
assert source.count('image: entrega-local:v1') == 1
assert source.count('replicas: 2') == 1
rendered = source.replace('image: entrega-local:v1', 'image: entrega-local:' + a.version)
rendered = rendered.replace('replicas: 2', 'replicas: ' + str(a.replicas))
if a.output:
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(rendered, encoding='utf-8')
else:
    print(rendered, end='')
