#!/usr/bin/env python3
import json
import sys
import tempfile
import uuid
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


class FakeResponse:
    def __init__(self, status_code, payload, raw_body=None, headers=None):
        self.status_code = status_code
        self._payload = payload
        self.content = raw_body if raw_body is not None else json.dumps(payload).encode("utf-8")
        self.headers = dict(headers or {})
    def json(self):
        return self._payload
    def iter_content(self, chunk_size=8192):
        for offset in range(0, len(self.content), chunk_size):
            yield self.content[offset:offset + chunk_size]




class BodyReadFailureResponse(FakeResponse):
    def __init__(self, status_code, payload, fail_after_chunks=0):
        super().__init__(status_code, payload)
        self.fail_after_chunks = fail_after_chunks
        self.closed = False
    def iter_content(self, chunk_size=8192):
        yielded = 0
        for offset in range(0, len(self.content), chunk_size):
            if yielded >= self.fail_after_chunks:
                raise job_runner.requests.RequestException("response body stream lost")
            yielded += 1
            yield self.content[offset:offset + chunk_size]
        raise job_runner.requests.RequestException("response body stream lost")
    def close(self):
        self.closed = True


class FakeSession:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []
        self.trust_env = True
    def post(self, url, json, headers, timeout, allow_redirects, stream=False):
        self.calls.append((url, json, headers, timeout, allow_redirects, stream))
        reply = self.replies.pop(0)
        if isinstance(reply, BaseException):
            raise reply
        return reply


def write_external_config(base, auth_mode="split_ping_token"):
    (base / "config" / "secrets").mkdir(parents=True)
    (base / "state").mkdir()
    (base / "config" / "capabilities.d").mkdir()
    (base / "scripts" / "capabilities").mkdir(parents=True)
    (base / "config" / "secrets" / "server.token").write_text("SERVERSECRET\n", encoding="utf-8")
    (base / "config" / "secrets" / "ping.token").write_text("PINGSECRET\n", encoding="utf-8")
    cfg = base / "config" / "config.ini"
    cfg.write_text(
        f"""[bot]
INSTANCE_NAME = {base.name}
MANAGEMENT_MODE = opscon_managed
DATABASE_MODE = external

[server]
SERVER_BASE = https://example.invalid/handler
AUTH_MODE = {auth_mode}

[paths]
BASE_DIR = {base}
""",
        encoding="utf-8",
    )
    return cfg


with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)

    identity = job_runner.RunnerIdentity(base / "state")
    first = identity.load_or_create()
    second = identity.load_or_create()
    assert first == second
    assert uuid.UUID(first).version == 4

    no_work = {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": True,
        "server_time": "2026-09-30T00:00:00Z",
        "lease": None,
        "retry_after_seconds": 60,
    }
    fake = FakeSession([FakeResponse(200, no_work)])
    rc = job_runner.run_once(cfg, session=fake)
    assert rc == 0
    assert fake.trust_env is False
    assert fake.calls[0][0].endswith("/jrbot/v1/runtime/jobs/lease")
    assert fake.calls[0][2]["Authorization"] == "Bearer SERVERSECRET"
    assert fake.calls[0][4] is False
    assert fake.calls[0][5] is True
    req = fake.calls[0][1]
    assert req["protocol"] == "jrbot-runtime/1"
    assert req["instance"] == "ggb"
    assert uuid.UUID(req["lease_request_id"]).version == 4
    assert uuid.UUID(req["runner_id"]).version == 4
    assert uuid.UUID(req["session_id"]).version == 4

with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    dispatch = str(uuid.uuid4())
    lease = {
        "job_id": "j1",
        "job_key": "jrbot_heartbeat",
        "job_revision": 1,
        "dispatch_id": dispatch,
        "scheduled_for": "2026-09-30T00:00:00Z",
        "attempt": 1,
        "max_attempts": 1,
        "lease_expires_at": "2026-09-30T00:05:00Z",
        "job_type": "system",
        "payload": {"action": "system.jrbot_heartbeat"},
    }
    replies = [
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:00Z",
            "lease": lease,
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:01Z",
            "lease_expires_at": "2026-09-30T00:05:01Z",
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:02Z",
            "presence_state": "recorded",
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:03Z",
            "result_state": "recorded",
        }),
    ]
    fake = FakeSession(replies)
    assert job_runner.run_once(cfg, session=fake) == 0
    paths = [c[0].split("/jrbot/v1", 1)[1] for c in fake.calls]
    assert paths == [
        "/runtime/jobs/lease",
        "/runtime/jobs/renew",
        "/runtime/presence",
        "/runtime/jobs/report",
    ]
    assert fake.calls[0][2]["Authorization"] == "Bearer SERVERSECRET"
    assert fake.calls[1][2]["Authorization"] == "Bearer SERVERSECRET"
    assert fake.calls[2][2]["Authorization"] == "Bearer PINGSECRET"
    assert fake.calls[3][2]["Authorization"] == "Bearer SERVERSECRET"
    report = fake.calls[3][1]
    assert report["outcome"] == "succeeded"
    assert report["retryable"] is False
    assert uuid.UUID(report["run_id"]).version == 4

