#!/usr/bin/env python3
from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Mapping, Optional

import requests

from jrbot_capabilities import CapabilityExecutor, CapabilityPolicyError, validate_descriptor


RUNTIME_PROTOCOL = "jrbot-runtime/1"
RUNTIME_VERSION = "0.4.0-dev-productive-runner"
SYSTEM_HEARTBEAT_ACTION = "system.jrbot_heartbeat"
SECRET_REF_RE = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")
RFC3339_UTC_Z_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$")
TRANSPORT_RETRY_ATTEMPTS = 2
MAX_REQUEST_BODY_BYTES = 64 * 1024
MAX_RESPONSE_BODY_BYTES = 64 * 1024
MAX_JOB_PAYLOAD_BYTES = 32 * 1024
MAX_RESULT_JSON_BYTES = 32 * 1024
MAX_JSON_MEMBERS = 256
MAX_JSON_DEPTH = 12
MAX_WIRE_STRING_BYTES = 512
MAX_JOB_ID_BYTES = 256
MAX_JOB_KEY_BYTES = 256
MAX_JOB_TYPE_BYTES = 32
MAX_RETRY_AFTER_SECONDS = 86400
MAX_ATTEMPTS = 1_000_000


class RunnerError(RuntimeError):
    pass


class ConfigError(RunnerError):
    pass


class ProviderNotImplemented(RunnerError):
    pass


class RuntimeTransportError(RunnerError):
    pass


class RuntimeProtocolError(RunnerError):
    pass


@dataclass(frozen=True)
class RuntimeConfig:
    instance: str
    management_mode: str
    database_mode: str
    base_dir: Path
    server_base: str
    auth_mode: str
    request_timeout_seconds: int = 15


@dataclass(frozen=True)
class ExecutionOutcome:
    outcome: str
    retryable: bool
    message: str
    result: Mapping[str, Any]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_rfc3339_utc(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_WIRE_STRING_BYTES:
        raise RuntimeProtocolError(f"{label} must be bounded RFC3339 UTC string")
    if RFC3339_UTC_Z_RE.fullmatch(value) is None:
        raise RuntimeProtocolError(f"{label} must use canonical RFC3339 UTC Z form")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise RuntimeProtocolError(f"{label} must be valid RFC3339 UTC") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise RuntimeProtocolError(f"{label} must be UTC")
    return parsed


def _require_uuid4(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) > 64:
        raise RuntimeProtocolError(f"{label} must be UUIDv4")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError) as exc:
        raise RuntimeProtocolError(f"{label} must be UUIDv4") from exc
    if parsed.version != 4 or str(parsed) != value.lower():
        raise RuntimeProtocolError(f"{label} must be canonical UUIDv4")
    return str(parsed)


def _require_bounded_string(value: Any, label: str, max_bytes: int) -> str:
    if not isinstance(value, str) or not value:
        raise RuntimeProtocolError(f"{label} must be non-empty string")
    if len(value.encode("utf-8")) > max_bytes:
        raise RuntimeProtocolError(f"{label} exceeds local bound")
    return value


def _require_int(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RuntimeProtocolError(f"{label} must be integer")
    if value < minimum or value > maximum:
        raise RuntimeProtocolError(f"{label} out of bounds")
    return value


def _json_size_and_shape(value: Any, label: str, max_bytes: int) -> int:
    members = 0

    def walk(node: Any, depth: int) -> None:
        nonlocal members
        if depth > MAX_JSON_DEPTH:
            raise RuntimeProtocolError(f"{label} exceeds JSON depth bound")
        if isinstance(node, Mapping):
            members += len(node)
            if members > MAX_JSON_MEMBERS:
                raise RuntimeProtocolError(f"{label} exceeds JSON member bound")
            for key, child in node.items():
                if not isinstance(key, str):
                    raise RuntimeProtocolError(f"{label} object keys must be strings")
                walk(child, depth + 1)
            return
        if isinstance(node, list):
            members += len(node)
            if members > MAX_JSON_MEMBERS:
                raise RuntimeProtocolError(f"{label} exceeds JSON member bound")
            for child in node:
                walk(child, depth + 1)
            return
        if node is None or isinstance(node, (str, bool, int)):
            return
        if isinstance(node, float):
            if node != node or node in (float("inf"), float("-inf")):
                raise RuntimeProtocolError(f"{label} contains non-finite number")
            return
        raise RuntimeProtocolError(f"{label} contains unsupported JSON value")

    walk(value, 1)
    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise RuntimeProtocolError(f"{label} is not canonical JSON") from exc
    if len(encoded) > max_bytes:
        raise RuntimeProtocolError(f"{label} exceeds byte bound")
    return len(encoded)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="JR-Bot productive generic runner")
    parser.add_argument("--config", required=True, help="Path to canonical config.ini")
    parser.add_argument("--prepare-local-db", action="store_true", help="Explicit local authority preparation; no runner activation")
    return parser.parse_args()


def _require_mode(value: str, allowed: set[str], label: str) -> str:
    normalized = value.strip().lower()
    if normalized not in allowed:
        raise ConfigError(f"invalid {label}: {value}")
    return normalized


