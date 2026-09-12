#!/usr/bin/env python3
"""Real namespaces, synthetic HOME, no live notification state or session bus."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import socket
import tempfile
from urllib.parse import quote
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0,str(ROOT/'bin'))
loader=importlib.machinery.SourceFileLoader('runner',str(ROOT/'bin/omapager-run-helper'))
spec=importlib.util.spec_from_loader('runner',loader)
r=importlib.util.module_from_spec(spec);loader.exec_module(r)
with tempfile.TemporaryDirectory(prefix='omapager-sandbox-') as tmp:
    r.HOME_DIR=Path(tmp)/'home';r.HOME_DIR.mkdir()
    r.STATE=r.HOME_DIR/'.local/state/omarchy/omapager'
    secret=r.HOME_DIR/'.ssh/id_test';secret.parent.mkdir();secret.write_text('synthetic secret')
    for kind in ('store','icon'):
        cmd=r.command(kind,[])
        cut=cmd.index('/usr/bin/python3')
        code=f'''import os,socket
assert not os.path.exists({str(secret)!r})
assert not os.path.exists({str(ROOT.parent)!r})
s=socket.socket();s.settimeout(.2)
assert s.connect_ex(('1.1.1.1',443)) != 0
'''
        writable=r.STATE if kind=='store' else r.STATE/'icons'
        code+=f"open({str(writable/'check')!r}, 'w').write('ok')\n"
        subprocess.run(cmd[:cut]+['/usr/bin/python3','-c',code],check=True,timeout=10)
    cmd=r.command('store',['put'])
    subprocess.run(cmd,input=json.dumps({'key':'n1','body':'Your code is 938271','codes':'938271'}),text=True,check=True,timeout=10)
    assert '938271' not in (r.STATE/'live/n1.json').read_text()
    runtime = r.HOME_DIR / 'private-runtime'
    runtime.mkdir()
    bus = runtime / 'session bus'
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as fixture:
        fixture.bind(str(bus))
        address = 'unix:path=' + quote(str(bus), safe='/') + ',guid=' + 'a' * 32
        demo = r.STATE / 'reply-demo'
        demo.mkdir(mode=0o700)
        demo_note = demo / 'notification.json'
        demo_note.write_text('{"synthetic":true}')
        with patch.dict(os.environ, {'DBUS_SESSION_BUS_ADDRESS': address,
                                     'XDG_RUNTIME_DIR': str(runtime)}):
            cmd = r.command('kdeconnect', [])
        cut = cmd.index('/usr/bin/python3')
        code = f'''import os
from pathlib import Path
assert os.environ['DBUS_SESSION_BUS_ADDRESS'] == {address!r}
assert os.environ['XDG_RUNTIME_DIR'] == {str(runtime)!r}
assert Path({str(bus)!r}).is_socket()
assert not Path('/run/user/{os.getuid()}/bus').exists()
'''
        subprocess.run(cmd[:cut] + ['/usr/bin/python3', '-c', code],
                       check=True, timeout=10)
        for args, readable, writable in [
            (['find', 'Chat', 'hello'], False, False),
            (['find', 'Omapager reply demo', 'hello'], True, False),
            (['reply', 'demo:' + 'a' * 32, 'reply', 'Omapager reply demo', 'hello'], True, True),
        ]:
            with patch.dict(os.environ, {'DBUS_SESSION_BUS_ADDRESS': address,
                                         'XDG_RUNTIME_DIR': str(runtime)}):
                cmd = r.command('kdeconnect', args)
            cut = cmd.index('/usr/bin/python3')
            code = f'''from pathlib import Path
assert not Path({str(secret)!r}).exists()
assert not Path({str(r.STATE / 'live/n1.json')!r}).exists()
assert Path({str(demo_note)!r}).exists() == {readable!r}
try:
    Path({str(demo / 'reply.json')!r}).write_text('synthetic reply')
except OSError:
    assert not {writable!r}
else:
    assert {writable!r}
'''
            subprocess.run(cmd[:cut] + ['/usr/bin/python3', '-c', code], check=True, timeout=10)
        for invalid in ('', 'tcp:host=localhost,port=1', 'unix:abstract=fixture',
                        'unix:path=relative', address + ';unix:path=/other',
                        'unix:path=' + str(bus) + ',path=/other'):
            with patch.dict(os.environ, {'DBUS_SESSION_BUS_ADDRESS': invalid,
                                         'XDG_RUNTIME_DIR': str(runtime)}):
                try:
                    r.command('kdeconnect', [])
                except (RuntimeError, ValueError):
                    pass
                else:
                    raise AssertionError('accepted unsupported bus address')
print('sandbox: HOME/network denied, scoped writes, OTP redaction, private bus and reply-demo isolation passed')
