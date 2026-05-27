# JR-Bot Structure Audit Handbook

Status: Active  
Handbook Version: 1.0  
Script Version Reference: 0.1.6  
Project: JR-Bot / OPSCON  
Recommended Path: `docs/audits/audit_jr-bot-structure.md`

---

## 1. Purpose

`audit_jr-bot-structure.sh` is the central read-only structure audit script for JR-Bot nodes.

Its purpose is to create a reliable, machine-readable inventory of how a JR-Bot node is installed, configured and integrated into the operating system.

The script does **not** repair, migrate or modify the bot. It only collects information and optionally uploads the generated JSON report to OPSCON.

The audit is used to answer questions such as:

- Which JR-Bot structure is installed on this node?
- Is the node a legacy, hybrid or target-layout installation?
- Which directories are present or missing?
- Which maintenance scripts exist?
- Does the bot use `.env` or `config.ini`?
- Is the Python virtual environment present?
- Are systemd service and timer units installed?
- Is the node prepared for future One-Liner / JR-Agent workflows?
- What deviations from the current target structure exist?

---

## 2. Role in the JR-Bot / OPSCON Ecosystem

The JR-Bot project uses several audit and reporting scripts. Each script has a different purpose.

| Script | Primary Purpose |
|---|---|
| `audit_jr-bot-structure.sh` | Audits bot structure, files, directories, Python, systemd and runtime layout |
| `audit_jr-bot-network-health.sh` | Audits network stack, WLAN, DHCP, routes, DNS, connectivity and network services |
| `jrbot_boot_report.sh` | Reports the system state shortly after boot |
| `reboot.sh` | Performs controlled node reboots from maintenance jobs |

The structure audit is the correct tool when the main question is:

> How is this JR-Bot node currently built?

It is not intended as a deep network diagnostic tool and does not replace the network-health audit.

---

## 3. Security Model

The script is designed to be read-only and safe for recurring execution.

### Security Principles

- No system files are modified.
- No services are restarted.
- No packages are installed or removed.
- Secret values are not printed.
- Config files are not uploaded in full.
- Only the presence of expected config keys is reported.
- Upload to OPSCON is optional.
- Temporary local reports are removed after successful upload unless explicitly kept.

### Secret Handling

The script checks whether expected keys exist, but it does not include their values in the JSON report.

Examples of checked keys:

- `PROJECT_NAME`
- `BOT_NAME`
- `INSTANCE_NAME`
- `SERVER_BASE`
- `SERVER_TOKEN`
- `PING_TOKEN`

The JSON report only contains boolean values such as:

```json
"contains_keys": {
  "SERVER_BASE": true,
  "SERVER_TOKEN": true,
  "PING_TOKEN": false
}
