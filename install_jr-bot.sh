#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Universal Installer
# Version: 0.3.0
# ==========================================================
#
# Purpose:
#   Installs a project-specific JR-Bot node on a Raspberry Pi.
#
# Default target:
#   TRAX / TRX
#
# Architecture:
#   - One bot per Pi / node
#   - Remote Project API backend
#   - External project DB remains on the webserver/project side
#   - Pi stores only local runtime config, logs, state, reports and venv
#   - systemd template units:
#       - bot-runner@.service / bot-runner@.timer
#       - jrbot-boot-report@.service
#       - jrbot-report-upload@.service / jrbot-report-upload@.timer
#
# Security:
#   - No secrets are embedded in this script
#   - SERVER_TOKEN, PING_TOKEN and REPORT_UPLOAD_TOKEN are requested interactively
#   - Local config.ini is stored with chmod 600
#   - Local report_upload.token is stored with chmod 600
#
# Boot Report:
#   - Creates maintenance/jrbot_boot_report.sh
#   - Creates reports/pending/
#   - Generates a compact boot/network/service report after boot
#   - Uploads pending reports to OPSCON if token and endpoint are available
#
# ==========================================================

SCRIPT_VERSION="0.4.0"

# ----------------------------------------------------------
# Default values
# ----------------------------------------------------------

DEFAULT_PROJECT_NAME="TRAX"
DEFAULT_BOT_NAME="TRX"
DEFAULT_INSTANCE_NAME="trx"
DEFAULT_RUN_AS_USER="trx"
DEFAULT_INSTALL_DIR="/opt/bots/trx"
DEFAULT_SERVER_BASE="https://trax.blenk.co.at/handler"
DEFAULT_INTERVAL_SECONDS="60"

DEFAULT_BOOT_REPORT_AUDIT_PUSH_URL="https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php"
DEFAULT_STRUCTURE_AUDIT_PUSH_URL="https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php"
DEFAULT_NETWORK_HEALTH_AUDIT_PUSH_URL="https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php"

# Compatibility aliases for D6 migration.
# These are intentionally kept during D6.1 so existing installer functions keep working
# until D6.2-D6.4 replace the legacy boot-report flow completely.
DEFAULT_BOOT_REPORT_PUSH_URL="${DEFAULT_BOOT_REPORT_AUDIT_PUSH_URL}"
DEFAULT_AUDIT_PUSH_URL="${DEFAULT_STRUCTURE_AUDIT_PUSH_URL}"

GITHUB_BRANCH="${JR_BOT_GITHUB_BRANCH:-main}"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/MrNiceGuy0x/jr-bot/${GITHUB_BRANCH}"

SYSTEMD_RUNNER_SERVICE_TEMPLATE="/etc/systemd/system/bot-runner@.service"
SYSTEMD_RUNNER_TIMER_TEMPLATE="/etc/systemd/system/bot-runner@.timer"

SYSTEMD_BOOT_REPORT_SERVICE_TEMPLATE="/etc/systemd/system/jrbot-boot-report@.service"
SYSTEMD_BOOT_REPORT_AUDIT_SERVICE_TEMPLATE="/etc/systemd/system/jrbot-boot-report-audit@.service"
SYSTEMD_REPORT_UPLOAD_SERVICE_TEMPLATE="/etc/systemd/system/jrbot-report-upload@.service"
SYSTEMD_REPORT_UPLOAD_TIMER_TEMPLATE="/etc/systemd/system/jrbot-report-upload@.timer"

# ----------------------------------------------------------
# Output helpers
# ----------------------------------------------------------

print_header() {
    echo "=================================================="
    echo " JR-Bot Universal Installer"
    echo " Version: ${SCRIPT_VERSION}"
    echo "=================================================="
    echo
}

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

# ----------------------------------------------------------
# Input helpers
# ----------------------------------------------------------

ask_with_default() {
    local prompt="$1"
    local default_value="$2"
    local value=""

    read -rp "${prompt} [${default_value}]: " value </dev/tty
    value="${value:-$default_value}"

    echo "$value"
}

ask_secret_required() {
    local prompt="$1"
    local value=""

    while [ -z "$value" ]; do
        read -rsp "${prompt}: " value </dev/tty
        echo
        if [ -z "$value" ]; then
            echo "Dieser Wert darf nicht leer sein."
        fi
    done

    echo "$value"
}

ask_secret_optional() {
    local prompt="$1"
    local value=""

    read -rsp "${prompt} (leer lassen zum Überspringen): " value </dev/tty
    echo

    echo "$value"
}

confirm_default_yes() {
    local prompt="$1"
    local answer=""

    read -rp "${prompt} [Y/n]: " answer </dev/tty

    case "$answer" in
        n|N|no|NO|No)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

confirm_default_no() {
    local prompt="$1"
    local answer=""

    read -rp "${prompt} [y/N]: " answer </dev/tty

    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ----------------------------------------------------------
# Validation helpers
# ----------------------------------------------------------

require_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "Benötigter Befehl fehlt: ${cmd}"
    fi
}

normalize_instance_name() {
    local raw="$1"

    echo "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9_-]+/-/g' \
        | sed -E 's/^-+|-+$//g'
}

