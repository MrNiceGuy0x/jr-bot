#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Network Health Audit
# Version: 0.2.1
# ==========================================================
#
# Purpose:
#   Deep read-only network and node health audit for JR-Bot
#   Raspberry Pi nodes.
#
#   This script is intentionally deeper than:
#   audits/audit_jr-bot-structure.sh
#
# It collects:
#   - Host / OS / Raspberry Pi information
#   - Network interfaces, IPv4/IPv6, routes, DNS resolver files
#   - Network service status:
#       systemd-networkd
#       NetworkManager
#       wpa_supplicant
#       wpa_supplicant@wlan0
#       dhcpcd
#       systemd-resolved
#       networking
#       ssh
#   - systemd unit contents for relevant services
#   - sanitized network configuration file contents
#   - systemd-networkd binary and library diagnostics
#   - ldd output and missing shared libraries
#   - package versions for relevant network/system packages
#   - journal excerpts for network-related services
#   - connectivity checks:
#       primary IPv4 present
#       default route present
#       gateway ping
#       DNS resolution
#       optional HTTPS test URL
#   - Wi-Fi diagnostics:
#       iw dev wlan0 link
#       rfkill
#       networkctl status
#       nmcli if available
#   - automatic findings and recommendations
#
# Security:
#   - Read-only by design.
#   - No changes are made to the system.
#   - Sensitive values are redacted:
#       psk=
#       password=
#       key=
#       token=
#       secret=
#       passphrase=
#       private_key=
#   - wpa_supplicant configs are sanitized before output.
#
# Local file behavior:
#   - Default output is written to <bot-path>/reports/pending/.
#   - If reports/pending cannot be created, /tmp is used as fallback.
#   - If upload succeeds and no --keep-local was set, the generated file is deleted.
#   - If --output <file> is set, the file is kept.
#   - If --keep-local is set, the file is kept.
#   - If upload fails, the file is kept for retry/debugging.
#
# OPSCON endpoint:
#   https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
#
# OPSCON storage model:
#   /OPSCON/data/audit_jr-bot-network-health/<instance>/
#   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ audit_jr-bot-network-health-<instance>.json
#   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ history/
#       Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ audit_jr-bot-network-health-<instance>-YYYYMMDD_HHMMSS.json
#
# Example local debug:
#   ./audits/audit_jr-bot-network-health.sh \
#     --instance trx \
#     --path /opt/bots/trx \
#     --output /opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-local-debug.json \
#     --print-summary
#
# Example OPSCON upload:
#   ./audits/audit_jr-bot-network-health.sh \
#     --instance trx \
#     --path /opt/bots/trx \
#     --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
#     --token <TOKEN>
#
# ==========================================================

SCRIPT_VERSION="0.2.1"
SCHEMA_VERSION="jrbot-network-health-audit-v1"

INSTANCE=""
INSTALL_PATH=""
MODE="target"
PUSH_URL="${NETWORK_HEALTH_AUDIT_PUSH_URL:-https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php}"
TOKEN="${REPORT_UPLOAD_TOKEN:-}"
OUTPUT_FILE=""
OUTPUT_FILE_USER_SET="false"
PRINT_JSON="false"
PRINT_SUMMARY="false"
KEEP_LOCAL="false"
TEST_URL=""
GATEWAY_OVERRIDE=""
WIFI_INTERFACE="wlan0"
ETH_INTERFACE="eth0"
MAX_FILE_BYTES="12000"
MAX_JOURNAL_LINES="120"

info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }
die() { error "$*"; exit 1; }

usage() {
    cat <<'EOF'
JR-Bot Network Health Audit

Usage:
  audit_jr-bot-network-health.sh --instance <name> --path <bot-path> [options]

Required:
  --instance <name>       Bot instance name, e.g. trx, dmr, ggb
  --path <bot-path>       Bot install path, e.g. /opt/bots/trx

Options:
  --legacy                Legacy mode for older DMR/GGB structures
  --push-url <url>        Optional OPSCON network health ingest endpoint
  --token <token>         Optional OPSCON audit token
  --output <file>         Optional output JSON file. File will be kept.
  --keep-local            Keep generated local JSON after successful upload
  --print-json            Print full JSON to stdout
  --print-summary         Print compact findings/recommendations summary
  --test-url <url>        Optional HTTPS URL to test, e.g. https://spl.blenk.co.at
  --gateway <ip>          Optional gateway override, e.g. <gateway-ip>
  --wifi-iface <iface>    Wi-Fi interface, default: wlan0
  --eth-iface <iface>     Ethernet interface, default: eth0
  -h, --help              Show this help

Examples:
  ./audits/audit_jr-bot-network-health.sh --instance trx --path /opt/bots/trx --print-summary

  ./audits/audit_jr-bot-network-health.sh \
    --instance trx \
    --path /opt/bots/trx \
    --output /opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-local-debug.json \
    --print-summary

  ./audits/audit_jr-bot-network-health.sh \
    --instance trx \
    --path /opt/bots/trx \
    --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
    --token <TOKEN>
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --instance) INSTANCE="${2:-}"; shift 2 ;;
        --path) INSTALL_PATH="${2:-}"; shift 2 ;;
        --legacy) MODE="legacy"; shift ;;
        --push-url) PUSH_URL="${2:-}"; shift 2 ;;
        --token) TOKEN="${2:-}"; shift 2 ;;
        --output) OUTPUT_FILE="${2:-}"; OUTPUT_FILE_USER_SET="true"; shift 2 ;;
        --keep-local) KEEP_LOCAL="true"; shift ;;
        --print-json) PRINT_JSON="true"; shift ;;
        --print-summary) PRINT_SUMMARY="true"; shift ;;
        --test-url) TEST_URL="${2:-}"; shift 2 ;;
        --gateway) GATEWAY_OVERRIDE="${2:-}"; shift 2 ;;
        --wifi-iface) WIFI_INTERFACE="${2:-}"; shift 2 ;;
        --eth-iface) ETH_INTERFACE="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unbekannter Parameter: $1" ;;
    esac
