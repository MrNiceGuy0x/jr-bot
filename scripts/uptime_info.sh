#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/uptime_info.sh
# Project: JR-Bot / OPSCON
# Purpose: Zeigt Systemlaufzeit, Load Average und aktuellen Zeitstempel.
# Job-Key: uptime_info
# Category: DIAGNOSTICS / LOW
# Dependencies:
#   - date command
#   - uptime command
# Security:
#   - Kein sudo erforderlich
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/uptime_info.sh
#   - Logical grouping: tbl_jobs.job_group = diagnostics
#   - Keine scripts-Unterordner verwenden
#   - Reines Diagnose-Skript
# =========================================================

set -u

SCRIPT_NAME="uptime_info.sh"

find_uptime_bin() {
    if [ -x "/usr/bin/uptime" ]; then
        echo "/usr/bin/uptime"
        return 0
    fi

    if [ -x "/bin/uptime" ]; then
        echo "/bin/uptime"
        return 0
    fi

    command -v uptime 2>/dev/null || return 1
}

UPTIME_BIN="$(find_uptime_bin || true)"

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Zeitpunkt:"
date '+%Y-%m-%d %H:%M:%S %Z'
echo

if [ -z "$UPTIME_BIN" ]; then
    echo "Fehler: uptime-Befehl wurde nicht gefunden."
    exit 1
fi

echo "System Uptime und Load Average:"
"$UPTIME_BIN"
