#!/usr/bin/env python3
"""Real namespaces, synthetic HOME, no live notification state or session bus."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
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
print('sandbox: HOME denied, network denied, scoped writes and OTP redaction passed')
