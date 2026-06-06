# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/tail_runner_log.md |
| Project | JR-Bot / OPSCON |
| Purpose | Zeigt die letzten Journal-Logzeilen des Bot-Runners. |
| Job-Key | tail_runner_log |
| Category | DIAGNOSTICS / LOW |
| Dependencies | `journalctl`, systemd unit: `bot-runner@<instance>.service` |
| Security | Optional sudoers entry for `$INSTALL_DIR/scripts/tail_runner_log.sh` if journal access needs elevated rights |
| Notes | Runtime path: `scripts/tail_runner_log.sh`; job_group: `diagnostics`; generic for `bot-runner@<instance>.service`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/tail_runner_log.sh
```

## Purpose

`tail_runner_log.sh` zeigt die letzten Journal-Logzeilen des JR-Bot Runners.

Das Skript verändert keine Systemkonfiguration und führt keine steuernden Aktionen aus.

## Behavior

Das Skript liest Logs der systemd-Unit:

```text
bot-runner@<instance>.service
```

Die konkrete Instanz wird in dieser Reihenfolge aufgelöst:

1. Environment Variable `INSTANCE_NAME`
2. Environment Variable `BOT_INSTANCE`
3. Environment Variable `INSTANCE`
4. Fallback: aktueller Arbeitsordnername

Die Unit kann optional direkt über `UNIT_NAME` überschrieben werden.

## Parameters

| Parameter | Beschreibung |
|---|---|
| `$1` | Anzahl der auszugebenden Logzeilen |

## Safety Limits

| Limit | Wert |
|---|---:|
| Minimum Lines | 1 |
| Maximum Lines | 300 |
| Default Lines | 50 |

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `tail_runner_log` |
| `job_type` | `shell` |
| `job_group` | `diagnostics` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX ohne sudo:

```json
{
  "cmd": "INSTANCE_NAME=trx /opt/bots/trx/scripts/tail_runner_log.sh 50"
}
```

Für TRX mit sudoers-Wrapper, falls Journalzugriff erhöhte Rechte benötigt:

```json
{
  "cmd": "sudo INSTANCE_NAME=trx /opt/bots/trx/scripts/tail_runner_log.sh 50"
}
```

Generisch:

```json
{
  "cmd": "INSTANCE_NAME=<instance> $INSTALL_DIR/scripts/tail_runner_log.sh 50"
}
```

## Security Model

Dieses Skript ist ein Diagnose-Skript.

Je nach Systemkonfiguration kann `journalctl` für den Bot-User ohne sudo funktionieren. Falls nicht, wird nicht der rohe Befehl `journalctl` freigegeben, sondern der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/tail_runner_log.sh
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

Wenn dieses Skript in sudoers freigegeben wird, muss es root-owned und nicht durch den Bot-User beschreibbar sein.

```bash
sudo chown root:root /opt/bots/trx/scripts/tail_runner_log.sh
sudo chmod 755 /opt/bots/trx/scripts/tail_runner_log.sh
```

## Expected Output

Beispiel:

```text
Skript: tail_runner_log.sh wurde gestartet.
Instance: trx
Unit: bot-runner@trx.service
Letzte 50 Log-Zeilen:

Mar 31 14:43:30 raspberrypi systemd[1]: Starting bot-runner@trx.service...
...
```

## Risks

Keine kritischen Risiken.

Dieses Skript:

- startet nichts neu
- stoppt keine Dienste
- fährt nichts herunter
- liest nur Logs aus
- begrenzt die Ausgabe auf maximal 300 Zeilen

## Troubleshooting

### Fehler: `journalctl wurde nicht gefunden`

Pfad prüfen:

```bash
command -v journalctl
```

### Fehler: `sudo: a password is required`

sudoers-Eintrag fehlt oder ist falsch.

Prüfen:

```bash
sudo cat /etc/sudoers.d/trx
sudo visudo -cf /etc/sudoers.d/trx
```

### Keine Logs sichtbar

Unit-Name prüfen:

```bash
systemctl status bot-runner@trx.service
```

oder:

```bash
systemctl list-units | grep bot-runner
```

Direkt mit Unit-Override testen:

```bash
UNIT_NAME=bot-runner@trx.service /opt/bots/trx/scripts/tail_runner_log.sh 50
```

## Related Scripts

```text
uptime_info.sh
check_disk.sh
check_memory.sh
ssh_status.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = diagnostics
```

Es werden keine Unterordner wie `scripts/diagnostics/` oder `07_scripts/diagnostics/` verwendet.
