#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/cancel_shutdown.sh
# Project: JR-Bot / OPSCON
# Purpose: Bricht einen geplanten Shutdown oder Reboot ab.
# Job-Key: cancel_shutdown
# Category: POWER / SAFETY
# Dependencies:
#   - shutdown command: /sbin/shutdown or /usr/sbin/shutdown
# Security:
#   - sudoers: /etc/sudoers.d/<instance>
#   - Required: <instance> ALL=(root) NOPASSWD: $INSTALL_DIR/scripts/cancel_shutdown.sh
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/cancel_shutdown.sh
#   - Logical grouping: tbl_jobs.job_group = maintenance
#   - Keine scripts-Unterordner verwenden
#   - Stoppt geplante Shutdowns und geplante Reboots
#   - Ersetzt cancel_reboot.sh vollständig
# =========================================================

set -u

SCRIPT_NAME="cancel_shutdown.sh"

find_shutdown_bin() {
    if [ -x "/sbin/shutdown" ]; then
        echo "/sbin/shutdown"
        return 0
    fi

    if [ -x "/usr/sbin/shutdown" ]; then
        echo "/usr/sbin/shutdown"
        return 0
    fi

    command -v shutdown 2>/dev/null || return 1
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Fehler: Dieses Skript muss über sudo ausgeführt werden."
    echo "Erwarteter Aufruf: sudo \$INSTALL_DIR/scripts/${SCRIPT_NAME}"
    exit 1
fi

SHUTDOWN_BIN="$(find_shutdown_bin || true)"

if [ -z "$SHUTDOWN_BIN" ]; then
    echo "Fehler: shutdown-Befehl wurde nicht gefunden."
    exit 1
fi

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Aktion: Geplanten Shutdown/Reboot abbrechen."
echo

"$SHUTDOWN_BIN" -c

EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "Geplanter Shutdown/Reboot wurde erfolgreich abgebrochen."
else
    echo "Kein geplanter Shutdown/Reboot gefunden oder Abbruch fehlgeschlagen."
fi

exit "$EXIT_CODE"
