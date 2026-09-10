#!/usr/bin/env python3
"""Verify the public-v1 local audit contract."""

from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]

AUDITS = [
    ROOT / "audits" / "audit_jr-bot-boot-report.sh",
    ROOT / "audits" / "audit_jr-bot-network-health.sh",
    ROOT / "audits" / "audit_jr-bot-structure.sh",
]

INSTALLER = ROOT / "install_jr-bot.sh"
LOCAL_STORAGE_CONTRACT = (
    ROOT / "docs" / "audits" / "audit-local-storage-contract.md"
)
BOOT_SERVICE = ROOT / "systemd" / "jrbot-boot-report-audit@.service"

LOCAL_REPORT_MARKER = "reports/audits"
TARGET_PATH_MARKER = "/opt/bots/"
INSTANCE_PATTERN = re.compile(
    r"\^\[a-z\]\(\[a-z0-9_-\]\{0,30\}\[a-z0-9\]\)\?\$"
)


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def require_file(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    installer_text = require_file(INSTALLER)
    contract_text = require_file(LOCAL_STORAGE_CONTRACT)
    boot_service_text = require_file(BOOT_SERVICE)

    if LOCAL_REPORT_MARKER not in installer_text:
        fail("installer does not create the canonical local audit directory")

    if TARGET_PATH_MARKER not in installer_text:
        fail("installer does not use the canonical target runtime root")

    if LOCAL_REPORT_MARKER not in contract_text:
        fail("local audit storage contract does not name the audit directory")

    if LOCAL_REPORT_MARKER not in boot_service_text:
        # The service may not spell out the report path, but it must invoke
        # the local audit script from the target runtime.
        if "/opt/bots/%i/audits/audit_jr-bot-boot-report.sh" not in boot_service_text:
            fail("boot audit service does not invoke the target-runtime audit")

    for path in AUDITS:
        text = require_file(path)

        if LOCAL_REPORT_MARKER not in text:
            fail(
                "canonical local audit directory missing from "
                f"{path.relative_to(ROOT)}"
            )

        if not INSTANCE_PATTERN.search(text):
            fail(
                "canonical 1-32 character instance grammar missing from "
                f"{path.relative_to(ROOT)}"
            )

    print("PASS: public-v1 audit reports use the canonical local directory")
    print("PASS: canonical instance grammar is present in all audit clients")
    print("PASS: target runtime and boot-audit integration are present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