validate_instance_name() {
    local instance="$1"

    if [[ ! "$instance" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        die "Ungültiger Instanzname: ${instance}. Erlaubt: lowercase a-z, 0-9, _ und -; muss mit Buchstabe/Zahl starten."
    fi
}

validate_user_name() {
    local user="$1"

    if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        die "Ungültiger Linux-Benutzername: ${user}"
    fi
}

validate_interval() {
    local interval="$1"

    if [[ ! "$interval" =~ ^[0-9]+$ ]]; then
        die "Polling-Intervall muss eine Zahl sein."
    fi

    if [ "$interval" -lt 10 ]; then
        die "Polling-Intervall ist zu niedrig. Minimum: 10 Sekunden."
    fi
}

# ----------------------------------------------------------
# System checks
# ----------------------------------------------------------

check_interactive_terminal() {
    if [ ! -e /dev/tty ]; then
        die "Kein interaktives Terminal verfügbar. Bitte Installer zuerst herunterladen und manuell ausführen."
    fi
}

check_basic_commands() {
    require_command bash
    require_command curl
    require_command sudo
    require_command sed
    require_command tr
}

# ----------------------------------------------------------
# User handling
# ----------------------------------------------------------

ensure_run_user_exists() {
    local run_as_user="$1"

    validate_user_name "$run_as_user"

    if id "$run_as_user" >/dev/null 2>&1; then
        info "Linux-Benutzer existiert bereits: ${run_as_user}"
        return 0
    fi

    warn "Linux-Benutzer existiert noch nicht: ${run_as_user}"

    if confirm_default_yes "Linux-Benutzer '${run_as_user}' jetzt automatisch als Systembenutzer erstellen?"; then
        sudo useradd --system --create-home --shell /usr/sbin/nologin "$run_as_user"
        info "Linux-Benutzer erstellt: ${run_as_user}"
    else
        die "Ohne gültigen Ausführungsbenutzer kann die Installation nicht fortgesetzt werden."
    fi
}

# ----------------------------------------------------------
# Package installation
# ----------------------------------------------------------

install_system_packages() {
    info "Installiere Systempakete..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y \
            python3 \
            python3-venv \
            python3-pip \
            curl \
            ca-certificates \
            htop \
            tree \
            iproute2 \
            dnsutils \
            procps \
            util-linux
    else
        warn "apt-get wurde nicht gefunden. Paketinstallation wird übersprungen."
    fi
}

# ----------------------------------------------------------
# Directory setup
# ----------------------------------------------------------

create_directory_structure() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle Bot-Verzeichnisstruktur unter: ${install_dir}"

    sudo mkdir -p "$install_dir"
    sudo mkdir -p "$install_dir/config"
    sudo mkdir -p "$install_dir/src"
    sudo mkdir -p "$install_dir/scripts"
    sudo mkdir -p "$install_dir/audits"
    sudo mkdir -p "$install_dir/docs"
    sudo mkdir -p "$install_dir/docs/scripts"
    sudo mkdir -p "$install_dir/docs/audits"
    sudo mkdir -p "$install_dir/reports"
    sudo mkdir -p "$install_dir/reports/pending"
    sudo mkdir -p "$install_dir/logs"
    sudo mkdir -p "$install_dir/state"
    sudo mkdir -p "$install_dir/tmp"

    sudo chown -R "${run_as_user}:${run_as_user}" "$install_dir"

    info "Verzeichnisstruktur erstellt."
}

# ----------------------------------------------------------
# Python venv setup
# ----------------------------------------------------------

create_python_venv() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle Python venv..."

    sudo -u "$run_as_user" python3 -m venv "$install_dir/venv"

    info "Aktualisiere pip..."
    sudo -u "$run_as_user" "$install_dir/venv/bin/python" -m pip install --upgrade pip
}

create_requirements_file() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle requirements.txt..."

    sudo tee "$install_dir/requirements.txt" >/dev/null <<'EOF'
requests
python-dotenv
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/requirements.txt"
    sudo chmod 644 "$install_dir/requirements.txt"

    info "Installiere Python-Abhängigkeiten..."
    sudo -u "$run_as_user" "$install_dir/venv/bin/pip" install -r "$install_dir/requirements.txt"
}

# ----------------------------------------------------------
# Config setup
# ----------------------------------------------------------

create_config_ini() {
    local install_dir="$1"
    local run_as_user="$2"
    local project_name="$3"
    local bot_name="$4"
    local instance_name="$5"
    local server_base="$6"
    local interval_seconds="$7"
    local server_token="$8"
    local ping_token="$9"
    local boot_report_push_url="${10}"
    local audit_push_url="${11}"

    info "Erstelle lokale config.ini..."

    sudo tee "$install_dir/config/config.ini" >/dev/null <<EOF
[bot]
PROJECT_NAME = ${project_name}
BOT_NAME = ${bot_name}
INSTANCE_NAME = ${instance_name}

[backend]
MODE = remote_api

[server]
SERVER_BASE = ${server_base}
SERVER_TOKEN = ${server_token}
PING_TOKEN = ${ping_token}

[polling]
INTERVAL_SECONDS = ${interval_seconds}
LOG_LEVEL = INFO

[paths]
BASE_DIR = ${install_dir}
LOG_DIR = logs
STATE_DIR = state
TMP_DIR = tmp
REPORTS_DIR = reports

[opscon]
BOOT_REPORT_PUSH_URL = ${boot_report_push_url}
AUDIT_PUSH_URL = ${audit_push_url}
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/config/config.ini"
    sudo chmod 600 "$install_dir/config/config.ini"

    info "config.ini wurde geschützt gespeichert: ${install_dir}/config/config.ini"
}

create_report_upload_token() {
    local install_dir="$1"
    local run_as_user="$2"
    local report_upload_token="$3"

    if [ -z "$report_upload_token" ]; then
        warn "REPORT_UPLOAD_TOKEN wurde übersprungen. Boot-Reports werden lokal erzeugt, aber nicht hochgeladen."
        return 0
    fi

    info "Speichere REPORT_UPLOAD_TOKEN..."

    sudo tee "$install_dir/config/report_upload.token" >/dev/null <<EOF
${report_upload_token}
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/config/report_upload.token"
    sudo chmod 600 "$install_dir/config/report_upload.token"

    info "REPORT_UPLOAD_TOKEN wurde geschützt gespeichert: ${install_dir}/config/report_upload.token"
}

create_install_info() {
    local install_dir="$1"
    local run_as_user="$2"
    local project_name="$3"
    local bot_name="$4"
    local instance_name="$5"
    local interval_seconds="$6"
    local boot_report_push_url="$7"
    local audit_push_url="$8"

    info "Erstelle install_info.txt..."

    sudo tee "$install_dir/install_info.txt" >/dev/null <<EOF
JR-Bot Universal Installer
Version: ${SCRIPT_VERSION}

Project: ${project_name}
Bot: ${bot_name}
Instance: ${instance_name}
Install dir: ${install_dir}
Run as user: ${run_as_user}
Backend: remote_api
Systemd runner timer: bot-runner@${instance_name}.timer
Boot report service: jrbot-boot-report@${instance_name}.service
Pending report upload timer: jrbot-report-upload@${instance_name}.timer
Interval seconds: ${interval_seconds}

Boot report push URL: ${boot_report_push_url}
Audit push URL: ${audit_push_url}

Installed at UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/install_info.txt"
    sudo chmod 644 "$install_dir/install_info.txt"
}

# ----------------------------------------------------------
# Minimal Python runner
# ----------------------------------------------------------

create_job_runner() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle job_runner.py für v0.3..."

    sudo tee "$install_dir/src/job_runner.py" >/dev/null <<'EOF'
#!/usr/bin/env python3
"""
JR-Bot job_runner.py
Version: 0.3 placeholder

This runner currently verifies:
- config.ini loading
- optional --config argument
- log writing to logs/job_runner.log
- basic remote_api configuration presence

The full get_jobs/report_job/bot_ping implementation follows in the next runtime version.
"""

from __future__ import annotations

import argparse
import configparser
from datetime import datetime, timezone
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_FILE = BASE_DIR / "config" / "config.ini"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="JR-Bot Runner")
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG_FILE),
        help="Path to config.ini",
    )
    return parser.parse_args()


def load_config(config_file: Path) -> configparser.ConfigParser:
    config = configparser.ConfigParser()
    read_files = config.read(config_file)

    if not read_files:
        raise FileNotFoundError(f"Config file not found or unreadable: {config_file}")

    return config