done

[[ -n "$INSTANCE" ]] || { usage; die "Parameter fehlt: --instance"; }
[[ -n "$INSTALL_PATH" ]] || { usage; die "Parameter fehlt: --path"; }

if [[ "$INSTALL_PATH" == "~/"* ]]; then
    INSTALL_PATH="${HOME}/${INSTALL_PATH#~/}"
fi

REPORTS_PENDING_DIR="${INSTALL_PATH}/reports/pending"

# Optional token file support.
# Priority:
#   1) <bot-path>/config/audit_network_health.token
#   2) <bot-path>/config/network_health_upload.token
#   3) <bot-path>/config/report_upload.token       # shared audit fallback
for token_file in \
    "$INSTALL_PATH/config/audit_network_health.token" \
    "$INSTALL_PATH/config/network_health_upload.token" \
    "$INSTALL_PATH/config/report_upload.token"
do
    if [[ -z "$TOKEN" && -s "$token_file" ]]; then
        TOKEN="$(tr -d '[:space:]' < "$token_file" || true)"
    fi
done

INSTANCE_LOWER="$(echo "$INSTANCE" | tr '[:upper:]' '[:lower:]')"

if ! [[ "$INSTANCE_LOWER" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    die "UngÃƒÂ¼ltiger Instanzname: $INSTANCE"
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    TS_FILE="$(date -u +"%Y%m%d_%H%M%S")"

    if mkdir -p "$REPORTS_PENDING_DIR" 2>/dev/null; then
        OUTPUT_FILE="${REPORTS_PENDING_DIR}/audit_jr-bot-network-health-${INSTANCE_LOWER}-${TS_FILE}.json"
    else
        warn "reports/pending konnte nicht erstellt werden. Fallback auf /tmp."
        OUTPUT_FILE="/tmp/audit_jr-bot-network-health-${INSTANCE_LOWER}-${TS_FILE}.json"
    fi
fi

command -v python3 >/dev/null 2>&1 || die "python3 wird benÃƒÂ¶tigt."

export JR_NET_AUDIT_SCRIPT_VERSION="$SCRIPT_VERSION"
export JR_NET_AUDIT_SCHEMA_VERSION="$SCHEMA_VERSION"
export JR_NET_AUDIT_INSTANCE="$INSTANCE_LOWER"
export JR_NET_AUDIT_MODE="$MODE"
export JR_NET_AUDIT_CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export JR_NET_AUDIT_INSTALL_PATH="$INSTALL_PATH"
export JR_NET_AUDIT_REPORTS_PENDING_DIR="$REPORTS_PENDING_DIR"
export JR_NET_AUDIT_WIFI_INTERFACE="$WIFI_INTERFACE"
export JR_NET_AUDIT_ETH_INTERFACE="$ETH_INTERFACE"
export JR_NET_AUDIT_TEST_URL="$TEST_URL"
export JR_NET_AUDIT_GATEWAY_OVERRIDE="$GATEWAY_OVERRIDE"
export JR_NET_AUDIT_MAX_FILE_BYTES="$MAX_FILE_BYTES"
export JR_NET_AUDIT_MAX_JOURNAL_LINES="$MAX_JOURNAL_LINES"

python3 > "$OUTPUT_FILE" <<'PY'
from __future__ import annotations

import glob
import json
import os
import platform
import re
import shutil
import socket
import subprocess
from pathlib import Path
from typing import Any


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


SCHEMA = env("JR_NET_AUDIT_SCHEMA_VERSION")
SCRIPT_VERSION = env("JR_NET_AUDIT_SCRIPT_VERSION")
INSTANCE = env("JR_NET_AUDIT_INSTANCE")
MODE = env("JR_NET_AUDIT_MODE")
CREATED_AT_UTC = env("JR_NET_AUDIT_CREATED_AT_UTC")
INSTALL_PATH = env("JR_NET_AUDIT_INSTALL_PATH")
REPORTS_PENDING_DIR = env("JR_NET_AUDIT_REPORTS_PENDING_DIR")
WIFI_IFACE = env("JR_NET_AUDIT_WIFI_INTERFACE", "wlan0")
ETH_IFACE = env("JR_NET_AUDIT_ETH_INTERFACE", "eth0")
TEST_URL = env("JR_NET_AUDIT_TEST_URL")
GATEWAY_OVERRIDE = env("JR_NET_AUDIT_GATEWAY_OVERRIDE")
MAX_FILE_BYTES = int(env("JR_NET_AUDIT_MAX_FILE_BYTES", "12000"))
MAX_JOURNAL_LINES = int(env("JR_NET_AUDIT_MAX_JOURNAL_LINES", "120"))

SENSITIVE_PATTERNS = [
    re.compile(r'(?i)(psk\s*=\s*)".*?"'),
    re.compile(r'(?i)(psk\s*=\s*)\S+'),
    re.compile(r'(?i)(password\s*=\s*)".*?"'),
    re.compile(r'(?i)(password\s*=\s*)\S+'),
    re.compile(r'(?i)(passwd\s*=\s*)".*?"'),
    re.compile(r'(?i)(passwd\s*=\s*)\S+'),
    re.compile(r'(?i)(passphrase\s*=\s*)".*?"'),
    re.compile(r'(?i)(passphrase\s*=\s*)\S+'),
    re.compile(r'(?i)(token\s*=\s*)".*?"'),
    re.compile(r'(?i)(token\s*=\s*)\S+'),
    re.compile(r'(?i)(secret\s*=\s*)".*?"'),
    re.compile(r'(?i)(secret\s*=\s*)\S+'),
    re.compile(r'(?i)(private_key\s*=\s*)".*?"'),
    re.compile(r'(?i)(private_key\s*=\s*)\S+'),
    re.compile(r'(?i)(key\s*=\s*)".*?"'),
    re.compile(r'(?i)(key\s*=\s*)\S+'),
]


def redact_text(text: str) -> str:
    redacted = text
    for pattern in SENSITIVE_PATTERNS:
        redacted = pattern.sub(r'\1"<REDACTED>"', redacted)
    return redacted


def run_command(args: list[str], timeout: int = 20) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "cmd": args,
            "available": True,
            "returncode": proc.returncode,
            "stdout": redact_text(proc.stdout.strip()),
            "stderr": redact_text(proc.stderr.strip()),
        }
    except FileNotFoundError:
        return {
            "cmd": args,
            "available": False,
            "returncode": None,
            "stdout": "",
            "stderr": "command not found",
        }
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        return {
            "cmd": args,
            "available": True,
            "returncode": 124,
            "stdout": redact_text(stdout.strip()),
            "stderr": f"timeout after {timeout}s",
        }
    except Exception as exc:
        return {
            "cmd": args,
            "available": True,
            "returncode": 999,
            "stdout": "",
            "stderr": str(exc),
        }


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def read_file_sanitized(path: str, max_bytes: int = MAX_FILE_BYTES) -> dict[str, Any]:
    p = Path(path)
    result: dict[str, Any] = {
        "path": path,
        "exists": p.exists(),
        "is_file": p.is_file(),
        "readable": os.access(path, os.R_OK) if p.exists() else False,
        "size_bytes": None,
        "truncated": False,
        "content_redacted": "",
        "error": "",
    }

    if not p.exists():
        return result

    try:
        result["size_bytes"] = p.stat().st_size
    except Exception as exc:
        result["error"] = f"stat failed: {exc}"
        return result

    if not p.is_file():
        return result

    if not os.access(path, os.R_OK):
        result["error"] = "not readable"
        return result

    try:
        raw = p.read_bytes()
        if len(raw) > max_bytes:
            raw = raw[:max_bytes]
            result["truncated"] = True

        text = raw.decode("utf-8", errors="replace")
        result["content_redacted"] = redact_text(text)
    except Exception as exc:
        result["error"] = f"read failed: {exc}"

    return result


def file_meta(path: str) -> dict[str, Any]:
    p = Path(path)
    result: dict[str, Any] = {
        "path": path,
        "exists": p.exists(),
        "is_file": p.is_file(),
        "is_symlink": p.is_symlink(),
        "readlink": "",
        "realpath": "",
        "permissions_octal": "",
        "owner_uid": None,
        "group_gid": None,
        "size_bytes": None,
    }

    if not p.exists() and not p.is_symlink():
        return result

    try:
        st = p.lstat()
        result["permissions_octal"] = oct(st.st_mode & 0o777)
        result["owner_uid"] = st.st_uid
        result["group_gid"] = st.st_gid
        result["size_bytes"] = st.st_size
    except Exception:
        pass

    if p.is_symlink():
        try:
            result["readlink"] = os.readlink(path)
            result["realpath"] = os.path.realpath(path)
        except Exception:
            pass
    else:
        try:
            result["realpath"] = str(p.resolve())
        except Exception:
            pass

    return result


def systemctl_show(unit: str) -> dict[str, Any]:
    props = [
        "LoadState",
        "ActiveState",
        "SubState",
        "UnitFileState",
        "Result",
        "ExecMainCode",
        "ExecMainStatus",
        "FragmentPath",
        "DropInPaths",
        "Description",
    ]

    result: dict[str, Any] = {
        "unit": unit,
        "exists": False,
        "load_state": "",
        "active_state": "",
        "sub_state": "",
        "unit_file_state": "",
        "result": "",
        "exec_main_code": "",
        "exec_main_status": "",
        "fragment_path": "",
        "drop_in_paths": "",
        "description": "",
        "systemctl_show": {},
        "systemctl_status": {},
        "systemctl_cat": {},
        "journal_recent": {},
    }

    show = run_command(["systemctl", "show", unit, "--no-pager"] + [f"-p{x}" for x in props])
    result["systemctl_show"] = show

    if show["returncode"] == 0:
        kv: dict[str, str] = {}
        for line in show["stdout"].splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                kv[k] = v

        result["load_state"] = kv.get("LoadState", "")
        result["active_state"] = kv.get("ActiveState", "")
        result["sub_state"] = kv.get("SubState", "")
        result["unit_file_state"] = kv.get("UnitFileState", "")
        result["result"] = kv.get("Result", "")
        result["exec_main_code"] = kv.get("ExecMainCode", "")
        result["exec_main_status"] = kv.get("ExecMainStatus", "")
        result["fragment_path"] = kv.get("FragmentPath", "")
        result["drop_in_paths"] = kv.get("DropInPaths", "")
        result["description"] = kv.get("Description", "")
        result["exists"] = result["load_state"] not in ("", "not-found")

    result["systemctl_status"] = run_command(["systemctl", "status", unit, "--no-pager"], timeout=15)
    result["systemctl_cat"] = run_command(["systemctl", "cat", unit, "--no-pager"], timeout=15)
    result["journal_recent"] = run_command(
        ["journalctl", "-u", unit, "-b", "--no-pager", "-n", str(MAX_JOURNAL_LINES)],
        timeout=20
    )

    return result


def parse_ipv4_addresses(ip_json_stdout: str) -> list[dict[str, Any]]:
    try:
        data = json.loads(ip_json_stdout)
    except Exception:
        return []

    rows: list[dict[str, Any]] = []

    for iface in data:
        ifname = iface.get("ifname", "")
        for addr in iface.get("addr_info", []):
            if addr.get("family") == "inet":
                rows.append({
                    "interface": ifname,
                    "local": addr.get("local", ""),
                    "prefixlen": addr.get("prefixlen"),
                    "scope": addr.get("scope", ""),
                    "dynamic": "dynamic" in addr.get("flags", []),
                })

    return rows


def parse_default_route(route_stdout: str) -> dict[str, Any]:
    result = {
        "present": False,
        "raw": "",
        "gateway": "",
        "interface": "",
        "source": "",
    }

    for line in route_stdout.splitlines():
        if line.startswith("default "):
            result["present"] = True
            result["raw"] = line
            parts = line.split()
            for i, part in enumerate(parts):
                if part == "via" and i + 1 < len(parts):
                    result["gateway"] = parts[i + 1]
                if part == "dev" and i + 1 < len(parts):
                    result["interface"] = parts[i + 1]
                if part == "src" and i + 1 < len(parts):
                    result["source"] = parts[i + 1]
            break

    return result


def extract_missing_libraries(ldd_stdout: str, journal_text: str) -> list[str]:
    libs = set()

    for line in ldd_stdout.splitlines():
        if "not found" in line:
            libs.add(line.strip())

    for match in re.findall(r'([\w.-]+\.so(?:\.\d+)*)[: ]+(?:cannot open shared object file|not found)', journal_text):
        libs.add(match)

    return sorted(libs)


def find_library_candidates(lib_name: str) -> list[str]:
    candidates: list[str] = []
    for base in ["/usr/lib", "/lib"]:
        for path in glob.glob(f"{base}/**/{lib_name}", recursive=True):
            candidates.append(path)
    return sorted(set(candidates))


def collect_config_files() -> dict[str, Any]:
    paths: list[str] = []

    explicit = [
        "/etc/systemd/network/25-wlan0.network",
        "/etc/systemd/network/20-wlan0.network",
        "/etc/systemd/network/10-wlan0.network",
        "/etc/systemd/network/25-eth0.network",
        "/etc/systemd/network/20-eth0.network",
        "/etc/systemd/network/10-eth0.network",
        "/etc/network/interfaces",
        "/etc/dhcpcd.conf",
        "/etc/resolv.conf",
        "/run/systemd/resolve/resolv.conf",
        "/etc/hostname",
        "/etc/hosts",
    ]

    paths.extend(explicit)

    globs = [
        "/etc/systemd/network/*.network",
        "/etc/systemd/network/*.link",
        "/etc/wpa_supplicant/*.conf",
        "/etc/NetworkManager/NetworkManager.conf",
        "/etc/NetworkManager/system-connections/*",
    ]

    for pattern in globs:
        paths.extend(glob.glob(pattern))

    unique_paths = []
    seen = set()
    for path in paths:
        if path not in seen:
            seen.add(path)
            unique_paths.append(path)

    files = []
    for path in unique_paths:
        files.append(read_file_sanitized(path))

    return {
        "files": files
    }


def collect_package_versions() -> dict[str, Any]:
    packages = [
        "systemd",
        "libsystemd0",
        "wpasupplicant",
        "network-manager",
        "dhcpcd5",
        "raspberrypi-net-mods",
        "isc-dhcp-client",
        "wireless-tools",
        "iw",
        "rfkill",
        "curl",
        "ca-certificates",
    ]

    result = {
        "dpkg_available": command_exists("dpkg-query"),
        "packages": {}
    }

    if not command_exists("dpkg-query"):
        return result

    for pkg in packages:
        cmd = run_command([
            "dpkg-query",
            "-W",
            "-f=${Status}|${Version}|${Architecture}",
            pkg
        ])
        installed = False
        version = ""
        arch = ""
        if cmd["returncode"] == 0 and "|" in cmd["stdout"]:
            parts = cmd["stdout"].split("|")
            installed = "install ok installed" in parts[0]
            version = parts[1] if len(parts) > 1 else ""
            arch = parts[2] if len(parts) > 2 else ""

        result["packages"][pkg] = {
            "installed": installed,
            "version": version,
            "architecture": arch,
            "query": cmd,
        }

    return result


def collect_systemd_integrity(services: dict[str, Any]) -> dict[str, Any]:
    networkd_binary = "/lib/systemd/systemd-networkd"

    ldd_networkd = run_command(["ldd", networkd_binary])
    version_networkd = run_command([networkd_binary, "--version"])

    journal_text = services.get("systemd-networkd.service", {}).get("journal_recent", {}).get("stdout", "")
    missing_libraries = extract_missing_libraries(ldd_networkd.get("stdout", ""), journal_text)

    library_candidates: dict[str, list[str]] = {}
    for lib in missing_libraries:
        lib_clean = lib.split()[0].strip()
        if lib_clean.endswith(".so") or ".so." in lib_clean or lib_clean.endswith(".so:"):
            lib_clean = lib_clean.rstrip(":")
            library_candidates[lib_clean] = find_library_candidates(lib_clean)

    expected_shared_libs = []
    for path in glob.glob("/usr/lib/**/systemd/libsystemd-shared-*.so", recursive=True):
        expected_shared_libs.append(path)
    for path in glob.glob("/lib/**/systemd/libsystemd-shared-*.so", recursive=True):
        expected_shared_libs.append(path)

    return {
        "systemd_networkd_binary": file_meta(networkd_binary),
        "systemd_networkd_libraries": ldd_networkd,
        "systemd_networkd_version_command": version_networkd,
        "missing_libraries_detected": missing_libraries,
        "library_candidates": library_candidates,
        "systemd_shared_library_candidates": sorted(set(expected_shared_libs)),
        "specific_paths": {
            "/lib/systemd/libsystemd-shared-252.so": file_meta("/lib/systemd/libsystemd-shared-252.so"),
            "/usr/lib/arm-linux-gnueabihf/systemd/libsystemd-shared-252.so": file_meta("/usr/lib/arm-linux-gnueabihf/systemd/libsystemd-shared-252.so"),
        }
    }


def connectivity_test(default_route: dict[str, Any]) -> dict[str, Any]:
    gateway = GATEWAY_OVERRIDE or default_route.get("gateway", "")

    result: dict[str, Any] = {
        "gateway": gateway,
        "gateway_ping": {},
        "dns_getent_google": {},
        "dns_getent_project_host": {},
        "https_test": {},
    }

    if gateway:
        result["gateway_ping"] = run_command(["ping", "-c", "4", "-W", "2", gateway], timeout=15)

    result["dns_getent_google"] = run_command(["getent", "hosts", "google.com"], timeout=10)

    if TEST_URL:
        host = ""
        try:
            from urllib.parse import urlparse
            parsed = urlparse(TEST_URL)
            host = parsed.hostname or ""
        except Exception:
            host = ""

        if host:
            result["dns_getent_project_host"] = run_command(["getent", "hosts", host], timeout=10)

        if command_exists("curl"):
            result["https_test"] = run_command(["curl", "-fsSI", "--max-time", "15", TEST_URL], timeout=20)
        else:
            result["https_test"] = {
                "cmd": ["curl", "-fsSI", TEST_URL],
                "available": False,
                "returncode": None,
                "stdout": "",
                "stderr": "curl not found",
            }

    return result


def collect_wifi() -> dict[str, Any]:
    return {
        "interface": WIFI_IFACE,
        "ip_link": run_command(["ip", "link", "show", WIFI_IFACE]),
        "iw_link": run_command(["iw", "dev", WIFI_IFACE, "link"]),
        "iw_dev": run_command(["iw", "dev"]),
        "iwconfig": run_command(["iwconfig", WIFI_IFACE]),
        "rfkill": run_command(["rfkill", "list"]),
        "wpa_cli_status": run_command(["wpa_cli", "-i", WIFI_IFACE, "status"]),
        "networkctl_status": run_command(["networkctl", "status", WIFI_IFACE, "--no-pager"]),
    }


def collect_nmcli() -> dict[str, Any]:
    if not command_exists("nmcli"):
        return {
            "available": False,
            "device_status": {},
            "connections": {},
        }

    return {
        "available": True,
        "device_status": run_command(["nmcli", "device", "status"]),
        "connections": run_command(["nmcli", "connection", "show"]),
    }


def collect_host() -> dict[str, Any]:
    os_release = read_file_sanitized("/etc/os-release")
    cpuinfo = read_file_sanitized("/proc/cpuinfo", max_bytes=8000)

    model = ""
    for path in ["/proc/device-tree/model", "/sys/firmware/devicetree/base/model"]:
        try:
            model = Path(path).read_bytes().replace(b"\x00", b"").decode("utf-8", errors="replace")
            if model:
                break
        except Exception:
            pass

    mem_total_mb = None
    try:
        meminfo = Path("/proc/meminfo").read_text()
        m = re.search(r"MemTotal:\s+(\d+)", meminfo)
        if m:
            mem_total_mb = int(int(m.group(1)) / 1024)
    except Exception:
        pass

    boot_time = run_command(["uptime", "-s"])

    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "kernel": run_command(["uname", "-a"]).get("stdout", ""),
        "raspberry_pi_model": model,
        "memory_total_mb": mem_total_mb,
        "boot_time": boot_time.get("stdout", ""),
        "os_release": os_release,
        "cpuinfo_excerpt": cpuinfo,
    }


