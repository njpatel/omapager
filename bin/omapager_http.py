"""No proxy environment, redirects or DNS decisions are delegated to urllib."""
import http.client
import ipaddress
import re
import socket
import ssl
import time
from urllib.parse import urlsplit, urlunsplit, urljoin

MAX_REDIRECTS = 3

def public_hostname(raw):
    if not isinstance(raw, str) or len(raw) > 253:
        return None
    h = raw.lower().removesuffix('.')
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+', h):
        return None
    if h.split('.')[-1].isdigit() or h.endswith(('.local', '.localhost', '.internal', '.home', '.lan')):
        return None
    return h

def parse_url(raw):
    if not isinstance(raw, str) or len(raw) > 4096 or re.search(r'[\x00-\x20\x7f-\x9f\\<>"\']|%(?:0[0-9a-f]|1[0-9a-f]|7f|25|5c)', raw, re.I):
        raise ValueError('invalid URL')
    p = urlsplit(raw)
    h = public_hostname(p.hostname)
    port = p.port or (443 if p.scheme == 'https' else 80)
    if p.scheme not in ('https', 'http') or not h or p.username is not None or p.password is not None or port != (443 if p.scheme == 'https' else 80):
        raise ValueError('forbidden destination')
    return p, h, port

def resolve_public_host(host, port):
    answers = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
    if not answers:
        raise ValueError('empty DNS response')
    for family, _, _, _, address in answers:
        ip = ipaddress.ip_address(address[0])
        if (family not in (socket.AF_INET, socket.AF_INET6)
                or not ip.is_global or ip.is_multicast or ip.is_reserved
                or (isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None)):
            raise ValueError('non-public DNS response')
    return answers[0]

class PinnedHTTPConnection(http.client.HTTPConnection):
    def __init__(self, host, port, answer, tls=False):
        super().__init__(host, port, timeout=5)
        self.answer, self.tls = answer, tls

    def connect(self):
        family, socktype, proto, _, address = self.answer
        sock = socket.socket(family, socktype, proto)
        try:
            sock.settimeout(self.timeout)
            # Numeric sockaddr from the validated resolution: no second lookup.
            sock.connect(address)
            self.sock = ssl.create_default_context().wrap_socket(sock, server_hostname=self.host) if self.tls else sock
        except BaseException:
            sock.close()
            raise

def fetch_once(url, limit):
    p, host, port = parse_url(url)
    conn = PinnedHTTPConnection(host, port, resolve_public_host(host, port), p.scheme == 'https')
    try:
        conn.request('GET', urlunsplit(('', '', p.path or '/', p.query, '')),
                     headers={'Host': host, 'User-Agent': 'omapager-hardened/0.1', 'Accept-Encoding': 'identity'})
        response = conn.getresponse()
        if response.status in (301, 302, 303, 307, 308):
            location = response.getheader('Location')
            if not location:
                raise ValueError('missing redirect')
            return None, location
        if response.status != 200 or response.getheader('Content-Encoding', 'identity') != 'identity':
            raise ValueError('unsupported response')
        length = response.getheader('Content-Length')
        if length is not None and (int(length) < 0 or int(length) > limit):
            raise ValueError('oversized response')
        body = bytearray()
        deadline = time.monotonic() + 12
        while len(body) <= limit:
            if time.monotonic() > deadline:
                raise ValueError('response deadline')
            block = response.read1(min(16384, limit + 1 - len(body)))
            if not block:
                break
            body.extend(block)
        if len(body) > limit:
            raise ValueError('oversized response')
        return bytes(body), None
    finally:
        conn.close()

def fetch(url, limit=512*1024):
    for hop in range(MAX_REDIRECTS + 1):
        parse_url(url)
        data, location = fetch_once(url, limit)
        if location is None:
            return data, url
        if hop == MAX_REDIRECTS:
            raise ValueError('redirect limit')
        # Validate Location before joining: urljoin can strip hostile controls.
        if len(location) > 4096 or re.search(r'[\x00-\x20\x7f\\]', location):
            raise ValueError('invalid redirect')
        url = urljoin(url, location)
    raise ValueError('redirect limit')