def write_log(message: str) -> None:
    log_file = BASE_DIR / "logs" / "job_runner.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)

    line = f"[{utc_now()}] {message}"

    with log_file.open("a", encoding="utf-8") as f:
        f.write(line + "\n")

    print(line)


def main() -> None:
    args = parse_args()
    config_file = Path(args.config).resolve()
    config = load_config(config_file)

    project_name = config.get("bot", "PROJECT_NAME", fallback="UNKNOWN")
    bot_name = config.get("bot", "BOT_NAME", fallback="UNKNOWN")
    instance_name = config.get("bot", "INSTANCE_NAME", fallback="UNKNOWN")
    backend_mode = config.get("backend", "MODE", fallback="UNKNOWN")
    server_base = config.get("server", "SERVER_BASE", fallback="")

    write_log(
        "JR-Bot runner start "
        f"project={project_name} "
        f"bot={bot_name} "
        f"instance={instance_name} "
        f"backend={backend_mode} "
        f"server_base={server_base} "
        f"config={config_file}"
    )

    write_log("JR-Bot runner placeholder finished successfully")


if __name__ == "__main__":
    main()
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/src/job_runner.py"
    sudo chmod 755 "$install_dir/src/job_runner.py"
}

# ----------------------------------------------------------
# Local shell scripts
# ----------------------------------------------------------

create_system_scripts() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle System-Skripte..."

    sudo tee "$install_dir/scripts/reboot.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DELAY_MINUTES="${1:-2}"

if [[ ! "$DELAY_MINUTES" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Delay must be a number of minutes." >&2
    exit 1
fi

echo "[INFO] Scheduling reboot in ${DELAY_MINUTES} minute(s)."
sudo /usr/sbin/shutdown -r "+${DELAY_MINUTES}" "JR-Bot scheduled reboot"
EOF

    sudo tee "$install_dir/scripts/cancel_reboot.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Cancelling scheduled reboot/shutdown if one exists."
sudo /usr/sbin/shutdown -c || true
EOF

    sudo tee "$install_dir/scripts/shutdown.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DELAY_MINUTES="${1:-2}"

if [[ ! "$DELAY_MINUTES" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Delay must be a number of minutes." >&2
    exit 1
fi

echo "[INFO] Scheduling shutdown in ${DELAY_MINUTES} minute(s)."
sudo /usr/sbin/shutdown -h "+${DELAY_MINUTES}" "JR-Bot scheduled shutdown"
EOF

    sudo tee "$install_dir/scripts/cancel_shutdown.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Cancelling scheduled shutdown/reboot if one exists."
sudo /usr/sbin/shutdown -c || true
EOF

    sudo chmod 755 "$install_dir/scripts/"*.sh
    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/scripts/"*.sh
}

create_check_scripts() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle Check-Skripte..."

    sudo tee "$install_dir/scripts/check_disk.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BOT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== JR-Bot Disk Check ==="
echo "Bot path: ${BOT_PATH}"
echo

df -hT /
echo

df -hT "$BOT_PATH"
echo

if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,MODEL
fi
EOF

    sudo tee "$install_dir/scripts/check_memory.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== JR-Bot Memory Check ==="
echo

free -h
echo

if command -v vmstat >/dev/null 2>&1; then
    vmstat 1 3
fi
EOF

    sudo tee "$install_dir/scripts/uptime_info.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== JR-Bot Uptime Info ==="
echo

hostnamectl 2>/dev/null || hostname
echo

uptime
echo

echo "Boot time:"
uptime -s 2>/dev/null || true
EOF

    sudo chmod 755 "$install_dir/scripts/"*.sh
    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/scripts/"*.sh
}

create_ssh_maintenance_scripts() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle SSH-Maintenance-Skripte..."

    sudo tee "$install_dir/scripts/ssh_status.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

echo "=== SSH Status ==="
echo

echo "[systemctl status ssh]"
sudo /usr/bin/systemctl status ssh --no-pager || true
echo

echo "[is-active]"
sudo /usr/bin/systemctl is-active ssh || true
echo

echo "[is-enabled]"
sudo /usr/bin/systemctl is-enabled ssh || true
EOF

    sudo tee "$install_dir/scripts/ssh_start.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== SSH Start ==="
sudo /usr/bin/systemctl start ssh
sudo /usr/bin/systemctl is-active ssh || true
EOF

    sudo tee "$install_dir/scripts/ssh_stop.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== SSH Stop ==="
sudo /usr/bin/systemctl stop ssh
sudo /usr/bin/systemctl is-active ssh || true
EOF

    sudo chmod 755 "$install_dir/scripts/ssh_"*.sh
    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/scripts/ssh_"*.sh
}

create_script_docs() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle Script-Dokumentationsdateien..."

    local docs_dir="$install_dir/scripts/docs"

    sudo tee "$docs_dir/reboot.md" >/dev/null <<'EOF'
# reboot.sh

Schedules a delayed system reboot using shutdown -r.
Default delay: 2 minutes.
EOF

    sudo tee "$docs_dir/cancel_reboot.md" >/dev/null <<'EOF'
# cancel_reboot.sh

Cancels a scheduled reboot or shutdown using shutdown -c.
EOF

    sudo tee "$docs_dir/shutdown.md" >/dev/null <<'EOF'
# shutdown.sh

Schedules a delayed system shutdown using shutdown -h.
Default delay: 2 minutes.
EOF

    sudo tee "$docs_dir/cancel_shutdown.md" >/dev/null <<'EOF'
# cancel_shutdown.sh

Cancels a scheduled shutdown or reboot using shutdown -c.
EOF

    sudo tee "$docs_dir/check_disk.md" >/dev/null <<'EOF'
# check_disk.sh

Shows filesystem usage for root and the JR-Bot installation path.
EOF

    sudo tee "$docs_dir/check_memory.md" >/dev/null <<'EOF'
# check_memory.sh

Shows memory usage via free and vmstat if available.
EOF

    sudo tee "$docs_dir/uptime_info.md" >/dev/null <<'EOF'
# uptime_info.sh

Shows hostname, system identity and uptime information.
EOF

    sudo tee "$docs_dir/audit_jr-bot-structure.md" >/dev/null <<'EOF'
# audit_jr-bot-structure.sh

Read-only JR-Bot structure audit script downloaded from GitHub tools/.
It checks host, network, storage, paths, files, Python/venv and systemd status without exposing secrets.
EOF

    sudo tee "$docs_dir/ssh_status.md" >/dev/null <<'EOF'
# ssh_status.sh

Shows SSH systemd status, active state and enabled state.
EOF

    sudo tee "$docs_dir/ssh_start.md" >/dev/null <<'EOF'
# ssh_start.sh

Starts the SSH service via systemctl.
EOF

    sudo tee "$docs_dir/ssh_stop.md" >/dev/null <<'EOF'
# ssh_stop.sh

Stops the SSH service via systemctl.
EOF

    sudo tee "$docs_dir/jrbot_boot_report.md" >/dev/null <<'EOF'
# jrbot_boot_report.sh

Creates a compact boot/network/service report after boot.
Reports are stored under reports/pending/ and uploaded to OPSCON if REPORT_UPLOAD_TOKEN and push URL are available.
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$docs_dir/"*.md
    sudo chmod 644 "$docs_dir/"*.md
}

