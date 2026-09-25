#!/usr/bin/env python3
"Verify the WP-FND-02 Public runtime config/secret storage contract."

from __future__ import annotations

from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install_jr-bot.sh"
STRUCTURE_AUDIT = ROOT / "audits" / "audit_jr-bot-structure.sh"
DOC = ROOT / "docs" / "runtime-config-secrets.md"
README = ROOT / "README.md"
SECURITY = ROOT / "SECURITY.md"
STRUCTURE_DOC = ROOT / "docs" / "audits" / "audit_jr-bot-structure.md"
SYSTEMD_DIR = ROOT / "systemd"

FORBIDDEN_PROJECT_TOKENS = ("ggb", "trx", "dmr")
SYNTH_SERVER = "SYNTHETIC_WP_FND_02_SERVER_TOKEN"
SYNTH_PING = "SYNTHETIC_WP_FND_02_PING_TOKEN"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require_all(text: str, markers, context: str) -> None:
    for marker in markers:
        if marker not in text:
            fail(f"{context}: missing marker {marker!r}")


def find_bash() -> str:
    candidates = [
        shutil.which("bash"),
        shutil.which("bash.exe"),
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    fail("bash is required for WP-FND-02 synthetic behavior tests")


def sh_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def bash_path(path: Path) -> str:
    value = str(path)
    if re.match(r"^[A-Za-z]:[\\/]", value):
        drive = value[0].lower()
        rest = value[2:].replace("\\", "/").lstrip("/")
        return f"/{drive}/{rest}"
    return value.replace("\\", "/")


def make_sourceable_installer(tmp: Path) -> Path:
    installer = read(INSTALLER)
    marker = '\nmain "$@"'
    if marker not in installer:
        fail('installer entry point main "$@" not found')
    lib = installer.rsplit(marker, 1)[0] + "\n"
    path = tmp / "installer-lib.sh"
    path.write_text(lib, encoding="utf-8", newline="\n")
    return path


def run_bash(bash: str, lib: Path, body: str, *, expect: int = 0):
    script = textwrap.dedent(
        f'''
        source {sh_quote(bash_path(lib))}
        set +e
        sudo() {{
            local cmd="$1"
            shift
            case "$cmd" in
                chown) return 0 ;;
                *) command "$cmd" "$@" ;;
            esac
        }}
        {body}
        '''
    )
    proc = subprocess.run(
        [bash, "-c", script],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != expect:
        fail(
            "synthetic bash case returned unexpected code "
            f"(expected {expect}, got {proc.returncode}); "
            f"stderr={proc.stderr.strip()!r}"
        )
    for secret in (SYNTH_SERVER, SYNTH_PING):
        if secret in proc.stdout or secret in proc.stderr:
            fail("synthetic secret leaked to installer stdout/stderr")
    return proc


def parse_config(path: Path) -> str:
    if not path.is_file():
        fail(f"expected config missing: {path}")
    return path.read_text(encoding="utf-8")


def assert_absent(path: Path, label: str) -> None:
    if path.exists():
        fail(f"{label} unexpectedly exists: {path}")


def assert_present(path: Path, label: str) -> None:
    if not path.is_file():
        fail(f"{label} missing: {path}")


def main() -> int:
    installer = read(INSTALLER)
    audit = read(STRUCTURE_AUDIT)
    doc = read(DOC)
    readme = read(README)
    security = read(SECURITY)
    structure_doc = read(STRUCTURE_DOC)

    require_all(
        installer,
        (
            "DEFAULT_MANAGEMENT_MODE",
            "DEFAULT_DATABASE_MODE",
            "DEFAULT_AUTH_MODE",
            "MANAGEMENT_MODE = ${management_mode}",
            "DATABASE_MODE = ${database_mode}",
            "SERVER_BASE = ${server_base}",
            "AUTH_MODE = ${auth_mode}",
            "${install_dir}/config/secrets",
            "server.token",
            "ping.token",
            "atomic_stage_root_file",
            "atomic_commit_staged_file",
            'sudo mv -f "$staged_path" "$target_path"',
            'sudo chmod 0750 "$secrets_dir"',
            '0640 "$server_token"',
            '0640 "$ping_token"',
        ),
        "installer C2 contract",
    )

    if "SERVER_TOKEN = ${server_token}" in installer:
        fail("installer still writes SERVER_TOKEN into config.ini")
    if "PING_TOKEN = ${ping_token}" in installer:
        fail("installer still writes PING_TOKEN into config.ini")

    foundation = re.search(
        r"create_directory_structure\(\) \{(?P<body>.*?)\n\}",
        installer,
        re.DOTALL,
    )
    if not foundation:
        fail("create_directory_structure function missing")
    if "config/secrets" in foundation.group("body"):
        fail("config/secrets became an unconditional mandatory directory")

    for path in sorted(SYSTEMD_DIR.glob("*")):
        body = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"^\s*Environment(File)?\s*=.*(?:SERVER_TOKEN|PING_TOKEN)", body, re.I | re.M):
            fail(f"systemd secret environment transport present: {path.name}")

    external_secret_argv = re.compile(
        r"^\s*(?:sudo\s+)?(?:curl|python3?|systemctl|env|bash)\b[^\n]*(?:SERVER_TOKEN|PING_TOKEN)",
        re.I | re.M,
    )
    if external_secret_argv.search(installer):
        fail("runtime token material appears on an external process argv")

    require_all(
        audit,
        (
            "import configparser",
            "runtime_config_summary",
            '"permissions_ok": file_meta(config_ini)["permissions"] == "640"',
            "MANAGEMENT_MODE",
            "DATABASE_MODE",
            "AUTH_MODE",
            "PLAINTEXT_RUNTIME_TOKEN_KEY_IN_CONFIG",
            '"runtime_config_secret_values_included": False',
        ),
        "Structure Audit C2 contract",
    )
    if re.search(
        r'(?:server_token|ping_token)[^\n]*\.(?:read_text|read_bytes|open)\(',
        audit,
        re.I,
    ):
        fail("Structure Audit appears to read runtime secret content")

    secret_meta = re.search(
        r"def secret_slot_meta\(path: Path\).*?\n\n",
        audit,
        re.DOTALL,
    )
    if not secret_meta:
        fail("Structure Audit secret_slot_meta helper missing")
    secret_meta_body = secret_meta.group(0)
    for forbidden_field in (
        "size_bytes",
        "modified_at_utc",
        "realpath",
        "readlink",
        "is_symlink",
        "is_file",
        "is_dir",
    ):
        if forbidden_field in secret_meta_body:
            fail(f"Structure Audit exposes forbidden runtime-secret metadata field: {forbidden_field}")
    require_all(
        secret_meta_body,
        ('"path"', '"exists"', '"owner"', '"group"', '"permissions"'),
        "Structure Audit runtime-secret metadata minimization",
    )
    if "file_meta(secrets_dir)" in audit or 'file_meta(secrets_dir / "server.token")' in audit or 'file_meta(secrets_dir / "ping.token")' in audit:
        fail("Structure Audit bypasses minimized runtime-secret metadata helper")

    require_all(
        doc,
        (
            "DATABASE_MODE = local_pi | external",
            "AUTH_MODE = none | server_token | split_ping_token",
            "config/secrets/",
            "server.token",
            "ping.token",
            "Claim / Finalize",
        ),
        "runtime config/secret documentation",
    )

    require_all(
        readme,
        ("## Public v1 scope", "## Runtime layout", "## Runtime configuration authority", "## Audits", "## Installer"),
        "README regression guard",
    )
    require_all(
        security,
        ("Do not open a public issue", "## Runtime configuration and secrets", "config/secrets/server.token"),
        "SECURITY regression guard",
    )
    require_all(
        structure_doc,
        ("## Purpose", "## Target runtime layout", "## Usage", "## Configuration and runtime-secret checks", "## systemd checks", "## Security"),
        "Structure Audit documentation regression guard",
    )

    lowered = installer.lower()
    for token in FORBIDDEN_PROJECT_TOKENS:
        if re.search(rf"\b{re.escape(token)}\b", lowered):
            fail(f"project-specific token found in generic installer: {token}")
    if "/jrbot/v1/provisioning/" in installer:
        fail("Public WP-FND-02 must not implement provisioning endpoints")

    bash = find_bash()
    with tempfile.TemporaryDirectory(prefix="wp-fnd-02-public-") as td:
        temp = Path(td)
        lib = make_sourceable_installer(temp)

        root = temp / "s01"
        (root / "config").mkdir(parents=True)
        run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot standalone local_pi "" none 60 "" ""')
        cfg = parse_config(root / "config/config.ini")
        require_all(cfg, ("MANAGEMENT_MODE = standalone", "DATABASE_MODE = local_pi"), "S01 config")
        if "[server]" in cfg:
            fail("S01 local_pi unexpectedly contains [server]")
        assert_absent(root / "config/secrets/server.token", "S01 server.token")
        assert_absent(root / "config/secrets/ping.token", "S01 ping.token")

        root = temp / "s02"
        (root / "config").mkdir(parents=True)
        run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot standalone external https://handler.example none 60 "" ""')
        cfg = parse_config(root / "config/config.ini")
        require_all(cfg, ("DATABASE_MODE = external", "[server]", "SERVER_BASE = https://handler.example", "AUTH_MODE = none"), "S02 config")
        assert_absent(root / "config/secrets/server.token", "S02 server.token")
        assert_absent(root / "config/secrets/ping.token", "S02 ping.token")

        root = temp / "s03"
        (root / "config").mkdir(parents=True)
        run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot standalone external https://handler.example server_token 60 {sh_quote(SYNTH_SERVER)} ""')
        cfg = parse_config(root / "config/config.ini")
        if SYNTH_SERVER in cfg or "SERVER_TOKEN =" in cfg:
            fail("S03 secret entered config.ini")
        assert_present(root / "config/secrets/server.token", "S03 server.token")
        if (root / "config/secrets/server.token").read_text(encoding="utf-8").strip() != SYNTH_SERVER:
            fail("S03 server.token content mismatch")
        assert_absent(root / "config/secrets/ping.token", "S03 ping.token")

        root = temp / "s04"
        (root / "config").mkdir(parents=True)
        run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot opscon_managed external https://handler.example split_ping_token 60 {sh_quote(SYNTH_SERVER)} {sh_quote(SYNTH_PING)}')
        cfg = parse_config(root / "config/config.ini")
        if SYNTH_SERVER in cfg or SYNTH_PING in cfg or "SERVER_TOKEN =" in cfg or "PING_TOKEN =" in cfg:
            fail("S04 secret entered config.ini")
        assert_present(root / "config/secrets/server.token", "S04 server.token")
        assert_present(root / "config/secrets/ping.token", "S04 ping.token")

        run_bash(bash, lib, 'normalize_management_mode invalid >/dev/null', expect=1)
        run_bash(bash, lib, 'normalize_database_mode invalid >/dev/null', expect=1)
        p = run_bash(bash, lib, 'normalize_server_base "https://handler.example///"')
        if p.stdout.strip() != "https://handler.example":
            fail("S09 SERVER_BASE trailing-slash canonicalization failed")
        run_bash(bash, lib, 'normalize_server_base "http://handler.example" >/dev/null', expect=1)
        run_bash(bash, lib, 'normalize_auth_mode invalid >/dev/null', expect=1)

        failure_cases = [
            ("s07", 'local_pi https://handler.example none 60 "" ""'),
            ("s08", 'external "" none 60 "" ""'),
            ("s11", 'external https://handler.example server_token 60 "" ""'),
            ("s12", f'external https://handler.example split_ping_token 60 "" {sh_quote(SYNTH_PING)}'),
            ("s13", f'external https://handler.example split_ping_token 60 {sh_quote(SYNTH_SERVER)} ""'),
            ("s14", f'external https://handler.example none 60 {sh_quote(SYNTH_SERVER)} ""'),
        ]
        for name, args in failure_cases:
            root = temp / name
            (root / "config").mkdir(parents=True)
            sentinel = root / "config/config.ini"
            sentinel.write_text("SENTINEL\n", encoding="utf-8")
            run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot standalone {args}', expect=1)
            if sentinel.read_text(encoding="utf-8") != "SENTINEL\n":
                fail(f"{name.upper()} replaced prior accepted config on validation failure")

        root = temp / "s14-clean"
        secrets = root / "config/secrets"
        secrets.mkdir(parents=True)
        (secrets / "server.token").write_text(SYNTH_SERVER, encoding="utf-8")
        (secrets / "ping.token").write_text(SYNTH_PING, encoding="utf-8")
        run_bash(bash, lib, f'apply_runtime_configuration {sh_quote(bash_path(root))} jrbot Project Bot jrbot standalone external https://handler.example none 60 "" ""')
        assert_absent(secrets / "server.token", "S14 cleanup server.token")
        assert_absent(secrets / "ping.token", "S14 cleanup ping.token")

        if os.name != "nt":
            if (root / "config/config.ini").stat().st_mode & 0o777 != 0o640:
                fail("config.ini mode is not 0640")

    print("PASS: PUB-04 static C2 contract checks")
    print("PASS: S01-S14 synthetic mode/fail-closed matrix")
    print("PASS: synthetic secrets absent from installer stdout/stderr and config.ini")
    print("PASS: no systemd-env / external-process argv secret transport detected")
    print("PASS: Public remains project-neutral and excludes provisioning endpoints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
