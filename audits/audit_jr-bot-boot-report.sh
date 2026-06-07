#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot / OPSCON – Boot Report Audit
# ==========================================================
#
# Script/Doc: audits/audit_jr-bot-boot-report.sh
# Project: JR-Bot / OPSCON
# Purpose: Create and upload a boot-time audit report for JR-Bot nodes.
# Job-Key: audit_jr-bot-boot-report
# Category: audit
# Dependencies: bash, python3, curl, systemctl, journalctl, iproute2, coreutils
# Security: Read-only diagnostics; secrets redacted; upload token read from env or config token file.
# Notes: Hybrid script for legacy GGB/DMR layouts and the new One-Liner target layout.
#
# ----------------------------------------------------------
# Purpose
# ----------------------------------------------------------
# Creates a boot-time diagnostic audit JSON after a Raspberry Pi
# or JR-Bot node restart.
#
# The report is stored locally first under:
#   <bot-path>/reports/pending/
#
# If network/upload is available, all pending boot report audit
# files are uploaded to OPSCON and deleted locally after a
# successful upload.
#
# If upload fails, reports remain pending and are retried on the
# next successful run.
#
# ----------------------------------------------------------
# Compatibility
# ----------------------------------------------------------
# Supported profiles:
#   legacy  - older GGB/DMR style, e.g. /home/ggb/bots/ggb
#   target  - new One-Liner style, e.g. /opt/bots/trx
#   hybrid  - transitional layout with both legacy and target markers
#   unknown - path exists, but no clear profile markers detected
#
# Supported modes:
#   auto, legacy, target, hybrid, migrate, test, boot
#
# The script auto-detects the profile by default. Explicit --mode
# values are still preserved in the JSON as mode_requested.
#
# ==========================================================

SCRIPT_VERSION="0.2.0"
SCHEMA_VERSION="jrbot-boot-report-audit-v1"

# ----------------------------------------------------------
# Defaults
# ----------------------------------------------------------

INSTANCE=""
INSTALL_PATH=""
MODE="auto"

PUSH_URL="https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php"
TOKEN="${REPORT_UPLOAD_TOKEN:-}"

KEEP_LOCAL="false"
NO_UPLOAD="false"
PRINT_SUMMARY="false"
PRINT_JSON="false"

WIFI_INTERFACE="wlan0"
ETH_INTERFACE="eth0"

MAX_JOURNAL_LINES="120"
MAX_TEXT_CHARS="16000"

# ----------------------------------------------------------
# Output helpers
# ----------------------------------------------------------

info() {
    echo "[INFO] $*" >&2
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

usage() {
    cat <<'EOF'
JR-Bot Boot Report

Usage:
  audit_jr-bot-boot-report.sh [options]

Options:
  --instance <name>       Bot instance, e.g. ggb, dmr, trx
  --path <bot-path>       Bot base path, e.g. /home/ggb/bots/ggb or /opt/bots/trx
  --legacy                Shortcut for --mode legacy
  --mode <mode>           Mode marker: auto, legacy, target, hybrid, migrate, test, boot
  --push-url <url>        OPSCON boot report audit ingest endpoint
  --token <token>         Report upload token
  --no-upload             Only create local pending report, do not upload
  --keep-local            Keep local report even after successful upload
  --print-summary         Print compact summary
  --print-json            Print full report JSON
  --wifi-iface <iface>    Wi-Fi interface, default wlan0
  --eth-iface <iface>     Ethernet interface, default eth0
  -h, --help              Show this help

Environment:
  REPORT_UPLOAD_TOKEN     Optional upload token

Default behavior:
  - Creates a report under <bot-path>/reports/pending/
  - Attempts to upload all pending reports
  - Deletes uploaded reports locally after successful upload
  - Keeps reports locally if upload fails

Examples:
  ./audit_jr-bot-boot-report.sh --instance ggb --path /home/ggb/bots/ggb --mode auto --token <TOKEN> --print-summary

  ./audit_jr-bot-boot-report.sh --instance trx --path /opt/bots/trx --mode target --token <TOKEN> --print-summary

  REPORT_UPLOAD_TOKEN=<TOKEN> ./audit_jr-bot-boot-report.sh --print-summary
EOF
}

# ----------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --instance)
            INSTANCE="${2:-}"
            shift 2
            ;;
        --path)
            INSTALL_PATH="${2:-}"
            shift 2
            ;;
        --legacy)
            MODE="auto"
            shift
            ;;
        --mode)
            MODE="${2:-legacy}"
            shift 2
            ;;
        --push-url)
            PUSH_URL="${2:-}"
            shift 2
            ;;
        --token)
            TOKEN="${2:-}"
            shift 2
            ;;
        --no-upload)
            NO_UPLOAD="true"
            shift
            ;;
        --keep-local)
            KEEP_LOCAL="true"
            shift
            ;;
        --print-summary)
            PRINT_SUMMARY="true"
            shift
            ;;
        --print-json)
            PRINT_JSON="true"
            shift
            ;;
        --wifi-iface)
            WIFI_INTERFACE="${2:-wlan0}"
            shift 2
            ;;
        --eth-iface)
            ETH_INTERFACE="${2:-eth0}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unbekannter Parameter: $1"
            ;;
    esac
