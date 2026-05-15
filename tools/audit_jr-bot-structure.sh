#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Structure Audit
# Version: 0.1.4
# ==========================================================
#
# Purpose:
#   Read-only audit script for JR-Bot Raspberry Pi nodes.
#
# This script collects:
#   - Host / Raspberry Pi / OS information
#   - Network information, local IP, gateway, SSH status
#   - Bot directory structure
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
# Examples:
#   ./audit_jr-bot-structure.sh --instance trx --path /opt/bots/trx
#
#   ./audit_jr-bot-structure.sh --instance dmr --path ~/bots/DMR --legacy
#
#   ./audit_jr-bot-structure.sh \
#     --instance dmr \
#     --path ~/bots/DMR \
#     --legacy \
#     --push-url https://opscon.blenk.co.at/api/jrbot_audit_ingest.php \
#     --token <TOKEN>
#
#   ./audit_jr-bot-structure.sh \
#     --instance dmr \
#     --path ~/bots/DMR \
#     --legacy \
#     --keep-local \
#     --push-url https://opscon.blenk.co.at/api/jrbot_audit_ingest.php \
#     --token <TOKEN>
#
# ==========================================================

SCRIPT_VERSION="0.1.4"
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
  --instance <name>       Bot instance name, e.g. trx, dmr, ggb, dmr01
  --path <bot-path>       Bot install path, e.g. /opt/bots/trx or ~/bots/DMR

Options:
  --legacy                Legacy mode for older DMR/GGB structures
  --push-url <url>        Optional OPSCON ingest endpoint
  --token <token>         Optional OPSCON audit token
  --output <file>         Optional output JSON file. File will be kept.
  --keep-local            Keep generated local JSON after successful upload
  --print-json            Print JSON to stdout
  -h, --help              Show this help

Examples:
  ./audit_jr-bot-structure.sh --instance trx --path /opt/bots/trx

  ./audit_jr-bot-structure.sh --instance dmr --path ~/bots/DMR --legacy

  ./audit_jr-bot-structure.sh \
    --instance dmr \
    --path ~/bots/DMR \
    --legacy \
    --push-url https://opscon.blenk.co.at/api/jrbot_audit_ingest.php \
    --token <TOKEN>

  ./audit_jr-bot-structure.sh \
    --instance dmr \
    --path ~/bots/DMR \
    --legacy \
    --keep-local \
    --push-url https://opscon.blenk.co.at/api/jrbot_audit_ingest.php \
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
EXPECTED_USER="$INSTANCE_LOWER"

if [[ -z "$OUTPUT_FILE" ]]; then
    TS_FILE="$(date -u +"%Y%m%d_%H%M%S")"
    OUTPUT_FILE="/tmp/jrbot-audit-${INSTANCE_LOWER}-${TS_FILE}.json"
fi

# ----------------------------------------------------------
# Small helpers
# ----------------------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

safe_cat() {
    local file="$1"

    if [[ -r "$file" ]]; then
        tr -d '\000' < "$file" 2>/dev/null || true
    fi
}

file_exists_bool() {
    local file="$1"
    [[ -e "$file" ]] && echo "true" || echo "false"
}

dir_exists_bool() {
    local dir="$1"
    [[ -d "$dir" ]] && echo "true" || echo "false"
}

