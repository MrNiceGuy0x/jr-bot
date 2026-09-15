#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Universal Installer
# Version: 0.4.0-dev-public-v1
# ==========================================================
#
# Public-v1 audit boundary:
#   - Audit reports are stored locally only.
#   - No audit upload endpoint, audit credential or external
#     audit database is configured by this installer.
#
# Runtime backend:
#   - The generic job runner may use a user-configured project
#     API. Runtime backend configuration is independent from
#     local-only audit storage.
# ==========================================================

SCRIPT_VERSION="0.4.0-dev-public-v1"

DEFAULT_PROJECT_NAME="My Project"
DEFAULT_BOT_NAME="JRBot"
DEFAULT_INSTANCE_NAME="jrbot"
DEFAULT_INTERVAL_SECONDS="60"

GITHUB_REF="${JR_BOT_GITHUB_REF:-main}"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/MrNiceGuy0x/jr-bot/${GITHUB_REF}"

SYSTEMD_RUNNER_SERVICE_TEMPLATE="/etc/systemd/system/bot-runner@.service"
SYSTEMD_RUNNER_TIMER_TEMPLATE="/etc/systemd/system/bot-runner@.timer"
SYSTEMD_BOOT_AUDIT_SERVICE_TEMPLATE="/etc/systemd/system/jrbot-boot-report-audit@.service"

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

ask_with_default() {
    local prompt="$1"
    local default_value="$2"
    local value=""

    read -rp "${prompt} [${default_value}]: " value </dev/tty
    value="${value:-$default_value}"
    printf '%s\n' "$value"
}

ask_required() {
    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do
        read -rp "${prompt}: " value </dev/tty
        if [[ -z "$value" ]]; then
            echo "This value is required." >/dev/tty
        fi
    done

    printf '%s\n' "$value"
}

ask_secret_required() {
    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do
        read -rsp "${prompt}: " value </dev/tty
        echo >/dev/tty
        if [[ -z "$value" ]]; then
            echo "This value is required." >/dev/tty
        fi
    done

    printf '%s\n' "$value"
}

confirm_default_yes() {
    local prompt="$1"
    local answer=""

    read -rp "${prompt} [Y/n]: " answer </dev/tty

    case "$answer" in
        n|N|no|NO|No) return 1 ;;
        *) return 0 ;;
    esac
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        die "Required command missing: ${command_name}"
    fi
}

