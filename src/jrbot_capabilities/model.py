from dataclasses import dataclass, field
from typing import Any, Dict, Mapping, Tuple

@dataclass(frozen=True)
class CapabilityDescriptor:
    capability_id: str
    revision: int
    script_path: str
    sha256: str
    interpreter: str
    argv: Tuple[Mapping[str, Any], ...] = field(default_factory=tuple)
    timeout_seconds: int = 30
    max_stdout_bytes: int = 65536
    max_stderr_bytes: int = 65536
    secret_bindings: Mapping[str, str] = field(default_factory=dict)
    retry_class: str = "never"

    @classmethod
    def from_mapping(cls, raw: Mapping[str, Any]) -> "CapabilityDescriptor":
        return cls(
            capability_id=raw["capability_id"], revision=raw["revision"],
            script_path=raw["script_path"], sha256=raw["sha256"],
            interpreter=raw["interpreter"], argv=tuple(raw.get("argv", ())),
            timeout_seconds=raw.get("timeout_seconds", 30),
            max_stdout_bytes=raw.get("max_stdout_bytes", 65536),
            max_stderr_bytes=raw.get("max_stderr_bytes", 65536),
            secret_bindings=dict(raw.get("secret_bindings", {})),
            retry_class=raw.get("retry_class", "never"),
        )