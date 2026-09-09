import importlib.machinery
import importlib.util
import io
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'bin'))
import omapager_http as net
import omapager_files as files

def module(name):
    loader=importlib.machinery.SourceFileLoader(name,str(ROOT/'bin'/name))
    spec=importlib.util.spec_from_loader(name,loader)
    mod=importlib.util.module_from_spec(spec);loader.exec_module(mod);return mod

class Storage(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.home=Path(self.tmp.name)
        self.env=dict(os.environ,HOME=str(self.home),PYTHONDONTWRITEBYTECODE='1')
    def tearDown(self): self.tmp.cleanup()
    def run_store(self,*args,payload=None):
        return subprocess.run([sys.executable,str(ROOT/'bin/omapager-store'),*args],input=json.dumps(payload) if payload is not None else '',text=True,capture_output=True,env=self.env)
    def test_secret_never_on_disk(self):
        for i,body in enumerate(['Your code is 938271','Your code is 938 271','Your code is &#57;38271','Your code is A9F3K2']):
            self.assertEqual(self.run_store('put',payload={'key':f'n{i}','body':body,'rawBody':body,'codes':'938271','image':'/etc/passwd'}).returncode,0)
            self.assertEqual(self.run_store('close',f'n{i}','done').returncode,0)
        for path in self.home.rglob('*'):
            if path.is_file():
                content=path.read_text()
                for secret in ['938271','938 271','&#57;38271','A9F3K2','/etc/passwd']: self.assertNotIn(secret,content)
                self.assertEqual(path.stat().st_mode&0o777,0o600)
        self.assertEqual((self.home/'.local/state/omarchy/omapager').stat().st_mode&0o777,0o700)
    def test_ordinary_restore_and_off(self):
        self.assertEqual(self.run_store('put',payload={'key':'n1','body':'ordinary message'}).returncode,0)
        self.assertEqual(json.loads(self.run_store('restore').stdout)[0]['body'],'ordinary message')
        self.assertEqual(self.run_store('policy',payload={'historyHours':0}).returncode,0)
        self.run_store('close','n1','done')
        self.assertEqual(json.loads(self.run_store('history').stdout),[])
    def test_symlink_and_oversize(self):
        self.run_store('restore')
        victim=self.home/'victim';victim.write_text('untouched')
        live=self.home/'.local/state/omarchy/omapager/live'
        (live/'n1.json').symlink_to(victim)
        self.assertNotEqual(self.run_store('put',payload={'key':'n1','body':'x'}).returncode,0)
        self.assertEqual(victim.read_text(),'untouched')
        self.assertNotEqual(self.run_store('put',payload={'key':'../../escape','body':'x'}).returncode,0)
        self.assertNotEqual(self.run_store('put',payload={'key':'n2','body':'x'*70000}).returncode,0)
    def test_directory_symlink(self):
        root=self.home/'.local/state/omarchy';root.mkdir(parents=True)
        target=self.home/'victim';target.mkdir()
        (root/'omapager').symlink_to(target,target_is_directory=True)
        self.assertNotEqual(self.run_store('put',payload={'key':'n1'}).returncode,0)
        self.assertEqual(list(target.iterdir()),[])
    def test_legacy_redaction(self):
        self.run_store('restore')
        live=self.home/'.local/state/omarchy/omapager/live/n1.json'
        live.write_text(json.dumps({'key':'n1','summary':'OTP 938271','rawBody':'938271'}))
        self.run_store('restore')
        self.assertNotIn('938271',live.read_text())

class Network(unittest.TestCase):
    def test_destinations(self):
        for u in ['file:///etc/passwd','https://u:p@example.com','https://example.com:22','https://127.1','http://169.254.169.254','https://[::1]','https://host.local','https://example.com/%250a']:
            with self.assertRaises(ValueError):net.parse_url(u)
    def test_dns(self):
        for ip in ['127.0.0.1','10.0.0.1','172.16.0.1','192.168.1.1','169.254.169.254','0.0.0.0','224.0.0.1','::1','fe80::1','fc00::1','::','::ffff:192.168.1.1']:
            family=socket.AF_INET6 if ':' in ip else socket.AF_INET
            answers=[(socket.AF_INET,socket.SOCK_STREAM,6,'',('93.184.216.34',443)),(family,socket.SOCK_STREAM,6,'',(ip,443))]
            with patch.object(socket,'getaddrinfo',return_value=answers):
                with self.assertRaises(ValueError,msg=ip):net.resolve_public_host('example.com',443)
    def test_no_reresolve_and_tls_hostname(self):
        answer=(socket.AF_INET,socket.SOCK_STREAM,6,'',('93.184.216.34',443))
        sock=MagicMock();ctx=MagicMock()
        with patch.object(socket,'socket',return_value=sock),patch.object(socket,'getaddrinfo',side_effect=AssertionError('second DNS lookup')),patch.object(net.ssl,'create_default_context',return_value=ctx):
            c=net.PinnedHTTPConnection('example.com',443,answer,True);c.connect()
        sock.connect.assert_called_once_with(('93.184.216.34',443))
        ctx.wrap_socket.assert_called_once_with(sock,server_hostname='example.com')
    def test_redirects(self):
        for target in ['http://127.0.0.1','http://10.0.0.1','file:///etc/passwd','https://user@example.com','https://example.com:22','\nhttps://example.com']:
            with patch.object(net,'fetch_once',return_value=(None,target)):
                with self.assertRaises(ValueError,msg=target):net.fetch('https://example.com')
        with patch.object(net,'fetch_once',return_value=(None,'/again')) as f:
            with self.assertRaises(ValueError):net.fetch('https://example.com')
            self.assertEqual(f.call_count,4)
    def test_stream_limit(self):
        response=MagicMock(status=200)
        response.getheader.side_effect=lambda k,d=None: d
        response.read1.return_value=b'x'*11
        conn=MagicMock();conn.getresponse.return_value=response
        with patch.object(net,'resolve_public_answers',return_value=()),patch.object(net,'PinnedHTTPConnection',return_value=conn):
            with self.assertRaises(ValueError):net.fetch_once('https://example.com',10)
        conn.close.assert_called_once()

class Replies(unittest.TestCase):
    def setUp(self):self.k=module('omapager-kdeconnect')
    def test_ambiguous_and_empty(self):
        a=dict(appName='Chat',text='hello',ticker='',replyId='1',path='/modules/kdeconnect/devices/device/notifications/1')
        with patch.object(self.k,'listing',return_value=[a,a]):self.assertIsNone(self.k.find('Chat','hello'))
        with patch.object(self.k,'listing',return_value=[a]):
            self.assertEqual(self.k.find('Chat','hello'),a)
            self.assertIsNone(self.k.find('Other','hello'))
            self.assertIsNone(self.k.find('Chat','something else'))
            self.assertIsNone(self.k.find('Chat',''))
    def test_path(self):
        self.assertTrue(self.k.valid_path('/modules/kdeconnect/devices/device_1/notifications/12'))
        for p in ['fake:1','/org/other','--help','; rm -rf ~','$(touch /tmp/pwned)','`touch /tmp/pwned`','/modules/kdeconnect/devices/x/notifications/1\n']:
            self.assertFalse(self.k.valid_path(p))
    def test_command_text_is_data(self):
        payloads=['; rm -rf ~','$(touch /tmp/pwned)','`touch /tmp/pwned`','--help','quotes"\n\\']
        target='/modules/kdeconnect/devices/device/notifications/1'
        for text in payloads:
            with patch.object(sys,'argv',['helper','reply',target,text,'Chat','body']),patch.object(self.k,'find',return_value={'path':target}),patch.object(self.k.subprocess,'run',return_value=MagicMock(returncode=0)) as run:
                with contextlib.redirect_stdout(io.StringIO()): self.assertEqual(self.k.main(),0)
                self.assertEqual(run.call_args_list[0].args[0][-1],text)
                self.assertEqual(run.call_args_list[0].args[0][2],"--")
                self.assertNotIn('shell',run.call_args_list[0].kwargs)

class Icons(unittest.TestCase):
    def test_icon_hint_traversal(self):
        icon=module('omapager-icon')
        with patch.object(icon.glob,'glob',return_value=[]) as glob:
            icon.from_icon_theme(['../../../../etc/passwd','/etc/passwd','*','--help'])
            for call in glob.call_args_list:
                self.assertNotIn('../',call.args[0])
    def test_svg_rejected(self):
        icon=module('omapager-icon')
        with tempfile.TemporaryDirectory() as temp,patch.object(icon,'CACHE',temp),patch.object(icon,'get',return_value=(b'<svg xmlns="http://www.w3.org/2000/svg"></svg>','https://example.com')):
            self.assertIsNone(icon.fetch_site('example.com','dark'))
            self.assertEqual(list(Path(temp).iterdir()),[])

class Raster(unittest.TestCase):
    def test_valid_raster_and_dimension_limit(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow not installed; run locked scanner/test environment")
        icon=module('omapager-icon')
        for size,accepted in [((256,256),True),((2049,1),False)]:
            buf=io.BytesIO();Image.new('RGB',size).save(buf,format='PNG')
            with tempfile.TemporaryDirectory() as temp,patch.object(icon,'CACHE',temp),patch.object(icon,'get',return_value=(buf.getvalue(),'https://example.com')):
                path=icon.fetch_site('example.com','dark')
                self.assertEqual(bool(path),accepted)
                if path:
                    with Image.open(path) as im:
                        self.assertEqual(im.format,'PNG')
                        self.assertLessEqual(max(im.size),128)
                    self.assertEqual(Path(path).stat().st_mode&0o777,0o600)

if __name__=='__main__':unittest.main()