# ----------------------------------------------------------
# Download existing GitHub tools
# ----------------------------------------------------------

download_github_tools() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Lade vorhandene GitHub Tools herunter..."

    local audit_target="$install_dir/scripts/maintenance/audit_jr-bot-structure.sh"
    local audit_url="${GITHUB_RAW_BASE}/tools/audit_jr-bot-structure.sh"

    if curl -fsSL "$audit_url" -o /tmp/audit_jr-bot-structure.sh; then
        sudo mv /tmp/audit_jr-bot-structure.sh "$audit_target"
        sudo chown "${run_as_user}:${run_as_user}" "$audit_target"
        sudo chmod 755 "$audit_target"
        info "Audit-Skript installiert: ${audit_target}"
    else
        warn "Audit-Skript konnte nicht von GitHub geladen werden: ${audit_url}"
        warn "Die Installation läuft weiter. Das Skript kann später manuell ergänzt werden."
        rm -f /tmp/audit_jr-bot-structure.sh || true
    fi
}

# ----------------------------------------------------------
# Boot report script
# ----------------------------------------------------------

create_boot_report_script() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Erstelle maintenance/jrbot_boot_report.sh..."

    sudo tee "$install_dir/maintenance/jrbot_boot_report.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="0.1.0"
SCHEMA_VERSION="jrbot-boot-report-v1"

INSTANCE=""
BOT_PATH=""
MODE="manual"
PUSH_URL=""
TOKEN=""
NO_UPLOAD="false"
KEEP_LOCAL="false"
PRINT_SUMMARY="false"
PRINT_JSON="false"

info() {
    echo "[INFO] $*" >&2
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
}

usage() {
    cat <<'USAGE'
JR-Bot Boot Report

Usage:
  jrbot_boot_report.sh [options]

Options:
  --instance <name>      Instance name, e.g. trx, dmr, ggb
  --path <bot-path>      Bot base path, e.g. /opt/bots/trx
  --mode <mode>          Mode marker, e.g. one-liner, boot, upload-pending
  --push-url <url>       OPSCON boot report ingest endpoint
  --token <token>        REPORT_UPLOAD_TOKEN
  --no-upload            Create report only, do not upload
  --keep-local           Keep local report even after successful upload
  --print-summary        Print compact summary
  --print-json           Print generated JSON
  -h, --help             Show help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --instance)
            INSTANCE="${2:-}"
            shift 2
            ;;
        --path)
            BOT_PATH="${2:-}"
            shift 2
            ;;
        --mode)
            MODE="${2:-}"
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
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

SCRIPT_PATH="$(readlink -f "$0")"
MAINTENANCE_DIR="$(dirname "$SCRIPT_PATH")"

if [[ -z "$BOT_PATH" ]]; then
    BOT_PATH="$(cd "$MAINTENANCE_DIR/.." && pwd)"
fi

if [[ -z "$INSTANCE" ]]; then
    INSTANCE="$(basename "$BOT_PATH" | tr '[:upper:]' '[:lower:]')"
fi

INSTANCE_LOWER="$(echo "$INSTANCE" | tr '[:upper:]' '[:lower:]')"

CONFIG_FILE="$BOT_PATH/config/config.ini"
TOKEN_FILE="$BOT_PATH/config/report_upload.token"
REPORTS_DIR="$BOT_PATH/reports"
PENDING_DIR="$REPORTS_DIR/pending"

mkdir -p "$PENDING_DIR"

if [[ -z "$PUSH_URL" && -r "$CONFIG_FILE" ]]; then
    PUSH_URL="$(awk -F '=' '/^[[:space:]]*BOOT_REPORT_PUSH_URL[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' "$CONFIG_FILE" | tail -n1 || true)"
fi

if [[ -z "$PUSH_URL" ]]; then
    PUSH_URL="https://opscon.blenk.co.at/api/jrbot_boot_report_ingest.php"
fi

if [[ -z "$TOKEN" && -r "$TOKEN_FILE" ]]; then
    TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE" || true)"
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_capture() {
    local timeout_seconds="$1"
    shift

    if command_exists timeout; then
        timeout "$timeout_seconds" "$@" 2>&1 || true
    else
        "$@" 2>&1 || true
    fi
}

service_state_json() {
    local unit="$1"

    if ! command_exists systemctl; then
        printf '{"unit":"%s","exists":false,"active":false,"enabled":false,"load_state":"","active_state":"","sub_state":""}' "$unit"
        return
    fi

    local load_state active_state sub_state enabled active
    load_state="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    active_state="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    sub_state="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"

    if systemctl is-enabled "$unit" >/dev/null 2>&1; then
        enabled="true"
    else
        enabled="false"
    fi

    if systemctl is-active "$unit" >/dev/null 2>&1; then
        active="true"
    else
        active="false"
    fi

    python3 - "$unit" "$load_state" "$active_state" "$sub_state" "$enabled" "$active" <<'PY'
import json
import sys

unit, load_state, active_state, sub_state, enabled, active = sys.argv[1:]
print(json.dumps({
    "unit": unit,
    "exists": bool(load_state and load_state != "not-found"),
    "active": active == "true",
    "enabled": enabled == "true",
    "load_state": load_state,
    "active_state": active_state,
    "sub_state": sub_state,
}))
PY
}

CREATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TS_FILE="$(date -u +"%Y%m%d_%H%M%S")"
REPORT_FILE="$PENDING_DIR/jrbot-boot-report-${INSTANCE_LOWER}-${TS_FILE}.json"

HOSTNAME_VALUE="$(hostname 2>/dev/null || true)"
KERNEL_VALUE="$(uname -a 2>/dev/null || true)"
PLATFORM_VALUE="$(uname -s 2>/dev/null || true)"
MACHINE_VALUE="$(uname -m 2>/dev/null || true)"
BOOT_TIME="$(uptime -s 2>/dev/null || true)"
UPTIME_PRETTY="$(uptime -p 2>/dev/null || uptime 2>/dev/null || true)"
BOOT_ID=""
if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
fi

RPI_MODEL=""
if [[ -r /proc/device-tree/model ]]; then
    RPI_MODEL="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)"
elif [[ -r /sys/firmware/devicetree/base/model ]]; then
    RPI_MODEL="$(tr -d '\000' < /sys/firmware/devicetree/base/model 2>/dev/null || true)"
fi

MEMORY_TOTAL_MB=""
if [[ -r /proc/meminfo ]]; then
    MEMORY_TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
fi

