import importlib.util
import json
from pathlib import Path
import sys
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen

path = Path(__file__).resolve().parents[1] / 'app/main.py'
spec = importlib.util.spec_from_file_location('entrega_app', path)
app = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = app
spec.loader.exec_module(app)

class AppTests(unittest.TestCase):
    def request(self, config, route):
        server = app.make_server('127.0.0.1', 0, config)
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .02}, daemon=True)
        thread.start()
        try:
            try:
                response = urlopen(f'http://127.0.0.1:{server.server_port}{route}', timeout=3)
            except HTTPError as error:
                response = error
            with response:
                return response.status, response.headers['Content-Type'], response.read()
        finally:
            server.shutdown();server.server_close();thread.join(timeout=2)

    def test_status_v1(self):
        status, _, body = self.request(app.Config('v1', 'Teste', 'pod-1'), '/api/status')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {'version':'v1','message':'Teste','pod':'pod-1','ready':True})

    def test_status_v2(self):
        status, _, body = self.request(app.Config('v2', 'Outra entrega', 'pod-2'), '/api/status')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['version'], 'v2')

    def test_readiness_healthy(self):
        status, _, body = self.request(app.Config('v1', '', 'p'), '/readyz')
        self.assertEqual(status, 200);self.assertTrue(json.loads(body)['ready'])

    def test_broken_readiness(self):
        status, _, body = self.request(app.Config('quebrada', '', 'p'), '/readyz')
        self.assertEqual(status, 503);self.assertFalse(json.loads(body)['ready'])

    def test_broken_alive(self):
        status, _, body = self.request(app.Config('quebrada', '', 'p'), '/healthz')
        self.assertEqual(status, 200);self.assertTrue(json.loads(body)['alive'])

    def test_broken_api(self):
        status, _, _ = self.request(app.Config('quebrada', '', 'p'), '/api/status')
        self.assertEqual(status, 503)

    def test_unknown(self):
        status, _, _ = self.request(app.Config('v1', '', 'p'), '/inexistente')
        self.assertEqual(status, 404)

    def test_html_escaping(self):
        status, kind, body = self.request(app.Config('v1', '<script>x</script>', '<pod>'), '/')
        self.assertEqual(status, 200);self.assertIn('text/html',kind)
        self.assertIn(b'&lt;script&gt;',body);self.assertNotIn(b'<script>',body)

if __name__ == '__main__':
    unittest.main()
