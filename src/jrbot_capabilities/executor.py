import os
import selectors
import subprocess
import time
from dataclasses import dataclass
from typing import Any, Callable, Mapping, Optional, Sequence
from .model import CapabilityDescriptor
from .validator import CapabilityPolicyError, verify_script_digest

class CapabilityExecutionError(RuntimeError): pass

@dataclass(frozen=True)
class ExecutionResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    stdout_truncated: bool
    stderr_truncated: bool

class CapabilityExecutor:
    def __init__(self, secret_resolver: Optional[Callable[[str], str]]=None):
        self.secret_resolver=secret_resolver

    @staticmethod
    def _value(spec: Mapping[str,Any], value: Any) -> Sequence[str]:
        typ=spec["type"]
        if typ=="bool":
            if type(value) is not bool: raise CapabilityPolicyError("bool argument required")
            return [spec["flag"]] if value and spec.get("flag") else ([] if not value else ["true"])
        if typ=="int":
            if type(value) is not int: raise CapabilityPolicyError("int argument required")
            if "min" in spec and value < spec["min"]: raise CapabilityPolicyError("argument below minimum")
            if "max" in spec and value > spec["max"]: raise CapabilityPolicyError("argument above maximum")
            rendered=str(value)
        elif typ=="enum":
            if not isinstance(value,str) or value not in spec.get("values",[]): raise CapabilityPolicyError("enum argument rejected")
            rendered=value
        else:
            if not isinstance(value,str): raise CapabilityPolicyError("string argument required")
            if len(value)>spec.get("max_length",256): raise CapabilityPolicyError("string argument too long")
            rendered=value
        return ([spec["flag"],rendered] if spec.get("flag") else [rendered])

    def build_argv(self,d: CapabilityDescriptor,params: Mapping[str,Any]) -> list[str]:
        if not isinstance(params,Mapping): raise CapabilityPolicyError("params must be a mapping")
        specs={s["name"]:s for s in d.argv}
        unknown=set(params)-set(specs)
        if unknown: raise CapabilityPolicyError("unknown remote parameters")
        out=[d.interpreter,d.script_path]
        for spec in d.argv:
            name=spec["name"]
            if name not in params:
                if spec.get("required",False): raise CapabilityPolicyError("missing required parameter: "+name)
                continue
            out.extend(self._value(spec,params[name]))
        return out

    def execute(self,d: CapabilityDescriptor,params: Mapping[str,Any]) -> ExecutionResult:
        verify_script_digest(d)
        argv=self.build_argv(d,params)
        env={"PATH":"/usr/bin:/bin","LANG":"C.UTF-8"}
        if d.secret_bindings:
            if self.secret_resolver is None: raise CapabilityExecutionError("secret resolver unavailable")
            for env_name,ref in d.secret_bindings.items(): env[env_name]=self.secret_resolver(ref)
        p=subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,shell=False)
        sel=selectors.DefaultSelector(); sel.register(p.stdout,selectors.EVENT_READ,"stdout"); sel.register(p.stderr,selectors.EVENT_READ,"stderr")
        bufs={"stdout":bytearray(),"stderr":bytearray()}; limits={"stdout":d.max_stdout_bytes,"stderr":d.max_stderr_bytes}; trunc={"stdout":False,"stderr":False}
        deadline=time.monotonic()+d.timeout_seconds
        try:
            while sel.get_map():
                remaining=deadline-time.monotonic()
                if remaining<=0: raise subprocess.TimeoutExpired(argv,d.timeout_seconds)
                for key,_ in sel.select(min(0.25,remaining)):
                    data=key.fileobj.read1(8192)
                    if not data: sel.unregister(key.fileobj); continue
                    name=key.data; room=max(0,limits[name]-len(bufs[name]))
                    if room: bufs[name].extend(data[:room])
                    if len(data)>room: trunc[name]=True
            rc=p.wait(timeout=max(0.01,deadline-time.monotonic()))
        except subprocess.TimeoutExpired:
            p.kill(); p.wait(); raise CapabilityExecutionError("capability timeout")
        finally:
            sel.close()
        return ExecutionResult(rc,bytes(bufs["stdout"]),bytes(bufs["stderr"]),trunc["stdout"],trunc["stderr"])