OS_RELEASE="$(cat /etc/os-release 2>/dev/null || true)"

HOSTNAME_I="$(hostname -I 2>/dev/null | xargs || true)"
ALL_IPV4=""
if command_exists ip; then
    ALL_IPV4="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd ' ' - || true)"
fi

IP_ADDR_JSON="[]"
if command_exists ip; then
    IP_ADDR_JSON="$(ip -j addr show 2>/dev/null || echo '[]')"
fi

IP_ROUTE="$(ip route 2>/dev/null || true)"
DEFAULT_ROUTE="$(ip route 2>/dev/null | grep '^default ' | head -n1 || true)"
DEFAULT_GATEWAY="$(echo "$DEFAULT_ROUTE" | awk '{for (i=1; i<=NF; i++) if ($i=="via") print $(i+1)}' | head -n1 || true)"
ROUTE_GET_1111="$(ip route get 1.1.1.1 2>/dev/null || true)"

GATEWAY_PING_OK="false"
if [[ -n "$DEFAULT_GATEWAY" ]]; then
    if ping -c 1 -W 2 "$DEFAULT_GATEWAY" >/dev/null 2>&1; then
        GATEWAY_PING_OK="true"
    fi
fi

DNS_OK="false"
DNS_TEST_OUTPUT=""
if command_exists getent; then
    DNS_TEST_OUTPUT="$(getent hosts google.com 2>/dev/null || true)"
    if [[ -n "$DNS_TEST_OUTPUT" ]]; then
        DNS_OK="true"
    fi
fi

RESOLV_CONF="$(cat /etc/resolv.conf 2>/dev/null || true)"

WLAN_STATUS="$(run_capture 5 ip addr show wlan0)"
ETH_STATUS="$(run_capture 5 ip addr show eth0)"

DF_ROOT="$(df -hT / 2>/dev/null || true)"
DF_BOT="$(df -hT "$BOT_PATH" 2>/dev/null || true)"
LSBLK_JSON="{}"
if command_exists lsblk; then
    LSBLK_JSON="$(lsblk -J -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL,RM,RO,TRAN 2>/dev/null || echo '{}')"
fi

JOURNAL_LIST_BOOTS="$(journalctl --list-boots --no-pager 2>/dev/null | tail -n 10 || true)"
JOURNAL_CURRENT_WARNINGS="$(journalctl -b -p warning --no-pager -n 80 2>/dev/null || true)"
JOURNAL_PREVIOUS_WARNINGS="$(journalctl -b -1 -p warning --no-pager -n 80 2>/dev/null || true)"
JOURNAL_RUNNER_CURRENT="$(journalctl -u "bot-runner@${INSTANCE_LOWER}.service" -b --no-pager -n 80 2>/dev/null || true)"
JOURNAL_RUNNER_PREVIOUS="$(journalctl -u "bot-runner@${INSTANCE_LOWER}.service" -b -1 --no-pager -n 80 2>/dev/null || true)"

HAS_IPV4="false"
if [[ -n "$ALL_IPV4" || -n "$HOSTNAME_I" ]]; then
    if echo "$ALL_IPV4 $HOSTNAME_I" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        HAS_IPV4="true"
    fi
fi

HAS_DEFAULT_ROUTE="false"
if [[ -n "$DEFAULT_ROUTE" ]]; then
    HAS_DEFAULT_ROUTE="true"
fi

SSH_ACTIVE="false"
if command_exists systemctl && systemctl is-active ssh >/dev/null 2>&1; then
    SSH_ACTIVE="true"
fi

BOT_TIMER_ACTIVE="false"
if command_exists systemctl && systemctl is-active "bot-runner@${INSTANCE_LOWER}.timer" >/dev/null 2>&1; then
    BOT_TIMER_ACTIVE="true"
fi

HEALTH_STATE="warning"
if [[ "$HAS_IPV4" == "true" && "$HAS_DEFAULT_ROUTE" == "true" && "$DNS_OK" == "true" ]]; then
    HEALTH_STATE="ok"
fi

export JRBR_SCRIPT_VERSION="$SCRIPT_VERSION"
export JRBR_SCHEMA_VERSION="$SCHEMA_VERSION"
export JRBR_INSTANCE="$INSTANCE_LOWER"
export JRBR_MODE="$MODE"
export JRBR_CREATED_AT_UTC="$CREATED_AT_UTC"

export JRBR_BOT_PATH="$BOT_PATH"
export JRBR_MAINTENANCE_DIR="$MAINTENANCE_DIR"
export JRBR_REPORTS_DIR="$REPORTS_DIR"

export JRBR_HOSTNAME="$HOSTNAME_VALUE"
export JRBR_KERNEL="$KERNEL_VALUE"
export JRBR_PLATFORM="$PLATFORM_VALUE"
export JRBR_MACHINE="$MACHINE_VALUE"
export JRBR_RPI_MODEL="$RPI_MODEL"
export JRBR_MEMORY_TOTAL_MB="$MEMORY_TOTAL_MB"
export JRBR_BOOT_TIME="$BOOT_TIME"
export JRBR_UPTIME_PRETTY="$UPTIME_PRETTY"
export JRBR_BOOT_ID="$BOOT_ID"
export JRBR_OS_RELEASE="$OS_RELEASE"

export JRBR_HOSTNAME_I="$HOSTNAME_I"
export JRBR_ALL_IPV4="$ALL_IPV4"
export JRBR_IP_ADDR_JSON="$IP_ADDR_JSON"
export JRBR_IP_ROUTE="$IP_ROUTE"
export JRBR_DEFAULT_ROUTE="$DEFAULT_ROUTE"
export JRBR_DEFAULT_GATEWAY="$DEFAULT_GATEWAY"
export JRBR_ROUTE_GET_1111="$ROUTE_GET_1111"
export JRBR_GATEWAY_PING_OK="$GATEWAY_PING_OK"
export JRBR_DNS_OK="$DNS_OK"
export JRBR_DNS_TEST_OUTPUT="$DNS_TEST_OUTPUT"
export JRBR_RESOLV_CONF="$RESOLV_CONF"
export JRBR_WLAN_STATUS="$WLAN_STATUS"
export JRBR_ETH_STATUS="$ETH_STATUS"

export JRBR_DF_ROOT="$DF_ROOT"
export JRBR_DF_BOT="$DF_BOT"
export JRBR_LSBLK_JSON="$LSBLK_JSON"

export JRBR_JOURNAL_LIST_BOOTS="$JOURNAL_LIST_BOOTS"
export JRBR_JOURNAL_CURRENT_WARNINGS="$JOURNAL_CURRENT_WARNINGS"
export JRBR_JOURNAL_PREVIOUS_WARNINGS="$JOURNAL_PREVIOUS_WARNINGS"
export JRBR_JOURNAL_RUNNER_CURRENT="$JOURNAL_RUNNER_CURRENT"
export JRBR_JOURNAL_RUNNER_PREVIOUS="$JOURNAL_RUNNER_PREVIOUS"

