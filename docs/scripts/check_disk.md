# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/check_disk.md |
| Project | JR-Bot / OPSCON |
| Purpose | Zeigt Speicherplatzbelegung der wichtigsten Dateisysteme. |
| Job-Key | check_disk |
| Category | DIAGNOSTICS / LOW |
| Dependencies | `date`, `df` |
| Security | Kein sudo erforderlich |
| Notes | Runtime path: `scripts/check_disk.sh`; job_group: `diagnostics`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/check_disk.sh
```

## Purpose

`check_disk.sh` zeigt die Speicherplatzbelegung der wichtigsten Dateisysteme des Raspberry Pi.

Das Skript führt keine Änderungen am System aus.

## Behavior

Das Skript gibt aus:

- aktueller Zeitstempel
- gezielte Prüfung von `/`
- gezielte Prüfung von `/home`
- vollständige `df -h` Speicherübersicht

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `check_disk` |
| `job_type` | `shell` |
| `job_group` | `diagnostics` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "/opt/bots/trx/scripts/check_disk.sh"
}
```

Generisch:

```json
{
  "cmd": "$INSTALL_DIR/scripts/check_disk.sh"
}
```

## Security

Kein sudoers-Eintrag erforderlich.

Dieses Skript ist ein reines Diagnose-Skript und benötigt keine erhöhten Rechte.

## Expected Output

Beispiel:

```text
Skript: check_disk.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

Wichtige Dateisysteme:
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/root      ext4   59G   12G   45G  21% /
...

Vollständige Speicherübersicht:
Filesystem      Size  Used Avail Use% Mounted on
...
```

## What to Check

| Mountpoint | Bedeutung |
|---|---|
| `/` | Root-Dateisystem, kritisch für Systembetrieb |
| `/home` | Benutzer-, Bot-, Log- und lokale Arbeitsdaten |

Warnsignale:

| Wert | Bewertung |
|---|---|
| `Use%` über 80 % | beobachten |
| `Use%` über 90 % | zeitnah bereinigen |
| `Use%` bei 100 % | kritisch |

## Related Scripts

```text
check_memory.sh
uptime_info.sh
tail_runner_log.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = diagnostics
```

Es werden keine Unterordner wie `scripts/diagnostics/` oder `07_scripts/diagnostics/` verwendet.

