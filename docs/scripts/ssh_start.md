# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/ssh_start.md |
| Project | JR-Bot / OPSCON |
| Purpose | Startet den SSH-Dienst auf dem Raspberry Pi. |
| Job-Key | ssh_start |
| Category | MAINTENANCE / MEDIUM |
| Dependencies | `date`, `systemctl`, systemd unit: `ssh` |
| Security | Requires sudoers entry for `$INSTALL_DIR/scripts/ssh_start.sh` |
| Notes | Runtime path: `scripts/ssh_start.sh`; job_group: `maintenance`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/ssh_start.sh
```

## Purpose

`ssh_start.sh` startet den SSH-Dienst auf dem Raspberry Pi.

Das Skript ändert keine SSH-Konfigurationsdateien. Es startet ausschließlich den systemd-Dienst:

```text
ssh
```

## Behavior

Das Skript führt aus:

```bash
systemctl start ssh
```

Danach wird der aktuelle SSH-Service-Status ausgegeben.

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `ssh_start` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/ssh_start.sh"
}
```

Generisch:

```json
{
  "cmd": "sudo $INSTALL_DIR/scripts/ssh_start.sh"
}
```

## Security Model

Dieses Skript muss über sudo gestartet werden, weil es einen systemd-Dienst steuert.

Wichtig: In sudoers wird nicht der rohe Systembefehl `systemctl start ssh` freigegeben, sondern nur der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/ssh_start.sh
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
sudo chown root:root /opt/bots/trx/scripts/ssh_start.sh
sudo chmod 755 /opt/bots/trx/scripts/ssh_start.sh
```

## Expected Output

Beispiel:

```text
Skript: ssh_start.sh wurde gestartet.
Zeitpunkt:
2026-05-29 10:15:00 CEST

Starte SSH-Dienst: ssh

SSH Service Status nach Startversuch:
active
SSH-Dienst wurde erfolgreich gestartet oder war bereits aktiv.
```

## Risks

Mittleres Risiko.

Dieses Skript:

- startet SSH
- öffnet dadurch Remote-Zugriff, sofern Netzwerk und Firewall dies zulassen
- ändert keine Konfiguration
- stoppt keine laufenden Prozesse

## Troubleshooting

### Fehler: `Dieses Skript muss über sudo ausgeführt werden`

Das Skript wurde ohne sudo gestartet.

Richtig:

```bash
sudo /opt/bots/trx/scripts/ssh_start.sh
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
ssh_stop.sh
```

## Notes

Die SSH-Familie bleibt gemeinsam in:

```text
tbl_jobs.job_group = maintenance
```

Dadurch bleiben `ssh_status.sh`, `ssh_start.sh` und `ssh_stop.sh` im OPSCON-Filter zusammen.

Es werden keine Unterordner wie `scripts/maintenance/` oder `07_scripts/maintenance/` verwendet.
