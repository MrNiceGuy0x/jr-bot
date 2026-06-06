#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/tail_runner_log.sh
# Project: JR-Bot / OPSCON
# Purpose: Zeigt die letzten Journal-Logzeilen des Bot-Runners.
# Job-Key: tail_runner_log
# Category: DIAGNOSTICS / LOW
# Dependencies:
#   - journalctl command: /bin/journalctl or /usr/bin/journalctl
#   - systemd unit: bot-runner@<instance>.service
# Security:
#   - sudoers: /etc/sudoers.d/<instance>
#   - Required if journal access needs elevated rights: <instance> ALL=(root) NOPASSWD: $INSTALL_DIR/scripts/tail_runner_log.sh
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/tail_runner_log.sh
#   - Logical grouping: tbl_jobs.job_group = diagnostics
#   - Keine scripts-Unterordner verwenden
#   - Standard: 50 Logzeilen
#   - Maximal: 300 Logzeilen
#   - Generisch für bot-runner@<instance>.service
# =========================================================

set -u

SCRIPT_NAME="tail_runner_log.sh"
DEFAULT_LINES=50
MIN_LINES=1
MAX_LINES=300

find_journalctl_bin() {
    if [ -x "/bin/journalctl" ]; then
        echo "/bin/journalctl"
        return 0
    fi

    if [ -x "/usr/bin/journalctl" ]; then
        echo "/usr/bin/journalctl"
        return 0
    fi

    command -v journalctl 2>/dev/null || return 1
}

detect_instance_name() {
    if [ -n "${INSTANCE_NAME:-}" ]; then
        echo "$INSTANCE_NAME"
        return 0
    fi

    if [ -n "${BOT_INSTANCE:-}" ]; then
        echo "$BOT_INSTANCE"
        return 0
    fi

    if [ -n "${INSTANCE:-}" ]; then
        echo "$INSTANCE"
        return 0
    fi

    basename "$(pwd)"
}

LINES="${1:-$DEFAULT_LINES}"
INSTANCE_NAME_RESOLVED="$(detect_instance_name)"
UNIT_NAME="${UNIT_NAME:-bot-runner@${INSTANCE_NAME_RESOLVED}.service}"
JOURNALCTL_BIN="$(find_journalctl_bin || true)"

if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
    echo "Fehler: LINES muss eine Zahl sein."
    exit 1
fi

if [ "$LINES" -lt "$MIN_LINES" ]; then
    echo "Fehler: LINES muss mindestens $MIN_LINES betragen."
    exit 1
fi

if [ "$LINES" -gt "$MAX_LINES" ]; then
    echo "Fehler: LINES darf maximal $MAX_LINES betragen."
    exit 1
fi

if [ -z "$JOURNALCTL_BIN" ]; then
    echo "Fehler: journalctl wurde nicht gefunden."
    exit 1
fi

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Instance: $INSTANCE_NAME_RESOLVED"
echo "Unit: $UNIT_NAME"
echo "Letzte $LINES Log-Zeilen:"
echo

"$JOURNALCTL_BIN" -u "$UNIT_NAME" -n "$LINES" --no-pager
