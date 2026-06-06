# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/ssh_status.md |
| Project | JR-Bot / OPSCON |
| Purpose | Zeigt den aktuellen Status des SSH-Dienstes. |
| Job-Key | ssh_status |
| Category | MAINTENANCE / LOW |
| Dependencies | `date`, `systemctl`, `ss`, systemd unit: `ssh` |
| Security | Kein sudo erforderlich |
| Notes | Runtime path: `scripts/ssh_status.sh`; job_group: `maintenance`; technically read-only, functionally grouped with SSH maintenance. |

## Runtime Script

```text
scripts/ssh_status.sh
```

## Purpose

`ssh_status.sh` zeigt den aktuellen Status des SSH-Dienstes auf dem Raspberry Pi.

Das Skript führt ausschließlich lesende Abfragen aus und benötigt keine erhöhten Rechte.

## Behavior

Das Skript gibt aus:

- aktueller Zeitstempel
- SSH-Service-Status
- ActiveState
- SubState
- UnitFileState
- offene SSH-Ports

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `ssh_status` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "/opt/bots/trx/scripts/ssh_status.sh"
}
```

Generisch:

```json
{
  "cmd": "$INSTALL_DIR/scripts/ssh_status.sh"
}
```

## Security

Kein sudoers-Eintrag erforderlich.

Dieses Skript ist technisch read-only. Es wird dennoch der SSH-Maintenance-Familie zugeordnet, damit `ssh_status.sh`, `ssh_start.sh` und `ssh_stop.sh` im OPSCON-Filter zusammenbleiben.

## Expected Output

Beispiel:

```text
Skript: ssh_status.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

SSH Service Status:
active

SSH Service Details:
ActiveState=active
SubState=running
UnitFileState=enabled

SSH Listening Ports:
LISTEN 0 128 0.0.0.0:22
LISTEN 0 128 [::]:22
```

## Related Scripts

```text
ssh_start.sh
ssh_stop.sh
uptime_info.sh
tail_runner_log.sh
```

## Notes

Die SSH-Familie bleibt gemeinsam in:

```text
tbl_jobs.job_group = maintenance
```

Es werden keine Unterordner wie `scripts/diagnostics/`, `scripts/maintenance/`, `07_scripts/diagnostics/` oder `07_scripts/maintenance/` verwendet.
