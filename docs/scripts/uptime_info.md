# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/uptime_info.md |
| Project | JR-Bot / OPSCON |
| Purpose | Zeigt Systemlaufzeit, Load Average und aktuellen Zeitstempel. |
| Job-Key | uptime_info |
| Category | DIAGNOSTICS / LOW |
| Dependencies | `date`, `uptime` |
| Security | Kein sudo erforderlich |
| Notes | Runtime path: `scripts/uptime_info.sh`; job_group: `diagnostics`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/uptime_info.sh
```

## Purpose

`uptime_info.sh` zeigt die aktuelle Systemlaufzeit, den Load Average und einen Zeitstempel des Raspberry Pi.

Das Skript führt keine Änderungen am System aus.

## Behavior

Das Skript gibt aus:

- aktueller Zeitstempel
- Systemlaufzeit
- Anzahl eingeloggter Benutzer, falls von `uptime` ausgegeben
- Load Average

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `uptime_info` |
| `job_type` | `shell` |
| `job_group` | `diagnostics` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "/opt/bots/trx/scripts/uptime_info.sh"
}
```

Generisch:

```json
{
  "cmd": "$INSTALL_DIR/scripts/uptime_info.sh"
}
```

## Security

Kein sudoers-Eintrag erforderlich.

Dieses Skript ist ein reines Diagnose-Skript und benötigt keine erhöhten Rechte.

## Expected Output

Beispiel:

```text
Skript: uptime_info.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

System Uptime und Load Average:
10:15:00 up 3 days,  2:14,  1 user,  load average: 0.08, 0.04, 0.01
```

## What to Check

| Wert | Bedeutung |
|---|---|
| `up` | Wie lange das System seit dem letzten Boot läuft |
| `load average` | Systemlast über 1, 5 und 15 Minuten |
| hohe Load-Werte | Hinweis auf CPU-/I/O-Last oder hängende Prozesse |

## Related Scripts

```text
check_disk.sh
check_memory.sh
tail_runner_log.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = diagnostics
```

Es werden keine Unterordner wie `scripts/diagnostics/` oder `07_scripts/diagnostics/` verwendet.
