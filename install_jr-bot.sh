#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# JR-Bot Universal Installer
# Version: 0.4.0-dev-wp-fnd-02
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

SCRIPT_VERSION="0.4.0-dev-wp-fnd-02"

DEFAULT_PROJECT_NAME="My Project"
DEFAULT_BOT_NAME="JRBot"
DEFAULT_INSTANCE_NAME="jrbot"
DEFAULT_INTERVAL_SECONDS="60"
DEFAULT_MANAGEMENT_MODE="standalone"
DEFAULT_DATABASE_MODE="local_pi"
DEFAULT_AUTH_MODE="none"

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


normalize_management_mode() {
    local value="$1"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        standalone|opscon_managed) ;;
        *) die "Invalid MANAGEMENT_MODE. Allowed: standalone, opscon_managed." ;;
    esac
    printf '%s\n' "$value"
}

normalize_database_mode() {
    local value="$1"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        local_pi|external) ;;
        *) die "Invalid DATABASE_MODE. Allowed: local_pi, external." ;;
    esac
    printf '%s\n' "$value"
}

normalize_auth_mode() {
    local value="$1"
    value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$value" in
        none|server_token|split_ping_token) ;;
        *) die "Invalid AUTH_MODE. Allowed: none, server_token, split_ping_token." ;;
    esac
    printf '%s\n' "$value"
}

normalize_server_base() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    while [[ "$value" == */ ]]; do value="${value%/}"; done
    [[ -n "$value" ]] || die "SERVER_BASE is required for DATABASE_MODE=external."
    [[ "$value" =~ ^https://[^[:space:]]+$ ]] || die "SERVER_BASE must be a canonical HTTPS URL without whitespace."
    printf '%s\n' "$value"
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

atomic_stage_root_file() {
    local target_path="$1"
    local group="$2"
    local mode="$3"
    local content="$4"
    local target_dir target_name tmp_path
    target_dir="$(dirname "$target_path")"
    target_name="$(basename "$target_path")"
    sudo mkdir -p "$target_dir"
    tmp_path="$(sudo mktemp "${target_dir}/.${target_name}.tmp.XXXXXX")"
    if ! printf '%s\n' "$content" | sudo tee "$tmp_path" >/dev/null; then
        sudo rm -f "$tmp_path" || true
        die "Failed to stage protected runtime file: ${target_path}"
    fi
    sudo chown "root:${group}" "$tmp_path"
    sudo chmod "$mode" "$tmp_path"
    printf '%s\n' "$tmp_path"
}

atomic_commit_staged_file() {
    local staged_path="$1"
    local target_path="$2"
    sudo mv -f "$staged_path" "$target_path"
}

remove_runtime_secret_if_present() {
    local path="$1"
    [[ ! -e "$path" && ! -L "$path" ]] || sudo rm -f "$path"
}

apply_runtime_configuration() {
    local install_dir="$1"
    local run_as_user="$2"
    local project_name="$3"
    local bot_name="$4"
    local instance_name="$5"
    local management_mode="$6"
    local database_mode="$7"
    local server_base="$8"
    local auth_mode="$9"
    local interval_seconds="${10}"
    local server_token="${11}"
    local ping_token="${12}"
    local config_path="${install_dir}/config/config.ini"
    local secrets_dir="${install_dir}/config/secrets"
    local server_token_path="${secrets_dir}/server.token"
    local ping_token_path="${secrets_dir}/ping.token"
    local config_body="" staged_config="" staged_server_token="" staged_ping_token=""

    if [[ "$database_mode" == "local_pi" ]]; then
        if [[ "$auth_mode" != "none" || -n "$server_base" || -n "$server_token" || -n "$ping_token" ]]; then
            die "DATABASE_MODE=local_pi forbids active server/auth configuration."
        fi
        config_body="$(cat <<EOF
[bot]
PROJECT_NAME = ${project_name}
BOT_NAME = ${bot_name}
INSTANCE_NAME = ${instance_name}
MANAGEMENT_MODE = ${management_mode}
DATABASE_MODE = ${database_mode}

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
)"
    else
        [[ -n "$server_base" ]] || die "SERVER_BASE is required for DATABASE_MODE=external."
        case "$auth_mode" in
            none)
                [[ -z "$server_token" && -z "$ping_token" ]] || die "AUTH_MODE=none forbids runtime token material."
                ;;
            server_token)
                [[ -n "$server_token" ]] || die "AUTH_MODE=server_token requires SERVER_TOKEN."
                [[ -z "$ping_token" ]] || die "AUTH_MODE=server_token forbids PING_TOKEN material."
                ;;
            split_ping_token)
                [[ -n "$server_token" ]] || die "AUTH_MODE=split_ping_token requires SERVER_TOKEN."
                [[ -n "$ping_token" ]] || die "AUTH_MODE=split_ping_token requires PING_TOKEN."
                ;;
            *) die "Unexpected AUTH_MODE: ${auth_mode}" ;;
        esac
        config_body="$(cat <<EOF
