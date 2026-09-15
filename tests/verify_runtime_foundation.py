#!/usr/bin/env python3
"""Verify the WP-FND-01 Public Runtime Foundation contract."""

from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install_jr-bot.sh"
AUDITS = [
    ROOT / "audits" / "audit_jr-bot-boot-report.sh",
    ROOT / "audits" / "audit_jr-bot-network-health.sh",
    ROOT / "audits" / "audit_jr-bot-structure.sh",
]

MANDATORY_DIR_MARKERS = [
    '"$install_dir/config"',
    '"$install_dir/src"',
    '"$install_dir/scripts"',
    '"$install_dir/audits"',
    '"$install_dir/docs/scripts"',
    '"$install_dir/docs/audits"',
    '"$install_dir/reports/audits"',
    '"$install_dir/logs"',
    '"$install_dir/state"',
    '"$install_dir/tmp"',
    '"$install_dir/venv"',
]

PRIVILEGED_DIRS = [
    "config",
    "src",
    "scripts",
    "audits",
    "docs",
    "docs/scripts",
    "docs/audits",
    "venv",
]

WRITABLE_DIRS = [
    "reports",
    "reports/audits",
    "logs",
    "state",
    "tmp",
]

FORBIDDEN_PROJECT_TOKENS = ("ggb", "trx", "dmr")


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require_all(text: str, markers: list[str], context: str) -> None:
    for marker in markers:
        if marker not in text:
            fail(f"{context}: missing marker {marker!r}")


def main() -> int:
    installer = read(INSTALLER)

    require_all(installer, MANDATORY_DIR_MARKERS, "installer mandatory tree")

    if 'sudo chown -R "${run_as_user}:${run_as_user}" "$install_dir"' in installer:
        fail("installer still recursively assigns the install root to runtime user")

    require_all(
        installer,
        [
            'sudo chown "root:${run_as_user}" "$install_dir"',
            'sudo chmod 0750 "$install_dir"',
            'sudo chown "root:${run_as_user}" "$install_dir/config/config.ini"',
            'sudo chmod 0640 "$install_dir/config/config.ini"',
            'sudo chown "root:${run_as_user}" "$install_dir/src/job_runner.py"',
            'sudo chmod 0640 "$install_dir/src/job_runner.py"',
            'sudo chown "root:${group}" "$target_path"',
            'normalize_venv_permissions "$install_dir" "$run_as_user"',
            'assert_foundation_path_safety "$install_dir"',
        ],
        "installer ownership contract",
    )

    privileged_block = re.search(
        r"local\s+-a\s+privileged_dirs=\((?P<body>.*?)\n\s*\)",
        installer,
        re.DOTALL,
    )
    if not privileged_block:
        fail("installer privileged_dirs declaration missing")

    writable_block = re.search(
        r"local\s+-a\s+writable_dirs=\((?P<body>.*?)\n\s*\)",
        installer,
        re.DOTALL,
    )
    if not writable_block:
        fail("installer writable_dirs declaration missing")

    for name in PRIVILEGED_DIRS:
        if name not in privileged_block.group("body"):
            fail(f"privileged directory class missing: {name}")

    for name in WRITABLE_DIRS:
        if name not in writable_block.group("body"):
            fail(f"writable directory class missing: {name}")

    for marker in [
        'download_public_file "scripts/${name}" "$install_dir/scripts/${name}" 750 "$run_as_user"',
        'download_public_file "audits/${name}" "$install_dir/audits/${name}" 750 "$run_as_user"',
        'download_public_file "docs/scripts/${name}" "$install_dir/docs/scripts/${name}" 640 "$run_as_user"',
        'download_public_file "docs/audits/${name}" "$install_dir/docs/audits/${name}" 640 "$run_as_user"',
    ]:
        if marker not in installer:
            fail(f"installer canonical payload mode missing: {marker}")

    if '"$install_dir/data"' in installer:
        fail("public Target must not create transitional data directory")
    if '"$install_dir/reports/pending"' in installer:
        fail("public Target must not create transitional reports/pending directory")

    lowered = installer.lower()
    for token in FORBIDDEN_PROJECT_TOKENS:
        if re.search(rf"\b{re.escape(token)}\b", lowered):
            fail(f"project-specific token found in generic installer: {token}")

    for path in AUDITS:
        text = read(path)
        if 'chmod 700 "$AUDIT_DIR"' in text:
            fail(f"{path.name} still downgrades reports/audits to 0700")
        if 'chmod 750 "$AUDIT_DIR"' not in text:
            fail(f"{path.name} does not preserve reports/audits at 0750")

    print("PASS: mandatory Target tree markers are present")
    print("PASS: privileged and runtime-writable ownership classes are explicit")
    print("PASS: blanket runtime-user install-root ownership is absent")
    print("PASS: canonical Public payload modes are 0750/0640")
    print("PASS: Public audit producers preserve reports/audits at 0750")
    print("PASS: no known transitional Target paths or project-specific instance logic")
    return 0


if __name__ == "__main__":
    sys.exit(main())