def build_findings(data: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    findings: list[dict[str, Any]] = []
    recommendations: list[dict[str, Any]] = []

    def add(level: str, code: str, message: str, evidence: Any = None):
        findings.append({
            "level": level,
            "code": code,
            "message": message,
            "evidence": evidence,
        })

    def rec(level: str, code: str, message: str, action: str = ""):
        recommendations.append({
            "level": level,
            "code": code,
            "message": message,
            "action": action,
        })

    ipv4s = data["network"]["ipv4_addresses"]
    default_route = data["network"]["default_route"]
    services = data["network_services"]
    integrity = data["systemd_integrity"]
    connectivity = data["connectivity"]

    if not ipv4s:
        add("critical", "NO_IPV4", "Keine IPv4-Adresse auf einem globalen Interface gefunden.", data["network"]["ip_addr_json"])
        rec("critical", "RESTORE_DHCP_IPV4", "DHCP/IPv4-Zuweisung prÃƒÂ¼fen.", "Network service reparieren oder temporÃƒÂ¤r IPv4 manuell setzen.")

    if not default_route.get("present"):
        add("critical", "NO_DEFAULT_ROUTE", "Keine Default Route vorhanden.", data["network"]["ip_route"])
        rec("critical", "RESTORE_DEFAULT_ROUTE", "Default Route prÃƒÂ¼fen.", "Gateway per DHCP oder temporÃƒÂ¤r mit ip route replace setzen.")

    sn = services.get("systemd-networkd.service", {})
    if sn.get("exists") and sn.get("active_state") == "failed":
        add(
            "critical",
            "SYSTEMD_NETWORKD_FAILED",
            "systemd-networkd ist failed.",
            {
                "active_state": sn.get("active_state"),
                "sub_state": sn.get("sub_state"),
                "result": sn.get("result"),
                "exec_main_status": sn.get("exec_main_status"),
            }
        )
        rec("critical", "REPAIR_SYSTEMD_NETWORKD", "systemd-networkd reparieren.", "journalctl prÃƒÂ¼fen, systemd/libsystemd0 reinstallieren.")

    nm = services.get("NetworkManager.service", {})
    dhcpcd = services.get("dhcpcd.service", {})
    wpa = services.get("wpa_supplicant.service", {})

    if nm.get("exists") and nm.get("active_state") != "active":
        add("info", "NETWORKMANAGER_INACTIVE", "NetworkManager ist nicht aktiv.", {"unit_file_state": nm.get("unit_file_state")})

    if not dhcpcd.get("exists"):
        add("info", "DHCPCD_NOT_FOUND", "dhcpcd.service ist nicht vorhanden.", None)

    if wpa.get("exists") and wpa.get("active_state") == "active":
        add("ok", "WPA_SUPPLICANT_ACTIVE", "wpa_supplicant lÃƒÂ¤uft.", None)

    missing_libs = integrity.get("missing_libraries_detected", [])
    if missing_libs:
        add("critical", "MISSING_SHARED_LIBRARY", "Fehlende Shared Library erkannt.", missing_libs)
        rec(
            "critical",
            "REPAIR_SYSTEMD_LIBRARIES",
            "Systemd-Library-AuflÃƒÂ¶sung reparieren.",
            "systemd/libsystemd0 reinstallieren; vorhandene Library-Kandidaten prÃƒÂ¼fen; Symlink nur als temporÃƒÂ¤ren Fix verwenden."
        )

    gateway_ping = connectivity.get("gateway_ping", {})
    if gateway_ping and gateway_ping.get("returncode") not in (0, None):
        add("critical", "GATEWAY_UNREACHABLE", "Gateway ist nicht erreichbar.", gateway_ping.get("stderr") or gateway_ping.get("stdout"))

    dns_google = connectivity.get("dns_getent_google", {})
    if dns_google and dns_google.get("returncode") not in (0, None):
        add("warning", "DNS_RESOLUTION_FAILED", "DNS-AuflÃƒÂ¶sung fÃƒÂ¼r google.com fehlgeschlagen.", dns_google.get("stderr") or dns_google.get("stdout"))

    config_files = data["network_config_files"]["files"]
    wlan_network_files = [
        f for f in config_files
        if f["path"].endswith(".network") and WIFI_IFACE in f.get("content_redacted", "")
    ]

    if not wlan_network_files:
        add("warning", "NO_WLAN_NETWORKD_CONFIG_DETECTED", f"Keine systemd-networkd .network Datei fÃƒÂ¼r {WIFI_IFACE} erkannt.", None)
    else:
        has_dhcp_yes = any("DHCP=yes" in f.get("content_redacted", "") for f in wlan_network_files)
        if not has_dhcp_yes:
            add("warning", "WLAN_NETWORKD_NO_DHCP_YES", f".network Datei fÃƒÂ¼r {WIFI_IFACE} enthÃƒÂ¤lt kein DHCP=yes.", wlan_network_files)
            rec("warning", "ENABLE_DHCP_FOR_WLAN", f"DHCP fÃƒÂ¼r {WIFI_IFACE} aktivieren.", f"/etc/systemd/network/*{WIFI_IFACE}*.network prÃƒÂ¼fen.")

    critical_count = len([f for f in findings if f["level"] == "critical"])
    warning_count = len([f for f in findings if f["level"] == "warning"])

    if critical_count == 0 and warning_count == 0:
        add("ok", "NETWORK_HEALTH_OK", "Keine kritischen Netzwerkprobleme erkannt.", None)

    return findings, recommendations


services_to_check = [
    "systemd-networkd.service",
    "NetworkManager.service",
    "wpa_supplicant.service",
    f"wpa_supplicant@{WIFI_IFACE}.service",
    "dhcpcd.service",
    "systemd-resolved.service",
    "networking.service",
    "ssh.service",
]

network_services = {unit: systemctl_show(unit) for unit in services_to_check}

ip_addr_json_cmd = run_command(["ip", "-j", "addr", "show"])
ip_addr_plain_cmd = run_command(["ip", "addr", "show"])
ip_route_cmd = run_command(["ip", "route"])
ip_route_get_cmd = run_command(["ip", "route", "get", "1.1.1.1"])

ipv4_addresses = parse_ipv4_addresses(ip_addr_json_cmd.get("stdout", ""))
default_route = parse_default_route(ip_route_cmd.get("stdout", ""))

systemd_integrity = collect_systemd_integrity(network_services)

data: dict[str, Any] = {
    "schema": SCHEMA,
    "script_version": SCRIPT_VERSION,
    "instance": INSTANCE,
    "mode": MODE,
    "created_at_utc": CREATED_AT_UTC,
    "security": {
        "read_only": True,
        "secrets_redacted": True,
        "secret_values_included": False,
        "network_passwords_redacted": True,
    },
    "host": collect_host(),
    "bot_context": {
        "install_path": INSTALL_PATH,
        "install_path_exists": Path(INSTALL_PATH).exists(),
        "reports_pending_dir": REPORTS_PENDING_DIR,
        "reports_pending_dir_exists": Path(REPORTS_PENDING_DIR).exists(),
        "mode": MODE,
    },
    "commands_available": {
        "systemctl": command_exists("systemctl"),
        "journalctl": command_exists("journalctl"),
        "ip": command_exists("ip"),
        "iw": command_exists("iw"),
        "iwconfig": command_exists("iwconfig"),
        "wpa_cli": command_exists("wpa_cli"),
        "networkctl": command_exists("networkctl"),
        "nmcli": command_exists("nmcli"),
        "rfkill": command_exists("rfkill"),
        "curl": command_exists("curl"),
        "getent": command_exists("getent"),
        "ldd": command_exists("ldd"),
        "dpkg_query": command_exists("dpkg-query"),
    },
    "network": {
        "wifi_interface": WIFI_IFACE,
        "eth_interface": ETH_IFACE,
        "hostname_I": run_command(["hostname", "-I"]),
        "ip_addr_json": ip_addr_json_cmd,
        "ip_addr_plain": ip_addr_plain_cmd,
        "ipv4_addresses": ipv4_addresses,
        "ip_route": ip_route_cmd,
        "ip_route_get_1_1_1_1": ip_route_get_cmd,
        "default_route": default_route,
    },
    "wifi": collect_wifi(),
    "network_manager_cli": collect_nmcli(),
    "network_services": network_services,
    "network_config_files": collect_config_files(),
    "systemd_integrity": systemd_integrity,
    "package_versions": collect_package_versions(),
    "connectivity": connectivity_test(default_route),
    "raw_reference_commands": {
        "ls_lib_systemd": run_command(["ls", "-la", "/lib/systemd"]),
        "ls_usr_lib_systemd_arch": run_command(["ls", "-la", "/usr/lib/arm-linux-gnueabihf/systemd"]),
        "find_systemd_shared": run_command(["find", "/usr", "/lib", "-name", "libsystemd-shared-*.so"]),
        "find_network_files": run_command(["find", "/etc/systemd/network", "-maxdepth", "2", "-type", "f", "-print"]),
    },
}

findings, recommendations = build_findings(data)

critical_count = len([f for f in findings if f["level"] == "critical"])
warning_count = len([f for f in findings if f["level"] == "warning"])

data["analysis"] = {
    "health_state": "critical" if critical_count > 0 else ("warning" if warning_count > 0 else "ok"),
    "critical_count": critical_count,
    "warning_count": warning_count,
    "findings": findings,
    "recommendations": recommendations,
    "comparison_hints": [
        "Vergleiche network_services.systemd-networkd.service zwischen funktionierendem und fehlerhaftem Bot.",
        "Vergleiche network.ipv4_addresses und network.default_route.",
        "Vergleiche systemd_integrity.missing_libraries_detected.",
        "Vergleiche network_config_files fÃƒÂ¼r /etc/systemd/network/*.network.",
        "Vergleiche package_versions.systemd und package_versions.libsystemd0.",
        "Vergleiche wifi.iw_link und connectivity.gateway_ping."
    ]
}

print(json.dumps(data, indent=2, ensure_ascii=False))
PY

if ! python3 -m json.tool "$OUTPUT_FILE" >/dev/null 2>&1; then
    die "Die erzeugte JSON-Datei ist ungÃƒÂ¼ltig: $OUTPUT_FILE"
fi

info "Network-Health-Audit JSON erstellt: ${OUTPUT_FILE}"

if [[ "$PRINT_JSON" == "true" ]]; then
    cat "$OUTPUT_FILE"
fi

if [[ "$PRINT_SUMMARY" == "true" ]]; then
    python3 - "$OUTPUT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

analysis = data.get("analysis", {})
print("")
print("============================================================")
print(" JR-Bot Network Health Summary")
print("============================================================")
print(f"Instance:      {data.get('instance')}")
print(f"Script:        {data.get('script_version')}")
print(f"Health state:  {analysis.get('health_state')}")
print(f"Critical:      {analysis.get('critical_count')}")
print(f"Warnings:      {analysis.get('warning_count')}")
print("")

print("Findings:")
for item in analysis.get("findings", []):
    print(f"- [{item.get('level')}] {item.get('code')}: {item.get('message')}")

print("")
print("Recommendations:")
for item in analysis.get("recommendations", []):
    print(f"- [{item.get('level')}] {item.get('code')}: {item.get('message')}")
    if item.get("action"):
        print(f"  Action: {item.get('action')}")

print("============================================================")
print("")
PY
fi

UPLOAD_SUCCESS="false"

if [[ -n "$PUSH_URL" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        die "curl wird fÃƒÂ¼r den Upload benÃƒÂ¶tigt."
    fi

    if [[ -z "$TOKEN" ]]; then
        if [[ -e /dev/tty ]]; then
            read -rsp "OPSCON Network Health Audit-Token eingeben: " TOKEN </dev/tty
            echo >&2
        fi
    fi

    if [[ -z "$TOKEN" ]]; then
        die "Kein OPSCON Audit-Token vorhanden. Upload abgebrochen."
    fi

    RESPONSE_FILE="$(mktemp /tmp/audit_jr-bot-network-health-upload-response.XXXXXX.txt)"
    CURL_CONFIG="$(mktemp /tmp/audit_jr-bot-network-health-curl.XXXXXX.conf)"
    chmod 600 "$RESPONSE_FILE" "$CURL_CONFIG" 2>/dev/null || true

    info "Sende Network-Health-Audit JSON an OPSCON als Datei-Upload..."

    cat > "$CURL_CONFIG" <<EOF
fail
show-error
silent
location
connect-timeout = 10
max-time = 60
request = "POST"
output = "$RESPONSE_FILE"
write-out = "%{http_code}"
header = "X-OPSCON-INGEST-TOKEN: ${TOKEN}"
form = "instance=${INSTANCE_LOWER}"
form = "mode=${MODE}"
form = "audit_file=@${OUTPUT_FILE};type=application/json"
url = "${PUSH_URL}"
EOF

    HTTP_CODE="$(curl --config "$CURL_CONFIG" || true)"
    rm -f "$CURL_CONFIG"

    if [[ "$HTTP_CODE" != "200" ]]; then
        error "Upload fehlgeschlagen. HTTP-Code: ${HTTP_CODE}"
        if [[ -s "$RESPONSE_FILE" ]]; then
            cat "$RESPONSE_FILE" >&2
            echo >&2
        fi
        rm -f "$RESPONSE_FILE" "$CURL_CONFIG" 2>/dev/null || true
        warn "Lokale Network-Health-Audit-Datei bleibt fÃƒÂ¼r Debugging erhalten: ${OUTPUT_FILE}"
        exit 1
    fi

    UPLOAD_SUCCESS="true"

    info "Upload erfolgreich."
    if [[ -s "$RESPONSE_FILE" ]]; then
        cat "$RESPONSE_FILE" >&2
        echo >&2
    fi

    rm -f "$RESPONSE_FILE" "$CURL_CONFIG" 2>/dev/null || true
fi

if [[ "$UPLOAD_SUCCESS" == "true" ]]; then
    if [[ "$KEEP_LOCAL" == "true" ]]; then
        info "Lokale Network-Health-Audit-Datei bleibt erhalten wegen --keep-local: ${OUTPUT_FILE}"
    elif [[ "$OUTPUT_FILE_USER_SET" == "true" ]]; then
        info "Lokale Network-Health-Audit-Datei bleibt erhalten wegen --output: ${OUTPUT_FILE}"
    else
        rm -f "$OUTPUT_FILE"
        info "Lokale temporÃƒÂ¤re Network-Health-Audit-Datei wurde nach erfolgreichem Upload gelÃƒÂ¶scht."
    fi
else
    info "Network health audit completed: ${OUTPUT_FILE}"
fi