normalize_instance_value() {
    local value="$1"
    local LC_ALL=C

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

    if (( ${#value} < 1 || ${#value} > 32 )); then
        die "Invalid instance name length."
    fi

    if ! [[ "$value" =~ ^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$ ]]; then
        die "Invalid instance name. Allowed: lowercase a-z, 0-9, _ and -; first character must be a letter and final character alphanumeric."
    fi

    printf '%s\n' "$value"
}

validate_runtime_user_separation() {
    local run_as_user="$1"
    local admin_user="${SUDO_USER:-$(id -un)}"

    case "$run_as_user" in
        root|pi|admin|jradmin|www-data|systemd-network|systemd-resolve|daemon|nobody)
            die "Runtime user '${run_as_user}' is reserved. Choose another instance name."
            ;;
    esac

    if [[ "$run_as_user" == "$admin_user" ]]; then
        die "Runtime user must differ from the current administrator account."
    fi
}

validate_interval() {
    local interval="$1"

    if [[ ! "$interval" =~ ^[0-9]+$ ]]; then
        die "Polling interval must be numeric."
    fi

    if (( interval < 10 )); then
        die "Polling interval is too low. Minimum: 10 seconds."
    fi
}

check_interactive_terminal() {
    if [[ ! -e /dev/tty ]]; then
        die "No interactive terminal available. Download the installer and run it from a terminal."
    fi
}

check_basic_commands() {
    require_command bash
    require_command curl
    require_command sudo
    require_command tr
}

ensure_run_user_exists() {
    local run_as_user="$1"

    if id "$run_as_user" >/dev/null 2>&1; then
        info "Runtime user already exists: ${run_as_user}"
        return 0
    fi

    warn "Runtime user does not exist yet: ${run_as_user}"

    if confirm_default_yes "Create dedicated system user '${run_as_user}' now?"; then
        sudo useradd --system --create-home --shell /usr/sbin/nologin "$run_as_user"
        info "Runtime user created: ${run_as_user}"
    else
        die "Installation requires a dedicated runtime user."
    fi
}

install_system_packages() {
    info "Installing system packages..."

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
        warn "apt-get not found. Package installation skipped."
    fi
}

assert_foundation_path_safety() {
    local install_dir="$1"
    local current="/"
    local part=""
    local rel=""
    local -a parts=()
    local -a canonical_dirs=(
        config
        src
        scripts
        audits
        docs
        docs/scripts
        docs/audits
        reports
        reports/audits
        logs
        state
        tmp
        venv
    )

    IFS='/' read -r -a parts <<< "${install_dir#/}"
    for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue

        if [[ "$current" == "/" ]]; then
            current="/${part}"
        else
            current="${current}/${part}"
        fi

        if [[ -L "$current" ]]; then
            die "Refusing Target path with symlink component: ${current}"
        fi
    done

    for rel in "${canonical_dirs[@]}"; do
        if [[ -L "$install_dir/$rel" ]]; then
            die "Refusing canonical runtime directory symlink: $install_dir/$rel"
        fi
    done
}

apply_foundation_directory_permissions() {
    local install_dir="$1"
    local run_as_user="$2"
    local rel=""
    local -a privileged_dirs=(
        config
        src
        scripts
        audits
        docs
        docs/scripts
        docs/audits
        venv
    )
    local -a writable_dirs=(
        reports
        reports/audits
        logs
        state
        tmp
    )

    sudo chown "root:${run_as_user}" "$install_dir"
    sudo chmod 0750 "$install_dir"

    for rel in "${privileged_dirs[@]}"; do
        sudo chown "root:${run_as_user}" "$install_dir/$rel"
        sudo chmod 0750 "$install_dir/$rel"
    done

    for rel in "${writable_dirs[@]}"; do
        sudo chown "${run_as_user}:${run_as_user}" "$install_dir/$rel"
        sudo chmod 0750 "$install_dir/$rel"
    done
}

normalize_venv_permissions() {
    local install_dir="$1"
    local run_as_user="$2"
    local venv_dir="$install_dir/venv"

    sudo chown -hR "root:${run_as_user}" "$venv_dir"
    sudo find -P "$venv_dir" -type d -exec chmod 0750 {} +
    sudo find -P "$venv_dir" -type f -perm /111 -exec chmod 0750 {} +
    sudo find -P "$venv_dir" -type f ! -perm /111 -exec chmod 0640 {} +
}

create_directory_structure() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Creating runtime structure under ${install_dir}..."

    assert_foundation_path_safety "$install_dir"

    sudo mkdir -p \
        "$install_dir/config" \
        "$install_dir/src" \
        "$install_dir/scripts" \
        "$install_dir/audits" \
        "$install_dir/docs/scripts" \
        "$install_dir/docs/audits" \
        "$install_dir/reports/audits" \
        "$install_dir/logs" \
        "$install_dir/state" \
        "$install_dir/tmp" \
        "$install_dir/venv"

    apply_foundation_directory_permissions "$install_dir" "$run_as_user"

    info "Runtime structure created."
}

create_python_venv() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Creating privileged Python virtual environment..."
    sudo python3 -m venv "$install_dir/venv"
    sudo "$install_dir/venv/bin/python" -m pip install --upgrade pip
    normalize_venv_permissions "$install_dir" "$run_as_user"
}

create_requirements_file() {
    local install_dir="$1"
    local run_as_user="$2"

    sudo tee "$install_dir/requirements.txt" >/dev/null <<'EOF'
requests
python-dotenv
EOF

    sudo chown "root:${run_as_user}" "$install_dir/requirements.txt"
    sudo chmod 0640 "$install_dir/requirements.txt"

    sudo "$install_dir/venv/bin/pip" install -r "$install_dir/requirements.txt"
    normalize_venv_permissions "$install_dir" "$run_as_user"
}

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
AUDIT_REPORTS_DIR = reports/audits
EOF

    sudo chown "root:${run_as_user}" "$install_dir/config/config.ini"
    sudo chmod 0640 "$install_dir/config/config.ini"

    info "Protected config written to ${install_dir}/config/config.ini"
}

create_install_info() {
    local install_dir="$1"
    local run_as_user="$2"
    local project_name="$3"
    local bot_name="$4"
    local instance_name="$5"
    local interval_seconds="$6"

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
Boot audit service: jrbot-boot-report-audit@${instance_name}.service
Interval seconds: ${interval_seconds}
Audit storage: ${install_dir}/reports/audits

Installed at UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    sudo chown "root:${run_as_user}" "$install_dir/install_info.txt"
    sudo chmod 0640 "$install_dir/install_info.txt"
}

create_job_runner() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Creating generic job_runner.py placeholder..."

    sudo tee "$install_dir/src/job_runner.py" >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""
JR-Bot job_runner.py
Version: 0.4.0-dev

This runner currently verifies:
- config.ini loading
- optional --config argument
- log writing to logs/job_runner.log
- basic remote_api configuration presence