[bot]
PROJECT_NAME = ${project_name}
BOT_NAME = ${bot_name}
INSTANCE_NAME = ${instance_name}
MANAGEMENT_MODE = ${management_mode}
DATABASE_MODE = ${database_mode}

[server]
SERVER_BASE = ${server_base}
AUTH_MODE = ${auth_mode}

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
)"
    fi

    if [[ "$auth_mode" == "server_token" || "$auth_mode" == "split_ping_token" ]]; then
        sudo mkdir -p "$secrets_dir"
        sudo chown "root:${run_as_user}" "$secrets_dir"
        sudo chmod 0750 "$secrets_dir"
        staged_server_token="$(atomic_stage_root_file "$server_token_path" "$run_as_user" 0640 "$server_token")"
    fi
    if [[ "$auth_mode" == "split_ping_token" ]]; then
        staged_ping_token="$(atomic_stage_root_file "$ping_token_path" "$run_as_user" 0640 "$ping_token")"
    fi
    staged_config="$(atomic_stage_root_file "$config_path" "$run_as_user" 0640 "$config_body")"
    [[ -z "$staged_server_token" ]] || atomic_commit_staged_file "$staged_server_token" "$server_token_path"
    [[ -z "$staged_ping_token" ]] || atomic_commit_staged_file "$staged_ping_token" "$ping_token_path"
    atomic_commit_staged_file "$staged_config" "$config_path"
    case "$auth_mode" in
        none)
            remove_runtime_secret_if_present "$server_token_path"
            remove_runtime_secret_if_present "$ping_token_path"
            sudo rmdir "$secrets_dir" 2>/dev/null || true
            ;;
        server_token) remove_runtime_secret_if_present "$ping_token_path" ;;
        split_ping_token) ;;
    esac
    info "Canonical runtime configuration written to ${config_path}"
}

