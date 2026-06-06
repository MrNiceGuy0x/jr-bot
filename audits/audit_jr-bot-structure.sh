#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Structure Audit
# Version: 0.1.6
# ==========================================================
#
# Purpose:
#   Read-only audit script for JR-Bot Raspberry Pi nodes.
#
#   This script collects:
#   - Host / Raspberry Pi / OS information
#   - Network information, local IP, gateway, SSH status
#   - Storage information, SD/root filesystem, bot filesystem, block devices
#   - Bot directory structure
#   - Runtime structure including scripts/audits/reports/docs
#   - Legacy vs template profile detection
#   - Structure deviations from the current One-Liner target layout
#   - File existence, permissions, owner/group
#   - config.ini / .env key presence only, without secret values
#   - Python / venv status
#   - systemd template and instance status
#   - Optional upload to OPSCON via HTTPS POST multipart file upload
#
# Security:
#   - No secrets are printed
#   - No config values are uploaded
#   - Only key presence is reported
#   - The script does not modify the system
#
# Local file behavior:
#   - Default output is a temporary file under /tmp.
#   - If upload succeeds and no --keep-local was set, the temp file is deleted.
#   - If --output <file> is set, the file is kept.
#   - If --keep-local is set, the file is kept.
#   - If upload fails, the file is kept for debugging.
#
# New OPSCON endpoint:
#   https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
#
# Examples:
#   ./audit_jr-bot-structure.sh --instance trx --path /opt/bots/trx
#
#   ./audit_jr-bot-structure.sh --instance dmr --path ~/bots/DMR --legacy
#
#   ./audit_jr-bot-structure.sh \
#     --instance dmr \
#     --path ~/bots/DMR \
#     --legacy \
#     --push-url https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php \
#     --token <TOKEN>
#
# ==========================================================

SCRIPT_VERSION="0.1.6"
SCHEMA_VERSION="jrbot-structure-audit-v1"

INSTANCE=""
INSTALL_PATH=""
MODE="target"
PUSH_URL=""
TOKEN=""
OUTPUT_FILE=""
OUTPUT_FILE_USER_SET="false"
PRINT_JSON="false"
KEEP_LOCAL="false"
TREE_MAX_DEPTH="3"
TREE_MAX_ITEMS="300"

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
JR-Bot Structure Audit

Usage:
  audit_jr-bot-structure.sh --instance <name> --path <bot-path> [options]

Required:
  --instance <name>       Bot instance name, e.g. trx, dmr, ggb
  --path <bot-path>       Bot install path, e.g. /opt/bots/trx or ~/bots/DMR

Options:
  --legacy                Legacy mode for older DMR/GGB structures
  --push-url <url>        Optional OPSCON structure ingest endpoint
  --token <token>         Optional OPSCON audit token
  --output <file>         Optional output JSON file. File will be kept.
  --keep-local            Keep generated local JSON after successful upload
  --print-json            Print JSON to stdout
  --tree-depth <n>        Runtime tree snapshot depth. Default: 3
  -h, --help              Show this help

Examples:
  ./audit_jr-bot-structure.sh --instance trx --path /opt/bots/trx

  ./audit_jr-bot-structure.sh --instance dmr --path ~/bots/DMR --legacy

  ./audit_jr-bot-structure.sh \
    --instance dmr \
    --path ~/bots/DMR \
    --legacy \
    --push-url https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php \
    --token <TOKEN>
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
            MODE="legacy"
            shift
            ;;
        --push-url)
            PUSH_URL="${2:-}"
            shift 2
            ;;
        --token)
            TOKEN="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="${2:-}"
            OUTPUT_FILE_USER_SET="true"
            shift 2
            ;;
        --keep-local)
            KEEP_LOCAL="true"
            shift
            ;;
        --print-json)
            PRINT_JSON="true"
            shift
            ;;
        --tree-depth)
            TREE_MAX_DEPTH="${2:-3}"
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

if [[ -z "$INSTANCE" ]]; then
    usage
    die "Parameter fehlt: --instance"
fi

if [[ -z "$INSTALL_PATH" ]]; then
    usage
    die "Parameter fehlt: --path"
fi

if [[ "$INSTALL_PATH" == "~/"* ]]; then
    INSTALL_PATH="${HOME}/${INSTALL_PATH#~/}"
fi

INSTANCE_LOWER="$(echo "$INSTANCE" | tr '[:upper:]' '[:lower:]')"