The full generic job protocol is outside the public-v1 audit cleanup scope.
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
PYEOF

    sudo chown "root:${run_as_user}" "$install_dir/src/job_runner.py"
    sudo chmod 0640 "$install_dir/src/job_runner.py"
}

download_public_file() {
    local source_path="$1"
    local target_path="$2"
    local mode="$3"
    local group="$4"

    local tmp_file
    tmp_file="$(mktemp)"

    if ! curl -fsSL "${GITHUB_RAW_BASE}/${source_path}" -o "$tmp_file"; then
        rm -f "$tmp_file"
        die "Failed to download public JR-Bot file: ${source_path}"
    fi

    sudo mkdir -p "$(dirname "$target_path")"
    sudo mv "$tmp_file" "$target_path"
    sudo chown "root:${group}" "$target_path"
    sudo chmod "$mode" "$target_path"
}

install_public_runtime_files() {
    local install_dir="$1"
    local run_as_user="$2"

    info "Installing canonical public scripts, audits and documentation..."

    local scripts=(
        cancel_shutdown.sh
        check_disk.sh
        check_memory.sh
        reboot.sh
        shutdown.sh
        ssh_start.sh
        ssh_status.sh
        ssh_stop.sh
        tail_runner_log.sh
        uptime_info.sh
    )

    local audits=(
        audit_jr-bot-boot-report.sh
        audit_jr-bot-network-health.sh
        audit_jr-bot-structure.sh
    )

    local script_docs=(
        cancel_shutdown.md
        check_disk.md
        check_memory.md
        reboot.md
        shutdown.md
        ssh_start.md
        ssh_status.md
        ssh_stop.md
        tail_runner_log.md
        uptime_info.md
    )

    local audit_docs=(
        audit-local-storage-contract.md
        audit_jr-bot-boot-report.md
        audit_jr-bot-network-health.md
        audit_jr-bot-structure.md
    )

    local name

    for name in "${scripts[@]}"; do
        download_public_file "scripts/${name}" "$install_dir/scripts/${name}" 750 "$run_as_user"
    done

    for name in "${audits[@]}"; do
        download_public_file "audits/${name}" "$install_dir/audits/${name}" 750 "$run_as_user"
    done

    for name in "${script_docs[@]}"; do
        download_public_file "docs/scripts/${name}" "$install_dir/docs/scripts/${name}" 640 "$run_as_user"
    done

    for name in "${audit_docs[@]}"; do
        download_public_file "docs/audits/${name}" "$install_dir/docs/audits/${name}" 640 "$run_as_user"
    done
}

install_systemd_templates() {
    info "Installing systemd template units..."

    local tmp_service
    local tmp_timer
    local tmp_boot

    tmp_service="$(mktemp)"
    tmp_timer="$(mktemp)"
    tmp_boot="$(mktemp)"

    curl -fsSL "${GITHUB_RAW_BASE}/systemd/bot-runner@.service" -o "$tmp_service" \
        || { rm -f "$tmp_service" "$tmp_timer" "$tmp_boot"; die "Failed to download bot-runner@.service"; }

    curl -fsSL "${GITHUB_RAW_BASE}/systemd/bot-runner@.timer" -o "$tmp_timer" \
        || { rm -f "$tmp_service" "$tmp_timer" "$tmp_boot"; die "Failed to download bot-runner@.timer"; }

    curl -fsSL "${GITHUB_RAW_BASE}/systemd/jrbot-boot-report-audit@.service" -o "$tmp_boot" \
        || { rm -f "$tmp_service" "$tmp_timer" "$tmp_boot"; die "Failed to download boot audit service"; }

    sudo install -o root -g root -m 0644 "$tmp_service" "$SYSTEMD_RUNNER_SERVICE_TEMPLATE"
    sudo install -o root -g root -m 0644 "$tmp_timer" "$SYSTEMD_RUNNER_TIMER_TEMPLATE"
    sudo install -o root -g root -m 0644 "$tmp_boot" "$SYSTEMD_BOOT_AUDIT_SERVICE_TEMPLATE"

    rm -f "$tmp_service" "$tmp_timer" "$tmp_boot"
}

enable_persistent_journald() {
    sudo mkdir -p /var/log/journal
    sudo systemctl restart systemd-journald || true
    info "Persistent journald prepared."
}

enable_systemd_units() {
    local instance_name="$1"

    sudo systemctl daemon-reload
    sudo systemctl enable --now "bot-runner@${instance_name}.timer"
    sudo systemctl enable "jrbot-boot-report-audit@${instance_name}.service"

    info "systemd units enabled."
}

run_manual_runner_test() {
    local install_dir="$1"
    local run_as_user="$2"

    sudo -u "$run_as_user" \
        "$install_dir/venv/bin/python" \
        "$install_dir/src/job_runner.py" \
        --config "$install_dir/config/config.ini"
}