export JRBR_HEALTH_STATE="$HEALTH_STATE"
export JRBR_HAS_IPV4="$HAS_IPV4"
export JRBR_HAS_DEFAULT_ROUTE="$HAS_DEFAULT_ROUTE"
export JRBR_SSH_ACTIVE="$SSH_ACTIVE"
export JRBR_BOT_TIMER_ACTIVE="$BOT_TIMER_ACTIVE"

python3 > "$REPORT_FILE" <<'PY'
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


def env_ipv4_list(name: str):
    raw = env(name)
    if not raw.strip():
        return []
    return [item for item in raw.split() if item.count(".") == 3]


def json_from_env(name: str, fallback):
    raw = env(name)
    try:
        return json.loads(raw)
    except Exception:
        return fallback


report = {
    "schema": env("JRBR_SCHEMA_VERSION"),
    "script_version": env("JRBR_SCRIPT_VERSION"),
    "instance": env("JRBR_INSTANCE"),
    "mode": env("JRBR_MODE"),
    "created_at_utc": env("JRBR_CREATED_AT_UTC"),
    "security": {
        "read_only": True,
        "secrets_redacted": True,
        "secret_values_included": False,
    },
    "bot_context": {
        "install_path": env("JRBR_BOT_PATH"),
        "maintenance_path": env("JRBR_MAINTENANCE_DIR"),
        "reports_path": env("JRBR_REPORTS_DIR"),
    },
    "host": {
        "hostname": env("JRBR_HOSTNAME"),
        "kernel": env("JRBR_KERNEL"),
        "platform": env("JRBR_PLATFORM"),
        "machine": env("JRBR_MACHINE"),
        "raspberry_pi_model": env("JRBR_RPI_MODEL"),
        "memory_total_mb": env_int_or_none("JRBR_MEMORY_TOTAL_MB"),
        "boot_time": env("JRBR_BOOT_TIME"),
        "uptime_pretty": env("JRBR_UPTIME_PRETTY"),
        "boot_id": env("JRBR_BOOT_ID"),
        "os_release": env("JRBR_OS_RELEASE"),
    },
    "storage": {
        "df_root": env("JRBR_DF_ROOT"),
        "df_bot": env("JRBR_DF_BOT"),
        "lsblk": json_from_env("JRBR_LSBLK_JSON", {}),
    },
    "network": {
        "hostname_i": env("JRBR_HOSTNAME_I"),
        "all_ipv4": env_ipv4_list("JRBR_ALL_IPV4"),
        "ip_addr": json_from_env("JRBR_IP_ADDR_JSON", []),
        "ip_route": env("JRBR_IP_ROUTE"),
        "default_route": env("JRBR_DEFAULT_ROUTE"),
        "default_gateway": env("JRBR_DEFAULT_GATEWAY"),
        "route_get_1_1_1_1": env("JRBR_ROUTE_GET_1111"),
        "gateway_ping_ok": env_bool("JRBR_GATEWAY_PING_OK"),
        "dns_ok": env_bool("JRBR_DNS_OK"),
        "dns_test_output": env("JRBR_DNS_TEST_OUTPUT"),
        "resolv_conf": env("JRBR_RESOLV_CONF"),
        "wlan0": env("JRBR_WLAN_STATUS"),
        "eth0": env("JRBR_ETH_STATUS"),
    },
    "services": {},
    "journals": {
        "list_boots": env("JRBR_JOURNAL_LIST_BOOTS"),
        "current_boot_warnings": env("JRBR_JOURNAL_CURRENT_WARNINGS"),
        "previous_boot_warnings": env("JRBR_JOURNAL_PREVIOUS_WARNINGS"),
        "runner_current_boot": env("JRBR_JOURNAL_RUNNER_CURRENT"),
        "runner_previous_boot": env("JRBR_JOURNAL_RUNNER_PREVIOUS"),
    },
    "summary": {
        "health_state": env("JRBR_HEALTH_STATE"),
        "has_ipv4": env_bool("JRBR_HAS_IPV4"),
        "has_default_route": env_bool("JRBR_HAS_DEFAULT_ROUTE"),
        "gateway_ping_ok": env_bool("JRBR_GATEWAY_PING_OK"),
        "dns_ok": env_bool("JRBR_DNS_OK"),
        "ssh_active": env_bool("JRBR_SSH_ACTIVE"),
        "bot_timer_active": env_bool("JRBR_BOT_TIMER_ACTIVE"),
    },
}

print(json.dumps(report, indent=2, ensure_ascii=False))
PY

python3 -m json.tool "$REPORT_FILE" >/dev/null

if [[ "$PRINT_JSON" == "true" ]]; then
    cat "$REPORT_FILE"
fi

if [[ "$PRINT_SUMMARY" == "true" ]]; then
    echo "=== JR-Bot Boot Report Summary ==="
    echo "Instance:        ${INSTANCE_LOWER}"
    echo "Mode:            ${MODE}"
    echo "Report file:     ${REPORT_FILE}"
    echo "Health:          ${HEALTH_STATE}"
    echo "IPv4:            ${HAS_IPV4}"
    echo "Default route:   ${HAS_DEFAULT_ROUTE}"
    echo "Gateway ping:    ${GATEWAY_PING_OK}"
    echo "DNS:             ${DNS_OK}"
    echo "SSH active:      ${SSH_ACTIVE}"
    echo "Bot timer active:${BOT_TIMER_ACTIVE}"
    echo
fi

upload_one_report() {
    local file="$1"

    if [[ "$NO_UPLOAD" == "true" ]]; then
        return 1
    fi

    if [[ -z "$PUSH_URL" || -z "$TOKEN" ]]; then
        return 1
    fi

    local response_file http_code
    response_file="$(mktemp /tmp/jrbot-boot-report-upload-response.XXXXXX.txt)"

    http_code="$(curl -fsSL \
        -w "%{http_code}" \
        -o "$response_file" \
        -X POST \
        -F "token=${TOKEN}" \
        -F "instance=${INSTANCE_LOWER}" \
        -F "mode=${MODE}" \
        -F "report_file=@${file};type=application/json" \
        "$PUSH_URL" || true)"

    if [[ "$http_code" != "200" ]]; then
        warn "Upload failed for ${file}. HTTP code: ${http_code}"
        if [[ -s "$response_file" ]]; then
            cat "$response_file" >&2 || true
        fi
        rm -f "$response_file"
        return 1
    fi

    rm -f "$response_file"
    return 0
}

UPLOAD_COUNT=0
FAILED_COUNT=0

if [[ "$NO_UPLOAD" != "true" && -n "$PUSH_URL" && -n "$TOKEN" ]]; then
    shopt -s nullglob
    for pending_file in "$PENDING_DIR"/jrbot-boot-report-"${INSTANCE_LOWER}"-*.json; do
        if upload_one_report "$pending_file"; then
            UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
            if [[ "$KEEP_LOCAL" != "true" ]]; then
                rm -f "$pending_file"
            fi
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done
    shopt -u nullglob
