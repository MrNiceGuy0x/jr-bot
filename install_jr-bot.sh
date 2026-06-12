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
#   - Downloads audits/audit_jr-bot-boot-report.sh
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

    local docs_dir="$install_dir/docs/scripts"

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

Read-only JR-Bot structure audit script downloaded from GitHub audits/.
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
# Download existing GitHub audits
# ----------------------------------------------------------

download_github_audits() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Lade vorhandene GitHub Audits herunter..."

    local audit_target="$install_dir/audits/audit_jr-bot-structure.sh"
    local audit_url="${GITHUB_RAW_BASE}/audits/audit_jr-bot-structure.sh"

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
# Boot report audit script
# ----------------------------------------------------------

create_boot_report_script() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Lade Boot-Report-Audit von GitHub herunter..."

    local audit_target="$install_dir/audits/audit_jr-bot-boot-report.sh"
    local audit_url="${GITHUB_RAW_BASE}/audits/audit_jr-bot-boot-report.sh"
    local tmp_file="/tmp/audit_jr-bot-boot-report.sh"

    rm -f "$tmp_file" || true

    if curl -fsSL "$audit_url" -o "$tmp_file"; then
        sudo mv "$tmp_file" "$audit_target"
        sudo chown "${run_as_user}:${run_as_user}" "$audit_target"
        sudo chmod 755 "$audit_target"
        info "Boot-Report-Audit installiert: ${audit_target}"
    else
        rm -f "$tmp_file" || true
        die "Boot-Report-Audit konnte nicht von GitHub geladen werden: ${audit_url}"
    fi
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
    echo "Audit Script:             ${install_dir}/audits/audit_jr-bot-structure.sh"
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
    echo "${install_dir}/audits/audit_jr-bot-structure.sh --instance ${instance_name} --path ${install_dir} --print-json"
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
    download_github_audits "$INSTALL_DIR" "$RUN_AS_USER"

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
