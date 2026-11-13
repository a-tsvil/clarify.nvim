"""Local provider fixtures; no credentials or internet required."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/v1/chat/completions':
            assert self.headers.get('Authorization') is None
            assert body['model'] == 'llama3.2'
        else:
            assert 'fixture-secret' in str(self.headers)
        assert 'quote " slash \\ newline\nλ' in json.dumps(body, ensure_ascii=False).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
        status = 200
        if self.path.startswith('/error'):
            status, result = 429, {'error': {'message': 'quota exhausted fixture-secret'}}
        elif self.path.startswith('/invalid'):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'not json')
            return
        elif self.path.endswith(':generateContent'):
            result = {'candidates': [{'content': {'parts': [{'text': 'Gemini fixture'}]}}]}
        elif self.path.endswith('/responses'):
            result = {'output': [{'content': [{'type': 'output_text', 'text': 'OpenAI fixture'}]}]}
        elif self.path.endswith('/messages'):
            result = {'content': [{'type': 'text', 'text': 'Anthropic fixture'}]}
        else:
            result = {'choices': [{'message': {'content': 'Compatible fixture'}}]}
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())


server = HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
