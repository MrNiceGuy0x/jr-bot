# JR-Bot Script Documentation

| Field | Value |
|---|---|
| Script/Doc | docs/scripts/cancel_shutdown.md |
| Project | JR-Bot / OPSCON |
| Purpose | Bricht einen geplanten Shutdown oder Reboot ab. |
| Job-Key | cancel_shutdown |
| Category | POWER / SAFETY |
| Dependencies | shutdown command: `/sbin/shutdown` or `/usr/sbin/shutdown` |
| Security | Requires sudoers entry for `$INSTALL_DIR/scripts/cancel_shutdown.sh` |
| Notes | Runtime path: `scripts/cancel_shutdown.sh`; job_group: `maintenance`; replaces `cancel_reboot.sh`; no scripts subfolders are used. |

## Runtime Script

```text
scripts/cancel_shutdown.sh
```

## Purpose

`cancel_shutdown.sh` bricht einen zuvor geplanten Shutdown oder Reboot ab.

Technisch werden geplante Shutdowns und Reboots beide über den Systembefehl `shutdown` geplant und können deshalb gemeinsam über:

```bash
shutdown -c
```

abgebrochen werden.

## Job Configuration

| Field | Value |
|---|---|
| `job_key` | `cancel_shutdown` |
| `job_type` | `shell` |
| `job_group` | `maintenance` |
| `schedule_type` | `once` |
| `enabled` | bei Bedarf |
| `grace_sec` | `30` |

## config_json

Für TRX:

```json
{
  "cmd": "sudo /opt/bots/trx/scripts/cancel_shutdown.sh"
}
```

Generisch:

```json
{
  "cmd": "sudo $INSTALL_DIR/scripts/cancel_shutdown.sh"
}
```

## Security Model

Dieses Skript muss über sudo gestartet werden, weil `shutdown -c` eine Systemaktion ist.

Wichtig: In sudoers wird nicht der rohe Systembefehl `/sbin/shutdown` freigegeben, sondern nur der konkrete JR-Bot Wrapper-Scriptpfad.

Beispiel für TRX:

```sudoers
trx ALL=(root) NOPASSWD: /opt/bots/trx/scripts/cancel_shutdown.sh
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
sudo chown root:root /opt/bots/trx/scripts/cancel_shutdown.sh
sudo chmod 755 /opt/bots/trx/scripts/cancel_shutdown.sh
```

## Expected Output

Erfolgreicher Abbruch:

```text
Skript: cancel_shutdown.sh wurde gestartet.
Aktion: Geplanten Shutdown/Reboot abbrechen.

Geplanter Shutdown/Reboot wurde erfolgreich abgebrochen.
```

Wenn nichts geplant war oder der Abbruch fehlschlägt:

```text
Kein geplanter Shutdown/Reboot gefunden oder Abbruch fehlgeschlagen.
```

## Related Scripts

```text
reboot.sh
shutdown.sh
```

## Notes

`cancel_reboot.sh` wird nicht mehr verwendet.

`cancel_shutdown.sh` ist der zentrale Abbruchmechanismus für:

```text
reboot.sh
shutdown.sh
```

Die Kategorisierung erfolgt ausschließlich über `tbl_jobs.job_group = maintenance`.

Es werden keine Unterordner wie `scripts/system/`, `scripts/power/` oder `scripts/maintenance/` verwendet.