def load_runtime_config(config_file: Path, runtime_base: Optional[Path] = None) -> RuntimeConfig:
    config_file = config_file.resolve()
    parser = configparser.ConfigParser()
    if not parser.read(config_file):
        raise ConfigError(f"config unreadable: {config_file}")
    if not parser.has_section("bot"):
        raise ConfigError("missing [bot] section")

    management_mode = _require_mode(
        parser.get("bot", "MANAGEMENT_MODE", fallback=""),
        {"standalone", "opscon_managed"},
        "MANAGEMENT_MODE",
    )
    database_mode = _require_mode(
        parser.get("bot", "DATABASE_MODE", fallback=""),
        {"local_pi", "external"},
        "DATABASE_MODE",
    )
    declared_instance = parser.get("bot", "INSTANCE_NAME", fallback="").strip().lower()

    if runtime_base is None:
        configured_base = parser.get("paths", "BASE_DIR", fallback="").strip()
        if not configured_base:
            raise ConfigError("missing paths.BASE_DIR")
        runtime_base = Path(configured_base)
    runtime_base = runtime_base.resolve()
    instance = runtime_base.name.lower()

    if not instance:
        raise ConfigError("cannot derive instance from runtime root")
    if declared_instance and declared_instance != instance:
        raise ConfigError("INSTANCE_NAME does not match runtime root identity")

    server_base = ""
    auth_mode = "none"
    if database_mode == "external":
        if not parser.has_section("server"):
            raise ConfigError("DATABASE_MODE=external requires [server]")
        server_base = parser.get("server", "SERVER_BASE", fallback="").strip().rstrip("/")
        if not server_base.startswith("https://") or any(c.isspace() for c in server_base):
            raise ConfigError("SERVER_BASE must be canonical HTTPS")
        auth_mode = _require_mode(
            parser.get("server", "AUTH_MODE", fallback=""),
            {"none", "server_token", "split_ping_token"},
            "AUTH_MODE",
        )
    elif parser.has_section("server"):
        raise ConfigError("DATABASE_MODE=local_pi forbids [server]")

    return RuntimeConfig(
        instance=instance,
        management_mode=management_mode,
        database_mode=database_mode,
        base_dir=runtime_base,
        server_base=server_base,
        auth_mode=auth_mode,
    )


class RunnerIdentity:
    def __init__(self, state_dir: Path):
        self.state_dir = state_dir
        self.path = state_dir / "runner_id"

    def load_or_create(self) -> str:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        if self.path.exists():
            value = self.path.read_text(encoding="utf-8").strip()
            try:
                parsed = uuid.UUID(value)
            except ValueError as exc:
                raise ConfigError("state/runner_id is not UUID") from exc
            if parsed.version != 4:
                raise ConfigError("state/runner_id must be UUIDv4")
            return str(parsed)

        value = str(uuid.uuid4())
        temp = self.path.with_name(f".runner_id.tmp.{os.getpid()}")
        try:
            with temp.open("x", encoding="utf-8") as handle:
                handle.write(value + "\n")
            os.chmod(temp, 0o640)
            os.replace(temp, self.path)
        finally:
            if temp.exists():
                temp.unlink()
        return value


class SecretStore:
    def __init__(self, secret_root: Path):
        self.secret_root = secret_root.resolve()

    def _read(self, filename: str) -> str:
        if not SECRET_REF_RE.fullmatch(filename):
            raise ConfigError("invalid secret reference")
        path = (self.secret_root / filename).resolve()
        try:
            path.relative_to(self.secret_root)
        except ValueError as exc:
            raise ConfigError("secret path outside canonical secret root") from exc
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise ConfigError(f"required runtime secret unavailable: {filename}") from exc
        if not value:
            raise ConfigError(f"required runtime secret empty: {filename}")
        return value

    def server_token(self) -> str:
        return self._read("server.token")

    def ping_token(self) -> str:
        return self._read("ping.token")

    def capability_secret(self, reference: str) -> str:
        return self._read(reference)


