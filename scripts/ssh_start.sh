#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/ssh_start.sh
# Project: JR-Bot / OPSCON
# Purpose: Startet den SSH-Dienst auf dem Raspberry Pi.
# Job-Key: ssh_start
# Category: MAINTENANCE / MEDIUM
# Dependencies:
#   - date command
#   - systemctl command: /bin/systemctl or /usr/bin/systemctl
#   - systemd unit: ssh
# Security:
#   - sudoers: /etc/sudoers.d/<instance>
#   - Required: <instance> ALL=(root) NOPASSWD: $INSTALL_DIR/scripts/ssh_start.sh
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/ssh_start.sh
#   - Logical grouping: tbl_jobs.job_group = maintenance
#   - Keine scripts-Unterordner verwenden
#   - Startet nur den SSH-Dienst
#   - Ändert keine SSH-Konfigurationsdateien
# =========================================================

set -u

SCRIPT_NAME="ssh_start.sh"
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

if [ "$(id -u)" -ne 0 ]; then
    echo "Fehler: Dieses Skript muss über sudo ausgeführt werden."
    echo "Erwarteter Aufruf: sudo \$INSTALL_DIR/scripts/${SCRIPT_NAME}"
    exit 1
fi

SYSTEMCTL_BIN="$(find_systemctl_bin || true)"

if [ -z "$SYSTEMCTL_BIN" ]; then
    echo "Fehler: systemctl wurde nicht gefunden."
    exit 1
fi

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Zeitpunkt:"
date '+%Y-%m-%d %H:%M:%S %Z'
echo

echo "Starte SSH-Dienst: $SSH_SERVICE"
"$SYSTEMCTL_BIN" start "$SSH_SERVICE"

EXIT_CODE=$?

echo
echo "SSH Service Status nach Startversuch:"
"$SYSTEMCTL_BIN" is-active "$SSH_SERVICE" 2>/dev/null || true

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "SSH-Dienst wurde erfolgreich gestartet oder war bereits aktiv."
    exit 0
else
    echo "Fehler: SSH-Dienst konnte nicht gestartet werden."
    exit "$EXIT_CODE"
fi