done

# ----------------------------------------------------------
# Auto-detect install path / instance
# ----------------------------------------------------------

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

if [[ -z "$INSTALL_PATH" ]]; then
    # Expected:
    #   <bot-path>/audits/audit_jr-bot-boot-report.sh
    INSTALL_PATH="$(dirname "$SCRIPT_DIR")"
fi

if [[ "$INSTALL_PATH" == "~/"* ]]; then
    INSTALL_PATH="${HOME}/${INSTALL_PATH#~/}"
fi

INSTALL_PATH="$(readlink -f "$INSTALL_PATH" 2>/dev/null || realpath "$INSTALL_PATH")"

if [[ -z "$INSTANCE" ]]; then
    INSTANCE="$(basename "$INSTALL_PATH" | tr '[:upper:]' '[:lower:]')"
fi

INSTANCE="$(echo "$INSTANCE" | tr '[:upper:]' '[:lower:]')"

if ! [[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    die "Ungültiger Instanzname: $INSTANCE"
fi

if [[ ! -d "$INSTALL_PATH" ]]; then
    die "Bot-Pfad existiert nicht: $INSTALL_PATH"
fi

REPORT_DIR="$INSTALL_PATH/reports"
PENDING_DIR="$REPORT_DIR/pending"

mkdir -p "$PENDING_DIR"

# Optional token file support.
# Order:
#   1) <bot-path>/config/audit_boot_report.token
#   2) <bot-path>/config/boot_report_upload.token
#   3) <bot-path>/config/report_upload.token       # legacy-compatible fallback
# chmod 600 recommended.
for token_file in \
    "$INSTALL_PATH/config/audit_boot_report.token" \
    "$INSTALL_PATH/config/boot_report_upload.token" \
    "$INSTALL_PATH/config/report_upload.token"
do
    if [[ -z "$TOKEN" && -f "$token_file" ]]; then
        TOKEN="$(tr -d '[:space:]' < "$token_file" || true)"
    fi
done


# ----------------------------------------------------------
# Profile detection
# ----------------------------------------------------------

detect_profile() {
    local path="$1"

    local legacy_score=0
    local target_score=0

    # Legacy / transitional markers
    [[ -d "$path/maintenance" ]] && legacy_score=$((legacy_score + 3))
    [[ -f "$path/maintenance/jrbot_boot_report.sh" ]] && legacy_score=$((legacy_score + 3))
    [[ -f "$path/.env" ]] && legacy_score=$((legacy_score + 1))
    [[ "$path" == /home/*/bots/* ]] && legacy_score=$((legacy_score + 1))

    # New One-Liner target markers
    [[ -d "$path/audits" ]] && target_score=$((target_score + 3))
    [[ -f "$path/audits/audit_jr-bot-boot-report.sh" ]] && target_score=$((target_score + 3))
    [[ -d "$path/scripts" ]] && target_score=$((target_score + 2))
    [[ -f "$path/src/job_runner.py" ]] && target_score=$((target_score + 2))
    [[ -f "$path/config/config.ini" ]] && target_score=$((target_score + 2))
    [[ "$path" == /opt/bots/* ]] && target_score=$((target_score + 2))

    if [[ "$legacy_score" -gt 0 && "$target_score" -gt 0 ]]; then
        echo "hybrid"
    elif [[ "$target_score" -gt 0 ]]; then
        echo "target"
    elif [[ "$legacy_score" -gt 0 ]]; then
        echo "legacy"
    else
        echo "unknown"
    fi
}

MODE_REQUESTED="$(echo "$MODE" | tr '[:upper:]' '[:lower:]')"
case "$MODE_REQUESTED" in
    auto|legacy|target|hybrid|migrate|test|boot)
        ;;
    one-liner|oneliner)
        MODE_REQUESTED="target"
        ;;
    *)
        warn "Unbekannter Modus '$MODE_REQUESTED'. Fallback auf auto."
        MODE_REQUESTED="auto"
        ;;
esac

PROFILE_DETECTED="$(detect_profile "$INSTALL_PATH")"

if [[ "$MODE_REQUESTED" == "auto" || "$MODE_REQUESTED" == "boot" || "$MODE_REQUESTED" == "test" ]]; then
    INSTALL_PROFILE="$PROFILE_DETECTED"
elif [[ "$MODE_REQUESTED" == "migrate" ]]; then
    INSTALL_PROFILE="hybrid"
else
    INSTALL_PROFILE="$MODE_REQUESTED"
fi

# For JSON compatibility, MODE keeps the requested mode.
MODE="$MODE_REQUESTED"


# ----------------------------------------------------------
# Basic command checks
# ----------------------------------------------------------

if ! command -v python3 >/dev/null 2>&1; then
    die "python3 wird benötigt."
fi

# ----------------------------------------------------------
# Create current report
# ----------------------------------------------------------

TS_FILE="$(date -u +"%Y%m%d_%H%M%S")"
REPORT_FILE="$PENDING_DIR/audit_jr-bot-boot-report-${INSTANCE}-${TS_FILE}.json"

export JR_BOOT_REPORT_SCHEMA="$SCHEMA_VERSION"
export JR_BOOT_REPORT_SCRIPT_VERSION="$SCRIPT_VERSION"
export JR_BOOT_REPORT_INSTANCE="$INSTANCE"
export JR_BOOT_REPORT_MODE="$MODE"
export JR_BOOT_REPORT_MODE_REQUESTED="$MODE_REQUESTED"
export JR_BOOT_REPORT_PROFILE_DETECTED="$PROFILE_DETECTED"
export JR_BOOT_REPORT_INSTALL_PROFILE="$INSTALL_PROFILE"
export JR_BOOT_REPORT_CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export JR_BOOT_REPORT_INSTALL_PATH="$INSTALL_PATH"
export JR_BOOT_REPORT_REPORTS_PENDING_DIR="$PENDING_DIR"
export JR_BOOT_REPORT_WIFI_INTERFACE="$WIFI_INTERFACE"
export JR_BOOT_REPORT_ETH_INTERFACE="$ETH_INTERFACE"
export JR_BOOT_REPORT_MAX_JOURNAL_LINES="$MAX_JOURNAL_LINES"
export JR_BOOT_REPORT_MAX_TEXT_CHARS="$MAX_TEXT_CHARS"

python3 > "$REPORT_FILE" <<'PY'
from __future__ import annotations

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


SCHEMA = env("JR_BOOT_REPORT_SCHEMA")
SCRIPT_VERSION = env("JR_BOOT_REPORT_SCRIPT_VERSION")
INSTANCE = env("JR_BOOT_REPORT_INSTANCE")
MODE = env("JR_BOOT_REPORT_MODE")
MODE_REQUESTED = env("JR_BOOT_REPORT_MODE_REQUESTED", MODE)
PROFILE_DETECTED = env("JR_BOOT_REPORT_PROFILE_DETECTED", "unknown")
INSTALL_PROFILE = env("JR_BOOT_REPORT_INSTALL_PROFILE", PROFILE_DETECTED)
CREATED_AT_UTC = env("JR_BOOT_REPORT_CREATED_AT_UTC")
INSTALL_PATH = env("JR_BOOT_REPORT_INSTALL_PATH")
REPORTS_PENDING_DIR = env("JR_BOOT_REPORT_REPORTS_PENDING_DIR", str(Path(INSTALL_PATH) / "reports" / "pending"))
WIFI_IFACE = env("JR_BOOT_REPORT_WIFI_INTERFACE", "wlan0")
ETH_IFACE = env("JR_BOOT_REPORT_ETH_INTERFACE", "eth0")
MAX_JOURNAL_LINES = int(env("JR_BOOT_REPORT_MAX_JOURNAL_LINES", "120"))
MAX_TEXT_CHARS = int(env("JR_BOOT_REPORT_MAX_TEXT_CHARS", "16000"))


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
]


def redact_text(text: str) -> str:
    value = text
    for pattern in SENSITIVE_PATTERNS:
        value = pattern.sub(r'\1"<REDACTED>"', value)
    return value


def trim_text(text: str, max_chars: int = MAX_TEXT_CHARS) -> dict[str, Any]:
    text = redact_text(text or "")
    truncated = len(text) > max_chars
    if truncated:
        text = text[:max_chars] + "\n...[TRUNCATED]..."
    return {
        "content": text,
        "truncated": truncated,
        "max_chars": max_chars,
    }


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(args: list[str], timeout: int = 20, max_chars: int = MAX_TEXT_CHARS) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )

        stdout = trim_text(proc.stdout.strip(), max_chars)
        stderr = trim_text(proc.stderr.strip(), max_chars)

        return {
            "cmd": args,
            "available": True,
            "returncode": proc.returncode,
            "stdout": stdout["content"],
            "stdout_truncated": stdout["truncated"],
            "stderr": stderr["content"],
            "stderr_truncated": stderr["truncated"],
        }
    except FileNotFoundError:
        return {
            "cmd": args,
            "available": False,
            "returncode": None,
            "stdout": "",
            "stdout_truncated": False,
            "stderr": "command not found",
            "stderr_truncated": False,
        }
    except subprocess.TimeoutExpired as exc:
        stdout_raw = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr_raw = exc.stderr if isinstance(exc.stderr, str) else ""
        stdout = trim_text(stdout_raw.strip(), max_chars)
        stderr = trim_text(stderr_raw.strip(), max_chars)

        return {
            "cmd": args,
            "available": True,
            "returncode": 124,
            "stdout": stdout["content"],
            "stdout_truncated": stdout["truncated"],
            "stderr": stderr["content"] or f"timeout after {timeout}s",
            "stderr_truncated": stderr["truncated"],
        }
    except Exception as exc:
        return {
            "cmd": args,
            "available": True,
            "returncode": 999,
            "stdout": "",
            "stdout_truncated": False,
            "stderr": str(exc),
            "stderr_truncated": False,
        }


def read_file_limited(path: str, max_chars: int = 5000) -> dict[str, Any]:
    p = Path(path)

    result: dict[str, Any] = {
        "path": path,
        "exists": p.exists(),
        "readable": os.access(path, os.R_OK) if p.exists() else False,
        "content": "",
        "truncated": False,
        "error": "",
    }

    if not p.exists():
        return result

    if not p.is_file():
        result["error"] = "not a regular file"
        return result

    if not os.access(path, os.R_OK):
        result["error"] = "not readable"
        return result

    try:
        raw = p.read_bytes()
        text = raw.decode("utf-8", errors="replace")
        trimmed = trim_text(text, max_chars)
        result["content"] = trimmed["content"]
        result["truncated"] = trimmed["truncated"]
    except Exception as exc:
        result["error"] = str(exc)

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
        "description": "",
    }

    cmd = run_command(["systemctl", "show", unit, "--no-pager"] + [f"-p{x}" for x in props], timeout=10)

    if cmd["returncode"] == 0:
        kv: dict[str, str] = {}
        for line in cmd["stdout"].splitlines():
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
        result["description"] = kv.get("Description", "")
        result["exists"] = result["load_state"] not in ("", "not-found")

    result["show_command"] = cmd
    return result


def journal_for_unit(unit: str, boot: str = "0") -> dict[str, Any]:
    return run_command(
        ["journalctl", "-b", boot, "-u", unit, "--no-pager", "-n", str(MAX_JOURNAL_LINES)],
        timeout=20,
        max_chars=MAX_TEXT_CHARS,
    )


def service_name_candidates(instance: str) -> dict[str, str]:
    return {
        "template_timer": f"bot-runner@{instance}.timer",
        "template_service": f"bot-runner@{instance}.service",
        "boot_report_service": f"jrbot-boot-report@{instance}.service",
        "legacy_timer": f"{instance}-runner.timer",
        "legacy_service": f"{instance}-runner.service",
    }


def collect_host() -> dict[str, Any]:
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

    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "kernel": run_command(["uname", "-a"]).get("stdout", ""),
        "raspberry_pi_model": model,
        "memory_total_mb": mem_total_mb,
        "boot_time": run_command(["uptime", "-s"]).get("stdout", ""),
        "uptime_pretty": run_command(["uptime", "-p"]).get("stdout", ""),
        "boot_id": read_file_limited("/proc/sys/kernel/random/boot_id", 200).get("content", "").strip(),
        "os_release": read_file_limited("/etc/os-release", 4000),
    }


def collect_storage() -> dict[str, Any]:
    root_df = run_command(["df", "-hT", "/"], timeout=10)
    bot_df = run_command(["df", "-hT", INSTALL_PATH], timeout=10)

    lsblk = run_command([
        "lsblk",
        "-J",
        "-o",
        "NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL,RM,RO,TRAN"
    ], timeout=10)

    return {
        "root_df": root_df,
        "bot_df": bot_df,
        "lsblk_json": lsblk,
    }


def collect_network() -> dict[str, Any]:
    ip_addr_json = run_command(["ip", "-j", "addr", "show"], timeout=10)
    ip_route = run_command(["ip", "route"], timeout=10)

    ipv4_addresses = parse_ipv4_addresses(ip_addr_json.get("stdout", ""))
    default_route = parse_default_route(ip_route.get("stdout", ""))

    gateway = default_route.get("gateway") or ""

    gateway_ping = {}
    if gateway:
        gateway_ping = run_command(["ping", "-c", "2", "-W", "2", gateway], timeout=10)

    dns_google = run_command(["getent", "hosts", "google.com"], timeout=10)

    return {
        "hostname_I": run_command(["hostname", "-I"], timeout=10),
        "ip_addr_json": ip_addr_json,
        "ipv4_addresses": ipv4_addresses,
        "ip_route": ip_route,
        "default_route": default_route,
        "ip_route_get_1_1_1_1": run_command(["ip", "route", "get", "1.1.1.1"], timeout=10),
        "gateway_ping": gateway_ping,
        "dns_google": dns_google,
        "wifi": {
            "interface": WIFI_IFACE,
            "ip_link": run_command(["ip", "link", "show", WIFI_IFACE], timeout=10),
            "iw_link": run_command(["iw", "dev", WIFI_IFACE, "link"], timeout=10),
            "wpa_cli_status": run_command(["wpa_cli", "-i", WIFI_IFACE, "status"], timeout=10),
            "rfkill": run_command(["rfkill", "list"], timeout=10),
        },
        "ethernet": {
            "interface": ETH_IFACE,
            "ip_link": run_command(["ip", "link", "show", ETH_IFACE], timeout=10),
        },
        "resolv_conf": read_file_limited("/etc/resolv.conf", 3000),
    }


def collect_services(instance: str) -> dict[str, Any]:
    units = [
        "systemd-networkd.service",
        "NetworkManager.service",
        "wpa_supplicant.service",
        f"wpa_supplicant@{WIFI_IFACE}.service",
        "dhcpcd.service",
        "systemd-resolved.service",
        "networking.service",
        "ssh.service",
    ]

    candidates = service_name_candidates(instance)
    units.extend(candidates.values())

    services: dict[str, Any] = {}
    for unit in units:
        services[unit] = systemctl_show(unit)

    return {
        "unit_candidates": candidates,
        "units": services,
    }


def collect_journals(instance: str) -> dict[str, Any]:
    candidates = service_name_candidates(instance)

    unit_list = [
        "systemd-networkd.service",
        "NetworkManager.service",
        "wpa_supplicant.service",
        f"wpa_supplicant@{WIFI_IFACE}.service",
        "dhcpcd.service",
        "ssh.service",
        candidates["template_timer"],
        candidates["template_service"],
        candidates["legacy_timer"],
        candidates["legacy_service"],
    ]

    current_boot: dict[str, Any] = {}
    previous_boot: dict[str, Any] = {}

    for unit in unit_list:
        current_boot[unit] = journal_for_unit(unit, "0")
        previous_boot[unit] = journal_for_unit(unit, "-1")

    return {
        "list_boots": run_command(["journalctl", "--list-boots", "--no-pager"], timeout=10, max_chars=12000),
        "current_boot_warnings": run_command(["journalctl", "-b", "0", "-p", "warning", "--no-pager", "-n", str(MAX_JOURNAL_LINES)], timeout=20),
        "previous_boot_warnings": run_command(["journalctl", "-b", "-1", "-p", "warning", "--no-pager", "-n", str(MAX_JOURNAL_LINES)], timeout=20),
        "current_boot_units": current_boot,
        "previous_boot_units": previous_boot,
    }


def build_summary(data: dict[str, Any]) -> dict[str, Any]:
    network = data.get("network", {})
    services = data.get("services", {}).get("units", {})

    ipv4s = network.get("ipv4_addresses", [])
    default_route = network.get("default_route", {})

    gateway_ping = network.get("gateway_ping", {})
    dns_google = network.get("dns_google", {})

    ssh = services.get("ssh.service", {})

    candidates = data.get("services", {}).get("unit_candidates", {})
    template_timer = services.get(candidates.get("template_timer", ""), {})
    legacy_timer = services.get(candidates.get("legacy_timer", ""), {})

    bot_timer_active = (
        template_timer.get("active_state") == "active"
        or legacy_timer.get("active_state") == "active"
    )

    checks = {
        "has_ipv4": bool(ipv4s),
        "has_default_route": bool(default_route.get("present")),
        "gateway_ping_ok": gateway_ping.get("returncode") == 0 if gateway_ping else False,
        "dns_ok": dns_google.get("returncode") == 0,
        "ssh_active": ssh.get("active_state") == "active",
        "bot_timer_active": bot_timer_active,
    }

    health_state = "ok"
    if not checks["has_ipv4"] or not checks["has_default_route"]:
        health_state = "critical"
    elif not checks["gateway_ping_ok"] or not checks["dns_ok"] or not checks["bot_timer_active"]:
        health_state = "warning"

    return {
        "health_state": health_state,
        "checks": checks,
    }


data: dict[str, Any] = {
    "schema": SCHEMA,
    "script_version": SCRIPT_VERSION,
    "instance": INSTANCE,
    "mode": MODE,
    "mode_requested": MODE_REQUESTED,
    "profile_detected": PROFILE_DETECTED,
    "install_profile": INSTALL_PROFILE,
    "compatibility": {
        "legacy_supported": True,
        "target_supported": True,
        "hybrid_supported": True,
    },
    "created_at_utc": CREATED_AT_UTC,
    "security": {
        "read_only": True,
        "secrets_redacted": True,
        "secret_values_included": False,
    },
    "bot_context": {
        "install_path": INSTALL_PATH,
        "install_path_exists": Path(INSTALL_PATH).exists(),
        "audits_path": str(Path(INSTALL_PATH) / "audits"),
        "audits_path_exists": (Path(INSTALL_PATH) / "audits").exists(),
        "scripts_path": str(Path(INSTALL_PATH) / "scripts"),
        "scripts_path_exists": (Path(INSTALL_PATH) / "scripts").exists(),
        "src_job_runner_path": str(Path(INSTALL_PATH) / "src" / "job_runner.py"),
        "src_job_runner_exists": (Path(INSTALL_PATH) / "src" / "job_runner.py").exists(),
        "config_ini_path": str(Path(INSTALL_PATH) / "config" / "config.ini"),
        "config_ini_exists": (Path(INSTALL_PATH) / "config" / "config.ini").exists(),
        "legacy_maintenance_path": str(Path(INSTALL_PATH) / "maintenance"),
        "legacy_maintenance_exists": (Path(INSTALL_PATH) / "maintenance").exists(),
        "reports_path": str(Path(INSTALL_PATH) / "reports"),
        "reports_pending_dir": REPORTS_PENDING_DIR,
        "reports_pending_dir_exists": Path(REPORTS_PENDING_DIR).exists(),
    },
    "commands_available": {
        "systemctl": command_exists("systemctl"),
        "journalctl": command_exists("journalctl"),
        "ip": command_exists("ip"),
        "iw": command_exists("iw"),
        "wpa_cli": command_exists("wpa_cli"),
        "rfkill": command_exists("rfkill"),
        "curl": command_exists("curl"),
        "getent": command_exists("getent"),
        "lsblk": command_exists("lsblk"),
        "df": command_exists("df"),
    },
    "host": collect_host(),
    "storage": collect_storage(),
    "network": collect_network(),
    "services": collect_services(INSTANCE),
    "journals": collect_journals(INSTANCE),
}

data["summary"] = build_summary(data)

print(json.dumps(data, indent=2, ensure_ascii=False))
PY

if ! python3 -m json.tool "$REPORT_FILE" >/dev/null 2>&1; then
    die "Erzeugter Boot-Report ist ungültiges JSON: $REPORT_FILE"
fi

info "Boot-Report-Audit erstellt: $REPORT_FILE"

# ----------------------------------------------------------
# Print options
# ----------------------------------------------------------

if [[ "$PRINT_JSON" == "true" ]]; then
    cat "$REPORT_FILE"
fi

if [[ "$PRINT_SUMMARY" == "true" ]]; then
    python3 - "$REPORT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

summary = data.get("summary", {})
checks = summary.get("checks", {})

print("")
print("============================================================")
print(" JR-Bot Boot Report Audit Summary")
print("============================================================")
print(f"Instance:      {data.get('instance')}")
print(f"Script:        {data.get('script_version')}")
print(f"Mode:          {data.get('mode_requested')}")
print(f"Profile:       {data.get('profile_detected')}")
print(f"Install:       {data.get('install_profile')}")
print(f"Created UTC:   {data.get('created_at_utc')}")
print(f"Health state:  {summary.get('health_state')}")
print("")
print("Checks:")
for key, value in checks.items():
    print(f"- {key}: {value}")
print("============================================================")
print("")
PY
fi

# ----------------------------------------------------------
# Upload helper
# ----------------------------------------------------------

upload_one_report() {
    local file="$1"

    if [[ "$NO_UPLOAD" == "true" ]]; then
        warn "Upload deaktiviert (--no-upload). Report bleibt lokal: $file"
        return 1
    fi

    if [[ -z "$PUSH_URL" ]]; then
        warn "Keine Push-URL gesetzt. Report bleibt lokal: $file"
        return 1
    fi

    if [[ -z "$TOKEN" ]]; then
        warn "Kein REPORT_UPLOAD_TOKEN vorhanden. Report bleibt lokal: $file"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl nicht verfügbar. Report bleibt lokal: $file"
        return 1
    fi

    local response_file
    response_file="$(mktemp /tmp/jrbot-boot-report-upload-response.XXXXXX.txt)"

    info "Sende Boot-Report-Audit an OPSCON: $(basename "$file")"

    local http_code
    http_code="$(curl -fsSL \
        -w "%{http_code}" \
        -o "$response_file" \
        -X POST \
        -F "token=${TOKEN}" \
        -F "instance=${INSTANCE}" \
        -F "mode=${MODE_REQUESTED}" \
        -F "audit_file=@${file};type=application/json" \
        "$PUSH_URL" || true)"

    if [[ "$http_code" != "200" ]]; then
        warn "Upload fehlgeschlagen für $(basename "$file"). HTTP-Code: ${http_code}"

        if [[ -s "$response_file" ]]; then
            cat "$response_file" >&2
            echo >&2
        fi

        rm -f "$response_file"
        return 1
    fi

    info "Upload erfolgreich für $(basename "$file")."

    if [[ -s "$response_file" ]]; then
        cat "$response_file" >&2
        echo >&2
    fi

    rm -f "$response_file"

    if [[ "$KEEP_LOCAL" == "true" ]]; then
        info "Lokaler Report bleibt erhalten wegen --keep-local: $file"
    else
        rm -f "$file"
        info "Lokaler Report wurde nach erfolgreichem Upload gelöscht: $file"
    fi

    return 0
}

# ----------------------------------------------------------
# Upload all pending reports
# ----------------------------------------------------------

upload_pending_reports() {
    shopt -s nullglob

    local files=("$PENDING_DIR"/audit_jr-bot-boot-report-"$INSTANCE"-*.json "$PENDING_DIR"/jrbot-boot-report-"$INSTANCE"-*.json)

    if [[ ${#files[@]} -eq 0 ]]; then
        info "Keine pending Boot-Reports vorhanden."
        return 0
    fi

    local success_count=0
    local fail_count=0

    for file in "${files[@]}"; do
        if upload_one_report "$file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    info "Upload-Zusammenfassung: success=${success_count}, failed=${fail_count}"

    if [[ "$fail_count" -gt 0 ]]; then
        return 1
    fi

    return 0
}

upload_pending_reports || true

info "Boot report audit completed."