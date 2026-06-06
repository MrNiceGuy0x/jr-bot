#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/reboot.sh
# Project: JR-Bot / OPSCON
# Purpose: Plant einen Raspberry-Pi-Neustart mit Sicherheitsverzögerung.
# Job-Key: manual_reboot
# Category: POWER / CRITICAL
# Dependencies:
#   - shutdown command: /sbin/shutdown or /usr/sbin/shutdown
#   - scripts/cancel_shutdown.sh
# Security:
#   - sudoers: /etc/sudoers.d/<instance>
#   - Required: <instance> ALL=(root) NOPASSWD: $INSTALL_DIR/scripts/reboot.sh
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/reboot.sh
#   - Logical grouping: tbl_jobs.job_group = maintenance
#   - Keine scripts-Unterordner verwenden
#   - Standard: Reboot in 3 Minuten
#   - Abbruch vor Ablauf über cancel_shutdown.sh möglich
#   - Nicht als interval-Job verwenden
# =========================================================

set -u

SCRIPT_NAME="reboot.sh"
DEFAULT_DELAY=3
MIN_DELAY=1
MAX_DELAY=60

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
    echo "Erwarteter Aufruf: sudo \$INSTALL_DIR/scripts/${SCRIPT_NAME} [delay_minutes]"
    exit 1
fi

DELAY="${1:-$DEFAULT_DELAY}"

if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    echo "Fehler: DELAY muss eine Zahl in Minuten sein."
    exit 1
fi

if [ "$DELAY" -lt "$MIN_DELAY" ]; then
    echo "Fehler: DELAY muss mindestens $MIN_DELAY Minute betragen."
    exit 1
fi

if [ "$DELAY" -gt "$MAX_DELAY" ]; then
    echo "Fehler: DELAY darf maximal $MAX_DELAY Minuten betragen."
    exit 1
fi

SHUTDOWN_BIN="$(find_shutdown_bin || true)"

if [ -z "$SHUTDOWN_BIN" ]; then
    echo "Fehler: shutdown-Befehl wurde nicht gefunden."
    exit 1
fi

echo "Skript: $SCRIPT_NAME wurde gestartet – Reboot in $DELAY Minuten geplant."
echo "Hinweis: Der geplante Reboot kann mit cancel_shutdown.sh abgebrochen werden."
echo

"$SHUTDOWN_BIN" -r +"$DELAY"

EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "Reboot erfolgreich geplant."
    exit 0
else
    echo "Fehler beim Planen des Reboots."
    exit "$EXIT_CODE"
fi
