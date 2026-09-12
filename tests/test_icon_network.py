"""Run with python3 -B -m unittest discover -s tests -p test_icon_network.py -v.

DNS is synthetic. Only public fixture addresses are routed to a server owned
by this test; every other connect is refused before any network operation.
HTTP, redirects, TLS handshakes and certificate hostname checks are real.
"""
import collections
import contextlib
import errno
import http.server
import os
from pathlib import Path
import runpy
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / "bin" / "omapager-icon"
# omapager-icon imports its network layer from bin/omapager_http.py; runpy
# does not add the script's own directory to sys.path for a plain file.
sys.path.insert(0, str(ROOT / "bin"))
PUBLIC = "93.184.216.34"
PUBLIC_V6 = "2606:4700:4700::1111"
BLOCKED = (
    "127.0.0.1", "10.0.0.1", "169.254.169.254", "240.0.0.1",
    "::1", "fd00::1", "fe80::1", "4000::1",
)


class IconNetworkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="omapager-network-")
        cls.addClassCleanup(cls.temp.cleanup)
        cert = Path(cls.temp.name) / "cert.pem"
        key = Path(cls.temp.name) / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(cert), "-days", "1",
            "-subj", "/CN=source.test",
            "-addext", "subjectAltName=DNS:source.test,DNS:target.test",
        ], check=True, capture_output=True)
        cls.server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.server_context.load_cert_chain(cert, key)
        cls.client_context = ssl.create_default_context(cafile=str(cert))

    @contextlib.contextmanager
    def transport(self, scheme="http", rebound=None, redirect=False,
                  answers=None, fail_first=False, proxy=False):
        calls = collections.Counter()
        attempts, requests, sni = [], [], []
        state = {"calls": calls, "attempts": attempts,
                 "requests": requests, "sni": sni}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append((self.headers["Host"], self.path))
                if redirect and self.path == "/start":
                    self.send_response(302)
                    self.send_header("Location", f"{scheme}://target.test/icon")
                    body = b""
                else:
                    self.send_response(200)
                    body = b"fixture icon"
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        if scheme == "https":
            self.server_context.set_servername_callback(
                lambda _sock, name, _ctx: sni.append(name))
            server.socket = self.server_context.wrap_socket(
                server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        real_connect = socket.socket.connect

        def resolve(host, port, *args, **kwargs):
            if host not in ("source.test", "target.test", "mismatch.test"):
                raise AssertionError("Unexpected DNS query: " + str(host))
            calls[host] += 1
            addresses = [PUBLIC]
            if answers is not None:
                addresses = answers(host)
            elif rebound and calls[host] > 1 and (not redirect or host == "target.test"):
                addresses = [rebound]
            return [
                (socket.AF_INET6, socket.SOCK_STREAM, socket.IPPROTO_TCP,
                 "", (address, port, 0, 0)) if ":" in address else
                (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP,
                 "", (address, port))
                for address in addresses
            ]

        def connect(sock, address):
            attempts.append(address[0])
            if address[0] not in (PUBLIC, PUBLIC_V6):
                raise OSError("Test blocked unapproved destination: " + address[0])
            if fail_first and address[0] == PUBLIC_V6:
                raise OSError("Synthetic IPv6 route failure")
            # Only our own loopback fixture can receive bytes. No external or
            # pre-existing local service is ever contacted, even before the fix.
            return real_connect(sock, server.server_address)

        environment = {"HOME": self.temp.name}
        if proxy:
            environment.update(http_proxy="http://proxy.test:3128",
                               https_proxy="http://proxy.test:3128")
        try:
            with mock.patch.dict(os.environ, environment, clear=True), \
                    mock.patch.object(socket, "getaddrinfo", resolve), \
                    mock.patch.object(socket.socket, "connect", connect), \
                    mock.patch.object(ssl, "create_default_context",
                                      return_value=self.client_context):
                icon = runpy.run_path(str(ICON))
                yield icon["get"], state
        finally:
            server.shutdown()
            thread.join(timeout=3)
            server.server_close()

    def test_rebinding_never_connects_to_second_answer(self):
        for scheme in ("http", "https"):
            for address in BLOCKED:
                for redirect in (False, True):
                    with self.subTest(scheme=scheme, address=address, redirect=redirect):
                        with self.transport(scheme, address, redirect) as (get, state):
                            url = f"{scheme}://source.test/start"
                            body, final = get(url)
                            self.assertEqual(body, b"fixture icon")
                            self.assertEqual(final, f"{scheme}://target.test/icon"
                                             if redirect else url)
                            expected = [("source.test", "/start")]
                            if redirect:
                                expected.append(("target.test", "/icon"))
                            self.assertEqual(state["requests"], expected)
                            self.assertEqual(state["attempts"], [PUBLIC] * len(expected))
                            self.assertEqual(dict(state["calls"]),
                                             {host.split(":")[0]: 1 for host, _ in expected})
                            self.assertEqual(state["sni"],
                                             [host.split(":")[0] for host, _ in expected]
                                             if scheme == "https" else [])

    def test_non_public_answers_block_initial_and_redirect_requests(self):
        for address in BLOCKED + ("224.0.0.1", "ff02::1", "0.0.0.0", "::"):
            for redirect in (False, True):
                with self.subTest(address=address, redirect=redirect):
                    def answers(host):
                        return [PUBLIC] if redirect and host == "source.test" else [address]
                    with self.transport(redirect=redirect, answers=answers) as (get, state):
                        with self.assertRaises((ValueError, urllib.error.URLError)):
                            get("http://source.test/start")
                        self.assertEqual(state["attempts"], [PUBLIC] if redirect else [])
                        self.assertEqual(state["requests"],
                                         [("source.test", "/start")] if redirect else [])

    def test_empty_and_mixed_answers_fail_before_connect(self):
        for addresses in ([], [PUBLIC, "10.0.0.1"], [PUBLIC, "fd00::1"]):
            with self.subTest(addresses=addresses):
                with self.transport(answers=lambda _host: addresses) as (get, state):
                    with self.assertRaises((ValueError, urllib.error.URLError)):
                        get("http://source.test/icon")
                    self.assertEqual(state["attempts"], [])
                    self.assertEqual(state["requests"], [])

    def test_public_address_fallback_retains_hostname(self):
        with self.transport("https", answers=lambda _host: [PUBLIC_V6, PUBLIC],
                            fail_first=True) as (get, state):
            self.assertEqual(get("https://source.test/icon"),
                             (b"fixture icon", "https://source.test/icon"))
            self.assertEqual(state["attempts"], [PUBLIC_V6, PUBLIC])
            self.assertEqual(state["requests"], [("source.test", "/icon")])
            self.assertEqual(state["sni"], ["source.test"])

    def test_socket_family_failure_uses_validated_fallback(self):
        with self.transport("https", answers=lambda _host: [PUBLIC_V6, PUBLIC]) as (get, state):
            real_socket = socket.socket

            def supported_socket(family, *args, **kwargs):
                if family == socket.AF_INET6:
                    raise OSError(errno.EAFNOSUPPORT, "Synthetic IPv6 unavailable")
                return real_socket(family, *args, **kwargs)

            with mock.patch.object(socket, "socket", supported_socket):
                self.assertEqual(get("https://source.test/icon"),
                                 (b"fixture icon", "https://source.test/icon"))
            self.assertEqual(state["attempts"], [PUBLIC])
            self.assertEqual(dict(state["calls"]), {"source.test": 1})
            self.assertEqual(state["sni"], ["source.test"])

    def test_tls_rejects_wrong_hostname_before_http(self):
        # The pinned transport talks http.client directly rather than through
        # urllib.request, so a certificate failure surfaces as the raw ssl
        # exception rather than a wrapped urllib.error.URLError.
        with self.transport("https") as (get, state):
            with self.assertRaises(ssl.SSLCertVerificationError):
                get("https://mismatch.test/icon")
            self.assertEqual(state["requests"], [])
            self.assertEqual(state["sni"], ["mismatch.test"])

    def test_environment_proxy_cannot_bypass_pinning(self):
        for scheme in ("http", "https"):
            with self.subTest(scheme=scheme):
                with self.transport(scheme, proxy=True) as (get, state):
                    self.assertEqual(get(f"{scheme}://source.test/icon")[0], b"fixture icon")
                    self.assertEqual(state["attempts"], [PUBLIC])
                    self.assertEqual(state["requests"], [("source.test", "/icon")])


if __name__ == "__main__":
    unittest.main()