with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "local"
    (base / "config").mkdir(parents=True)
    (base / "state").mkdir()
    cfg_path = base / "config" / "config.ini"
    cfg_path.write_text(
        f"""[bot]
INSTANCE_NAME = local
MANAGEMENT_MODE = standalone
DATABASE_MODE = local_pi

[paths]
BASE_DIR = {base}
""",
        encoding="utf-8",
    )
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    try:
        job_runner.run_once(cfg)
    except job_runner.ConfigError:
        pass
    else:
        raise AssertionError("local_pi must fail closed without an explicitly prepared authority")


with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    fake = FakeSession([FakeResponse(426, {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": False,
        "server_time": "2026-09-30T00:00:00Z",
        "error": {"code": "PROTOCOL_VERSION_UNSUPPORTED", "message": "unsupported"},
    })])
    try:
        job_runner.run_once(cfg, session=fake)
    except job_runner.RuntimeProtocolError:
        pass
    else:
        raise AssertionError("HTTP 426 must fail closed as protocol mismatch")


# Lease transport retry must preserve the same lease_request_id and full logical payload.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    no_work = {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": True,
        "server_time": "2026-09-30T00:00:00Z",
        "lease": None,
        "retry_after_seconds": 60,
    }
    fake = FakeSession([
        job_runner.requests.RequestException("lost response"),
        FakeResponse(200, no_work),
    ])
    assert job_runner.run_once(cfg, session=fake) == 0
    lease_calls = [c for c in fake.calls if c[0].endswith("/runtime/jobs/lease")]
    assert len(lease_calls) == 2
    assert lease_calls[0][1] == lease_calls[1][1]
    assert lease_calls[0][1]["lease_request_id"] == lease_calls[1][1]["lease_request_id"]

# Report transport retry must preserve dispatch_id, run_id and canonical result content.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    dispatch = str(uuid.uuid4())
    lease = {
        "job_id": "j1",
        "job_key": "jrbot_heartbeat",
        "job_revision": 1,
        "dispatch_id": dispatch,
        "scheduled_for": "2026-09-30T00:00:00Z",
        "attempt": 1,
        "max_attempts": 1,
        "lease_expires_at": "2026-09-30T00:05:00Z",
        "job_type": "system",
        "payload": {"action": "system.jrbot_heartbeat"},
    }
    fake = FakeSession([
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:00Z",
            "lease": lease,
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:01Z",
            "lease_expires_at": "2026-09-30T00:05:01Z",
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:02Z",
            "presence_state": "recorded",
        }),
        job_runner.requests.RequestException("report response lost"),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:03Z",
            "result_state": "already_recorded",
        }),
    ])
    assert job_runner.run_once(cfg, session=fake) == 0
    reports = [c for c in fake.calls if c[0].endswith("/runtime/jobs/report")]
    assert len(reports) == 2
    assert reports[0][1] == reports[1][1]
    assert reports[0][1]["dispatch_id"] == dispatch
    assert uuid.UUID(reports[0][1]["run_id"]).version == 4



# Lease retry must also cover a transport failure while reading the response body.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    no_work = {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": True,
        "server_time": "2026-09-30T00:00:00Z",
        "lease": None,
        "retry_after_seconds": 60,
    }
    broken = BodyReadFailureResponse(200, no_work, fail_after_chunks=0)
    fake = FakeSession([broken, FakeResponse(200, no_work)])
    assert job_runner.run_once(cfg, session=fake) == 0
    lease_calls = [c for c in fake.calls if c[0].endswith("/runtime/jobs/lease")]
    assert len(lease_calls) == 2
    assert lease_calls[0][1] == lease_calls[1][1]
    assert lease_calls[0][1]["lease_request_id"] == lease_calls[1][1]["lease_request_id"]
    assert broken.closed is True

# Report retry must also cover a transport failure while reading the response body.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    dispatch = str(uuid.uuid4())
    lease = {
        "job_id": "j1",
        "job_key": "jrbot_heartbeat",
        "job_revision": 1,
        "dispatch_id": dispatch,
        "scheduled_for": "2026-09-30T00:00:00Z",
        "attempt": 1,
        "max_attempts": 1,
        "lease_expires_at": "2026-09-30T00:05:00Z",
        "job_type": "system",
        "payload": {"action": "system.jrbot_heartbeat"},
    }
    report_ack = {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": True,
        "server_time": "2026-09-30T00:00:03Z",
        "result_state": "recorded",
    }
    broken_report = BodyReadFailureResponse(200, report_ack, fail_after_chunks=0)
    fake = FakeSession([
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:00Z",
            "lease": lease,
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:01Z",
            "lease_expires_at": "2026-09-30T00:05:01Z",
        }),
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:02Z",
            "presence_state": "recorded",
        }),
        broken_report,
        FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:03Z",
            "result_state": "already_recorded",
        }),
    ])
    assert job_runner.run_once(cfg, session=fake) == 0
    reports = [c for c in fake.calls if c[0].endswith("/runtime/jobs/report")]
    assert len(reports) == 2
    assert reports[0][1] == reports[1][1]
    assert reports[0][1]["dispatch_id"] == dispatch
    assert uuid.UUID(reports[0][1]["run_id"]).version == 4
    assert broken_report.closed is True


