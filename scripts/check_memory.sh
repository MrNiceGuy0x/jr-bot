#!/usr/bin/env bash
# =========================================================
# JR-Bot Script Header
# =========================================================
# Script: scripts/check_memory.sh
# Project: JR-Bot
# Purpose: Zeigt RAM- und Swap-Auslastung des Raspberry Pi.
# Job-Key: check_memory
# Category: DIAGNOSTICS / LOW
# Dependencies:
#   - date command
#   - free command
#   - ps command
#   - head command
# Security:
#   - Kein sudo erforderlich
# Notes:
#   - Runtime path: $INSTALL_DIR/scripts/check_memory.sh
#   - Logical grouping: tbl_jobs.job_group = diagnostics
#   - Keine scripts-Unterordner verwenden
#   - Reines Diagnose-Skript
# =========================================================

set -u

SCRIPT_NAME="check_memory.sh"

echo "Skript: $SCRIPT_NAME wurde gestartet."
echo "Zeitpunkt:"
date '+%Y-%m-%d %H:%M:%S %Z'
echo

echo "RAM- und Swap-Auslastung:"
free -h
echo

echo "Top Memory Prozesse:"
ps -eo pid,pmem,comm --sort=-pmem | head -n 6