get_file_perm() {
    local file="$1"

    if [[ -e "$file" ]]; then
        stat -c "%a" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_file_owner() {
    local file="$1"

    if [[ -e "$file" ]]; then
        stat -c "%U" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_file_group() {
    local file="$1"

    if [[ -e "$file" ]]; then
        stat -c "%G" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_file_size() {
    local file="$1"

    if [[ -e "$file" ]]; then
        stat -c "%s" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_file_mtime_utc() {
    local file="$1"

    if [[ -e "$file" ]]; then
        local epoch
        epoch="$(stat -c "%Y" "$file" 2>/dev/null || echo "")"

        if [[ -n "$epoch" ]]; then
            date -u -d "@${epoch}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo ""
        else
            echo ""
        fi
    else
        echo ""
    fi
}

key_present_ini_or_env() {
    local file="$1"
    local key="$2"

    if [[ ! -r "$file" ]]; then
        echo "false"
        return
    fi

    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

systemctl_exists() {
    command_exists systemctl
}

systemd_is_enabled() {
    local unit="$1"

    if systemctl_exists; then
        systemctl is-enabled "$unit" >/dev/null 2>&1 && echo "true" || echo "false"
    else
        echo "false"
    fi
}

systemd_is_active() {
    local unit="$1"

    if systemctl_exists; then
        systemctl is-active "$unit" >/dev/null 2>&1 && echo "true" || echo "false"
    else
        echo "false"
    fi
}

systemd_load_state() {
    local unit="$1"

    if systemctl_exists; then
        systemctl show "$unit" -p LoadState --value 2>/dev/null || echo ""
    else
        echo ""
    fi
}

systemd_active_state() {
    local unit="$1"

    if systemctl_exists; then
        systemctl show "$unit" -p ActiveState --value 2>/dev/null || echo ""
    else
        echo ""
    fi
}

systemd_sub_state() {
    local unit="$1"

    if systemctl_exists; then
        systemctl show "$unit" -p SubState --value 2>/dev/null || echo ""
    else
        echo ""
    fi
}

first_ipv4_from_list() {
    local raw="$1"
    echo "$raw" | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true
}

# ----------------------------------------------------------
# Determine important paths
# ----------------------------------------------------------

CONFIG_DIR="${INSTALL_PATH}/config"
SRC_DIR="${INSTALL_PATH}/src"
LOGS_DIR="${INSTALL_PATH}/logs"
STATE_DIR="${INSTALL_PATH}/state"
TMP_DIR="${INSTALL_PATH}/tmp"
VENV_DIR="${INSTALL_PATH}/venv"
DATA_DIR="${INSTALL_PATH}/data"

CONFIG_INI="${CONFIG_DIR}/config.ini"
ENV_FILE="${INSTALL_PATH}/.env"
JOB_RUNNER="${SRC_DIR}/job_runner.py"
REQUIREMENTS="${INSTALL_PATH}/requirements.txt"
INSTALL_INFO="${INSTALL_PATH}/install_info.txt"

SERVICE_TEMPLATE="/etc/systemd/system/bot-runner@.service"
TIMER_TEMPLATE="/etc/systemd/system/bot-runner@.timer"
INSTANCE_SERVICE="bot-runner@${INSTANCE_LOWER}.service"
INSTANCE_TIMER="bot-runner@${INSTANCE_LOWER}.timer"

LEGACY_SERVICE_1="/etc/systemd/system/${INSTANCE_LOWER}-runner.service"
LEGACY_TIMER_1="/etc/systemd/system/${INSTANCE_LOWER}-runner.timer"

if ! command_exists python3; then
    die "python3 wird benötigt, um die Audit-JSON sicher zu erzeugen."
fi

# ----------------------------------------------------------
# Collect host values
# ----------------------------------------------------------

CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

HOSTNAME_VALUE="$(hostname 2>/dev/null || echo "")"
KERNEL_VALUE="$(uname -a 2>/dev/null || echo "")"
ARCH_VALUE="$(uname -m 2>/dev/null || echo "")"
UPTIME_SINCE="$(uptime -s 2>/dev/null || echo "")"

OS_PRETTY_NAME=""
OS_ID=""
OS_VERSION_ID=""
OS_VERSION_CODENAME=""

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_PRETTY_NAME="${PRETTY_NAME:-}"
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
fi

RPI_MODEL=""
if [[ -r /proc/device-tree/model ]]; then
    RPI_MODEL="$(safe_cat /proc/device-tree/model)"
elif [[ -r /sys/firmware/devicetree/base/model ]]; then
    RPI_MODEL="$(safe_cat /sys/firmware/devicetree/base/model)"
fi

CPU_MODEL=""
if grep -qi "model name" /proc/cpuinfo 2>/dev/null; then
    CPU_MODEL="$(grep -m1 "model name" /proc/cpuinfo | cut -d ':' -f2- | sed 's/^ //')"
elif grep -qi "Hardware" /proc/cpuinfo 2>/dev/null; then
    CPU_MODEL="$(grep -m1 "Hardware" /proc/cpuinfo | cut -d ':' -f2- | sed 's/^ //')"
fi

CPU_REVISION=""
if grep -qi "Revision" /proc/cpuinfo 2>/dev/null; then
    CPU_REVISION="$(grep -m1 "Revision" /proc/cpuinfo | cut -d ':' -f2- | sed 's/^ //')"
fi

MEMORY_TOTAL_MB=""
if [[ -r /proc/meminfo ]]; then
    MEMORY_TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
fi

# ----------------------------------------------------------
# Collect network values
# ----------------------------------------------------------

HOSTNAME_I=""
if command_exists hostname; then
    HOSTNAME_I="$(hostname -I 2>/dev/null | xargs || true)"
fi

ALL_IPV4=""
if command_exists ip; then
    ALL_IPV4="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd ' ' - || true)"
fi

PRIMARY_IPV4=""
PRIMARY_INTERFACE=""
DEFAULT_GATEWAY=""
DEFAULT_ROUTE=""

if command_exists ip; then
    DEFAULT_ROUTE="$(ip route 2>/dev/null | grep '^default ' | head -n1 || true)"
    PRIMARY_INTERFACE="$(echo "$DEFAULT_ROUTE" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") print $(i+1)}' | head -n1 || true)"
    DEFAULT_GATEWAY="$(echo "$DEFAULT_ROUTE" | awk '{for (i=1; i<=NF; i++) if ($i=="via") print $(i+1)}' | head -n1 || true)"

    PRIMARY_IPV4="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") print $(i+1)}' | head -n1 || true)"
fi

if [[ -z "$PRIMARY_IPV4" ]]; then
    PRIMARY_IPV4="$(first_ipv4_from_list "$HOSTNAME_I")"
fi

if [[ -z "$PRIMARY_IPV4" ]]; then
    PRIMARY_IPV4="$(first_ipv4_from_list "$ALL_IPV4")"
fi

SSH_SERVICE_EXISTS="false"
SSH_SERVICE_ENABLED="false"
SSH_SERVICE_ACTIVE="false"
SSH_LOAD_STATE=""
SSH_ACTIVE_STATE=""
SSH_SUB_STATE=""

if systemctl_exists; then
    SSH_LOAD_STATE="$(systemctl show ssh -p LoadState --value 2>/dev/null || echo "")"
    SSH_ACTIVE_STATE="$(systemctl show ssh -p ActiveState --value 2>/dev/null || echo "")"
    SSH_SUB_STATE="$(systemctl show ssh -p SubState --value 2>/dev/null || echo "")"

    if [[ "$SSH_LOAD_STATE" != "" && "$SSH_LOAD_STATE" != "not-found" ]]; then
        SSH_SERVICE_EXISTS="true"
    fi

    SSH_SERVICE_ENABLED="$(systemd_is_enabled ssh)"
    SSH_SERVICE_ACTIVE="$(systemd_is_active ssh)"
fi

# ----------------------------------------------------------
# Collect Python values
# ----------------------------------------------------------

SYSTEM_PYTHON_VERSION=""
if command_exists python3; then
    SYSTEM_PYTHON_VERSION="$(python3 --version 2>&1 || true)"
fi

VENV_PYTHON_VERSION=""
if [[ -x "${VENV_DIR}/bin/python" ]]; then
    VENV_PYTHON_VERSION="$("${VENV_DIR}/bin/python" --version 2>&1 || true)"
fi

REQUESTS_IMPORT="false"
if [[ -x "${VENV_DIR}/bin/python" ]]; then
    if "${VENV_DIR}/bin/python" -c "import requests" >/dev/null 2>&1; then
        REQUESTS_IMPORT="true"
    fi
fi

DOTENV_IMPORT="false"
if [[ -x "${VENV_DIR}/bin/python" ]]; then
    if "${VENV_DIR}/bin/python" -c "import dotenv" >/dev/null 2>&1; then
        DOTENV_IMPORT="true"
    fi
fi

# ----------------------------------------------------------
# Collect user and permission values
# ----------------------------------------------------------

USER_EXISTS="false"
USER_UID=""
USER_GID=""

if id "$EXPECTED_USER" >/dev/null 2>&1; then
    USER_EXISTS="true"
    USER_UID="$(id -u "$EXPECTED_USER" 2>/dev/null || echo "")"
    USER_GID="$(id -g "$EXPECTED_USER" 2>/dev/null || echo "")"
fi

CONFIG_PERM="$(get_file_perm "$CONFIG_INI")"
CONFIG_PERMISSIONS_OK="false"
if [[ "$CONFIG_PERM" == "600" ]]; then
    CONFIG_PERMISSIONS_OK="true"
fi

ENV_PERM="$(get_file_perm "$ENV_FILE")"
ENV_PERMISSIONS_OK="false"
if [[ "$ENV_PERM" == "600" ]]; then
    ENV_PERMISSIONS_OK="true"
fi

# ----------------------------------------------------------
# Export values for Python JSON builder
# ----------------------------------------------------------

export JR_AUDIT_SCRIPT_VERSION="$SCRIPT_VERSION"
export JR_AUDIT_SCHEMA_VERSION="$SCHEMA_VERSION"
export JR_AUDIT_INSTANCE="$INSTANCE_LOWER"
export JR_AUDIT_MODE="$MODE"
export JR_AUDIT_CREATED_AT_UTC="$CREATED_AT_UTC"

export JR_AUDIT_HOSTNAME="$HOSTNAME_VALUE"
export JR_AUDIT_KERNEL="$KERNEL_VALUE"
export JR_AUDIT_ARCH="$ARCH_VALUE"
export JR_AUDIT_OS_PRETTY_NAME="$OS_PRETTY_NAME"
export JR_AUDIT_OS_ID="$OS_ID"
export JR_AUDIT_OS_VERSION_ID="$OS_VERSION_ID"
export JR_AUDIT_OS_VERSION_CODENAME="$OS_VERSION_CODENAME"
export JR_AUDIT_RPI_MODEL="$RPI_MODEL"
export JR_AUDIT_CPU_MODEL="$CPU_MODEL"
export JR_AUDIT_CPU_REVISION="$CPU_REVISION"
export JR_AUDIT_MEMORY_TOTAL_MB="$MEMORY_TOTAL_MB"
export JR_AUDIT_BOOT_TIME="$UPTIME_SINCE"

export JR_AUDIT_HOSTNAME_I="$HOSTNAME_I"
export JR_AUDIT_ALL_IPV4="$ALL_IPV4"
export JR_AUDIT_PRIMARY_IPV4="$PRIMARY_IPV4"
export JR_AUDIT_PRIMARY_INTERFACE="$PRIMARY_INTERFACE"
export JR_AUDIT_DEFAULT_GATEWAY="$DEFAULT_GATEWAY"
export JR_AUDIT_DEFAULT_ROUTE="$DEFAULT_ROUTE"
export JR_AUDIT_SSH_SERVICE_EXISTS="$SSH_SERVICE_EXISTS"
export JR_AUDIT_SSH_SERVICE_ENABLED="$SSH_SERVICE_ENABLED"
export JR_AUDIT_SSH_SERVICE_ACTIVE="$SSH_SERVICE_ACTIVE"
export JR_AUDIT_SSH_LOAD_STATE="$SSH_LOAD_STATE"
export JR_AUDIT_SSH_ACTIVE_STATE="$SSH_ACTIVE_STATE"
export JR_AUDIT_SSH_SUB_STATE="$SSH_SUB_STATE"

export JR_AUDIT_INSTALL_PATH="$INSTALL_PATH"
export JR_AUDIT_CONFIG_DIR="$CONFIG_DIR"
export JR_AUDIT_SRC_DIR="$SRC_DIR"
export JR_AUDIT_LOGS_DIR="$LOGS_DIR"
export JR_AUDIT_STATE_DIR="$STATE_DIR"
export JR_AUDIT_TMP_DIR="$TMP_DIR"
export JR_AUDIT_VENV_DIR="$VENV_DIR"
export JR_AUDIT_DATA_DIR="$DATA_DIR"

export JR_AUDIT_EXPECTED_USER="$EXPECTED_USER"
export JR_AUDIT_USER_EXISTS="$USER_EXISTS"
export JR_AUDIT_USER_UID="$USER_UID"
export JR_AUDIT_USER_GID="$USER_GID"

export JR_AUDIT_CONFIG_INI="$CONFIG_INI"
export JR_AUDIT_ENV_FILE="$ENV_FILE"
export JR_AUDIT_JOB_RUNNER="$JOB_RUNNER"
export JR_AUDIT_REQUIREMENTS="$REQUIREMENTS"
export JR_AUDIT_INSTALL_INFO="$INSTALL_INFO"

export JR_AUDIT_SYSTEM_PYTHON_VERSION="$SYSTEM_PYTHON_VERSION"
export JR_AUDIT_VENV_PYTHON_VERSION="$VENV_PYTHON_VERSION"
export JR_AUDIT_REQUESTS_IMPORT="$REQUESTS_IMPORT"
export JR_AUDIT_DOTENV_IMPORT="$DOTENV_IMPORT"

export JR_AUDIT_SERVICE_TEMPLATE="$SERVICE_TEMPLATE"
export JR_AUDIT_TIMER_TEMPLATE="$TIMER_TEMPLATE"
export JR_AUDIT_INSTANCE_SERVICE="$INSTANCE_SERVICE"
export JR_AUDIT_INSTANCE_TIMER="$INSTANCE_TIMER"
export JR_AUDIT_LEGACY_SERVICE_1="$LEGACY_SERVICE_1"
export JR_AUDIT_LEGACY_TIMER_1="$LEGACY_TIMER_1"

export JR_AUDIT_INSTALL_DIR_EXISTS="$(dir_exists_bool "$INSTALL_PATH")"
export JR_AUDIT_CONFIG_DIR_EXISTS="$(dir_exists_bool "$CONFIG_DIR")"
export JR_AUDIT_SRC_DIR_EXISTS="$(dir_exists_bool "$SRC_DIR")"
export JR_AUDIT_LOGS_DIR_EXISTS="$(dir_exists_bool "$LOGS_DIR")"
export JR_AUDIT_STATE_DIR_EXISTS="$(dir_exists_bool "$STATE_DIR")"
export JR_AUDIT_TMP_DIR_EXISTS="$(dir_exists_bool "$TMP_DIR")"
export JR_AUDIT_VENV_DIR_EXISTS="$(dir_exists_bool "$VENV_DIR")"
export JR_AUDIT_DATA_DIR_EXISTS="$(dir_exists_bool "$DATA_DIR")"

export JR_AUDIT_CONFIG_EXISTS="$(file_exists_bool "$CONFIG_INI")"
export JR_AUDIT_CONFIG_PERM="$CONFIG_PERM"
export JR_AUDIT_CONFIG_OWNER="$(get_file_owner "$CONFIG_INI")"
export JR_AUDIT_CONFIG_GROUP="$(get_file_group "$CONFIG_INI")"
export JR_AUDIT_CONFIG_SIZE="$(get_file_size "$CONFIG_INI")"
export JR_AUDIT_CONFIG_MTIME="$(get_file_mtime_utc "$CONFIG_INI")"
export JR_AUDIT_CONFIG_PERMISSIONS_OK="$CONFIG_PERMISSIONS_OK"

export JR_AUDIT_ENV_EXISTS="$(file_exists_bool "$ENV_FILE")"
export JR_AUDIT_ENV_PERM="$ENV_PERM"
export JR_AUDIT_ENV_OWNER="$(get_file_owner "$ENV_FILE")"
export JR_AUDIT_ENV_GROUP="$(get_file_group "$ENV_FILE")"
export JR_AUDIT_ENV_SIZE="$(get_file_size "$ENV_FILE")"
export JR_AUDIT_ENV_MTIME="$(get_file_mtime_utc "$ENV_FILE")"
export JR_AUDIT_ENV_PERMISSIONS_OK="$ENV_PERMISSIONS_OK"

export JR_AUDIT_JOB_RUNNER_EXISTS="$(file_exists_bool "$JOB_RUNNER")"
export JR_AUDIT_JOB_RUNNER_PERM="$(get_file_perm "$JOB_RUNNER")"
export JR_AUDIT_JOB_RUNNER_OWNER="$(get_file_owner "$JOB_RUNNER")"
export JR_AUDIT_JOB_RUNNER_GROUP="$(get_file_group "$JOB_RUNNER")"
export JR_AUDIT_JOB_RUNNER_SIZE="$(get_file_size "$JOB_RUNNER")"
export JR_AUDIT_JOB_RUNNER_MTIME="$(get_file_mtime_utc "$JOB_RUNNER")"

export JR_AUDIT_REQUIREMENTS_EXISTS="$(file_exists_bool "$REQUIREMENTS")"
export JR_AUDIT_REQUIREMENTS_PERM="$(get_file_perm "$REQUIREMENTS")"
export JR_AUDIT_REQUIREMENTS_OWNER="$(get_file_owner "$REQUIREMENTS")"
export JR_AUDIT_REQUIREMENTS_GROUP="$(get_file_group "$REQUIREMENTS")"
export JR_AUDIT_REQUIREMENTS_SIZE="$(get_file_size "$REQUIREMENTS")"
export JR_AUDIT_REQUIREMENTS_MTIME="$(get_file_mtime_utc "$REQUIREMENTS")"

export JR_AUDIT_INSTALL_INFO_EXISTS="$(file_exists_bool "$INSTALL_INFO")"
export JR_AUDIT_INSTALL_INFO_PERM="$(get_file_perm "$INSTALL_INFO")"
export JR_AUDIT_INSTALL_INFO_OWNER="$(get_file_owner "$INSTALL_INFO")"
export JR_AUDIT_INSTALL_INFO_GROUP="$(get_file_group "$INSTALL_INFO")"
export JR_AUDIT_INSTALL_INFO_SIZE="$(get_file_size "$INSTALL_INFO")"
export JR_AUDIT_INSTALL_INFO_MTIME="$(get_file_mtime_utc "$INSTALL_INFO")"

export JR_AUDIT_VENV_PYTHON_EXISTS="$(file_exists_bool "${VENV_DIR}/bin/python")"
export JR_AUDIT_VENV_PIP_EXISTS="$(file_exists_bool "${VENV_DIR}/bin/pip")"

export JR_AUDIT_CONFIG_HAS_PROJECT_NAME="$(key_present_ini_or_env "$CONFIG_INI" "PROJECT_NAME")"
export JR_AUDIT_CONFIG_HAS_BOT_NAME="$(key_present_ini_or_env "$CONFIG_INI" "BOT_NAME")"
export JR_AUDIT_CONFIG_HAS_INSTANCE_NAME="$(key_present_ini_or_env "$CONFIG_INI" "INSTANCE_NAME")"
export JR_AUDIT_CONFIG_HAS_SERVER_BASE="$(key_present_ini_or_env "$CONFIG_INI" "SERVER_BASE")"
export JR_AUDIT_CONFIG_HAS_SERVER_TOKEN="$(key_present_ini_or_env "$CONFIG_INI" "SERVER_TOKEN")"
export JR_AUDIT_CONFIG_HAS_PING_TOKEN="$(key_present_ini_or_env "$CONFIG_INI" "PING_TOKEN")"

export JR_AUDIT_ENV_HAS_SERVER_BASE="$(key_present_ini_or_env "$ENV_FILE" "SERVER_BASE")"
export JR_AUDIT_ENV_HAS_SERVER_TOKEN="$(key_present_ini_or_env "$ENV_FILE" "SERVER_TOKEN")"
export JR_AUDIT_ENV_HAS_BOT_NAME="$(key_present_ini_or_env "$ENV_FILE" "BOT_NAME")"
export JR_AUDIT_ENV_HAS_PING_TOKEN="$(key_present_ini_or_env "$ENV_FILE" "PING_TOKEN")"

export JR_AUDIT_SERVICE_TEMPLATE_EXISTS="$(file_exists_bool "$SERVICE_TEMPLATE")"
export JR_AUDIT_TIMER_TEMPLATE_EXISTS="$(file_exists_bool "$TIMER_TEMPLATE")"
export JR_AUDIT_SERVICE_TEMPLATE_PERM="$(get_file_perm "$SERVICE_TEMPLATE")"
export JR_AUDIT_TIMER_TEMPLATE_PERM="$(get_file_perm "$TIMER_TEMPLATE")"

export JR_AUDIT_LEGACY_SERVICE_EXISTS="$(file_exists_bool "$LEGACY_SERVICE_1")"
export JR_AUDIT_LEGACY_TIMER_EXISTS="$(file_exists_bool "$LEGACY_TIMER_1")"

export JR_AUDIT_INSTANCE_TIMER_ENABLED="$(systemd_is_enabled "$INSTANCE_TIMER")"
export JR_AUDIT_INSTANCE_TIMER_ACTIVE="$(systemd_is_active "$INSTANCE_TIMER")"
export JR_AUDIT_INSTANCE_SERVICE_ACTIVE="$(systemd_is_active "$INSTANCE_SERVICE")"
export JR_AUDIT_INSTANCE_TIMER_LOAD_STATE="$(systemd_load_state "$INSTANCE_TIMER")"
export JR_AUDIT_INSTANCE_TIMER_ACTIVE_STATE="$(systemd_active_state "$INSTANCE_TIMER")"
export JR_AUDIT_INSTANCE_TIMER_SUB_STATE="$(systemd_sub_state "$INSTANCE_TIMER")"
export JR_AUDIT_INSTANCE_SERVICE_LOAD_STATE="$(systemd_load_state "$INSTANCE_SERVICE")"
export JR_AUDIT_INSTANCE_SERVICE_ACTIVE_STATE="$(systemd_active_state "$INSTANCE_SERVICE")"
export JR_AUDIT_INSTANCE_SERVICE_SUB_STATE="$(systemd_sub_state "$INSTANCE_SERVICE")"

# ----------------------------------------------------------
# Generate JSON via Python
# ----------------------------------------------------------

python3 > "$OUTPUT_FILE" <<'PY'
import json
import os


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def env_bool(name: str) -> bool:
    return env(name).lower() == "true"


def env_int_or_none(name: str):
    value = env(name)
    if value == "":
        return None
    try:
        return int(value)
    except ValueError:
        return value


def env_list(name: str):
    value = env(name)
    if value.strip() == "":
        return []
    return [item for item in value.split() if item]


data = {
    "schema": env("JR_AUDIT_SCHEMA_VERSION"),
    "script_version": env("JR_AUDIT_SCRIPT_VERSION"),
    "instance": env("JR_AUDIT_INSTANCE"),
    "mode": env("JR_AUDIT_MODE"),
    "created_at_utc": env("JR_AUDIT_CREATED_AT_UTC"),
    "security": {
        "read_only": True,
        "secrets_redacted": True,
        "secret_values_included": False
    },
    "host": {
        "hostname": env("JR_AUDIT_HOSTNAME"),
        "kernel": env("JR_AUDIT_KERNEL"),
        "architecture": env("JR_AUDIT_ARCH"),
        "os_pretty_name": env("JR_AUDIT_OS_PRETTY_NAME"),
        "os_id": env("JR_AUDIT_OS_ID"),
        "os_version_id": env("JR_AUDIT_OS_VERSION_ID"),
        "os_version_codename": env("JR_AUDIT_OS_VERSION_CODENAME"),
        "raspberry_pi_model": env("JR_AUDIT_RPI_MODEL"),
        "cpu_model": env("JR_AUDIT_CPU_MODEL"),
        "cpu_revision": env("JR_AUDIT_CPU_REVISION"),
        "memory_total_mb": env_int_or_none("JR_AUDIT_MEMORY_TOTAL_MB"),
        "boot_time": env("JR_AUDIT_BOOT_TIME")
    },
    "network": {
        "hostname_i": env("JR_AUDIT_HOSTNAME_I"),
        "all_ipv4": env_list("JR_AUDIT_ALL_IPV4"),
        "primary_ipv4": env("JR_AUDIT_PRIMARY_IPV4"),
        "primary_interface": env("JR_AUDIT_PRIMARY_INTERFACE"),
        "default_gateway": env("JR_AUDIT_DEFAULT_GATEWAY"),
        "default_route": env("JR_AUDIT_DEFAULT_ROUTE"),
        "ssh": {
            "service_exists": env_bool("JR_AUDIT_SSH_SERVICE_EXISTS"),
            "enabled": env_bool("JR_AUDIT_SSH_SERVICE_ENABLED"),
            "active": env_bool("JR_AUDIT_SSH_SERVICE_ACTIVE"),
            "load_state": env("JR_AUDIT_SSH_LOAD_STATE"),
            "active_state": env("JR_AUDIT_SSH_ACTIVE_STATE"),
            "sub_state": env("JR_AUDIT_SSH_SUB_STATE")
        }
    },
    "paths": {
        "install_dir": {"path": env("JR_AUDIT_INSTALL_PATH"), "exists": env_bool("JR_AUDIT_INSTALL_DIR_EXISTS")},
        "config_dir": {"path": env("JR_AUDIT_CONFIG_DIR"), "exists": env_bool("JR_AUDIT_CONFIG_DIR_EXISTS")},
        "src_dir": {"path": env("JR_AUDIT_SRC_DIR"), "exists": env_bool("JR_AUDIT_SRC_DIR_EXISTS")},
        "logs_dir": {"path": env("JR_AUDIT_LOGS_DIR"), "exists": env_bool("JR_AUDIT_LOGS_DIR_EXISTS")},
        "state_dir": {"path": env("JR_AUDIT_STATE_DIR"), "exists": env_bool("JR_AUDIT_STATE_DIR_EXISTS")},
        "tmp_dir": {"path": env("JR_AUDIT_TMP_DIR"), "exists": env_bool("JR_AUDIT_TMP_DIR_EXISTS")},
        "venv_dir": {"path": env("JR_AUDIT_VENV_DIR"), "exists": env_bool("JR_AUDIT_VENV_DIR_EXISTS")},
        "data_dir": {"path": env("JR_AUDIT_DATA_DIR"), "exists": env_bool("JR_AUDIT_DATA_DIR_EXISTS")}
    },
    "user": {
        "expected_user": env("JR_AUDIT_EXPECTED_USER"),
        "exists": env_bool("JR_AUDIT_USER_EXISTS"),
        "uid": env("JR_AUDIT_USER_UID"),
        "gid": env("JR_AUDIT_USER_GID")
    },
    "files": {
        "config_ini": {
            "exists": env_bool("JR_AUDIT_CONFIG_EXISTS"),
            "path": env("JR_AUDIT_CONFIG_INI"),
            "permissions": env("JR_AUDIT_CONFIG_PERM"),
            "owner": env("JR_AUDIT_CONFIG_OWNER"),
            "group": env("JR_AUDIT_CONFIG_GROUP"),
            "size_bytes": env_int_or_none("JR_AUDIT_CONFIG_SIZE"),
            "modified_at_utc": env("JR_AUDIT_CONFIG_MTIME"),
            "permissions_ok": env_bool("JR_AUDIT_CONFIG_PERMISSIONS_OK"),
            "contains_keys": {
                "PROJECT_NAME": env_bool("JR_AUDIT_CONFIG_HAS_PROJECT_NAME"),
                "BOT_NAME": env_bool("JR_AUDIT_CONFIG_HAS_BOT_NAME"),
                "INSTANCE_NAME": env_bool("JR_AUDIT_CONFIG_HAS_INSTANCE_NAME"),
                "SERVER_BASE": env_bool("JR_AUDIT_CONFIG_HAS_SERVER_BASE"),
                "SERVER_TOKEN": env_bool("JR_AUDIT_CONFIG_HAS_SERVER_TOKEN"),
                "PING_TOKEN": env_bool("JR_AUDIT_CONFIG_HAS_PING_TOKEN")
            }
        },
        "env_file": {
            "exists": env_bool("JR_AUDIT_ENV_EXISTS"),
            "path": env("JR_AUDIT_ENV_FILE"),
            "permissions": env("JR_AUDIT_ENV_PERM"),
            "owner": env("JR_AUDIT_ENV_OWNER"),
            "group": env("JR_AUDIT_ENV_GROUP"),
            "size_bytes": env_int_or_none("JR_AUDIT_ENV_SIZE"),
            "modified_at_utc": env("JR_AUDIT_ENV_MTIME"),
            "permissions_ok": env_bool("JR_AUDIT_ENV_PERMISSIONS_OK"),
            "contains_keys": {
                "SERVER_BASE": env_bool("JR_AUDIT_ENV_HAS_SERVER_BASE"),
                "SERVER_TOKEN": env_bool("JR_AUDIT_ENV_HAS_SERVER_TOKEN"),
                "BOT_NAME": env_bool("JR_AUDIT_ENV_HAS_BOT_NAME"),
                "PING_TOKEN": env_bool("JR_AUDIT_ENV_HAS_PING_TOKEN")
            }
        },
        "job_runner": {
            "exists": env_bool("JR_AUDIT_JOB_RUNNER_EXISTS"),
            "path": env("JR_AUDIT_JOB_RUNNER"),
            "permissions": env("JR_AUDIT_JOB_RUNNER_PERM"),
            "owner": env("JR_AUDIT_JOB_RUNNER_OWNER"),
            "group": env("JR_AUDIT_JOB_RUNNER_GROUP"),
            "size_bytes": env_int_or_none("JR_AUDIT_JOB_RUNNER_SIZE"),
            "modified_at_utc": env("JR_AUDIT_JOB_RUNNER_MTIME")
        },
        "requirements": {
            "exists": env_bool("JR_AUDIT_REQUIREMENTS_EXISTS"),
            "path": env("JR_AUDIT_REQUIREMENTS"),
            "permissions": env("JR_AUDIT_REQUIREMENTS_PERM"),
            "owner": env("JR_AUDIT_REQUIREMENTS_OWNER"),
            "group": env("JR_AUDIT_REQUIREMENTS_GROUP"),
            "size_bytes": env_int_or_none("JR_AUDIT_REQUIREMENTS_SIZE"),
            "modified_at_utc": env("JR_AUDIT_REQUIREMENTS_MTIME")
        },
        "install_info": {
            "exists": env_bool("JR_AUDIT_INSTALL_INFO_EXISTS"),
            "path": env("JR_AUDIT_INSTALL_INFO"),
            "permissions": env("JR_AUDIT_INSTALL_INFO_PERM"),
            "owner": env("JR_AUDIT_INSTALL_INFO_OWNER"),
            "group": env("JR_AUDIT_INSTALL_INFO_GROUP"),
            "size_bytes": env_int_or_none("JR_AUDIT_INSTALL_INFO_SIZE"),
            "modified_at_utc": env("JR_AUDIT_INSTALL_INFO_MTIME")
        }
    },
    "python": {
        "system_python": env("JR_AUDIT_SYSTEM_PYTHON_VERSION"),
        "venv_python_exists": env_bool("JR_AUDIT_VENV_PYTHON_EXISTS"),
        "venv_pip_exists": env_bool("JR_AUDIT_VENV_PIP_EXISTS"),
        "venv_python": env("JR_AUDIT_VENV_PYTHON_VERSION"),
        "requests_import": env_bool("JR_AUDIT_REQUESTS_IMPORT"),
        "dotenv_import": env_bool("JR_AUDIT_DOTENV_IMPORT")
    },
    "systemd": {
        "service_template": {
            "exists": env_bool("JR_AUDIT_SERVICE_TEMPLATE_EXISTS"),
            "path": env("JR_AUDIT_SERVICE_TEMPLATE"),
            "permissions": env("JR_AUDIT_SERVICE_TEMPLATE_PERM")
        },
        "timer_template": {
            "exists": env_bool("JR_AUDIT_TIMER_TEMPLATE_EXISTS"),
            "path": env("JR_AUDIT_TIMER_TEMPLATE"),
            "permissions": env("JR_AUDIT_TIMER_TEMPLATE_PERM")
        },
        "instance_service": {
            "name": env("JR_AUDIT_INSTANCE_SERVICE"),
            "active": env_bool("JR_AUDIT_INSTANCE_SERVICE_ACTIVE"),
            "load_state": env("JR_AUDIT_INSTANCE_SERVICE_LOAD_STATE"),
            "active_state": env("JR_AUDIT_INSTANCE_SERVICE_ACTIVE_STATE"),
            "sub_state": env("JR_AUDIT_INSTANCE_SERVICE_SUB_STATE")
        },
        "instance_timer": {
            "name": env("JR_AUDIT_INSTANCE_TIMER"),
            "enabled": env_bool("JR_AUDIT_INSTANCE_TIMER_ENABLED"),
            "active": env_bool("JR_AUDIT_INSTANCE_TIMER_ACTIVE"),
            "load_state": env("JR_AUDIT_INSTANCE_TIMER_LOAD_STATE"),
            "active_state": env("JR_AUDIT_INSTANCE_TIMER_ACTIVE_STATE"),
            "sub_state": env("JR_AUDIT_INSTANCE_TIMER_SUB_STATE")
        },
        "legacy_service": {
            "exists": env_bool("JR_AUDIT_LEGACY_SERVICE_EXISTS"),
            "path": env("JR_AUDIT_LEGACY_SERVICE_1")
        },
        "legacy_timer": {
            "exists": env_bool("JR_AUDIT_LEGACY_TIMER_EXISTS"),
            "path": env("JR_AUDIT_LEGACY_TIMER_1")
        }
    }
}

checks = {
    "install_dir_exists": data["paths"]["install_dir"]["exists"],
    "job_runner_exists": data["files"]["job_runner"]["exists"],
    "config_or_env_exists": data["files"]["config_ini"]["exists"] or data["files"]["env_file"]["exists"],
    "venv_python_exists": data["python"]["venv_python_exists"],
    "systemd_timer_known": (
        data["systemd"]["instance_timer"]["load_state"] not in ("", "not-found")
        or data["systemd"]["legacy_timer"]["exists"]
    )
}

data["summary"] = {
    "ok_basic_structure": all(checks.values()),
    "checks": checks
}

print(json.dumps(data, indent=2, ensure_ascii=False))
PY

if ! python3 -m json.tool "$OUTPUT_FILE" >/dev/null 2>&1; then
    die "Die erzeugte JSON-Datei ist ungültig: $OUTPUT_FILE"
fi

info "Audit-JSON erstellt: ${OUTPUT_FILE}"

if [[ "$PRINT_JSON" == "true" ]]; then
    cat "$OUTPUT_FILE"
fi

# ----------------------------------------------------------
# Optional OPSCON upload
# ----------------------------------------------------------

UPLOAD_SUCCESS="false"

if [[ -n "$PUSH_URL" ]]; then
    if ! command_exists curl; then
        die "curl wird für den Upload benötigt."
    fi

    if [[ -z "$TOKEN" ]]; then
        if [[ -e /dev/tty ]]; then
            read -rsp "OPSCON Audit-Token eingeben: " TOKEN </dev/tty
            echo >&2
        fi
    fi

    if [[ -z "$TOKEN" ]]; then
        die "Kein OPSCON Audit-Token vorhanden. Upload abgebrochen."
    fi

    RESPONSE_FILE="$(mktemp /tmp/jrbot-audit-upload-response.XXXXXX.txt)"

    info "Sende Audit-JSON an OPSCON als Datei-Upload..."

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
        warn "Lokale Audit-Datei bleibt für Debugging erhalten: ${OUTPUT_FILE}"
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
        info "Lokale Audit-Datei bleibt erhalten wegen --keep-local: ${OUTPUT_FILE}"
    elif [[ "$OUTPUT_FILE_USER_SET" == "true" ]]; then
        info "Lokale Audit-Datei bleibt erhalten wegen --output: ${OUTPUT_FILE}"
    else
        rm -f "$OUTPUT_FILE"
        info "Lokale temporäre Audit-Datei wurde nach erfolgreichem Upload gelöscht."
    fi
else
    info "Audit completed: ${OUTPUT_FILE}"
fi
