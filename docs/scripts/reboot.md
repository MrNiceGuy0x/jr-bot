# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/reboot.md |
| Project | JR-Bot / OPSCON |
| Purpose | Plant einen Raspberry-Pi-Neustart mit Sicherheitsverzögerung. |
| Job-Key | manual_reboot |
| Category | POWER / CRITICAL |
| Dependencies | shutdown command: `/sbin/shutdown` or `/usr/sbin/shutdown`; `scripts/cancel_shutdown.sh` |
| Security | Requires sudoers entry for `$INSTALL_DIR/scripts/reboot.sh` |
| Notes | Runtime path: `scripts/reboot.sh`; job_group: `maintenance`; default delay: 3 minutes; no scripts subfolders are used. |

## Runtime Script

```text
scripts/reboot.sh
```

## Purpose

`reboot.sh` plant einen kontrollierten Neustart des Raspberry Pi mit Sicherheitsverzögerung.

Das Skript führt den Reboot nicht sofort aus, sondern plant ihn über `shutdown -r +<minutes>`.

## Default Behavior

Standardmäßig wird ein Reboot in 3 Minuten geplant.

```bash
sudo ./reboot.sh
```

entspricht:

```bash
sudo ./reboot.sh 3
```

## Parameters

| Parameter | Beschreibung |
|---|---|
| `$1` | Minuten bis zum geplanten Reboot |

Beispiel:

```bash
sudo ./reboot.sh 5
```

plant einen Reboot in 5 Minuten.

## Safety Limits

| Limit | Wert |
|---|---:|
| Minimum Delay | 1 Minute |
| Maximum Delay | 60 Minuten |
| Default Delay | 3 Minuten |

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `manual_reboot` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | nur bei Bedarf |
| `grace_sec` | `60` |

## config_json

Für TRX:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/reboot.sh"
}
```

Optional mit 5 Minuten Delay:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/reboot.sh 5"
}
```

Generisch:

```json
{
  "cmd": "sudo $INSTALL_DIR/scripts/reboot.sh 5"
}
```

## Security Model

Dieses Skript muss über sudo gestartet werden, weil es eine System-Power-Aktion plant.

Wichtig: In sudoers wird nicht der rohe Systembefehl `/sbin/shutdown` freigegeben, sondern nur der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/reboot.sh
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
sudo chown root:root /opt/bots/trx/scripts/reboot.sh
sudo chmod 755 /opt/bots/trx/scripts/reboot.sh
```

## Abort / Cancel

Der geplante Reboot kann vor Ablauf mit folgendem Skript abgebrochen werden:

```bash
sudo /opt/bots/trx/scripts/cancel_shutdown.sh
```

Technisch verwendet `cancel_shutdown.sh`:

```bash
shutdown -c
```

Dieses Skript stoppt sowohl geplante Reboots als auch geplante Shutdowns.

## Expected Output

```text
Skript: reboot.sh wurde gestartet – Reboot in 3 Minuten geplant.
Hinweis: Der geplante Reboot kann mit cancel_shutdown.sh abgebrochen werden.

Reboot erfolgreich geplant.
```

## Risks

- Verbindung geht nach Ablauf des Timers verloren.
- Laufende Prozesse werden beendet.
- Falscher Delay kann zu ungeplantem Neustart führen.
- Nicht als `interval`-Job verwenden.

## Troubleshooting

### Fehler: `Dieses Skript muss über sudo ausgeführt werden`

Das Skript wurde ohne sudo gestartet.

Richtig:

```bash
sudo /opt/bots/trx/scripts/reboot.sh
```

### Fehler: `sudo: a password is required`

Der sudoers-Eintrag fehlt oder ist falsch.

Prüfen:

```bash
sudo cat /etc/sudoers.d/trx
sudo visudo -cf /etc/sudoers.d/trx
```

### Fehler: `shutdown-Befehl wurde nicht gefunden`

Pfad prüfen:

```bash
command -v shutdown
```

## Related Scripts

```text
shutdown.sh
cancel_shutdown.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = maintenance
```

Es werden keine Unterordner wie `scripts/power/`, `scripts/system/` oder `07_scripts/power/` verwendet.

`cancel_reboot.sh` existiert im One-Liner-Standard nicht. `cancel_shutdown.sh` übernimmt den Abbruch für geplante Reboots und Shutdowns.