class RemoteHandlerProvider:
    def __init__(
        self,
        cfg: RuntimeConfig,
        runner_id: str,
        session_id: str,
        session: Optional[requests.Session] = None,
    ):
        if cfg.database_mode != "external":
            raise ConfigError("RemoteHandlerProvider requires DATABASE_MODE=external")
        self.cfg = cfg
        self.runner_id = runner_id
        self.session_id = session_id
        self.secrets = SecretStore(cfg.base_dir / "config" / "secrets")
        self.session = session or requests.Session()
        self.session.trust_env = False

    def _credential(self, role: str) -> Optional[str]:
        if self.cfg.auth_mode == "none":
            return None
        if role == "presence" and self.cfg.auth_mode == "split_ping_token":
            return self.secrets.ping_token()
        return self.secrets.server_token()

    @staticmethod
    def _read_bounded_response(response: Any) -> bytes:
        headers = getattr(response, "headers", {}) or {}
        content_length = None
        if isinstance(headers, Mapping):
            raw_length = headers.get("Content-Length")
            if raw_length is not None:
                try:
                    content_length = int(raw_length)
                except (TypeError, ValueError) as exc:
                    raise RuntimeProtocolError("invalid response Content-Length") from exc
                if content_length < 0 or content_length > MAX_RESPONSE_BODY_BYTES:
                    raise RuntimeProtocolError("runtime response exceeds byte bound")

        if hasattr(response, "iter_content"):
            chunks = []
            total = 0
            for chunk in response.iter_content(chunk_size=8192):
                if not chunk:
                    continue
                total += len(chunk)
                if total > MAX_RESPONSE_BODY_BYTES:
                    raise RuntimeProtocolError("runtime response exceeds byte bound")
                chunks.append(chunk)
            body = b"".join(chunks)
        else:
            body = bytes(getattr(response, "content", b"") or b"")
            if len(body) > MAX_RESPONSE_BODY_BYTES:
                raise RuntimeProtocolError("runtime response exceeds byte bound")

        if content_length is not None and content_length != len(body):
            raise RuntimeProtocolError("runtime response Content-Length mismatch")
        return body

    def _post(
        self,
        path: str,
        payload: Mapping[str, Any],
        role: str,
        transport_attempts: int = 1,
    ) -> Mapping[str, Any]:
        request_payload = dict(payload)
        _json_size_and_shape(request_payload, f"request {path}", MAX_REQUEST_BODY_BYTES)
        if transport_attempts < 1 or transport_attempts > TRANSPORT_RETRY_ATTEMPTS:
            raise RuntimeProtocolError("invalid transport retry bound")

        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        credential = self._credential(role)
        if credential is not None:
            headers["Authorization"] = f"Bearer {credential}"

        url = f"{self.cfg.server_base}/jrbot/v1{path}"
        last_transport_error: Optional[BaseException] = None
        response = None
        body = b""

        for attempt_index in range(transport_attempts):
            response = None
            try:
                response = self.session.post(
                    url,
                    json=request_payload,
                    headers=headers,
                    timeout=self.cfg.request_timeout_seconds,
                    allow_redirects=False,
                    stream=True,
                )
                body = self._read_bounded_response(response)
                last_transport_error = None
                break
            except requests.RequestException as exc:
                last_transport_error = exc
                if response is not None and hasattr(response, "close"):
                    try:
                        response.close()
                    except Exception:
                        pass
                response = None
                if attempt_index + 1 >= transport_attempts:
                    break

        if response is None:
            raise RuntimeTransportError(f"runtime transport failed for {path}") from last_transport_error

        data: Mapping[str, Any] = {}
        if body:
            try:
                decoded = json.loads(body.decode("utf-8"))
            except (UnicodeDecodeError, ValueError) as exc:
                raise RuntimeProtocolError(f"non-JSON response for {path}") from exc
            if not isinstance(decoded, Mapping):
                raise RuntimeProtocolError(f"invalid JSON response shape for {path}")
            _json_size_and_shape(decoded, f"response {path}", MAX_RESPONSE_BODY_BYTES)
            data = decoded

        if response.status_code == 426:
            raise RuntimeProtocolError("runtime protocol major version unsupported")
        if response.status_code < 200 or response.status_code >= 300:
            code = "HTTP_ERROR"
            error_obj = data.get("error") if isinstance(data, Mapping) else None
            if isinstance(error_obj, Mapping) and isinstance(error_obj.get("code"), str):
                code = error_obj["code"]
            raise RuntimeTransportError(f"{path} failed HTTP {response.status_code} {code}")

        if data.get("protocol") != RUNTIME_PROTOCOL:
            raise RuntimeProtocolError(f"protocol mismatch for {path}")
        if data.get("ok") is not True:
            raise RuntimeProtocolError(f"runtime response not ok for {path}")
        _parse_rfc3339_utc(data.get("server_time"), "server_time")
        return data

    def lease(self) -> Mapping[str, Any]:
        lease_request_id = str(uuid.uuid4())
        response = self._post(
            "/runtime/jobs/lease",
            {
                "protocol": RUNTIME_PROTOCOL,
                "lease_request_id": lease_request_id,
                "instance": self.cfg.instance,
                "runner_id": self.runner_id,
                "session_id": self.session_id,
            },
            "server",
            transport_attempts=TRANSPORT_RETRY_ATTEMPTS,
        )
        lease = response.get("lease")
        if lease is None:
            retry_after = response.get("retry_after_seconds")
            if retry_after is not None:
                _require_int(
                    retry_after,
                    "retry_after_seconds",
                    0,
                    MAX_RETRY_AFTER_SECONDS,
                )
            return response
        if not isinstance(lease, Mapping):
            raise RuntimeProtocolError("lease must be object or null")
        validate_lease(lease, response["server_time"])
        return response

    def renew(self, dispatch_id: str, run_id: str) -> Mapping[str, Any]:
        response = self._post(
            "/runtime/jobs/renew",
            {
                "protocol": RUNTIME_PROTOCOL,
                "instance": self.cfg.instance,
                "runner_id": self.runner_id,
                "session_id": self.session_id,
                "dispatch_id": dispatch_id,
                "run_id": run_id,
            },
            "server",
        )
        server_time = _parse_rfc3339_utc(response["server_time"], "server_time")
        expires = _parse_rfc3339_utc(response.get("lease_expires_at"), "lease_expires_at")
        if expires <= server_time:
            raise RuntimeProtocolError("renewed lease_expires_at must be after server_time")
        return response

    def report(
        self,
        lease: Mapping[str, Any],
        run_id: str,
        started_at: str,
        outcome: ExecutionOutcome,
    ) -> Mapping[str, Any]:
        result = dict(outcome.result)
        _json_size_and_shape(result, "result", MAX_RESULT_JSON_BYTES)
        report_payload = {
            "protocol": RUNTIME_PROTOCOL,
            "instance": self.cfg.instance,
            "runner_id": self.runner_id,
            "session_id": self.session_id,
            "job_id": lease["job_id"],
            "job_key": lease["job_key"],
            "job_revision": lease["job_revision"],
            "dispatch_id": lease["dispatch_id"],
            "run_id": run_id,
            "scheduled_for": lease["scheduled_for"],
            "attempt": lease["attempt"],
            "started_at": started_at,
            "finished_at": utc_now(),
            "outcome": outcome.outcome,
            "retryable": outcome.retryable,
            "message": _safe_message(outcome.message),
            "result": result,
        }
        response = self._post(
            "/runtime/jobs/report",
            report_payload,
            "server",
            transport_attempts=TRANSPORT_RETRY_ATTEMPTS,
        )
        result_state = response.get("result_state")
        if result_state is not None:
            _require_bounded_string(result_state, "result_state", 64)
        return response

    def write_self_presence(self) -> Mapping[str, Any]:
        response = self._post(
            "/runtime/presence",
            {
                "protocol": RUNTIME_PROTOCOL,
                "instance": self.cfg.instance,
                "runner_id": self.runner_id,
                "session_id": self.session_id,
                "runtime_version": RUNTIME_VERSION,
                "client_time": utc_now(),
            },
            "presence",
        )
        presence_state = response.get("presence_state")
        if presence_state is not None:
            _require_bounded_string(presence_state, "presence_state", 64)
        return response



