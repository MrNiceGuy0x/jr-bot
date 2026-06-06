# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/ssh_stop.md |
| Project | JR-Bot / OPSCON |
| Purpose | Stoppt den SSH-Dienst auf dem Raspberry Pi. |
| Job-Key | ssh_stop |
| Category | MAINTENANCE / CRITICAL |
| Dependencies | `date`, `systemctl`, systemd unit: `ssh` |
| Security | Requires sudoers entry for `$INSTALL_DIR/scripts/ssh_stop.sh` |
| Notes | Runtime path: `scripts/ssh_stop.sh`; job_group: `maintenance`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/ssh_stop.sh
```

## Purpose

`ssh_stop.sh` stoppt den SSH-Dienst auf dem Raspberry Pi.

Das Skript ändert keine SSH-Konfigurationsdateien. Es stoppt ausschließlich den systemd-Dienst:

```text
ssh
```

## Behavior

Das Skript führt aus:

```bash
systemctl stop ssh
```

Danach wird der aktuelle SSH-Service-Status ausgegeben.

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `ssh_stop` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | nur bewusst bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/ssh_stop.sh"
}
```

Generisch:

```json
{
  "cmd": "sudo $INSTALL_DIR/scripts/ssh_stop.sh"
}
```

## Security Model

Dieses Skript muss über sudo gestartet werden, weil es einen systemd-Dienst steuert.

Wichtig: In sudoers wird nicht der rohe Systembefehl `systemctl stop ssh` freigegeben, sondern nur der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/ssh_stop.sh
```

Sudoers-Datei:

```text
/etc/sudoers.d/trx
```

Validierung:

```bash
sudo visudo -cf /etc/sudoers.d/trx
```

## File Ownership

Sudoers-freigegebene Skripte müssen root-owned und nicht durch den Bot-User beschreibbar sein.

```bash
sudo chown root:root /opt/bots/trx/scripts/ssh_stop.sh
sudo chmod 755 /opt/bots/trx/scripts/ssh_stop.sh
```

## Expected Output

Beispiel:

```text
Skript: ssh_stop.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

WARNUNG: SSH-Dienst wird gestoppt.
Bestehende SSH-Verbindungen können abbrechen.
Remote-Zugriff per SSH ist danach nicht mehr möglich.
Neustart ist über ssh_start.sh möglich, solange job_runner und Backend-Verbindung weiterlaufen.

Stoppe SSH-Dienst: ssh

SSH Service Status nach Stop-Versuch:
inactive
SSH-Dienst wurde erfolgreich gestoppt oder war bereits inaktiv.
```

## Risks

Kritisches Risiko.

Dieses Skript:

- stoppt SSH
- kann bestehende SSH-Verbindungen beenden
- verhindert weiteren SSH-Zugriff
- sollte nur bewusst manuell verwendet werden

## Recovery

Wenn der JR-Bot und die Web-/Backend-Verbindung weiter funktionieren:

```text
ssh_start.sh
```

Falls JR-Bot/Web-Zugriff nicht mehr funktioniert, ist physischer Zugriff auf den Raspberry Pi erforderlich.

## Troubleshooting

### Fehler: `Dieses Skript muss über sudo ausgeführt werden`

Das Skript wurde ohne sudo gestartet.

Richtig:

```bash
sudo /opt/bots/trx/scripts/ssh_stop.sh
```

### Fehler: `sudo: a password is required`

Der sudoers-Eintrag fehlt oder ist falsch.

Prüfen:

```bash
sudo cat /etc/sudoers.d/trx
sudo visudo -cf /etc/sudoers.d/trx
```

### Fehler: `Unit ssh.service could not be found`

Auf manchen Systemen heißt der Dienst eventuell anders.

Prüfen:

```bash
systemctl list-units | grep -i ssh
```

### Fehler: `systemctl wurde nicht gefunden`

Pfad prüfen:

```bash
command -v systemctl
```

## Related Scripts

```text
ssh_status.sh
ssh_start.sh
```

## Notes

Die SSH-Familie bleibt gemeinsam in:

```text
tbl_jobs.job_group = maintenance
```

Dadurch bleiben `ssh_status.sh`, `ssh_start.sh` und `ssh_stop.sh` im OPSCON-Filter zusammen.

Es werden keine Unterordner wie `scripts/maintenance/` oder `07_scripts/maintenance/` verwendet.
