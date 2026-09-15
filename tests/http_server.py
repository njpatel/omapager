#!/usr/bin/env python3
"""Owned loopback TLS fixture; only tests bypass public DNS selection."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bin'))
import omapager_http as net


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == '/private':
            self.send_response(302)
            self.send_header('Location', 'https://127.0.0.1/secret')
            self.end_headers()
        elif self.path == '/loop':
            self.send_response(302)
            self.send_header('Location', '/loop')
            self.end_headers()
        else:
            body = b'ok' if self.path == '/ok' else b'x' * 2048
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass


with tempfile.TemporaryDirectory(prefix='omapager-tls-smoke-') as directory:
    cert, key = Path(directory) / 'cert.pem', Path(directory) / 'key.pem'
    subprocess.run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', str(key), '-out', str(cert), '-days', '1',
        '-subj', '/CN=example.com', '-addext', 'subjectAltName=DNS:example.com',
    ], check=True, capture_output=True)
    server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.minimum_version = ssl.TLSVersion.TLSv1_2
    server_context.load_cert_chain(cert, key)
    client_context = ssl.create_default_context(cafile=str(cert))
    client_context.minimum_version = ssl.TLSVersion.TLSv1_2
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.socket = server_context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    answer = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', server.server_address)]
    try:
        with patch.object(net, 'resolve_public_answers', return_value=answer), \
                patch.object(net.ssl, 'create_default_context', return_value=client_context):
            assert net.fetch('https://example.com/ok', 100)[0] == b'ok'
            for route in ('private', 'loop', 'large'):
                try:
                    net.fetch('https://example.com/' + route, 100)
                except ValueError:
                    pass
                else:
                    raise AssertionError('accepted ' + route)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
print('HTTPS transport: valid body, private redirect, redirect loop and size cap passed')
