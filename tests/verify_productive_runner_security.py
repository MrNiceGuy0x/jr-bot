#!/usr/bin/env python3
import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

# Test harness dependency shim: the productive runtime installs requests in its
# venv, but these unit tests use FakeSession and must also run on a clean
# developer Python without mutating the host environment.
try:
    import requests as _requests  # noqa: F401
except ModuleNotFoundError:
    import types

    requests_stub = types.ModuleType("requests")

    class _RequestException(Exception):
        pass

    class _Session:
        def __init__(self):
            self.trust_env = True

    requests_stub.RequestException = _RequestException
    requests_stub.Session = _Session
    sys.modules["requests"] = requests_stub

import job_runner


class PresenceOnlyProvider:
    def write_self_presence(self):
        return {"presence_state": "recorded"}


with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    (base / "config" / "capabilities.d").mkdir(parents=True)
    (base / "config" / "secrets").mkdir()
    scripts = base / "scripts" / "capabilities"
    scripts.mkdir(parents=True)
    (base / "state").mkdir()

    safe = scripts / "safe.sh"
    safe.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    sha = hashlib.sha256(safe.read_bytes()).hexdigest()
    descriptor = {
        "capability_id": "backup.rotate",
        "revision": 3,
        "script_path": str(safe),
        "sha256": sha,
        "interpreter": "/bin/sh",
        "argv": [{"name": "profile", "type": "enum", "flag": "--profile", "values": ["nightly"]}],
        "timeout_seconds": 5,
        "max_stdout_bytes": 32,
        "max_stderr_bytes": 32,
        "secret_bindings": {},
        "retry_class": "never",
    }
    (base / "config" / "capabilities.d" / "backup.json").write_text(json.dumps(descriptor), encoding="utf-8")

    cfg = job_runner.RuntimeConfig(
        instance="ggb",
        management_mode="opscon_managed",
        database_mode="external",
        base_dir=base,
        server_base="https://example.invalid/handler",
        auth_mode="none",
    )

    rejected_http = job_runner.execute_lease(
        cfg,
        PresenceOnlyProvider(),
        {"job_type": "http", "payload": {"action": "service.refresh_cache", "params": {}}},
    )
    assert rejected_http.outcome == "rejected"
    assert rejected_http.retryable is False

    rejected_shell = job_runner.execute_lease(
        cfg,
        PresenceOnlyProvider(),
        {"job_type": "shell", "payload": {"action": "id", "command": "id"}},
    )
    assert rejected_shell.outcome == "rejected"

    rejected_unknown_system = job_runner.execute_lease(
        cfg,
        PresenceOnlyProvider(),
        {"job_type": "system", "payload": {"action": "system.exec"}},
    )
    assert rejected_unknown_system.outcome == "rejected"

    heartbeat = job_runner.execute_lease(
        cfg,
        PresenceOnlyProvider(),
        {"job_type": "system", "payload": {"action": "system.jrbot_heartbeat"}},
    )
    assert heartbeat.outcome == "succeeded"

    legacy_wire_heartbeat = job_runner.execute_lease(
        cfg,
        PresenceOnlyProvider(),
        {"job_type": "system", "payload": {"action": "jrbot_heartbeat"}},
    )
    assert legacy_wire_heartbeat.outcome == "rejected"

source = (ROOT / "src" / "job_runner.py").read_text(encoding="utf-8")
for forbidden in (
    "subprocess.Popen(",
    "shell=True",
    "os.system(",
    "eval(",
    "exec(",
    "X-JRBot-Token",
):
    assert forbidden not in source, forbidden

assert "/runtime/jobs/lease" in source
assert "/runtime/jobs/renew" in source
assert "/runtime/jobs/report" in source
assert "/runtime/presence" in source
assert "Authorization" in source
assert "Bearer " in source
# HTTP is now restricted to a privileged registered template.
assert "execute_guild_overview" in source
with tempfile.TemporaryDirectory() as td:
    cfg = job_runner.RuntimeConfig('ggb', 'standalone', 'local_pi', Path(td), '', 'none')
    for payload in ({'url':'https://example.invalid'}, {'action':'guild_overview_refresh','url':'https://example.invalid'}, {'action':'unknown'}):
        outcome = job_runner.execute_lease(cfg, object(), {'job_type':'http','payload':payload})
        assert outcome.outcome == 'rejected' and outcome.retryable is False
assert 'SYSTEM_HEARTBEAT_ACTION = "system.jrbot_heartbeat"' in source
assert "TRANSPORT_RETRY_ATTEMPTS = 2" in source
assert "MAX_RESPONSE_BODY_BYTES" in source

print("PRODUCTIVE_RUNNER_SECURITY_PASS")
