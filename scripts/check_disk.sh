#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/check_disk.sh
# Project: JR-Bot / OPSCON
# Purpose: Zeigt Speicherplatzbelegung der wichtigsten Dateisysteme.
# Job-Key: check_disk
# Category: DIAGNOSTICS / LOW
# Dependencies:
#   - date command
#   - df command
# Security:
#   - Kein sudo erforderlich
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/check_disk.sh
#   - Logical grouping: tbl_jobs.job_group = diagnostics
#   - Keine scripts-Unterordner verwenden
#   - Reines Diagnose-Skript
# =========================================================

set -u

SCRIPT_NAME="check_disk.sh"

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Zeitpunkt:"
date '+%Y-%m-%d %H:%M:%S %Z'
echo

echo "Wichtige Dateisysteme:"
df -hT / /home 2>/dev/null
echo

echo "Vollständige Speicherübersicht:"
df -h
