#!/usr/bin/env python3
# Verify the WP-FND-03 Public generic systemd deployment contract.

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "systemd" / "bot-runner@.service"
TIMER = ROOT / "systemd" / "bot-runner@.timer"
INSTALLER = ROOT / "install_jr-bot.sh"
DOC = ROOT / "docs" / "runtime-systemd.md"
README = ROOT / "README.md"

EXPECTED_SERVICE_SHA256 = "d6449e731e23fb3480926adc47c70ad61d9796ce4c008d959cf856946335ef34"
EXPECTED_TIMER_SHA256 = "0f790bbeffbd6d09033bf988bdc34552a36653263b34f8588a5d1205275942ce"

SERVICE_MARKERS = (
    "Type=oneshot",
    "User=%i",
    "Group=%i",
    "WorkingDirectory=/opt/bots/%i",
    "ExecStart=/opt/bots/%i/venv/bin/python /opt/bots/%i/src/job_runner.py --config /opt/bots/%i/config/config.ini",
)
TIMER_MARKERS = (
    "OnBootSec=90s",
    "OnUnitActiveSec=60s",
    "AccuracySec=15s",
    "Persistent=true",
    "Unit=bot-runner@%i.service",
)

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def canonical_bytes(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n")

def sha(path: Path) -> str:
    return hashlib.sha256(canonical_bytes(path)).hexdigest()

def read(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")

def main() -> int:
    service = read(SERVICE)
    timer = read(TIMER)
    installer = read(INSTALLER)
    doc = read(DOC)
    readme = read(README)

    if sha(SERVICE) != EXPECTED_SERVICE_SHA256:
        fail("canonical bot-runner@.service bytes changed")
    if sha(TIMER) != EXPECTED_TIMER_SHA256:
        fail("canonical bot-runner@.timer baseline bytes changed")

    for marker in SERVICE_MARKERS:
        if marker not in service:
            fail(f"service contract marker missing: {marker}")
    for marker in TIMER_MARKERS:
        if marker not in timer:
            fail(f"timer baseline marker missing: {marker}")

    if re.search(r"systemctl\s+enable(?:\s+--now)?\s+[\"']?bot-runner@", installer):
        fail("Public installer enables the generic runner")
    if re.search(r"systemctl\s+(?:start|restart)\s+[\"']?bot-runner@", installer):
        fail("Public installer starts/restarts the generic runner")
    if 'sudo systemctl daemon-reload' not in installer:
        fail("Public installer no longer reloads systemd after template install")
    if 'install_systemd_templates' not in installer or 'apply_systemd_install_state' not in installer:
        fail("Public installer WP-FND-03 install functions missing")

    if 'sudo systemctl enable "jrbot-boot-report-audit@${instance_name}.service"' not in installer:
        fail("pre-existing boot-audit enablement changed unexpectedly")

    for unit_name, unit in (("service", service), ("timer", timer)):
        if re.search(r"^\s*Environment(File)?\s*=", unit, re.I | re.M):
            fail(f"{unit_name}: systemd environment transport present")
        if "SERVER_TOKEN" in unit or "PING_TOKEN" in unit:
            fail(f"{unit_name}: runtime token marker present")
        lowered = unit.lower()
        for token in ("ggb", "trx", "dmr"):
            if re.search(rf"\b{re.escape(token)}\b", lowered):
                fail(f"{unit_name}: project-specific token found: {token}")

    for marker in ("install templates","!= enable runner","timer cadence","Persistent=","It must not enable or","start the generic runner timer"):
        if marker not in doc:
            fail(f"runtime-systemd.md marker missing: {marker}")

    if "WP-FND-03 does not enable or start the generic runner timer" not in readme:
        fail("README activation boundary missing")

    print("PASS: Public runner service bytes and frozen service core")
    print("PASS: Public timer relationship and preserved baseline bytes")
    print("PASS: installer no longer enables/starts generic runner")
    print("PASS: no systemd secret environment transport or project-specific runner unit")
    print("PASS: WP-FND-03 documentation boundary")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
