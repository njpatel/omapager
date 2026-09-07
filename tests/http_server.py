#!/usr/bin/env python3
"""Synthetic loopback transport fixture; only tests bypass public DNS selection."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import sys
import threading
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'bin'))
import omapager_http as net
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        if self.path=='/private':
            self.send_response(302);self.send_header('Location','http://127.0.0.1/secret');self.end_headers()
        elif self.path=='/loop':
            self.send_response(302);self.send_header('Location','/loop');self.end_headers()
        else:
            body=b'ok' if self.path=='/ok' else b'x'*2048
            self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers()
            try:self.wfile.write(body)
            except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
answer=(socket.AF_INET,socket.SOCK_STREAM,6,'',server.server_address)
try:
    with patch.object(net,'resolve_public_host',return_value=answer):
        assert net.fetch('http://example.com/ok',100)[0]==b'ok'
        for route in ('private','loop','large'):
            try:net.fetch('http://example.com/'+route,100)
            except ValueError:pass
            else:raise AssertionError('accepted '+route)
finally:server.shutdown();server.server_close();thread.join()
print('HTTP transport: valid body, private redirect, redirect loop and size cap passed')
