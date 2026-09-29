import hashlib
import os
import re
from pathlib import Path
from typing import Any, Mapping
from .model import CapabilityDescriptor

ID_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
INTERPRETERS = {"/bin/sh", "/bin/bash", "/usr/bin/python3"}
RETRY_CLASSES = {"never", "safe_once", "idempotent"}
ARG_TYPES = {"str", "int", "enum", "bool"}
ALLOWED_KEYS = {"capability_id","revision","script_path","sha256","interpreter","argv","timeout_seconds","max_stdout_bytes","max_stderr_bytes","secret_bindings","retry_class"}

class CapabilityPolicyError(ValueError): pass

def _fail(msg: str): raise CapabilityPolicyError(msg)

def validate_descriptor(raw: Mapping[str, Any], trusted_script_root: str) -> CapabilityDescriptor:
    if not isinstance(raw, Mapping): _fail("descriptor must be a mapping")
    unknown=set(raw)-ALLOWED_KEYS
    if unknown: _fail("unknown descriptor fields: "+",".join(sorted(unknown)))
    for k in ("capability_id","revision","script_path","sha256","interpreter"):
        if k not in raw: _fail("missing field: "+k)
    d=CapabilityDescriptor.from_mapping(raw)
    if not isinstance(d.capability_id,str) or not ID_RE.fullmatch(d.capability_id): _fail("invalid capability_id")
    if type(d.revision) is not int or d.revision < 1: _fail("invalid revision")
    if not isinstance(d.script_path,str) or not os.path.isabs(d.script_path): _fail("script_path must be absolute")
    root=Path(trusted_script_root).resolve(strict=False)
    path=Path(d.script_path).resolve(strict=False)
    try: path.relative_to(root)
    except ValueError: _fail("script_path outside trusted root")
    if not isinstance(d.sha256,str) or not SHA_RE.fullmatch(d.sha256): _fail("invalid sha256")
    if d.interpreter not in INTERPRETERS: _fail("interpreter not allowed")
    if type(d.timeout_seconds) is not int or not 1 <= d.timeout_seconds <= 300: _fail("timeout out of bounds")
    for n,v in (("max_stdout_bytes",d.max_stdout_bytes),("max_stderr_bytes",d.max_stderr_bytes)):
        if type(v) is not int or not 0 <= v <= 1048576: _fail(n+" out of bounds")
    if d.retry_class not in RETRY_CLASSES: _fail("invalid retry_class")
    if not isinstance(d.secret_bindings,Mapping): _fail("secret_bindings must be a mapping")
    for env_name, secret_ref in d.secret_bindings.items():
        if not isinstance(env_name,str) or not re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}",env_name): _fail("invalid secret env name")
        if not isinstance(secret_ref,str) or not re.fullmatch(r"[a-zA-Z0-9_.-]{1,128}",secret_ref): _fail("invalid secret reference")
    if not isinstance(d.argv,tuple): _fail("argv must be a list")
    for spec in d.argv:
        if not isinstance(spec,Mapping): _fail("argv spec must be a mapping")
        if set(spec)-{"name","type","flag","required","min","max","max_length","values"}: _fail("unknown argv policy field")
        if not isinstance(spec.get("name"),str) or not ID_RE.fullmatch(spec["name"]): _fail("invalid argv name")
        if spec.get("type") not in ARG_TYPES: _fail("invalid argv type")
        flag=spec.get("flag")
        if flag is not None and (not isinstance(flag,str) or not re.fullmatch(r"--[a-z0-9][a-z0-9-]{0,63}",flag)): _fail("invalid argv flag")
    return d

def verify_script_digest(d: CapabilityDescriptor) -> None:
    p=Path(d.script_path)
    if not p.is_file(): _fail("script missing")
    h=hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda:f.read(131072),b""): h.update(chunk)
    if h.hexdigest()!=d.sha256: _fail("script digest mismatch")