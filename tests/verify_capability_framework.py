#!/usr/bin/env python3
import hashlib, json, os, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; sys.path.insert(0,str(ROOT/'src'))
from jrbot_capabilities import CapabilityPolicyError, CapabilityRegistry, validate_descriptor

def expect_fail(fn):
    try: fn()
    except (CapabilityPolicyError,KeyError,TypeError,ValueError): return
    raise AssertionError("expected rejection")

with tempfile.TemporaryDirectory() as td:
    root=Path(td)/'scripts'; policy=Path(td)/'policy'; root.mkdir(); policy.mkdir()
    script=root/'safe.sh'; script.write_text('#!/bin/sh\nprintf ok',encoding='utf-8')
    sha=hashlib.sha256(script.read_bytes()).hexdigest()
    base={"capability_id":"test.echo","revision":1,"script_path":str(script),"sha256":sha,"interpreter":"/bin/sh","argv":[{"name":"count","type":"int","flag":"--count","min":1,"max":3}],"timeout_seconds":5,"max_stdout_bytes":64,"max_stderr_bytes":64,"secret_bindings":{},"retry_class":"never"}
    d=validate_descriptor(base,str(root)); assert d.capability_id=='test.echo'
    for patch in ({"revision":0},{"script_path":"/tmp/evil"},{"sha256":"x"*64},{"interpreter":"/usr/bin/env"},{"timeout_seconds":0},{"retry_class":"remote"},{"command":"id"},{"argv_raw":["sh","-c","id"]}):
        bad=dict(base); bad.update(patch); expect_fail(lambda b=bad:validate_descriptor(b,str(root)))
    (policy/'echo.json').write_text(json.dumps(base),encoding='utf-8')
    reg=CapabilityRegistry(str(policy),str(root)).load(); assert reg.get('test.echo',1).revision==1
    expect_fail(lambda:reg.get('test.echo',2)); expect_fail(lambda:reg.get('missing',1))
print('CAP01_FRAMEWORK_PASS')