"""Aplicacao didatica sem dependencias externas. Python 3.10+."""
import html
import json
import os
import signal
import socket
import threading
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

@dataclass(frozen=True)
class Config:
    version: str
    message: str
    pod: str

    @classmethod
    def from_env(cls):
        return cls(os.getenv('APP_VERSION', 'v1'),
                   os.getenv('APP_MESSAGE', 'Entrega pronta para uso.'),
                   os.getenv('POD_NAME', socket.gethostname()))

    @property
    def ready(self):
        # Defeito proposital do laboratorio: processo vivo, mas nao pronto.
        return self.version != 'quebrada'

    def payload(self):
        return {'version': self.version, 'message': self.message,
                'pod': self.pod, 'ready': self.ready}

def page(config):
    status = 'Pronta para receber trafego' if config.ready else 'Versao com falha proposital'
    return f'''<!doctype html><html lang="pt-BR"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Painel de Entregas</title><style>
body{{margin:0;background:#f3f5f4;color:#242424;font:18px system-ui}}
main{{max-width:780px;margin:10vh auto;padding:36px;background:white;border-top:8px solid #004823}}
h1{{font-size:40px;color:#004823;margin:0 0 12px}}
p{{line-height:1.6}}dl{{display:grid;grid-template-columns:120px 1fr;gap:14px}}
dt{{font-weight:bold}}dd{{margin:0;overflow-wrap:anywhere}}
a{{color:#004823}}code{{font-family:monospace}}</style><main>
<h1>Painel de Entregas</h1><p>{html.escape(config.message)}</p>
<dl><dt>Versao</dt><dd>{html.escape(config.version)}</dd>
<dt>Instancia</dt><dd><code>{html.escape(config.pod)}</code></dd>
<dt>Situacao</dt><dd>{status}</dd></dl>
<p><a href="/api/status">Ver resposta da API</a></p></main></html>'''.encode()

def handler_for(config):
    class Handler(BaseHTTPRequestHandler):
        def send(self, status, content, kind='application/json; charset=utf-8'):
            data = content if isinstance(content, bytes) else json.dumps(content, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            route = urlsplit(self.path).path
            if route == '/healthz':
                self.send(200, {'alive': True})
            elif route == '/readyz':
                self.send(200 if config.ready else 503, {'ready': config.ready})
            elif route == '/api/status':
                self.send(200 if config.ready else 503, config.payload())
            elif route == '/':
                self.send(200 if config.ready else 503, page(config), 'text/html; charset=utf-8')
            else:
                self.send(404, {'error': 'rota inexistente'})

        def log_message(self, fmt, *args):
            print(f'pod={config.pod} version={config.version} {fmt % args}', flush=True)
    return Handler

def make_server(host='0.0.0.0', port=8000, config=None):
    return ThreadingHTTPServer((host, port), handler_for(config or Config.from_env()))

def main():
    config = Config.from_env()
    server = make_server(port=int(os.getenv('PORT', '8000')), config=config)
    def stop(_signum, _frame):
        # shutdown precisa rodar fora da thread de serve_forever.
        threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f'Listening on :{server.server_port}; version={config.version}; pod={config.pod}', flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()

if __name__ == '__main__':
    main()
