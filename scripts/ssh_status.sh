#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/ssh_status.sh
# Project: JR-Bot / OPSCON
# Purpose: Zeigt den aktuellen Status des SSH-Dienstes.
# Job-Key: ssh_status
# Category: MAINTENANCE / LOW
# Dependencies:
#   - date command
#   - systemctl command: /bin/systemctl or /usr/bin/systemctl
#   - ss command: /usr/bin/ss or /bin/ss
#   - systemd unit: ssh
# Security:
#   - Kein sudo erforderlich
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/ssh_status.sh
#   - Logical grouping: tbl_jobs.job_group = maintenance
#   - Keine scripts-Unterordner verwenden
#   - Technisch read-only, funktional der SSH-Maintenance-Familie zugeordnet
#   - Prüft SSH-Service und offenen SSH-Port
# =========================================================

set -u

SCRIPT_NAME="ssh_status.sh"
SSH_SERVICE="ssh"

find_systemctl_bin() {
    if [ -x "/bin/systemctl" ]; then
        echo "/bin/systemctl"
        return 0
    fi

    if [ -x "/usr/bin/systemctl" ]; then
        echo "/usr/bin/systemctl"
        return 0
    fi

    command -v systemctl 2>/dev/null || return 1
}

find_ss_bin() {
    if [ -x "/usr/bin/ss" ]; then
        echo "/usr/bin/ss"
        return 0
    fi

    if [ -x "/bin/ss" ]; then
        echo "/bin/ss"
        return 0
    fi

    command -v ss 2>/dev/null || return 1
}

SYSTEMCTL_BIN="$(find_systemctl_bin || true)"
SS_BIN="$(find_ss_bin || true)"

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Zeitpunkt:"
date '+%Y-%m-%d %H:%M:%S %Z'
echo

if [ -z "$SYSTEMCTL_BIN" ]; then
    echo "Fehler: systemctl wurde nicht gefunden."
    exit 1
fi

echo "SSH Service Status:"
"$SYSTEMCTL_BIN" is-active "$SSH_SERVICE" 2>/dev/null || true
echo

echo "SSH Service Details:"
"$SYSTEMCTL_BIN" show "$SSH_SERVICE" \
    -p ActiveState \
    -p SubState \
    -p UnitFileState 2>/dev/null || true
echo

echo "SSH Listening Ports:"
if [ -n "$SS_BIN" ]; then
    "$SS_BIN" -tlnp 2>/dev/null | grep -E '(:22\s|:22$)' || echo "Kein SSH-Port 22 Listener gefunden."
else
    echo "ss nicht gefunden."
fi