if ! [[ "$INSTANCE_LOWER" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    die "UngÃƒÂ¼ltiger Instanzname: $INSTANCE"
fi

if ! [[ "$TREE_MAX_DEPTH" =~ ^[0-9]+$ ]]; then
    die "--tree-depth muss eine Zahl sein."
fi

EXPECTED_USER="$INSTANCE_LOWER"

if [[ -z "$OUTPUT_FILE" ]]; then
    TS_FILE="$(date -u +"%Y%m%d_%H%M%S")"
    OUTPUT_FILE="/tmp/audit_jr-bot-structure-${INSTANCE_LOWER}-${TS_FILE}.json"
fi

if ! command -v python3 >/dev/null 2>&1; then
    die "python3 wird benÃƒÂ¶tigt, um die Audit-JSON sicher zu erzeugen."
fi

# ----------------------------------------------------------
# Export collector values
# ----------------------------------------------------------

export JR_STRUCT_AUDIT_SCRIPT_VERSION="$SCRIPT_VERSION"
export JR_STRUCT_AUDIT_SCHEMA_VERSION="$SCHEMA_VERSION"
export JR_STRUCT_AUDIT_INSTANCE="$INSTANCE_LOWER"
export JR_STRUCT_AUDIT_MODE="$MODE"
export JR_STRUCT_AUDIT_CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export JR_STRUCT_AUDIT_INSTALL_PATH="$INSTALL_PATH"
export JR_STRUCT_AUDIT_EXPECTED_USER="$EXPECTED_USER"
export JR_STRUCT_AUDIT_TREE_MAX_DEPTH="$TREE_MAX_DEPTH"
export JR_STRUCT_AUDIT_TREE_MAX_ITEMS="$TREE_MAX_ITEMS"

# ----------------------------------------------------------
# Generate JSON via Python
# ----------------------------------------------------------

python3 > "$OUTPUT_FILE" <<'PY'
from __future__ import annotations

import json
import os
import platform
import pwd
import grp
import re
import shutil
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


SCRIPT_VERSION = env("JR_STRUCT_AUDIT_SCRIPT_VERSION")
SCHEMA_VERSION = env("JR_STRUCT_AUDIT_SCHEMA_VERSION")
INSTANCE = env("JR_STRUCT_AUDIT_INSTANCE")
MODE = env("JR_STRUCT_AUDIT_MODE")
CREATED_AT_UTC = env("JR_STRUCT_AUDIT_CREATED_AT_UTC")
INSTALL_PATH = Path(env("JR_STRUCT_AUDIT_INSTALL_PATH")).expanduser()
EXPECTED_USER = env("JR_STRUCT_AUDIT_EXPECTED_USER")
TREE_MAX_DEPTH = int(env("JR_STRUCT_AUDIT_TREE_MAX_DEPTH", "3"))
TREE_MAX_ITEMS = int(env("JR_STRUCT_AUDIT_TREE_MAX_ITEMS", "300"))


def command_exists(cmd: str) -> bool:
    return shutil.which(cmd) is not None


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
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
        }
    except FileNotFoundError:
        return {
            "cmd": args,
            "available": False,
            "returncode": None,
            "stdout": "",
            "stderr": "command not found",
        }
    except subprocess.TimeoutExpired:
        return {
            "cmd": args,
            "available": True,
            "returncode": 124,
            "stdout": "",
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


def file_meta(path: Path) -> dict[str, Any]:
    exists = path.exists()
    is_symlink = path.is_symlink()

    result: dict[str, Any] = {
        "path": str(path),
        "exists": exists,
        "is_file": path.is_file() if exists else False,
        "is_dir": path.is_dir() if exists else False,
        "is_symlink": is_symlink,
        "readlink": "",
        "realpath": "",
        "permissions": "",
        "owner": "",
        "group": "",
        "size_bytes": None,
        "modified_at_utc": "",
    }

    if not exists and not is_symlink:
        return result

    try:
        st = path.lstat()
        result["permissions"] = oct(st.st_mode & 0o777)[2:]
        result["size_bytes"] = st.st_size

        try:
            result["owner"] = pwd.getpwuid(st.st_uid).pw_name
        except Exception:
            result["owner"] = str(st.st_uid)

        try:
            result["group"] = grp.getgrgid(st.st_gid).gr_name
        except Exception:
            result["group"] = str(st.st_gid)

        result["modified_at_utc"] = datetime.fromtimestamp(
            st.st_mtime,
            timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        pass

    if is_symlink:
        try:
            result["readlink"] = os.readlink(path)
            result["realpath"] = os.path.realpath(path)
        except Exception:
            pass
    else:
        try:
            result["realpath"] = str(path.resolve())
        except Exception:
            pass

    return result


def key_present(path: Path, key: str) -> bool:
    if not path.is_file():
        return False

    try:
        with path.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if re.match(rf"^\s*{re.escape(key)}\s*=", line):
                    return True
    except Exception:
        return False

    return False


def user_info(username: str) -> dict[str, Any]:
    try:
        p = pwd.getpwnam(username)

        return {
            "expected_user": username,
            "exists": True,
            "uid": str(p.pw_uid),
            "gid": str(p.pw_gid),
        }
    except KeyError:
        return {
            "expected_user": username,
            "exists": False,
            "uid": "",
            "gid": "",
        }


def read_os_release() -> dict[str, str]:
    result = {
        "PRETTY_NAME": "",
        "ID": "",
        "VERSION_ID": "",
        "VERSION_CODENAME": "",
    }

    path = Path("/etc/os-release")
    if not path.is_file():
        return result

    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line:
                continue

            k, v = line.split("=", 1)
            v = v.strip().strip('"')

            if k in result:
                result[k] = v
    except Exception:
        pass

    return result


def read_raspberry_model() -> str:
    for raw_path in ["/proc/device-tree/model", "/sys/firmware/devicetree/base/model"]:
        path = Path(raw_path)

        if path.is_file():
            try:
                return path.read_bytes().replace(b"\x00", b"").decode("utf-8", errors="replace")
            except Exception:
                pass

    return ""


def read_cpu_info() -> dict[str, str]:
    model = ""
    revision = ""

    path = Path("/proc/cpuinfo")
    if not path.is_file():
        return {
            "cpu_model": "",
            "cpu_revision": "",
        }

    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if ":" not in line:
                continue

            k, v = [x.strip() for x in line.split(":", 1)]

            if k.lower() in ("model name", "hardware") and not model:
                model = v

            if k.lower() == "revision":
                revision = v
    except Exception:
        pass

    return {
        "cpu_model": model,
        "cpu_revision": revision,
    }


def memory_total_mb() -> int | None:
    path = Path("/proc/meminfo")
    if not path.is_file():
        return None

    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("MemTotal:"):
                parts = line.split()

                if len(parts) >= 2:
                    return int(int(parts[1]) / 1024)
    except Exception:
        pass

    return None


def systemctl_value(unit: str, prop: str) -> str:
    if not command_exists("systemctl"):
        return ""

    cmd = run_command(["systemctl", "show", unit, "-p", prop, "--value"], timeout=10)

    if cmd["returncode"] != 0:
        return ""

    return cmd["stdout"].strip()


def systemd_bool(unit: str, action: str) -> bool:
    if not command_exists("systemctl"):
        return False

    if action == "is-enabled":
        cmd = run_command(["systemctl", "is-enabled", unit], timeout=10)
        return cmd["returncode"] == 0

    if action == "is-active":
        cmd = run_command(["systemctl", "is-active", unit], timeout=10)
        return cmd["returncode"] == 0

    return False


def collect_network() -> dict[str, Any]:
    hostname_i = ""

    if command_exists("hostname"):
        hostname_i = run_command(["hostname", "-I"], timeout=10)["stdout"].strip()

    all_ipv4: list[str] = []
    primary_ipv4 = ""
    primary_interface = ""
    default_gateway = ""
    default_route = ""

    if command_exists("ip"):
        addr_cmd = run_command(["ip", "-o", "-4", "addr", "show", "scope", "global"], timeout=10)

        if addr_cmd["returncode"] == 0:
            for line in addr_cmd["stdout"].splitlines():
                parts = line.split()

                if len(parts) >= 4:
                    all_ipv4.append(parts[3].split("/")[0])

        route_cmd = run_command(["ip", "route"], timeout=10)

        if route_cmd["returncode"] == 0:
            for line in route_cmd["stdout"].splitlines():
                if line.startswith("default "):
                    default_route = line
                    parts = line.split()

                    for i, part in enumerate(parts):
                        if part == "via" and i + 1 < len(parts):
                            default_gateway = parts[i + 1]

                        if part == "dev" and i + 1 < len(parts):
                            primary_interface = parts[i + 1]

                    break

        route_get = run_command(["ip", "route", "get", "1.1.1.1"], timeout=10)

        if route_get["returncode"] == 0:
            parts = route_get["stdout"].split()

            for i, part in enumerate(parts):
                if part == "src" and i + 1 < len(parts):
                    primary_ipv4 = parts[i + 1]
                    break

    if not primary_ipv4 and all_ipv4:
        primary_ipv4 = all_ipv4[0]

    ssh_load_state = systemctl_value("ssh", "LoadState")
    ssh_active_state = systemctl_value("ssh", "ActiveState")
    ssh_sub_state = systemctl_value("ssh", "SubState")

    return {
        "hostname_i": hostname_i,
        "all_ipv4": all_ipv4,
        "primary_ipv4": primary_ipv4,
        "primary_interface": primary_interface,
        "default_gateway": default_gateway,
        "default_route": default_route,
        "ssh": {
            "service_exists": ssh_load_state not in ("", "not-found"),
            "enabled": systemd_bool("ssh", "is-enabled"),
            "active": systemd_bool("ssh", "is-active"),
            "load_state": ssh_load_state,
            "active_state": ssh_active_state,
            "sub_state": ssh_sub_state,
        },
    }


def parse_df_path(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": str(path),
        "available": False,
        "error": "",
        "filesystem": "",
        "type": "",
        "mountpoint": "",
        "size_total_bytes": None,
        "size_used_bytes": None,
        "size_available_bytes": None,
        "use_percent": "",
        "human": {
            "size_total": "",
            "size_used": "",
            "size_available": "",
            "use_percent": "",
        },
    }

    if not command_exists("df"):
        result["error"] = "df not available"
        return result

    cmd = run_command(["df", "-P", "-B1", str(path)], timeout=10)

    if cmd["returncode"] != 0:
        result["error"] = cmd["stderr"] or cmd["stdout"]
        return result

    lines = cmd["stdout"].splitlines()

    if len(lines) < 2:
        result["error"] = "df output incomplete"
        return result

    parts = lines[1].split()

    if len(parts) < 6:
        result["error"] = "df parse failed"
        return result

    result["filesystem"] = parts[0]
    result["size_total_bytes"] = int(parts[1]) if parts[1].isdigit() else None
    result["size_used_bytes"] = int(parts[2]) if parts[2].isdigit() else None
    result["size_available_bytes"] = int(parts[3]) if parts[3].isdigit() else None
    result["use_percent"] = parts[4]
    result["mountpoint"] = parts[5]
    result["available"] = True

    cmd_h = run_command(["df", "-hT", str(path)], timeout=10)

    if cmd_h["returncode"] == 0:
        h_lines = cmd_h["stdout"].splitlines()

        if len(h_lines) >= 2:
            h_parts = h_lines[1].split()

            if len(h_parts) >= 7:
                result["type"] = h_parts[1]
                result["human"] = {
                    "size_total": h_parts[2],
                    "size_used": h_parts[3],
                    "size_available": h_parts[4],
                    "use_percent": h_parts[5],
                }

    return result


def mounted_filesystems() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []

    if not command_exists("df"):
        return rows

    cmd = run_command(["df", "-hT"], timeout=10)

    if cmd["returncode"] != 0:
        return rows

    for line in cmd["stdout"].splitlines()[1:]:
        parts = line.split()

        if len(parts) < 7:
            continue

        filesystem, fs_type, size_total, size_used, size_available, use_percent, mountpoint = parts[:7]

        if fs_type in ("tmpfs", "devtmpfs", "overlay", "squashfs"):
            continue

        rows.append({
            "filesystem": filesystem,
            "type": fs_type,
            "size_total": size_total,
            "size_used": size_used,
            "size_available": size_available,
            "use_percent": use_percent,
            "mountpoint": mountpoint,
        })

    return rows


def block_devices() -> dict[str, Any]:
    if not command_exists("lsblk"):
        return {
            "available": False,
            "error": "lsblk not available",
            "raw_json": {},
        }

    cmd = run_command(["lsblk", "-J", "-o", "NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL,RM,RO,TRAN"], timeout=15)

    if cmd["returncode"] != 0:
        return {
            "available": True,
            "error": cmd["stderr"] or cmd["stdout"],
            "raw_json": {},
        }

    try:
        return {
            "available": True,
            "error": "",
            "raw_json": json.loads(cmd["stdout"]),
        }
    except Exception as exc:
        return {
            "available": True,
            "error": str(exc),
            "raw_json": {},
        }


def collect_storage() -> dict[str, Any]:
    warnings: list[str] = []

    root_fs = parse_df_path(Path("/"))
    bot_fs = parse_df_path(INSTALL_PATH)

    try:
        if root_fs["available"] and root_fs["size_available_bytes"] is not None:
            if int(root_fs["size_available_bytes"]) < 1024 * 1024 * 1024:
                warnings.append("Root filesystem has less than 1 GB available.")
    except Exception:
        pass

    return {
        "commands_available": {
            "df": command_exists("df"),
            "lsblk": command_exists("lsblk"),
        },
        "root_filesystem": root_fs,
        "bot_filesystem": bot_fs,
        "mounted_filesystems": mounted_filesystems(),
        "block_devices": block_devices(),
        "warnings": warnings,
    }


def collect_python(venv_dir: Path) -> dict[str, Any]:
    system_python_cmd = run_command(["python3", "--version"], timeout=10)
    system_python = system_python_cmd["stdout"] or system_python_cmd["stderr"]

    venv_python = venv_dir / "bin" / "python"
    venv_pip = venv_dir / "bin" / "pip"

    venv_python_version = ""
    requests_import = False
    dotenv_import = False

    if venv_python.exists() and os.access(venv_python, os.X_OK):
        cmd = run_command([str(venv_python), "--version"], timeout=10)
        venv_python_version = cmd["stdout"] or cmd["stderr"]

        requests_import = run_command([str(venv_python), "-c", "import requests"], timeout=10)["returncode"] == 0
        dotenv_import = run_command([str(venv_python), "-c", "import dotenv"], timeout=10)["returncode"] == 0

    return {
        "system_python": system_python,
        "venv_python_exists": venv_python.exists(),
        "venv_pip_exists": venv_pip.exists(),
        "venv_python": venv_python_version,
        "requests_import": requests_import,
        "dotenv_import": dotenv_import,
    }


def collect_systemd() -> dict[str, Any]:
    service_template = Path("/etc/systemd/system/bot-runner@.service")
    timer_template = Path("/etc/systemd/system/bot-runner@.timer")

    instance_service = f"bot-runner@{INSTANCE}.service"
    instance_timer = f"bot-runner@{INSTANCE}.timer"

    legacy_service_path = Path(f"/etc/systemd/system/{INSTANCE}-runner.service")
    legacy_timer_path = Path(f"/etc/systemd/system/{INSTANCE}-runner.timer")

    return {
        "service_template": {
            "exists": service_template.exists(),
            "path": str(service_template),
            "permissions": file_meta(service_template)["permissions"] if service_template.exists() else "",
        },
        "timer_template": {
            "exists": timer_template.exists(),
            "path": str(timer_template),
            "permissions": file_meta(timer_template)["permissions"] if timer_template.exists() else "",
        },
        "instance_service": {
            "name": instance_service,
            "active": systemd_bool(instance_service, "is-active"),
            "load_state": systemctl_value(instance_service, "LoadState") or "not-found",
            "active_state": systemctl_value(instance_service, "ActiveState") or "inactive",
            "sub_state": systemctl_value(instance_service, "SubState") or "dead",
        },
        "instance_timer": {
            "name": instance_timer,
            "enabled": systemd_bool(instance_timer, "is-enabled"),
            "active": systemd_bool(instance_timer, "is-active"),
            "load_state": systemctl_value(instance_timer, "LoadState") or "not-found",
            "active_state": systemctl_value(instance_timer, "ActiveState") or "inactive",
            "sub_state": systemctl_value(instance_timer, "SubState") or "dead",
        },
        "legacy_service": {
            "exists": legacy_service_path.exists(),
            "path": str(legacy_service_path),
        },
        "legacy_timer": {
            "exists": legacy_timer_path.exists(),
            "path": str(legacy_timer_path),
        },
    }


def tree_snapshot(base: Path, max_depth: int, max_items: int) -> dict[str, Any]:
    result = {
        "max_depth": max_depth,
        "max_items": max_items,
        "truncated": False,
        "directories": [],
        "files": [],
    }

    if not base.exists() or not base.is_dir():
        return result

    count = 0

    for root, dirs, files in os.walk(base):
        root_path = Path(root)

        try:
            rel = root_path.relative_to(base)
            depth = 0 if str(rel) == "." else len(rel.parts)
        except Exception:
            depth = 0

        dirs[:] = sorted([d for d in dirs if d not in ("venv", "__pycache__", ".git", ".cache")])
        files = sorted(files)

        if depth > max_depth:
            dirs[:] = []
            continue

        if root_path != base:
            result["directories"].append(str(root_path))
            count += 1

        for filename in files:
            if filename.endswith((".pyc", ".pyo")):
                continue

            if count >= max_items:
                result["truncated"] = True
                return result

            file_path = root_path / filename
            result["files"].append(str(file_path))
            count += 1

            if count >= max_items:
                result["truncated"] = True
                return result

    return result


def collect_runtime_structure(systemd_data: dict[str, Any]) -> dict[str, Any]:
    scripts_dir = INSTALL_PATH / "scripts"
    audits_dir = INSTALL_PATH / "audits"
    reports_dir = INSTALL_PATH / "reports"
    reports_pending_dir = reports_dir / "pending"
    docs_dir = INSTALL_PATH / "docs"
    docs_scripts_dir = docs_dir / "scripts"
    docs_audits_dir = docs_dir / "audits"

    legacy_maintenance_dir = INSTALL_PATH / "maintenance"
    legacy_tools_dir = INSTALL_PATH / "tools"

    known_dirs = {
        "scripts_dir": file_meta(scripts_dir),
        "audits_dir": file_meta(audits_dir),
        "reports_dir": file_meta(reports_dir),
        "reports_pending_dir": file_meta(reports_pending_dir),
        "docs_dir": file_meta(docs_dir),
        "docs_scripts_dir": file_meta(docs_scripts_dir),
        "docs_audits_dir": file_meta(docs_audits_dir),

        "legacy_tools_dir": file_meta(legacy_tools_dir),
        "legacy_maintenance_dir": file_meta(legacy_maintenance_dir),
        "legacy_scripts_system_dir": file_meta(scripts_dir / "system"),
        "legacy_scripts_checks_dir": file_meta(scripts_dir / "checks"),
        "legacy_scripts_maintenance_dir": file_meta(scripts_dir / "maintenance"),
        "legacy_scripts_docs_dir": file_meta(scripts_dir / "docs"),
    }

    standard_script_names = [
        "cancel_shutdown.sh",
        "check_disk.sh",
        "check_memory.sh",
        "reboot.sh",
        "shutdown.sh",
        "ssh_start.sh",
        "ssh_status.sh",
        "ssh_stop.sh",
        "tail_runner_log.sh",
        "uptime_info.sh",
    ]

    standard_scripts_flat = {
        name: file_meta(scripts_dir / name)
        for name in standard_script_names
    }

    boot_report_primary = audits_dir / "audit_jr-bot-boot-report.sh"

    boot_report_legacy_candidates = [
        legacy_maintenance_dir / "jrbot_boot_report.sh",
        scripts_dir / "maintenance" / "jrbot_boot_report.sh",
        scripts_dir / "system" / "jrbot_boot_report.sh",
        INSTALL_PATH / "jrbot_boot_report.sh",
    ]

    boot_report_candidates = [
        boot_report_primary,
        *boot_report_legacy_candidates,
    ]

    audit_structure_primary = audits_dir / "audit_jr-bot-structure.sh"
    audit_structure_legacy_candidates = [
        legacy_tools_dir / "audit_jr-bot-structure.sh",
        INSTALL_PATH / "audit_jr-bot-structure.sh",
        Path.home() / "audit_jr-bot-structure.sh",
    ]

    audit_network_health_primary = audits_dir / "audit_jr-bot-network-health.sh"
    audit_network_health_legacy_candidates = [
        legacy_tools_dir / "audit_jr-bot-network-health.sh",
        INSTALL_PATH / "audit_jr-bot-network-health.sh",
        Path.home() / "audit_jr-bot-network-health.sh",
    ]

    audit_boot_report_candidates = [
        audits_dir / "audit_jr-bot-boot-report.sh",
        legacy_maintenance_dir / "jrbot_boot_report.sh",
        scripts_dir / "maintenance" / "jrbot_boot_report.sh",
        scripts_dir / "system" / "jrbot_boot_report.sh",
        INSTALL_PATH / "jrbot_boot_report.sh",
    ]

    sudoers_file = Path("/etc/sudoers.d") / INSTANCE

    known_scripts = {
        "standard_scripts_flat": standard_scripts_flat,

        "scripts_reboot": file_meta(scripts_dir / "reboot.sh"),
        "maintenance_reboot": file_meta(legacy_maintenance_dir / "reboot.sh"),
        "scripts_maintenance_reboot": file_meta(scripts_dir / "maintenance" / "reboot.sh"),

        "boot_report_primary": file_meta(boot_report_primary),
        "boot_report_legacy_candidates": [file_meta(path) for path in boot_report_legacy_candidates],
        "boot_report_candidates": [file_meta(path) for path in boot_report_candidates],

        "audit_structure_primary": file_meta(audit_structure_primary),
        "audit_structure_legacy_candidates": [file_meta(path) for path in audit_structure_legacy_candidates],
        "audit_structure_candidates": [
            file_meta(audit_structure_primary),
            *[file_meta(path) for path in audit_structure_legacy_candidates],
        ],

        "audit_network_health_primary": file_meta(audit_network_health_primary),
        "audit_network_health_legacy_candidates": [file_meta(path) for path in audit_network_health_legacy_candidates],
        "audit_network_health_candidates": [
            file_meta(audit_network_health_primary),
            *[file_meta(path) for path in audit_network_health_legacy_candidates],
        ],

        "audit_boot_report_candidates": [file_meta(path) for path in audit_boot_report_candidates],
    }

    top_level_entries: list[dict[str, Any]] = []

    if INSTALL_PATH.exists() and INSTALL_PATH.is_dir():
        for entry in sorted(INSTALL_PATH.iterdir(), key=lambda p: p.name.lower()):
            entry_meta = file_meta(entry)

            if entry.name == "venv":
                entry_meta["note"] = "venv content omitted from tree snapshot"

            top_level_entries.append(entry_meta)

    legacy_detected = bool(
        systemd_data["legacy_service"]["exists"]
        or systemd_data["legacy_timer"]["exists"]
        or (INSTALL_PATH / ".env").exists()
    )

    template_detected = bool(
        systemd_data["service_template"]["exists"]
        or systemd_data["timer_template"]["exists"]
        or systemd_data["instance_timer"]["load_state"] != "not-found"
    )

    config_ini_detected = (INSTALL_PATH / "config" / "config.ini").exists()

    if legacy_detected and template_detected:
        profile = "hybrid"
    elif template_detected and config_ini_detected:
        profile = "template"
    elif legacy_detected:
        profile = "legacy"
    else:
        profile = "unknown"

    deviations: list[dict[str, Any]] = []

    def add_deviation(level: str, code: str, message: str, path: str = "") -> None:
        deviations.append({
            "level": level,
            "code": code,
            "message": message,
            "path": path,
        })

    if profile == "legacy":
        add_deviation(
            "info",
            "LEGACY_PROFILE_DETECTED",
            "Legacy runner/profile detected. This can be valid for older DMR/GGB bots.",
        )

    if profile == "hybrid":
        add_deviation(
            "warning",
            "HYBRID_PROFILE_DETECTED",
            "Both legacy and template signals detected. Review migration state.",
        )

    if not scripts_dir.exists():
        add_deviation(
            "warning",
            "SCRIPTS_DIR_MISSING",
            "scripts directory is missing.",
            str(scripts_dir),
        )

    if not audits_dir.exists():
        add_deviation(
            "warning",
            "AUDITS_DIR_MISSING",
            "audits directory is missing.",
            str(audits_dir),
        )

    if not reports_dir.exists():
        add_deviation(
            "info",
            "REPORTS_DIR_MISSING",
            "reports directory is missing.",
            str(reports_dir),
        )

    if not reports_pending_dir.exists():
        add_deviation(
            "info",
            "REPORTS_PENDING_DIR_MISSING",
            "reports/pending directory is missing.",
            str(reports_pending_dir),
        )

    missing_standard_scripts = [
        name for name, meta in standard_scripts_flat.items()
        if not meta["exists"]
    ]

    if missing_standard_scripts:
        add_deviation(
            "warning",
            "STANDARD_SCRIPTS_MISSING",
            "One or more standard flat scripts are missing: " + ", ".join(missing_standard_scripts),
            str(scripts_dir),
        )

    legacy_dirs_found = [
        str(path)
        for path in [
            legacy_tools_dir,
            legacy_maintenance_dir,
            scripts_dir / "system",
            scripts_dir / "checks",
            scripts_dir / "maintenance",
            scripts_dir / "docs",
        ]
        if path.exists()
    ]

    if legacy_dirs_found:
        add_deviation(
            "info",
            "LEGACY_DIRECTORIES_DETECTED",
            "Legacy directories detected. They are recorded for migration tracking, not treated as current target layout.",
            ", ".join(legacy_dirs_found),
        )

    if not boot_report_primary.exists():
        add_deviation(
            "warning",
            "BOOT_REPORT_AUDIT_SCRIPT_MISSING",
            "No audit_jr-bot-boot-report.sh script detected in audits/.",
            str(boot_report_primary),
        )

    if not audit_structure_primary.exists():
        add_deviation(
            "warning",
            "STRUCTURE_AUDIT_SCRIPT_MISSING",
            "No audit_jr-bot-structure.sh script detected in audits/.",
            str(audit_structure_primary),
        )

    if not audit_network_health_primary.exists():
        add_deviation(
            "warning",
            "NETWORK_HEALTH_AUDIT_SCRIPT_MISSING",
            "No audit_jr-bot-network-health.sh script detected in audits/.",
            str(audit_network_health_primary),
        )

    if not sudoers_file.exists():
        add_deviation(
            "info",
            "SUDOERS_FILE_MISSING",
            "No /etc/sudoers.d/<instance> file detected. Required for sudo-managed wrapper scripts such as reboot/shutdown/ssh controls.",
            str(sudoers_file),
        )

    if not systemd_data["service_template"]["exists"] and not systemd_data["legacy_service"]["exists"]:
        add_deviation(
            "warning",
            "NO_SYSTEMD_SERVICE_FOUND",
            "No template or legacy service file detected.",
        )

    if not systemd_data["timer_template"]["exists"] and not systemd_data["legacy_timer"]["exists"]:
        add_deviation(
            "warning",
            "NO_SYSTEMD_TIMER_FOUND",
            "No template or legacy timer file detected.",
        )

    return {
        "profile_detected": profile,
        "expected_layout": "one_liner_v0_4_flat_scripts_audits",
        "mode_requested": MODE,
        "top_level_entries": top_level_entries,
        "known_dirs": known_dirs,
        "known_scripts": known_scripts,
        "tree_snapshot": tree_snapshot(INSTALL_PATH, TREE_MAX_DEPTH, TREE_MAX_ITEMS),
        "deviations": deviations,
    }

config_dir = INSTALL_PATH / "config"
src_dir = INSTALL_PATH / "src"
logs_dir = INSTALL_PATH / "logs"
state_dir = INSTALL_PATH / "state"
tmp_dir = INSTALL_PATH / "tmp"
venv_dir = INSTALL_PATH / "venv"
data_dir = INSTALL_PATH / "data"

config_ini = config_dir / "config.ini"
env_file = INSTALL_PATH / ".env"
job_runner = src_dir / "job_runner.py"
requirements = INSTALL_PATH / "requirements.txt"
install_info = INSTALL_PATH / "install_info.txt"

os_release = read_os_release()
cpu = read_cpu_info()
systemd_data = collect_systemd()
runtime_structure = collect_runtime_structure(systemd_data)

data: dict[str, Any] = {
    "schema": SCHEMA_VERSION,
    "script_version": SCRIPT_VERSION,
    "instance": INSTANCE,
    "mode": MODE,
    "created_at_utc": CREATED_AT_UTC,
    "security": {
        "read_only": True,
        "secrets_redacted": True,
        "secret_values_included": False,
    },
    "host": {
        "hostname": socket.gethostname(),
        "kernel": run_command(["uname", "-a"], timeout=10)["stdout"],
        "architecture": platform.machine(),
        "os_pretty_name": os_release["PRETTY_NAME"],
        "os_id": os_release["ID"],
        "os_version_id": os_release["VERSION_ID"],
        "os_version_codename": os_release["VERSION_CODENAME"],
        "raspberry_pi_model": read_raspberry_model(),
        "cpu_model": cpu["cpu_model"],
        "cpu_revision": cpu["cpu_revision"],
        "memory_total_mb": memory_total_mb(),
        "boot_time": run_command(["uptime", "-s"], timeout=10)["stdout"],
    },
    "network": collect_network(),
    "storage": collect_storage(),
    "paths": {
        "install_dir": {
            "path": str(INSTALL_PATH),
            "exists": INSTALL_PATH.exists(),
        },
        "config_dir": {
            "path": str(config_dir),
            "exists": config_dir.exists(),
        },
        "src_dir": {
            "path": str(src_dir),
            "exists": src_dir.exists(),
        },
        "logs_dir": {
            "path": str(logs_dir),
            "exists": logs_dir.exists(),
        },
        "state_dir": {
            "path": str(state_dir),
            "exists": state_dir.exists(),
        },
        "tmp_dir": {
            "path": str(tmp_dir),
            "exists": tmp_dir.exists(),
        },
        "venv_dir": {
            "path": str(venv_dir),
            "exists": venv_dir.exists(),
        },
        "data_dir": {
            "path": str(data_dir),
            "exists": data_dir.exists(),
        },
    },
    "runtime_structure": runtime_structure,
    "user": user_info(EXPECTED_USER),
    "files": {
        "config_ini": {
            **file_meta(config_ini),
            "permissions_ok": file_meta(config_ini)["permissions"] == "600",
            "contains_keys": {
                "PROJECT_NAME": key_present(config_ini, "PROJECT_NAME"),
                "BOT_NAME": key_present(config_ini, "BOT_NAME"),
                "INSTANCE_NAME": key_present(config_ini, "INSTANCE_NAME"),
                "SERVER_BASE": key_present(config_ini, "SERVER_BASE"),
                "SERVER_TOKEN": key_present(config_ini, "SERVER_TOKEN"),
                "PING_TOKEN": key_present(config_ini, "PING_TOKEN"),
            },
        },
        "env_file": {
            **file_meta(env_file),
            "permissions_ok": file_meta(env_file)["permissions"] == "600",
            "contains_keys": {
                "SERVER_BASE": key_present(env_file, "SERVER_BASE"),
                "SERVER_TOKEN": key_present(env_file, "SERVER_TOKEN"),
                "BOT_NAME": key_present(env_file, "BOT_NAME"),
                "PING_TOKEN": key_present(env_file, "PING_TOKEN"),
            },
        },
        "job_runner": file_meta(job_runner),
        "requirements": file_meta(requirements),
        "install_info": file_meta(install_info),
    },
    "python": collect_python(venv_dir),
    "systemd": systemd_data,
}

data["summary"] = {
    "ok_basic_structure": bool(INSTALL_PATH.exists() and job_runner.exists() and venv_dir.exists()),
    "profile_detected": runtime_structure["profile_detected"],
    "deviation_count": len(runtime_structure["deviations"]),
    "checks": {
        "install_dir_exists": INSTALL_PATH.exists(),
        "job_runner_exists": job_runner.exists(),
        "config_or_env_exists": config_ini.exists() or env_file.exists(),
        "venv_python_exists": (venv_dir / "bin" / "python").exists(),
        "systemd_timer_known": systemd_data["instance_timer"]["load_state"] != "not-found" or systemd_data["legacy_timer"]["exists"],
        "storage_root_available": data["storage"]["root_filesystem"]["available"],
        "storage_bot_available": data["storage"]["bot_filesystem"]["available"],
        "scripts_dir_exists": (INSTALL_PATH / "scripts").exists(),
        "audits_dir_exists": (INSTALL_PATH / "audits").exists(),
        "reports_dir_exists": (INSTALL_PATH / "reports").exists(),
        "reports_pending_dir_exists": (INSTALL_PATH / "reports" / "pending").exists(),
        "docs_scripts_dir_exists": (INSTALL_PATH / "docs" / "scripts").exists(),
        "docs_audits_dir_exists": (INSTALL_PATH / "docs" / "audits").exists(),
        "sudoers_file_exists": (Path("/etc/sudoers.d") / INSTANCE).exists(),
        "standard_scripts_flat_complete": all(
            item["exists"]
            for item in runtime_structure["known_scripts"]["standard_scripts_flat"].values()
        ),
        "boot_report_audit_script_detected": runtime_structure["known_scripts"]["boot_report_primary"]["exists"],
        "structure_audit_script_detected": runtime_structure["known_scripts"]["audit_structure_primary"]["exists"],
        "network_health_audit_script_detected": runtime_structure["known_scripts"]["audit_network_health_primary"]["exists"],
        "reboot_script_detected": runtime_structure["known_scripts"]["scripts_reboot"]["exists"],
    },
}

print(json.dumps(data, indent=4, ensure_ascii=False))
PY

# ----------------------------------------------------------
# Validate generated JSON
# ----------------------------------------------------------

if ! python3 -m json.tool "$OUTPUT_FILE" >/dev/null 2>&1; then
    die "Die erzeugte JSON-Datei ist ungÃƒÂ¼ltig: $OUTPUT_FILE"
fi

info "Structure-Audit JSON erstellt: ${OUTPUT_FILE}"

if [[ "$PRINT_JSON" == "true" ]]; then
    cat "$OUTPUT_FILE"
fi

# ----------------------------------------------------------
# Optional OPSCON upload
# ----------------------------------------------------------

UPLOAD_SUCCESS="false"

if [[ -n "$PUSH_URL" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        die "curl wird fÃƒÂ¼r den Upload benÃƒÂ¶tigt."
    fi

    if [[ -z "$TOKEN" ]]; then
        if [[ -e /dev/tty ]]; then
            read -rsp "OPSCON Structure-Audit Token eingeben: " TOKEN </dev/tty
            echo >&2
        fi
    fi

    if [[ -z "$TOKEN" ]]; then
        die "Kein OPSCON Audit-Token vorhanden. Upload abgebrochen."
    fi

    RESPONSE_FILE="$(mktemp /tmp/audit_jr-bot-structure-upload-response.XXXXXX.txt)"

    info "Sende Structure-Audit JSON an OPSCON als Datei-Upload..."

    HTTP_CODE="$(curl -fsSL \
        -w "%{http_code}" \
        -o "$RESPONSE_FILE" \
        -X POST \
        -F "token=${TOKEN}" \
        -F "instance=${INSTANCE_LOWER}" \
        -F "mode=${MODE}" \
        -F "audit_file=@${OUTPUT_FILE};type=application/json" \
        "$PUSH_URL" || true)"

    if [[ "$HTTP_CODE" != "200" ]]; then
        error "Upload fehlgeschlagen. HTTP-Code: ${HTTP_CODE}"

        if [[ -s "$RESPONSE_FILE" ]]; then
            cat "$RESPONSE_FILE" >&2
            echo >&2
        fi

        rm -f "$RESPONSE_FILE"

        warn "Lokale Structure-Audit-Datei bleibt fÃƒÂ¼r Debugging erhalten: ${OUTPUT_FILE}"
        exit 1
    fi

    UPLOAD_SUCCESS="true"

    info "Upload erfolgreich."

    if [[ -s "$RESPONSE_FILE" ]]; then
        cat "$RESPONSE_FILE" >&2
        echo >&2
    fi

    rm -f "$RESPONSE_FILE"
fi

# ----------------------------------------------------------
# Local file cleanup
# ----------------------------------------------------------

if [[ "$UPLOAD_SUCCESS" == "true" ]]; then
    if [[ "$KEEP_LOCAL" == "true" ]]; then
        info "Lokale Structure-Audit-Datei bleibt erhalten wegen --keep-local: ${OUTPUT_FILE}"
    elif [[ "$OUTPUT_FILE_USER_SET" == "true" ]]; then
        info "Lokale Structure-Audit-Datei bleibt erhalten wegen --output: ${OUTPUT_FILE}"
    else
        rm -f "$OUTPUT_FILE"
        info "Lokale temporÃƒÂ¤re Structure-Audit-Datei wurde nach erfolgreichem Upload gelÃƒÂ¶scht."
    fi
else
    info "Structure audit completed: ${OUTPUT_FILE}"
fi