# Canonical RFC3339 UTC Z syntax is strict before datetime parsing.
for good_timestamp in (
    "2026-09-30T00:00:00Z",
    "2026-09-30T00:00:00.123456Z",
):
    parsed = job_runner._parse_rfc3339_utc(good_timestamp, "test_timestamp")
    assert parsed.utcoffset().total_seconds() == 0

for bad_timestamp in (
    "20260930T000000Z",
    "2026-W40-3T00:00:00Z",
    "2026-09-30 00:00:00Z",
    "2026-09-30T00:00:00",
    "2026-02-30T00:00:00Z",
    "2026-09-30T24:00:00Z",
):
    try:
        job_runner._parse_rfc3339_utc(bad_timestamp, "test_timestamp")
    except job_runner.RuntimeProtocolError:
        pass
    else:
        raise AssertionError(f"non-canonical RFC3339 UTC timestamp accepted: {bad_timestamp}")

# Malformed / unsafe lease envelopes must fail before execution.
def assert_bad_lease(mutator):
    with tempfile.TemporaryDirectory() as td:
        base = Path(td) / "ggb"
        cfg_path = write_external_config(base)
        cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
        lease = {
            "job_id": "j1",
            "job_key": "jrbot_heartbeat",
            "job_revision": 1,
            "dispatch_id": str(uuid.uuid4()),
            "scheduled_for": "2026-09-30T00:00:00Z",
            "attempt": 1,
            "max_attempts": 1,
            "lease_expires_at": "2026-09-30T00:05:00Z",
            "job_type": "system",
            "payload": {"action": "system.jrbot_heartbeat"},
        }
        mutator(lease)
        fake = FakeSession([FakeResponse(200, {
            "protocol": job_runner.RUNTIME_PROTOCOL,
            "ok": True,
            "server_time": "2026-09-30T00:00:00Z",
            "lease": lease,
        })])
        try:
            job_runner.run_once(cfg, session=fake)
        except job_runner.RuntimeProtocolError:
            pass
        else:
            raise AssertionError("malformed lease must fail closed")
        assert len(fake.calls) == 1

assert_bad_lease(lambda lease: lease.__setitem__("dispatch_id", "not-a-uuid"))
assert_bad_lease(lambda lease: lease.__setitem__("scheduled_for", "not-a-time"))
assert_bad_lease(lambda lease: lease.__setitem__("lease_expires_at", "2026-09-29T23:59:59Z"))
assert_bad_lease(lambda lease: lease.__setitem__("attempt", 0))
assert_bad_lease(lambda lease: lease.__setitem__("max_attempts", 0))
assert_bad_lease(lambda lease: lease.__setitem__("job_revision", True))
assert_bad_lease(lambda lease: lease.__setitem__("payload", {"x": "y" * (job_runner.MAX_JOB_PAYLOAD_BYTES + 1)}))

# Deep JSON payloads are bounded independently of byte length.
def make_deep_payload():
    node = {"action": "system.jrbot_heartbeat"}
    for _ in range(job_runner.MAX_JSON_DEPTH + 1):
        node = {"nested": node}
    return node
assert_bad_lease(lambda lease: lease.__setitem__("payload", make_deep_payload()))

# Common response envelope requires bounded RFC3339 UTC server_time.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    fake = FakeSession([FakeResponse(200, {
        "protocol": job_runner.RUNTIME_PROTOCOL,
        "ok": True,
        "server_time": "not-a-time",
        "lease": None,
    })])
    try:
        job_runner.run_once(cfg, session=fake)
    except job_runner.RuntimeProtocolError:
        pass
    else:
        raise AssertionError("invalid server_time must fail closed")

# Response-body byte bound is enforced before JSON execution.
with tempfile.TemporaryDirectory() as td:
    base = Path(td) / "ggb"
    cfg_path = write_external_config(base)
    cfg = job_runner.load_runtime_config(cfg_path, runtime_base=base)
    oversized = b"{" + (b"x" * (job_runner.MAX_RESPONSE_BODY_BYTES + 1)) + b"}"
    fake = FakeSession([FakeResponse(200, {}, raw_body=oversized)])
    try:
        job_runner.run_once(cfg, session=fake)
    except job_runner.RuntimeProtocolError:
        pass
    else:
        raise AssertionError("oversized response must fail closed")

print("PRODUCTIVE_RUNNER_PROTOCOL_PASS")
