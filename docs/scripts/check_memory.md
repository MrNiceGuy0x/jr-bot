# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/check_memory.md |
| Project | JR-Bot / OPSCON |
| Purpose | Zeigt RAM- und Swap-Auslastung des Raspberry Pi. |
| Job-Key | check_memory |
| Category | DIAGNOSTICS / LOW |
| Dependencies | `date`, `free`, `ps`, `head` |
| Security | Kein sudo erforderlich |
| Notes | Runtime path: `scripts/check_memory.sh`; job_group: `diagnostics`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/check_memory.sh
```

## Purpose

`check_memory.sh` zeigt RAM- und Swap-Auslastung sowie die speicherintensivsten Prozesse des Raspberry Pi.

Das Skript führt keine Änderungen am System aus.

## Behavior

Das Skript gibt aus:

- aktueller Zeitstempel
- RAM-Auslastung
- verfügbarer RAM
- Swap-Nutzung
- Top-Memory-Prozesse nach Speicherverbrauch

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `check_memory` |
| `job_type` | `shell` |
| `job_group` | `diagnostics` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "/opt/bots/trx/scripts/check_memory.sh"
}
```

Generisch:

```json
{
  "cmd": "$INSTALL_DIR/scripts/check_memory.sh"
}
```

## Security

Kein sudoers-Eintrag erforderlich.

Dieses Skript ist ein reines Diagnose-Skript und benötigt keine erhöhten Rechte.

## Expected Output

Beispiel:

```text
Skript: check_memory.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

RAM- und Swap-Auslastung:
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       420Mi       2.9Gi        12Mi       520Mi       3.2Gi
Swap:          200Mi          0B       200Mi

Top Memory Prozesse:
PID %MEM COMMAND
1234 12.5 python3
...
```

## What to Check

| Wert | Bedeutung |
|---|---|
| `available` | tatsächlich noch nutzbarer RAM |
| `Swap used` | Hinweis auf Speicherdruck |
| Top-Memory-Prozesse | auffällige Prozesse mit hohem RAM-Verbrauch |

Warnsignale:

- `available` dauerhaft sehr niedrig
- Swap wird stark genutzt
- einzelne Prozesse verbrauchen ungewöhnlich viel RAM
- Runner reagiert verzögert

## Related Scripts

```text
check_disk.sh
uptime_info.sh
tail_runner_log.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = diagnostics
```

Es werden keine Unterordner wie `scripts/diagnostics/` oder `07_scripts/diagnostics/` verwendet.