run_manual_boot_audit_test() {
    local install_dir="$1"
    local run_as_user="$2"
    local instance_name="$3"

    sudo -u "$run_as_user" \
        "$install_dir/audits/audit_jr-bot-boot-report.sh" \
        --instance "$instance_name" \
        --path "$install_dir" \
        --mode target \
        --print-summary
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
    echo " Installation complete"
    echo "=================================================="
    echo "Project:              ${project_name}"
    echo "Bot:                  ${bot_name}"
    echo "Instance:             ${instance_name}"
    echo "Runtime user:         ${run_as_user}"
    echo "Install path:         ${install_dir}"
    echo "Backend:              remote_api"
    echo "Server base:          ${server_base}"
    echo "Polling interval:     ${interval_seconds} seconds"
    echo
    echo "Local runtime paths:"
    echo "Config:               ${install_dir}/config/config.ini"
    echo "Runner:               ${install_dir}/src/job_runner.py"
    echo "Runner log:           ${install_dir}/logs/job_runner.log"
    echo "Scripts:              ${install_dir}/scripts"
    echo "Audits:               ${install_dir}/audits"
    echo "Local audit reports:  ${install_dir}/reports/audits"
    echo
    echo "systemd:"
    echo "Runner timer:         bot-runner@${instance_name}.timer"
    echo "Runner service:       bot-runner@${instance_name}.service"
    echo "Boot audit service:   jrbot-boot-report-audit@${instance_name}.service"
    echo
    echo "Checks:"
    echo "sudo systemctl status bot-runner@${instance_name}.timer"
    echo "sudo systemctl status jrbot-boot-report-audit@${instance_name}.service"
    echo "${install_dir}/audits/audit_jr-bot-structure.sh --instance ${instance_name} --path ${install_dir} --print-json"
    echo "=================================================="
}

main() {
    print_header
    check_interactive_terminal
    check_basic_commands

    echo "Public v1 onboarding"
    echo "--------------------"
    echo "Target: one JR-Bot runtime per node under /opt/bots/<instance>"
    echo "Audit storage: local only"
    echo

    PROJECT_NAME="$(ask_with_default "Project name" "$DEFAULT_PROJECT_NAME")"
    BOT_NAME="$(ask_with_default "Bot display name" "$DEFAULT_BOT_NAME")"
    INSTANCE_NAME_RAW="$(ask_with_default "Instance name" "$DEFAULT_INSTANCE_NAME")"
    INSTANCE_NAME="$(normalize_instance_value "$INSTANCE_NAME_RAW")"

    RUN_AS_USER="$INSTANCE_NAME"
    validate_runtime_user_separation "$RUN_AS_USER"

    INSTALL_DIR="/opt/bots/${INSTANCE_NAME}"

    SERVER_BASE="$(ask_required "Project API base URL")"
    INTERVAL_SECONDS="$(ask_with_default "Polling interval in seconds" "$DEFAULT_INTERVAL_SECONDS")"
    validate_interval "$INTERVAL_SECONDS"

    echo
    echo "Runtime backend credentials are stored locally in protected config.ini."
    SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN")"
    PING_TOKEN="$(ask_secret_required "PING_TOKEN")"

    echo
    echo "Planned installation:"
    echo "Project:              ${PROJECT_NAME}"
    echo "Bot:                  ${BOT_NAME}"
    echo "Instance:             ${INSTANCE_NAME}"
    echo "Runtime user:         ${RUN_AS_USER}"
    echo "Install path:         ${INSTALL_DIR}"
    echo "Backend:              remote_api"
    echo "Project API base URL: ${SERVER_BASE}"
    echo "Audit storage:        ${INSTALL_DIR}/reports/audits (local only)"
    echo

    if ! confirm_default_yes "Start installation with these values?"; then
        echo "Installation cancelled."
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
    install_public_runtime_files "$INSTALL_DIR" "$RUN_AS_USER"

    if confirm_default_yes "Enable persistent journald?"; then
        enable_persistent_journald
    else
        warn "Persistent journald not enabled."
    fi

    if confirm_default_yes "Install systemd templates and enable the runner timer / boot audit?"; then
        install_systemd_templates
        enable_systemd_units "$INSTANCE_NAME"
    else
        warn "systemd units were not installed/enabled."
    fi

    echo
    if confirm_default_yes "Run a manual runner test now?"; then
        run_manual_runner_test "$INSTALL_DIR" "$RUN_AS_USER"
    fi

    echo
    if confirm_default_yes "Run a manual boot audit now?"; then
        run_manual_boot_audit_test "$INSTALL_DIR" "$RUN_AS_USER" "$INSTANCE_NAME"
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
