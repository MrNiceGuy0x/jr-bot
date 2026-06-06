# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/shutdown.md |
| Project | JR-Bot / OPSCON |
| Purpose | Plant ein kontrolliertes Herunterfahren des Raspberry Pi. |
| Job-Key | manual_shutdown |
| Category | POWER / CRITICAL |
| Dependencies | shutdown command: `/sbin/shutdown` or `/usr/sbin/shutdown`; `scripts/cancel_shutdown.sh` |
| Security | Requires sudoers entry for `$INSTALL_DIR/scripts/shutdown.sh` |
| Notes | Runtime path: `scripts/shutdown.sh`; job_group: `maintenance`; default delay: 3 minutes; no scripts subfolders are used. |

## Runtime Script

```text
scripts/shutdown.sh
```

## Purpose

`shutdown.sh` plant ein kontrolliertes Herunterfahren des Raspberry Pi mit Sicherheitsverzögerung.

Das Skript fährt den Pi nicht sofort herunter, sondern plant den Shutdown über `shutdown -h +<minutes>`.

## Default Behavior

Standardmäßig wird ein Shutdown in 3 Minuten geplant.

```bash
sudo ./shutdown.sh
```

entspricht:

```bash
sudo ./shutdown.sh 3
```

## Parameters

| Parameter | Beschreibung |
|---|---|
| `$1` | Minuten bis zum geplanten Shutdown |

Beispiel:

```bash
sudo ./shutdown.sh 5
```

plant einen Shutdown in 5 Minuten.

## Safety Limits

| Limit | Wert |
|---|---:|
| Minimum Delay | 1 Minute |
| Maximum Delay | 60 Minuten |
| Default Delay | 3 Minuten |

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `manual_shutdown` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | nur bewusst bei Bedarf |
| `grace_sec` | `60` |

## config_json

Für TRX:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/shutdown.sh"
}
```

Optional mit 5 Minuten Delay:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/shutdown.sh 5"
}
```

Generisch:

```json
{
  "cmd": "sudo $INSTALL_DIR/scripts/shutdown.sh 5"
}
```

## Security Model

Dieses Skript muss über sudo gestartet werden, weil es eine System-Power-Aktion plant.

Wichtig: In sudoers wird nicht der rohe Systembefehl `/sbin/shutdown` freigegeben, sondern nur der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/shutdown.sh
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
sudo chown root:root /opt/bots/trx/scripts/shutdown.sh
sudo chmod 755 /opt/bots/trx/scripts/shutdown.sh
```

## Abort / Cancel

Der geplante Shutdown kann vor Ablauf mit folgendem Skript abgebrochen werden:

```bash
sudo /opt/bots/trx/scripts/cancel_shutdown.sh
```

Technisch verwendet `cancel_shutdown.sh`:

```bash
shutdown -c
```

Dieses Skript stoppt sowohl geplante Shutdowns als auch geplante Reboots.

## Expected Output

```text
Skript: shutdown.sh wurde gestartet – Shutdown in 3 Minuten geplant.
Hinweis: Der geplante Shutdown kann mit cancel_shutdown.sh abgebrochen werden.
Achtung: Nach dem Herunterfahren ist normalerweise physischer Zugriff zum Einschalten erforderlich.

Shutdown erfolgreich geplant.
```

## Risks

- Nach Ablauf fährt der Raspberry Pi vollständig herunter.
- Danach ist normalerweise ein physischer Start erforderlich.
- Remote-Zugriff und JR-Bot-Kommunikation sind nach dem Shutdown nicht mehr möglich.
- Nicht als `interval`-Job verwenden.

## Troubleshooting

### Fehler: `Dieses Skript muss über sudo ausgeführt werden`

Das Skript wurde ohne sudo gestartet.

Richtig:

```bash
sudo /opt/bots/trx/scripts/shutdown.sh
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
reboot.sh
cancel_shutdown.sh
```

## Notes

Die Kategorisierung erfolgt über:

```text
tbl_jobs.job_group = maintenance
```

Es werden keine Unterordner wie `scripts/power/`, `scripts/system/` oder `07_scripts/power/` verwendet.

`cancel_reboot.sh` existiert im One-Liner-Standard nicht. `cancel_shutdown.sh` übernimmt den Abbruch für geplante Reboots und Shutdowns.
