#!/usr/bin/env python3
"""No network: test the registered request and conservative response projection."""
import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import jrbot_http_capability as h

GOOD=b'<p>Anzahl der abgerufenen Gildenmitglieder: 2</p>alice erfolgreich gespeichert.<br>bob erfolgreich gespeichert.<br></p>Verarbeitung abgeschlossen. Alle Mitglieder wurden aktualisiert.<br>'
def failed(status=200,body=GOOD,headers=None):
    assert h.project_response(status,headers or {},body)['outcome']=='failed'

def main():
    assert h.project_response(200,{},GOOD)['result']['member_count']==2
    for body in [b'',GOOD[:-15],GOOD.replace(b'bob',b'alice'),GOOD.replace(b': 2',b': 3'),
        GOOD+b'Warning: partial write',GOOD.replace(b'bob erfolgreich gespeichert.',b'Fehler beim Aktualisieren'),
        b"<div class='err'>Spam-Schutz aktiviert</div>",GOOD+b'<script>alert(1)</script>',
        GOOD+b'<!-- unexpected -->',b'x'*(h.POLICY['max_response_bytes']+1)]:failed(body=body)
    for status in (201,302,403,500):failed(status=status)
    failed(headers={'content-encoding':'gzip'})
    with tempfile.TemporaryDirectory() as td:
        root=Path(td);p=root/'config/capabilities.d/guild_overview.http.json';p.parent.mkdir(parents=True)
        p.write_text(json.dumps(h.POLICY));os.chmod(p,0o600)
        assert h.load_policy(root)==h.POLICY
        for field,value in [('host','evil.invalid'),('redirects',True),('tls_verify',False),('method','POST'),('total_timeout_seconds',61)]:
            bad=dict(h.POLICY);bad[field]=value;p.write_text(json.dumps(bad))
            try:h.load_policy(root)
            except h.HttpCapabilityError:pass
            else:raise AssertionError('unregistered policy accepted')
        p.write_text(json.dumps(h.POLICY));os.chmod(p,0o666)
        try:h.load_policy(root)
        except h.HttpCapabilityError:pass
        else:raise AssertionError('writable policy accepted')
        os.chmod(p,0o600);p.unlink();p.symlink_to(root/'absent')
        try:h.load_policy(root)
        except h.HttpCapabilityError:pass
        else:raise AssertionError('symlink accepted')
    class Socket:
        def settimeout(self,value):assert value==60
    class Response:
        status=200
        def getheaders(self):return [('Content-Type','text/html')]
        def read(self,n):assert n==1048577;return GOOD
    class Connection:
        def __init__(self,*args,**kwargs):
            assert args==('www.blenk.co.at',443) and kwargs['timeout']==10
            assert kwargs['context'].verify_mode!=0
            self.sock=Socket()
        def connect(self):pass
        def request(self,method,path,headers):
            assert method=='GET' and path==h.POLICY['path'] and headers==h.POLICY['headers']
        def getresponse(self):return Response()
        def close(self):pass
    with patch.object(h.http.client,'HTTPSConnection',Connection):assert h._request(h.POLICY)['outcome']=='succeeded'
    class Pipe:
        def poll(self,budget):assert budget==60;return False
        def close(self):pass
    class Process:
        def __init__(self,*a,**k):self.alive=True;self.terminated=False
        def start(self):pass
        def is_alive(self):return self.alive
        def terminate(self):self.terminated=True;self.alive=False
        def join(self,timeout):assert timeout==2
    class Context:
        def Pipe(self,duplex):assert duplex is False;return Pipe(),Pipe()
        def Process(self,*a,**k):self.child=Process();return self.child
    context=Context()
    with patch.object(h,'load_policy',return_value=h.POLICY),patch.object(h.multiprocessing,'get_context',return_value=context):
        result=h.execute_guild_overview(Path('/synthetic'),{'action':'guild_overview_refresh'})
        assert result['outcome']=='failed' and context.child.terminated
        try:h.execute_guild_overview(Path('/synthetic'),{'action':'guild_overview_refresh','url':'evil'})
        except h.HttpCapabilityError:pass
        else:raise AssertionError('job URL accepted')
    print('GUILD_OVERVIEW_POLICY_BOUNDS_NO_RETRY_CONSERVATIVE_RESPONSE=PASS; LIVE_HTTP=NONE')
if __name__=='__main__':main()