else
    warn "Upload skipped. Missing token, missing push URL or --no-upload was set."
fi

if [[ "$PRINT_SUMMARY" == "true" ]]; then
    echo "Upload success count: ${UPLOAD_COUNT}"
    echo "Upload failed count:  ${FAILED_COUNT}"
fi

exit 0
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/maintenance/jrbot_boot_report.sh"
    sudo chmod 755 "$install_dir/maintenance/jrbot_boot_report.sh"
}

# ----------------------------------------------------------
# journald persistence
# ----------------------------------------------------------

enable_persistent_journald() {
    info "Aktiviere persistentes journald..."

    sudo mkdir -p /var/log/journal
    sudo systemctl restart systemd-journald || true

    info "Persistentes journald wurde vorbereitet."
}

# ----------------------------------------------------------
# systemd setup
# ----------------------------------------------------------

install_runner_systemd_templates() {
    info "Installiere Runner systemd Template Units..."

    sudo tee "$SYSTEMD_RUNNER_SERVICE_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Runner (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=%i
Group=%i
WorkingDirectory=/opt/bots/%i
ExecStart=/opt/bots/%i/venv/bin/python /opt/bots/%i/src/job_runner.py --config /opt/bots/%i/config/config.ini

StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_RUNNER_TIMER_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Timer (%i)

[Timer]
OnBootSec=90s
OnUnitActiveSec=60s
AccuracySec=15s
Persistent=true
Unit=bot-runner@%i.service

[Install]
WantedBy=timers.target
EOF

    info "Runner systemd Templates installiert."
}

install_boot_report_systemd_templates() {
    info "Installiere Boot-Report systemd Template Units..."

    sudo tee "$SYSTEMD_BOOT_REPORT_SERVICE_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Boot Report for %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=%i
Group=%i
WorkingDirectory=/opt/bots/%i
ExecStartPre=/bin/sleep 30
ExecStart=/opt/bots/%i/maintenance/jrbot_boot_report.sh --instance %i --path /opt/bots/%i --mode one-liner

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo tee "$SYSTEMD_REPORT_UPLOAD_SERVICE_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Pending Report Upload for %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=%i
Group=%i
WorkingDirectory=/opt/bots/%i
ExecStart=/opt/bots/%i/maintenance/jrbot_boot_report.sh --instance %i --path /opt/bots/%i --mode upload-pending

StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_REPORT_UPLOAD_TIMER_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Pending Report Upload Timer for %i

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true
Unit=jrbot-report-upload@%i.service

[Install]
WantedBy=timers.target
EOF

    info "Boot-Report systemd Templates installiert."
}

enable_systemd_units() {
    local instance_name="$1"

    info "Aktiviere systemd Units für Instanz: ${instance_name}"

    sudo systemctl daemon-reload

    sudo systemctl enable --now "bot-runner@${instance_name}.timer"
    sudo systemctl enable "jrbot-boot-report@${instance_name}.service"
    sudo systemctl enable --now "jrbot-report-upload@${instance_name}.timer"

    info "systemd Units aktiviert."
}

# ----------------------------------------------------------
# Test runs
# ----------------------------------------------------------

run_manual_runner_test() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Führe manuellen Runner-Testlauf aus..."

    sudo -u "$run_as_user" "$install_dir/venv/bin/python" "$install_dir/src/job_runner.py" --config "$install_dir/config/config.ini"
}

run_manual_boot_report_test() {
    local install_dir="$1"
    local run_as_user="$2"
    local instance_name="$3"

    info "Führe manuellen Boot-Report-Testlauf aus..."

    sudo -u "$run_as_user" "$install_dir/maintenance/jrbot_boot_report.sh" \
        --instance "$instance_name" \
        --path "$install_dir" \
        --mode one-liner \
        --print-summary
}

# ----------------------------------------------------------
# Summary
# ----------------------------------------------------------

