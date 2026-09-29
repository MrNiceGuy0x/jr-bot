#!/usr/bin/env python3
import hashlib, io, subprocess, sys, tempfile
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT/'src'))
from jrbot_capabilities import CapabilityExecutor, CapabilityPolicyError, validate_descriptor
import jrbot_capabilities.executor as executor_module

def reject(fn):
    try: fn()
    except CapabilityPolicyError: return
    raise AssertionError('expected policy rejection')

class FakeStream:
    def __init__(self,data): self._data=bytearray(data)
    def read1(self,n):
        if not self._data: return b''
        out=bytes(self._data[:n]); del self._data[:n]; return out

class FakeSelector:
    def __init__(self): self.items={}
    def register(self,obj,event,data): self.items[obj]=data
    def unregister(self,obj): self.items.pop(obj,None)
    def get_map(self): return self.items
    def select(self,timeout=None): return [(type('K',(),{'fileobj':o,'data':d})(),None) for o,d in list(self.items.items())]
    def close(self): self.items.clear()

class FakePopen:
    calls=[]
    def __init__(self,argv,**kwargs):
        self.argv=argv; self.kwargs=kwargs; self.stdout=FakeStream(b'1234567890'); self.stderr=FakeStream(b'err'); self.returncode=0
        FakePopen.calls.append((argv,kwargs))
    def wait(self,timeout=None): return self.returncode
    def kill(self): self.returncode=-9

with tempfile.TemporaryDirectory() as td:
    root=Path(td); script=root/'safe.sh'; script.write_text('#!/bin/sh\nprintf 1234567890; printf err >&2',encoding='utf-8')
    raw={"capability_id":"test.safe","revision":1,"script_path":str(script),"sha256":hashlib.sha256(script.read_bytes()).hexdigest(),"interpreter":"/bin/sh","argv":[{"name":"mode","type":"enum","flag":"--mode","values":["safe"]}],"timeout_seconds":5,"max_stdout_bytes":4,"max_stderr_bytes":4,"secret_bindings":{},"retry_class":"never"}
    d=validate_descriptor(raw,str(root)); ex=CapabilityExecutor(); expected=['/bin/sh',str(script),'--mode','safe']; assert ex.build_argv(d,{"mode":"safe"})==expected
    for params in ({"argv":["sh","-c","id"]},{"command":"id"},{"mode":"safe","executable":"/bin/bash"},{"mode":"$(id)"}): reject(lambda p=params:ex.build_argv(d,p))
    with patch.object(executor_module.subprocess,'Popen',FakePopen), patch.object(executor_module.selectors,'DefaultSelector',FakeSelector):
        r=ex.execute(d,{"mode":"safe"})
    assert FakePopen.calls and FakePopen.calls[0][0]==expected
    assert FakePopen.calls[0][1]["shell"] is False
    assert r.stdout==b'1234' and r.stdout_truncated
    assert r.stderr==b'err' and not r.stderr_truncated
    script.write_text('#!/bin/sh\nprintf changed',encoding='utf-8'); reject(lambda:ex.execute(d,{"mode":"safe"}))
print('CAP01_EXECUTION_SECURITY_PASS')