create_install_info() {
    local install_dir="$1" run_as_user="$2" project_name="$3" bot_name="$4" instance_name="$5"
    local management_mode="$6" database_mode="$7" server_base="$8" auth_mode="$9" interval_seconds="${10}"
    sudo tee "$install_dir/install_info.txt" >/dev/null <<EOF
JR-Bot Universal Installer
Version: ${SCRIPT_VERSION}

Project: ${project_name}
Bot: ${bot_name}
Instance: ${instance_name}
Install dir: ${install_dir}
Run as user: ${run_as_user}
Management mode: ${management_mode}
Database mode: ${database_mode}
Server base: ${server_base}
Auth mode: ${auth_mode}
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
- canonical management/database/server configuration presence

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
    management_mode = config.get("bot", "MANAGEMENT_MODE", fallback="UNKNOWN")
    database_mode = config.get("bot", "DATABASE_MODE", fallback="UNKNOWN")
    if config.has_section("server"):
        server_base = config.get("server", "SERVER_BASE", fallback="")
        auth_mode = config.get("server", "AUTH_MODE", fallback="UNKNOWN")
    else:
        server_base = ""
        auth_mode = "none"

    write_log(
        "JR-Bot runner start "
        f"project={project_name} "
        f"bot={bot_name} "
        f"instance={instance_name} "
        f"management_mode={management_mode} "
        f"database_mode={database_mode} "
        f"server_base={server_base} "
        f"auth_mode={auth_mode} "
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
    local management_mode="$6"
    local database_mode="$7"
    local server_base="$8"
    local auth_mode="$9"
    local interval_seconds="${10}"

    echo
    echo "=================================================="
    echo " Installation complete"
    echo "=================================================="
    echo "Project:              ${project_name}"
    echo "Bot:                  ${bot_name}"
    echo "Instance:             ${instance_name}"
    echo "Runtime user:         ${run_as_user}"
    echo "Install path:         ${install_dir}"
    echo "Management mode:      ${management_mode}"
    echo "Database mode:        ${database_mode}"
    echo "Server base:          ${server_base}"
    echo "Auth mode:            ${auth_mode}"
    echo "Polling interval:     ${interval_seconds} seconds"
    echo
    echo "Local runtime paths:"
    echo "Config:               ${install_dir}/config/config.ini"
    echo "Runtime secrets:      ${install_dir}/config/secrets (conditional)"
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

    echo "Public WP-FND-02 onboarding"
    echo "---------------------------"
    echo "Target: one JR-Bot runtime per node under /opt/bots/<instance>"
    echo "Audit storage: local only"
    echo "Runtime credentials: protected files under config/secrets/ when required"
    echo

    PROJECT_NAME="$(ask_with_default "Project name" "$DEFAULT_PROJECT_NAME")"
    BOT_NAME="$(ask_with_default "Bot display name" "$DEFAULT_BOT_NAME")"
    INSTANCE_NAME_RAW="$(ask_with_default "Instance name" "$DEFAULT_INSTANCE_NAME")"
    INSTANCE_NAME="$(normalize_instance_value "$INSTANCE_NAME_RAW")"

    RUN_AS_USER="$INSTANCE_NAME"
    validate_runtime_user_separation "$RUN_AS_USER"

    INSTALL_DIR="/opt/bots/${INSTANCE_NAME}"

    MANAGEMENT_MODE_RAW="$(ask_with_default "MANAGEMENT_MODE (standalone|opscon_managed)" "$DEFAULT_MANAGEMENT_MODE")"
    MANAGEMENT_MODE="$(normalize_management_mode "$MANAGEMENT_MODE_RAW")"

    DATABASE_MODE_RAW="$(ask_with_default "DATABASE_MODE (local_pi|external)" "$DEFAULT_DATABASE_MODE")"
    DATABASE_MODE="$(normalize_database_mode "$DATABASE_MODE_RAW")"

    SERVER_BASE=""
    AUTH_MODE="none"
    SERVER_TOKEN=""
    PING_TOKEN=""

    if [[ "$DATABASE_MODE" == "external" ]]; then
        SERVER_BASE_RAW="$(ask_required "Project Handler SERVER_BASE (HTTPS)")"
        SERVER_BASE="$(normalize_server_base "$SERVER_BASE_RAW")"

        AUTH_MODE_RAW="$(ask_with_default "AUTH_MODE (none|server_token|split_ping_token)" "$DEFAULT_AUTH_MODE")"
        AUTH_MODE="$(normalize_auth_mode "$AUTH_MODE_RAW")"

        case "$AUTH_MODE" in
            none)
                ;;
            server_token)
                SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN")"
                ;;
            split_ping_token)
                SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN")"
                PING_TOKEN="$(ask_secret_required "PING_TOKEN")"
                ;;
        esac
    fi

    INTERVAL_SECONDS="$(ask_with_default "Polling interval in seconds" "$DEFAULT_INTERVAL_SECONDS")"
    validate_interval "$INTERVAL_SECONDS"

    echo
    echo "Planned installation:"
    echo "Project:              ${PROJECT_NAME}"
    echo "Bot:                  ${BOT_NAME}"
    echo "Instance:             ${INSTANCE_NAME}"
    echo "Runtime user:         ${RUN_AS_USER}"
    echo "Install path:         ${INSTALL_DIR}"
    echo "Management mode:      ${MANAGEMENT_MODE}"
    echo "Database mode:        ${DATABASE_MODE}"
    echo "Server base:          ${SERVER_BASE}"
    echo "Auth mode:            ${AUTH_MODE}"
    echo "Audit storage:        ${INSTALL_DIR}/reports/audits (local only)"
    echo "Runtime secrets:      ${INSTALL_DIR}/config/secrets (conditional)"
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

    apply_runtime_configuration \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$MANAGEMENT_MODE" \
        "$DATABASE_MODE" \
        "$SERVER_BASE" \
        "$AUTH_MODE" \
        "$INTERVAL_SECONDS" \
        "$SERVER_TOKEN" \
        "$PING_TOKEN"

    create_install_info \
        "$INSTALL_DIR" \
        "$RUN_AS_USER" \
        "$PROJECT_NAME" \
        "$BOT_NAME" \
        "$INSTANCE_NAME" \
        "$MANAGEMENT_MODE" \
        "$DATABASE_MODE" \
        "$SERVER_BASE" \
        "$AUTH_MODE" \
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
        "$MANAGEMENT_MODE" \
        "$DATABASE_MODE" \
        "$SERVER_BASE" \
        "$AUTH_MODE" \
        "$INTERVAL_SECONDS"
}

main "$@"