print_summary() {
    local project_name="$1"
    local bot_name="$2"
    local instance_name="$3"
    local install_dir="$4"
    local run_as_user="$5"
    local server_base="$6"
    local interval_seconds="$7"
    local boot_report_push_url="$8"
    local audit_push_url="$9"

    echo
    echo "=================================================="
    echo " Installation abgeschlossen"
    echo "=================================================="
    echo "Projekt:                  ${project_name}"
    echo "Botname:                  ${bot_name}"
    echo "Instanz:                  ${instance_name}"
    echo "Linux-User:               ${run_as_user}"
    echo "Installationspfad:        ${install_dir}"
    echo "Backend:                  remote_api"
    echo "Server Base:              ${server_base}"
    echo "Intervall:                ${interval_seconds} Sekunden"
    echo
    echo "Wichtige Pfade:"
    echo "Config:                   ${install_dir}/config/config.ini"
    echo "Report Token:             ${install_dir}/config/report_upload.token"
    echo "Runner:                   ${install_dir}/src/job_runner.py"
    echo "Runner Logfile:           ${install_dir}/logs/job_runner.log"
    echo "Boot Report Script:       ${install_dir}/maintenance/jrbot_boot_report.sh"
    echo "Pending Reports:          ${install_dir}/reports/pending"
    echo "Audit Script:             ${install_dir}/scripts/maintenance/audit_jr-bot-structure.sh"
    echo
    echo "OPSCON:"
    echo "Boot Report Push URL:     ${boot_report_push_url}"
    echo "Audit Push URL:           ${audit_push_url}"
    echo
    echo "systemd:"
    echo "Runner Timer:             bot-runner@${instance_name}.timer"
    echo "Runner Service:           bot-runner@${instance_name}.service"
    echo "Boot Report Service:      jrbot-boot-report@${instance_name}.service"
    echo "Pending Upload Timer:     jrbot-report-upload@${instance_name}.timer"
    echo
    echo "Prüfbefehle:"
    echo "sudo systemctl status bot-runner@${instance_name}.timer"
    echo "sudo systemctl status bot-runner@${instance_name}.service"
    echo "sudo systemctl status jrbot-boot-report@${instance_name}.service"
    echo "sudo systemctl status jrbot-report-upload@${instance_name}.timer"
    echo "sudo journalctl -u bot-runner@${instance_name}.service --no-pager"
    echo "sudo journalctl -u jrbot-boot-report@${instance_name}.service --no-pager"
    echo
    echo "Manuelle Testbefehle:"
    echo "sudo -u ${run_as_user} ${install_dir}/venv/bin/python ${install_dir}/src/job_runner.py --config ${install_dir}/config/config.ini"
    echo "sudo -u ${run_as_user} ${install_dir}/maintenance/jrbot_boot_report.sh --instance ${instance_name} --path ${install_dir} --mode one-liner --print-summary"
    echo
    echo "Audit-Test:"
    echo "${install_dir}/scripts/maintenance/audit_jr-bot-structure.sh --instance ${instance_name} --path ${install_dir} --print-json"
    echo "=================================================="
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------

main() {
    print_header
    check_interactive_terminal
    check_basic_commands

    echo "Onboarding"
    echo "----------"
    echo "Standardmodus: Remote Project API"
    echo "Zielbild: ein JR-Bot pro Pi / Node"
    echo "Default: TRAX / TRX"
    echo

    PROJECT_NAME="$(ask_with_default "Projektname" "$DEFAULT_PROJECT_NAME")"
    BOT_NAME="$(ask_with_default "Botname" "$DEFAULT_BOT_NAME")"

    SUGGESTED_INSTANCE="$(normalize_instance_name "$BOT_NAME")"
    if [ -z "$SUGGESTED_INSTANCE" ]; then
        SUGGESTED_INSTANCE="$DEFAULT_INSTANCE_NAME"
    fi

    INSTANCE_NAME="$(ask_with_default "Instanzname / systemd-Name" "$SUGGESTED_INSTANCE")"
    INSTANCE_NAME="$(normalize_instance_name "$INSTANCE_NAME")"
    validate_instance_name "$INSTANCE_NAME"

    SUGGESTED_RUN_USER="$INSTANCE_NAME"
    RUN_AS_USER="$(ask_with_default "Linux-Benutzer für Bot-Ausführung" "$SUGGESTED_RUN_USER")"
    RUN_AS_USER="$(normalize_instance_name "$RUN_AS_USER")"
    validate_user_name "$RUN_AS_USER"

    SUGGESTED_INSTALL_DIR="/opt/bots/${INSTANCE_NAME}"
    INSTALL_DIR="$(ask_with_default "Installationsordner" "$SUGGESTED_INSTALL_DIR")"

    SERVER_BASE="$(ask_with_default "Server Base URL" "$DEFAULT_SERVER_BASE")"
    INTERVAL_SECONDS="$(ask_with_default "Polling-Intervall in Sekunden" "$DEFAULT_INTERVAL_SECONDS")"
    validate_interval "$INTERVAL_SECONDS"

    BOOT_REPORT_PUSH_URL="$(ask_with_default "Boot Report Push URL" "$DEFAULT_BOOT_REPORT_PUSH_URL")"
    AUDIT_PUSH_URL="$(ask_with_default "Audit Push URL" "$DEFAULT_AUDIT_PUSH_URL")"

    echo
    echo "Sensible Werte werden jetzt lokal abgefragt."
    echo "Diese Werte werden nicht nach GitHub geschrieben."
    echo

    SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN eingeben")"
    PING_TOKEN="$(ask_secret_required "PING_TOKEN eingeben")"
    REPORT_UPLOAD_TOKEN="$(ask_secret_optional "REPORT_UPLOAD_TOKEN eingeben")"

    echo
    echo "Geplante Installation:"
    echo "Projekt:                   ${PROJECT_NAME}"
    echo "Botname:                   ${BOT_NAME}"
    echo "Instanzname:               ${INSTANCE_NAME}"
    echo "Linux-User:                ${RUN_AS_USER}"
    echo "Installationsordner:       ${INSTALL_DIR}"
    echo "Backend:                   remote_api"
    echo "Server Base URL:           ${SERVER_BASE}"
    echo "Polling-Intervall:         ${INTERVAL_SECONDS} Sekunden"
    echo "Boot Report Push URL:      ${BOOT_REPORT_PUSH_URL}"
    echo "Audit Push URL:            ${AUDIT_PUSH_URL}"
    echo "systemd Runner Timer:      bot-runner@${INSTANCE_NAME}.timer"
    echo "Boot Report Service:       jrbot-boot-report@${INSTANCE_NAME}.service"
    echo "Pending Upload Timer:      jrbot-report-upload@${INSTANCE_NAME}.timer"
    echo

    if ! confirm_default_yes "Installation mit diesen Werten starten?"; then
        echo "Installation abgebrochen."
        exit 0
    fi

    ensure_run_user_exists "$RUN_AS_USER"
    install_system_packages
    create_directory_structure "$INSTALL_DIR" "$RUN_AS_USER"

    create_python_venv "$INSTALL_DIR" "$RUN_AS_USER"
    create_requirements_file "$INSTALL_DIR" "$RUN_AS_USER"

    create_config_ini \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$SERVER_BASE" \
        "$INTERVAL_SECONDS" \
        "$SERVER_TOKEN" \
        "$PING_TOKEN" \
        "$BOOT_REPORT_PUSH_URL" \
        "$AUDIT_PUSH_URL"

    create_report_upload_token "$INSTALL_DIR" "$RUN_AS_USER" "$REPORT_UPLOAD_TOKEN"

    create_install_info \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$INTERVAL_SECONDS" \
        "$BOOT_REPORT_PUSH_URL" \
        "$AUDIT_PUSH_URL"

    create_job_runner "$INSTALL_DIR" "$RUN_AS_USER"
    create_system_scripts "$INSTALL_DIR" "$RUN_AS_USER"
    create_check_scripts "$INSTALL_DIR" "$RUN_AS_USER"
    create_ssh_maintenance_scripts "$INSTALL_DIR" "$RUN_AS_USER"
    create_script_docs "$INSTALL_DIR" "$RUN_AS_USER"
    create_boot_report_script "$INSTALL_DIR" "$RUN_AS_USER"
    download_github_tools "$INSTALL_DIR" "$RUN_AS_USER"

    if confirm_default_yes "Persistentes journald aktivieren?"; then
        enable_persistent_journald
    else
        warn "Persistentes journald wurde nicht aktiviert."
    fi

    if confirm_default_yes "systemd Template Units installieren/aktualisieren und Timer aktivieren?"; then
        install_runner_systemd_templates
        install_boot_report_systemd_templates
        enable_systemd_units "$INSTANCE_NAME"
    else
        warn "systemd wurde nicht aktiviert. Der Runner kann manuell gestartet werden:"
        echo "sudo -u ${RUN_AS_USER} ${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/src/job_runner.py --config ${INSTALL_DIR}/config/config.ini"
    fi

    echo
    if confirm_default_yes "Manuellen Runner-Testlauf jetzt ausführen?"; then
        run_manual_runner_test "$INSTALL_DIR" "$RUN_AS_USER"
    fi

    echo
    if confirm_default_yes "Manuellen Boot-Report-Testlauf jetzt ausführen?"; then
        run_manual_boot_report_test "$INSTALL_DIR" "$RUN_AS_USER" "$INSTANCE_NAME"
    fi

    print_summary \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$SERVER_BASE" \
        "$INTERVAL_SECONDS" \
        "$BOOT_REPORT_PUSH_URL" \
        "$AUDIT_PUSH_URL"
}

main "$@"
