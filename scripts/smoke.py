#!/usr/bin/env python3
"""Teste HTTP apos publicacao. Retenta ate o encaminhamento estar disponivel."""
import argparse
import json
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen
p = argparse.ArgumentParser()
p.add_argument('url')
p.add_argument('--version', required=True)
p.add_argument('--message')
p.add_argument('--output', type=Path, help='Grava a resposta JSON em UTF-8')
p.add_argument('--attempts', type=int, default=30)
a = p.parse_args()
if a.attempts < 1: p.error('attempts deve ser positivo')
last = ''
for _ in range(a.attempts):
    try:
        with urlopen(a.url.rstrip('/') + '/api/status', timeout=2) as r:
            data = json.load(r)
        if data.get('version') != a.version or data.get('ready') is not True:
            raise ValueError('Versao ou prontidao diferente da esperada: ' + str(data))
        if a.message is not None and data.get('message') != a.message:
            raise ValueError('Mensagem diferente da esperada')
        if a.output:
            a.output.parent.mkdir(parents=True, exist_ok=True)
            a.output.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(data, ensure_ascii=False))
        print('SMOKE OK')
        break
    except (URLError, OSError, ValueError) as error:
        last = str(error)
        time.sleep(.5)
else:
    raise SystemExit('SMOKE FALHOU: ' + last)
