#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Universal Installer
# Version: 0.2.0
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
#   - Pi stores only local runtime config, logs, state and venv
#   - systemd template units: bot-runner@.service / bot-runner@.timer
#
# Security:
#   - No secrets are embedded in this script
#   - SERVER_TOKEN and PING_TOKEN are requested interactively
#   - Local config.ini is stored with chmod 600
#
# ==========================================================

SCRIPT_VERSION="0.2.0"

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

SYSTEMD_SERVICE_TEMPLATE="/etc/systemd/system/bot-runner@.service"
SYSTEMD_TIMER_TEMPLATE="/etc/systemd/system/bot-runner@.timer"

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

    # Lowercase, replace unsupported characters with hyphen.
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
            tree
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
    sudo mkdir -p "$install_dir/src"
    sudo mkdir -p "$install_dir/config"
    sudo mkdir -p "$install_dir/logs"
    sudo mkdir -p "$install_dir/state"
    sudo mkdir -p "$install_dir/tmp"

    sudo chown -R "${run_as_user}:${run_as_user}" "$install_dir"
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
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/config/config.ini"
    sudo chmod 600 "$install_dir/config/config.ini"

    info "config.ini wurde geschützt gespeichert: ${install_dir}/config/config.ini"
}

create_install_info() {
    local install_dir="$1"
    local run_as_user="$2"
    local project_name="$3"
    local bot_name="$4"
    local instance_name="$5"
    local interval_seconds="$6"

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
Systemd timer: bot-runner@${instance_name}.timer
Interval seconds: ${interval_seconds}

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

    info "Erstelle minimalen job_runner.py für v0.2..."

    sudo tee "$install_dir/src/job_runner.py" >/dev/null <<'EOF'
#!/usr/bin/env python3
"""
JR-Bot job_runner.py
Version: 0.2 placeholder

This runner currently verifies:
- config.ini loading
- log writing
- basic remote_api configuration presence

The real get_jobs/report_job/bot_ping implementation follows in the next version.
"""

from __future__ import annotations

import configparser
from datetime import datetime, timezone
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]
CONFIG_FILE = BASE_DIR / "config" / "config.ini"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_config() -> configparser.ConfigParser:
    config = configparser.ConfigParser()
    read_files = config.read(CONFIG_FILE)

    if not read_files:
        raise FileNotFoundError(f"Config file not found or unreadable: {CONFIG_FILE}")

    return config


def write_log(message: str) -> None:
    log_file = BASE_DIR / "logs" / "bot.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)

    line = f"[{utc_now()}] {message}"

    with log_file.open("a", encoding="utf-8") as f:
        f.write(line + "\n")

    print(line)


def main() -> None:
    config = load_config()

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
        f"server_base={server_base}"
    )

    write_log("JR-Bot runner placeholder finished successfully")


if __name__ == "__main__":
    main()
EOF

    sudo chown "${run_as_user}:${run_as_user}" "$install_dir/src/job_runner.py"
    sudo chmod 755 "$install_dir/src/job_runner.py"
}

# ----------------------------------------------------------
# systemd setup
# ----------------------------------------------------------

install_systemd_templates() {
    local run_as_user="$1"

    info "Installiere systemd Template Units..."

    sudo tee "$SYSTEMD_SERVICE_TEMPLATE" >/dev/null <<EOF
[Unit]
Description=JR-Bot Runner (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${run_as_user}
Group=${run_as_user}
WorkingDirectory=/opt/bots/%i
ExecStart=/opt/bots/%i/venv/bin/python /opt/bots/%i/src/job_runner.py

StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_TIMER_TEMPLATE" >/dev/null <<'EOF'
[Unit]
Description=JR-Bot Timer (%i)

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5
Persistent=true
Unit=bot-runner@%i.service

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload

    info "systemd Templates installiert:"
    info "  ${SYSTEMD_SERVICE_TEMPLATE}"
    info "  ${SYSTEMD_TIMER_TEMPLATE}"
}

enable_systemd_timer() {
    local instance_name="$1"

    info "Aktiviere systemd Timer: bot-runner@${instance_name}.timer"

    sudo systemctl enable --now "bot-runner@${instance_name}.timer"

    info "Timer aktiviert."
}

run_manual_test() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Führe manuellen Testlauf aus..."

    sudo -u "$run_as_user" "$install_dir/venv/bin/python" "$install_dir/src/job_runner.py"
}

print_summary() {
    local project_name="$1"
    local bot_name="$2"
    local instance_name="$3"
    local install_dir="$4"
    local run_as_user="$5"
    local server_base="$6"
    local interval_seconds="$7"

    echo
    echo "=================================================="
    echo " Installation abgeschlossen"
    echo "=================================================="
    echo "Projekt:          ${project_name}"
    echo "Botname:          ${bot_name}"
    echo "Instanz:          ${instance_name}"
    echo "Linux-User:       ${run_as_user}"
    echo "Installationspfad:${install_dir}"
    echo "Backend:          remote_api"
    echo "Server Base:      ${server_base}"
    echo "Intervall:        ${interval_seconds} Sekunden"
    echo
    echo "Wichtige Pfade:"
    echo "Config:           ${install_dir}/config/config.ini"
    echo "Runner:           ${install_dir}/src/job_runner.py"
    echo "Logfile:          ${install_dir}/logs/bot.log"
    echo
    echo "systemd:"
    echo "Timer:            bot-runner@${instance_name}.timer"
    echo "Service:          bot-runner@${instance_name}.service"
    echo
    echo "Prüfbefehle:"
    echo "sudo systemctl status bot-runner@${instance_name}.timer"
    echo "sudo systemctl status bot-runner@${instance_name}.service"
    echo "sudo journalctl -u bot-runner@${instance_name}.service --no-pager"
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

    echo
    echo "Sensible Werte werden jetzt lokal abgefragt."
    echo "Diese Werte werden nicht nach GitHub geschrieben."
    echo

    SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN eingeben")"
    PING_TOKEN="$(ask_secret_required "PING_TOKEN eingeben")"

    echo
    echo "Geplante Installation:"
    echo "Projekt:             ${PROJECT_NAME}"
    echo "Botname:             ${BOT_NAME}"
    echo "Instanzname:         ${INSTANCE_NAME}"
    echo "Linux-User:          ${RUN_AS_USER}"
    echo "Installationsordner: ${INSTALL_DIR}"
    echo "Backend:             remote_api"
    echo "Server Base URL:     ${SERVER_BASE}"
    echo "Polling-Intervall:   ${INTERVAL_SECONDS} Sekunden"
    echo "systemd Timer:       bot-runner@${INSTANCE_NAME}.timer"
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
        "$PING_TOKEN"

    create_install_info \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$INTERVAL_SECONDS"

    create_job_runner "$INSTALL_DIR" "$RUN_AS_USER"

    if confirm_default_yes "systemd Template Units installieren/aktualisieren und Timer aktivieren?"; then
        install_systemd_templates "$RUN_AS_USER"
        enable_systemd_timer "$INSTANCE_NAME"
    else
        warn "systemd wurde nicht aktiviert. Der Runner kann manuell gestartet werden:"
        echo "sudo -u ${RUN_AS_USER} ${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/src/job_runner.py"
    fi

    echo
    if confirm_default_yes "Manuellen Testlauf jetzt ausführen?"; then
        run_manual_test "$INSTALL_DIR" "$RUN_AS_USER"
    fi

    print_summary \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$SERVER_BASE" \
        "$INTERVAL_SECONDS"
}

main "$@"