def _safe_message(text: str) -> str:
    compact = " ".join(str(text).split())
    return compact.encode("utf-8")[:512].decode("utf-8", errors="ignore")


def _load_script_descriptor(cfg: RuntimeConfig, action: str):
    policy_dir = cfg.base_dir / "config" / "capabilities.d"
    trusted_root = str((cfg.base_dir / "scripts" / "capabilities").resolve())
    found = []
    if not policy_dir.is_dir():
        raise CapabilityPolicyError("policy directory missing")
    for path in sorted(policy_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        descriptor = validate_descriptor(raw, trusted_root)
        if descriptor.capability_id == action:
            found.append(descriptor)
    if len(found) != 1:
        raise CapabilityPolicyError("capability must resolve to exactly one local descriptor")
    return found[0]


def _execute_system(provider: Any, action: str) -> ExecutionOutcome:
    if action != SYSTEM_HEARTBEAT_ACTION:
        return ExecutionOutcome("rejected", False, "unknown system action", {})
    presence = provider.write_self_presence()
    return ExecutionOutcome(
        "succeeded",
        False,
        "self presence recorded",
        {"presence_state": presence.get("presence_state", "recorded")},
    )


def _execute_script(cfg: RuntimeConfig, payload: Mapping[str, Any]) -> ExecutionOutcome:
    action = payload.get("action")
    params = payload.get("params", {})
    if not isinstance(action, str) or not action:
        return ExecutionOutcome("rejected", False, "missing script capability action", {})
    if not isinstance(params, Mapping):
        return ExecutionOutcome("rejected", False, "script params must be an object", {})

    descriptor = None
    try:
        descriptor = _load_script_descriptor(cfg, action)
        executor = CapabilityExecutor(
            trusted_script_root=str((cfg.base_dir / "scripts" / "capabilities").resolve()),
            secret_resolver=SecretStore(cfg.base_dir / "config" / "secrets").capability_secret,
        )
        result = executor.execute(descriptor, params)
    except CapabilityPolicyError as exc:
        return ExecutionOutcome("rejected", False, _safe_message(exc), {})
    except Exception as exc:
        from jrbot_capabilities.executor import CapabilityExecutionError
        if isinstance(exc, CapabilityExecutionError):
            retryable = bool(descriptor and descriptor.retry_class in {"safe_once", "idempotent"})
            return ExecutionOutcome("failed", retryable, _safe_message(exc), {})
        raise

    succeeded = result.returncode == 0
    retryable = (not succeeded) and descriptor.retry_class in {"safe_once", "idempotent"}
    return ExecutionOutcome(
        "succeeded" if succeeded else "failed",
        retryable,
        f"script capability exit={result.returncode}",
        {
            "capability_id": descriptor.capability_id,
            "capability_revision": descriptor.revision,
            "exit_status": result.returncode,
            "stdout_truncated": result.stdout_truncated,
            "stderr_truncated": result.stderr_truncated,
        },
    )


def execute_lease(cfg: RuntimeConfig, provider: Any, lease: Mapping[str, Any]) -> ExecutionOutcome:
    job_type = lease.get("job_type")
    payload = lease.get("payload")
    if not isinstance(payload, Mapping):
        return ExecutionOutcome("rejected", False, "job payload must be an object", {})

    if job_type == "system":
        return _execute_system(provider, str(payload.get("action", "")))
    if job_type == "script":
        return _execute_script(cfg, payload)
    if job_type == "http":
        return ExecutionOutcome("rejected", False, "http capability not implemented in current public authority", {})
    return ExecutionOutcome("rejected", False, "unknown job_type", {})


def validate_lease(lease: Mapping[str, Any], server_time_value: Any) -> None:
    required = {
        "job_id",
        "job_key",
        "job_revision",
        "dispatch_id",
        "scheduled_for",
        "attempt",
        "max_attempts",
        "lease_expires_at",
        "job_type",
        "payload",
    }
    missing = sorted(required - set(lease))
    if missing:
        raise RuntimeProtocolError("lease missing required fields: " + ",".join(missing))

    _json_size_and_shape(lease, "lease", MAX_RESPONSE_BODY_BYTES)
    _require_bounded_string(lease["job_id"], "job_id", MAX_JOB_ID_BYTES)
    _require_bounded_string(lease["job_key"], "job_key", MAX_JOB_KEY_BYTES)
    _require_int(lease["job_revision"], "job_revision", 1, 2_147_483_647)
    _require_uuid4(lease["dispatch_id"], "dispatch_id")
    _require_bounded_string(lease["job_type"], "job_type", MAX_JOB_TYPE_BYTES)

    attempt = _require_int(lease["attempt"], "attempt", 1, MAX_ATTEMPTS)
    max_attempts = _require_int(lease["max_attempts"], "max_attempts", 1, MAX_ATTEMPTS)
    if attempt > max_attempts:
        raise RuntimeProtocolError("attempt cannot exceed max_attempts")

    server_time = _parse_rfc3339_utc(server_time_value, "server_time")
    _parse_rfc3339_utc(lease["scheduled_for"], "scheduled_for")
    lease_expires_at = _parse_rfc3339_utc(lease["lease_expires_at"], "lease_expires_at")
    if lease_expires_at <= server_time:
        raise RuntimeProtocolError("lease_expires_at must be after server_time")

    payload = lease["payload"]
    if not isinstance(payload, Mapping):
        raise RuntimeProtocolError("payload must be JSON object")
    _json_size_and_shape(payload, "job payload", MAX_JOB_PAYLOAD_BYTES)



def run_once(cfg: RuntimeConfig, session: Optional[requests.Session] = None) -> int:
    if cfg.database_mode == "local_pi":
        # Validate canonical local storage before RunnerIdentity can write state.
        LocalDbProvider(cfg, str(uuid.uuid4()), str(uuid.uuid4()))
    runner_id = RunnerIdentity(cfg.base_dir / "state").load_or_create()
    session_id = str(uuid.uuid4())
    provider = (LocalDbProvider(cfg, runner_id, session_id) if cfg.database_mode == "local_pi"
                else RemoteHandlerProvider(cfg, runner_id, session_id, session=session))

    lease_response = provider.lease()
    lease = lease_response.get("lease")
    if lease is None:
        return 0
    if not isinstance(lease, Mapping):
        raise RuntimeProtocolError("lease must be object or null")

    run_id = str(uuid.uuid4())
    started_at = utc_now()

    # Bind run_id to the active dispatch and obtain a fresh server-authoritative
    # lease expiry before executing the capability.
    provider.renew(str(lease["dispatch_id"]), run_id)

    try:
        outcome = execute_lease(cfg, provider, lease)
    except Exception as exc:
        outcome = ExecutionOutcome("failed", False, _safe_message(exc), {})

    provider.report(lease, run_id, started_at, outcome)
    return 0 if outcome.outcome == "succeeded" else 2


def main() -> int:
    args = parse_args()
    config_path = Path(args.config)
    runtime_base = Path(__file__).resolve().parents[1]
    cfg = load_runtime_config(config_path, runtime_base=runtime_base)
    if args.prepare_local_db:
        LocalDbProvider.prepare(cfg)
        return 0
    return run_once(cfg)


# WP-PRV-01: the local provider is part of the existing trusted runner payload.
PROVIDER_STATE_LIMIT = 4 * 1024 * 1024


class ProviderStateError(RunnerError):
    pass


def _provider_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _provider_time(value):
    return _parse_rfc3339_utc(value, "provider timestamp")


def _provider_stamp(value):
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _cron_fields(expression):
    fields = expression.split()
    if len(fields) != 5:
        raise ProviderStateError("CRON_INVALID")
    values = []
    for field, low, high in zip(fields, (0, 0, 1, 1, 0), (59, 23, 31, 12, 7)):
        selected = set()
        for item in field.split(","):
            match = re.fullmatch(r"(\*|\d+(?:-\d+)?)(?:/(\d+))?", item)
            if match is None:
                raise ProviderStateError("CRON_INVALID")
            term, step_text = match.groups()
            step = int(step_text or 1)
            if step < 1 or step > high - low + 1:
                raise ProviderStateError("CRON_INVALID")
            if term == "*":
                start, end = low, high
            elif "-" in term:
                start, end = map(int, term.split("-"))
            else:
                start = int(term)
                end = high if step_text else start
            if not low <= start <= end <= high:
                raise ProviderStateError("CRON_INVALID")
            selected.update(range(start, end + 1, step))
        values.append(selected)
    values[4] = {v % 7 for v in values[4]}
    return fields, values


def provider_cron_next(expression, zone_name, after, *, previous=False):
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
    fields, values = _cron_fields(expression)
    try:
        zone = ZoneInfo(zone_name)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ProviderStateError("CRON_TIMEZONE_INVALID") from exc
    # Generate local wall times, then round-trip both folds. This excludes gaps
    # and preserves both UTC occurrences in an autumn fold.
    day = after.astimezone(zone).date()
    for offset in range(366 * 8):
        date = day + timedelta(days=-offset if previous else offset)
        if date.month not in values[3]:
            continue
        dom, dow = date.day in values[2], (date.weekday() + 1) % 7 in values[4]
        if fields[2] == "*":
            day_ok = dow
        elif fields[4] == "*":
            day_ok = dom
        else:
            day_ok = dom or dow
        if not day_ok:
            continue
        candidates = set()
        for hour in sorted(values[1]):
            for minute in sorted(values[0]):
                wall = datetime(date.year, date.month, date.day, hour, minute)
                for fold in (0, 1):
                    utc = wall.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
                    if (utc <= after if previous else utc > after) and utc.astimezone(zone).replace(tzinfo=None) == wall:
                        candidates.add(utc)
        if candidates:
            return max(candidates) if previous else min(candidates)
    raise ProviderStateError("CRON_NO_OCCURRENCE_IN_BOUND")


def _provider_next(schedule, after):
    if schedule["kind"] == "once":
        return None
    if schedule["kind"] == "interval":
        return after + timedelta(seconds=schedule["seconds"])
    return provider_cron_next(schedule["expression"], schedule["timezone"], after)


def _provider_job(job):
    required = {"job_id", "job_key", "job_revision", "job_type", "payload", "schedule", "start_at", "max_attempts", "retry_delay_seconds", "lease_seconds", "catch_up", "enabled"}
    if not isinstance(job, Mapping) or set(job) != required:
        raise ProviderStateError("JOB_INVALID")
    _require_bounded_string(job["job_id"], "job_id", MAX_JOB_ID_BYTES)
    _require_bounded_string(job["job_key"], "job_key", MAX_JOB_KEY_BYTES)
    _require_int(job["job_revision"], "job_revision", 1, MAX_ATTEMPTS)
    if job["job_type"] not in {"system", "script", "http"} or not isinstance(job["payload"], Mapping):
        raise ProviderStateError("JOB_INVALID")
    _json_size_and_shape(job["payload"], "payload", MAX_JOB_PAYLOAD_BYTES)
    if type(job["enabled"]) is not bool:
        raise ProviderStateError("JOB_INVALID")
    _provider_time(job["start_at"])
    for field, minimum, maximum in (("max_attempts", 1, MAX_ATTEMPTS), ("retry_delay_seconds", 0, 86400), ("lease_seconds", 1, 86400)):
        _require_int(job[field], field, minimum, maximum)
    if job["catch_up"] not in {"coalesce_latest", "skip_missed"}:
        raise ProviderStateError("JOB_INVALID")
    schedule = job["schedule"]
    if not isinstance(schedule, Mapping):
        raise ProviderStateError("JOB_INVALID")
    if schedule.get("kind") == "once" and set(schedule) == {"kind"}:
        pass
    elif schedule.get("kind") == "interval" and set(schedule) == {"kind", "seconds"}:
        _require_int(schedule["seconds"], "seconds", 1, 31536000)
    elif schedule.get("kind") == "cron" and set(schedule) == {"kind", "expression", "timezone"}:
        _require_bounded_string(schedule["expression"], "expression", 100)
        _require_bounded_string(schedule["timezone"], "timezone", 128)
        provider_cron_next(schedule["expression"], schedule["timezone"], _provider_time(job["start_at"]))
    else:
        raise ProviderStateError("JOB_INVALID")
    return json.loads(_provider_json(job))


def _provider_transition(state, operation, data, instance, runner, session, now):
    def response(**extra):
        return {"protocol": RUNTIME_PROTOCOL, "ok": True, "server_time": _provider_stamp(now), **extra}

    def finish(record, outcome, retryable):
        slot = state["jobs"][record["lease"]["job_id"]]
        occurrence = slot["occurrence"]
        definition = occurrence["definition"]
        if outcome == "failed" and retryable and occurrence["attempt"] < definition["max_attempts"]:
            occurrence["retry_at"] = _provider_stamp(now + timedelta(seconds=definition["retry_delay_seconds"]))
        else:
            slot["occurrence"] = None

    for record in state["dispatches"].values():
        if record["status"] == "active" and _provider_time(record["lease"]["lease_expires_at"]) <= now:
            record["status"] = "expired"
            finish(record, "failed", True)

    if operation == "put_job":
        job = _provider_job(data)
        existing = state["jobs"].get(job["job_id"])
        if existing and job["job_revision"] <= existing["definition"]["job_revision"]:
            raise ProviderStateError("JOB_REVISION_CONFLICT")
        if any(k != job["job_id"] and v["definition"]["job_key"] == job["job_key"] for k, v in state["jobs"].items()):
            raise ProviderStateError("JOB_KEY_CONFLICT")
        first = _provider_time(job["start_at"])
        if job["schedule"]["kind"] == "cron":
            first = _provider_next(job["schedule"], first - timedelta(seconds=1))
        if existing and existing["occurrence"] is not None:
            existing["definition"] = job
            existing["next_for"] = _provider_stamp(first)
        else:
            state["jobs"][job["job_id"]] = {"definition": job, "next_for": _provider_stamp(first), "occurrence": None}
        return response(job_state="recorded")

    if operation == "lease":
        request = _require_uuid4(data["lease_request_id"], "lease_request_id")
        request_key = runner + "/" + session + "/" + request
        if request_key in state["requests"]:
            dispatch = state["requests"][request_key]
            if dispatch is None:
                return response(lease=None, retry_after_seconds=60)
            record = state["dispatches"][dispatch]
            if record["status"] != "active":
                raise ProviderStateError("DISPATCH_STALE")
            return response(lease=record["lease"])
        for job_id in sorted(state["jobs"]):
            slot = state["jobs"][job_id]
            if any(r["status"] == "active" and r["lease"]["job_id"] == job_id for r in state["dispatches"].values()):
                continue
            occurrence = slot["occurrence"]
            definition = slot["definition"]
            if not definition["enabled"]:
                continue
            if occurrence is None:
                due = _provider_time(slot["next_for"]) if slot["next_for"] else None
                if due is None or due > now:
                    continue
                schedule = definition["schedule"]
                if schedule["kind"] != "once":
                    if schedule["kind"] == "interval":
                        latest = due + timedelta(seconds=int((now - due).total_seconds() // schedule["seconds"]) * schedule["seconds"])
                        following = latest + timedelta(seconds=schedule["seconds"])
                    else:
                        latest = provider_cron_next(schedule["expression"], schedule["timezone"], now, previous=True)
                        following = _provider_next(schedule, latest)
                    if definition["catch_up"] == "skip_missed" and due < now:
                        slot["next_for"] = _provider_stamp(following)
                        continue
                    due = latest
                else:
                    following = None
                occurrence = {"scheduled_for": _provider_stamp(due), "attempt": 0, "retry_at": _provider_stamp(due), "definition": json.loads(_provider_json(definition))}
                slot["occurrence"] = occurrence
                slot["next_for"] = _provider_stamp(following) if following else None
            if _provider_time(occurrence["retry_at"]) > now:
                continue
            definition = occurrence["definition"]
            occurrence["attempt"] += 1
            dispatch = str(uuid.uuid4())
            lease = {k: definition[k] for k in ("job_id", "job_key", "job_revision", "job_type", "payload", "max_attempts")}
            lease.update(dispatch_id=dispatch, scheduled_for=occurrence["scheduled_for"], attempt=occurrence["attempt"], lease_expires_at=_provider_stamp(now + timedelta(seconds=definition["lease_seconds"])))
            state["dispatches"][dispatch] = {"lease": lease, "runner": runner, "session": session, "run": None, "status": "active", "lease_seconds": definition["lease_seconds"], "report": None}
            state["requests"][request_key] = dispatch
            return response(lease=lease)
        state["requests"][request_key] = None
        return response(lease=None, retry_after_seconds=60)

    if operation not in {"renew", "report"}:
        raise ProviderStateError("OPERATION_INVALID")
    dispatch = _require_uuid4(data["dispatch_id"], "dispatch_id")
    run = _require_uuid4(data["run_id"], "run_id")
    record = state["dispatches"].get(dispatch)
    if record is None:
        raise ProviderStateError("DISPATCH_STALE")
    if record["runner"] != runner or record["session"] != session or record["run"] not in (None, run):
        raise ProviderStateError("DISPATCH_BINDING_MISMATCH")
    if operation == "report":
        required = {"protocol", "instance", "runner_id", "session_id", "job_id", "job_key", "job_revision", "dispatch_id", "run_id", "scheduled_for", "attempt", "started_at", "finished_at", "outcome", "retryable", "message", "result"}
        if set(data) != required or data["protocol"] != RUNTIME_PROTOCOL or data["instance"] != instance or data["runner_id"] != runner or data["session_id"] != session:
            raise ProviderStateError("REPORT_INVALID")
        for field in ("job_id", "job_key", "job_revision", "scheduled_for", "attempt"):
            if type(data[field]) is not type(record["lease"][field]) or data[field] != record["lease"][field]:
                raise ProviderStateError("DISPATCH_BINDING_MISMATCH")
        if data["outcome"] not in {"succeeded", "failed", "rejected"} or type(data["retryable"]) is not bool or not isinstance(data["result"], Mapping):
            raise ProviderStateError("REPORT_INVALID")
        if not isinstance(data["message"], str) or len(data["message"].encode()) > 512:
            raise ProviderStateError("REPORT_INVALID")
        if _provider_time(data["finished_at"]) < _provider_time(data["started_at"]):
            raise ProviderStateError("REPORT_INVALID")
        _json_size_and_shape(data["result"], "result", MAX_RESULT_JSON_BYTES)
        canonical = _provider_json(data)
        if record["report"] is not None:
            if record["report"] != canonical:
                raise ProviderStateError("REPORT_CONFLICT")
            return response(result_state="already_recorded")
    if record["status"] != "active":
        raise ProviderStateError("DISPATCH_STALE")
    record["run"] = run
    if operation == "renew":
        record["lease"]["lease_expires_at"] = _provider_stamp(now + timedelta(seconds=record["lease_seconds"]))
        return response(lease_expires_at=record["lease"]["lease_expires_at"])
    record["report"] = canonical
    record["status"] = "completed"
    finish(record, data["outcome"], data["retryable"])
    return response(result_state="recorded")


class LocalDbProvider:
    """One transaction-locked SQLite authority; never a remote fallback."""

    def __init__(self, cfg, runner_id, session_id, *, clock=None):
        if cfg.database_mode != "local_pi":
            raise ConfigError("LocalDbProvider requires DATABASE_MODE=local_pi")
        if re.fullmatch(r"[a-z](?:[a-z0-9_-]{0,30}[a-z0-9])?", cfg.instance) is None:
            raise ConfigError("INSTANCE_INVALID")
        self.cfg = cfg
        self.runner_id = _require_uuid4(runner_id, "runner_id")
        self.session_id = _require_uuid4(session_id, "session_id")
        self.clock = clock  # trusted test/embedding hook, never read from config or wire
        self.path = cfg.base_dir / "state" / "local_db" / "runtime.sqlite3"
        self._check_path()
        if self.path.is_file():
            info = self.path.stat()
            if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                raise ConfigError("local DB ownership/permissions unsafe")
        if not self.path.is_file():
            raise ConfigError("local DB missing; explicit --prepare-local-db required")

    def _check_path(self):
        for path in (self.cfg.base_dir, self.cfg.base_dir / "state", self.path.parent, self.path):
            if path.is_symlink():
                raise ConfigError("local DB path must not contain symlinks")

    @classmethod
    def prepare(cls, cfg):
        import sqlite3
        if cfg.database_mode != "local_pi":
            raise ConfigError("preparation requires DATABASE_MODE=local_pi")
        if re.fullmatch(r"[a-z](?:[a-z0-9_-]{0,30}[a-z0-9])?", cfg.instance) is None:
            raise ConfigError("INSTANCE_INVALID")
        path = cfg.base_dir / "state" / "local_db" / "runtime.sqlite3"
        for item in (cfg.base_dir, cfg.base_dir / "state", path.parent, path):
            if item.is_symlink():
                raise ConfigError("local DB path must not contain symlinks")
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if path.exists():
            provider = cls(cfg, str(uuid.uuid4()), str(uuid.uuid4()))
            provider._operation("inspect", {})
            return  # never reseed or replace an existing authority
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
        os.close(fd)
        db = sqlite3.connect(path)
        try:
            db.execute("BEGIN IMMEDIATE")
            db.execute("CREATE TABLE jrbot_provider_state (instance TEXT PRIMARY KEY, document TEXT NOT NULL)")
            db.execute("CREATE TABLE jrbot_provider_dispatches (instance TEXT NOT NULL, dispatch_id TEXT NOT NULL, status TEXT NOT NULL, document TEXT NOT NULL, PRIMARY KEY(instance,dispatch_id))")
            db.execute("CREATE INDEX jrbot_active_dispatches ON jrbot_provider_dispatches(instance,status)")
            db.execute("CREATE TABLE jrbot_provider_requests (instance TEXT NOT NULL, request_key TEXT NOT NULL, dispatch_id TEXT, PRIMARY KEY(instance,request_key))")
            db.execute("CREATE TABLE tbl_bot_status (bot_name TEXT PRIMARY KEY, last_seen TEXT NOT NULL, last_status TEXT NOT NULL DEFAULT 'yellow', last_alert_at TEXT)")
            state = {"version": 1, "instance": cfg.instance, "jobs": {}, "dispatches": {}, "requests": {}}
            db.execute("INSERT INTO jrbot_provider_state VALUES (?,?)", (cfg.instance, _provider_json(state)))
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def _operation(self, operation, data):
        import sqlite3
        self._check_path()
        db = sqlite3.connect(self.path.as_uri() + "?mode=rw", uri=True, timeout=5)
        try:
            db.execute("BEGIN IMMEDIATE")
            expected_keys = {"jrbot_provider_state": ["instance"], "jrbot_provider_dispatches": ["instance", "dispatch_id"], "jrbot_provider_requests": ["instance", "request_key"], "tbl_bot_status": ["bot_name"]}
            for table, expected in expected_keys.items():
                columns = db.execute("PRAGMA table_info(" + table + ")").fetchall()
                actual = [r[1] for r in sorted(columns, key=lambda r: r[5]) if r[5]]
                if actual != expected:
                    raise ProviderStateError("PROVIDER_SCHEMA_INVALID")
            row = db.execute("SELECT document FROM jrbot_provider_state WHERE instance=?", (self.cfg.instance,)).fetchone()
            if row is None or len(row[0].encode()) > PROVIDER_STATE_LIMIT:
                raise ProviderStateError("PROVIDER_STATE_INVALID")
            state = json.loads(row[0])
            if type(state.get("version")) is not int or state.get("version") != 1 or state.get("instance") != self.cfg.instance or any(not isinstance(state.get(k), dict) for k in ("jobs", "dispatches", "requests")):
                raise ProviderStateError("PROVIDER_STATE_INVALID")
            # History is durable in per-identity rows, not an ever-growing document.
            state["dispatches"] = {r[0]: json.loads(r[1]) for r in db.execute("SELECT dispatch_id,document FROM jrbot_provider_dispatches WHERE instance=? AND status='active'", (self.cfg.instance,))}
            state["requests"] = {}
            if operation == "lease":
                request = _require_uuid4(data["lease_request_id"], "lease_request_id")
                key = self.runner_id + "/" + self.session_id + "/" + request
                found = db.execute("SELECT dispatch_id FROM jrbot_provider_requests WHERE instance=? AND request_key=?", (self.cfg.instance, key)).fetchone()
                if found is not None:
                    state["requests"][key] = found[0]
                    requested_dispatch = found[0]
                else:
                    requested_dispatch = None
            elif operation in {"report", "renew"}:
                requested_dispatch = _require_uuid4(data["dispatch_id"], "dispatch_id")
            else:
                requested_dispatch = None
            if requested_dispatch and requested_dispatch not in state["dispatches"]:
                found = db.execute("SELECT document FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?", (self.cfg.instance, requested_dispatch)).fetchone()
                if found is not None:
                    state["dispatches"][requested_dispatch] = json.loads(found[0])
            now = self.clock() if self.clock else _provider_time(db.execute("SELECT strftime('%Y-%m-%dT%H:%M:%SZ','now')").fetchone()[0])
            if operation == "inspect":
                result = state
            elif operation == "presence":
                if data:
                    raise ProviderStateError("PRESENCE_SCOPE_INVALID")
                db.execute("INSERT INTO tbl_bot_status(bot_name,last_seen) VALUES (?,?) ON CONFLICT(bot_name) DO UPDATE SET last_seen=excluded.last_seen", (self.cfg.instance, _provider_stamp(now)))
                result = {"protocol": RUNTIME_PROTOCOL, "ok": True, "server_time": _provider_stamp(now), "presence_state": "recorded"}
            else:
                result = _provider_transition(state, operation, data, self.cfg.instance, self.runner_id, self.session_id, now)
            for identity, record in state["dispatches"].items():
                db.execute("INSERT INTO jrbot_provider_dispatches VALUES (?,?,?,?) ON CONFLICT(instance,dispatch_id) DO UPDATE SET status=excluded.status,document=excluded.document", (self.cfg.instance, identity, record["status"], _provider_json(record)))
            for key, identity in state["requests"].items():
                db.execute("INSERT INTO jrbot_provider_requests VALUES (?,?,?) ON CONFLICT(instance,request_key) DO NOTHING", (self.cfg.instance, key, identity))
            stored = {**state, "dispatches": {}, "requests": {}}
            document = _provider_json(stored)
            if len(document.encode()) > PROVIDER_STATE_LIMIT:
                raise ProviderStateError("PROVIDER_STATE_CAPACITY_EXCEEDED")
            db.execute("UPDATE jrbot_provider_state SET document=? WHERE instance=?", (document, self.cfg.instance))
            db.commit()
            return result
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def put_job(self, job):
        return self._operation("put_job", job)

    def lease(self, lease_request_id=None):
        return self._operation("lease", {"lease_request_id": lease_request_id or str(uuid.uuid4())})

    def renew(self, dispatch_id, run_id):
        return self._operation("renew", {"dispatch_id": dispatch_id, "run_id": run_id})

    def report(self, lease, run_id, started_at, outcome):
        data = {k: lease[k] for k in ("job_id", "job_key", "job_revision", "dispatch_id", "scheduled_for", "attempt")}
        data.update(protocol=RUNTIME_PROTOCOL, instance=self.cfg.instance, runner_id=self.runner_id, session_id=self.session_id, run_id=run_id, started_at=started_at, finished_at=utc_now(), outcome=outcome.outcome, retryable=outcome.retryable, message=_safe_message(outcome.message), result=dict(outcome.result))
        return self._operation("report", data)

    def write_self_presence(self):
        return self._operation("presence", {})


if __name__ == "__main__":
    raise SystemExit(main())
