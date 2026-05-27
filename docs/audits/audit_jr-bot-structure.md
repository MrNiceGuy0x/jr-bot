# JR-Bot Structure Audit Handbook

Status: Active  
Handbook Version: 1.0  
Script Version Reference: 0.1.6  
Project: JR-Bot / OPSCON  
Recommended Path: `docs/audits/audit_jr-bot-structure.md`

---

## 1. Purpose

`audit_jr-bot-structure.sh` is the main read-only structure audit script for JR-Bot nodes.

Its purpose is to inspect how a JR-Bot instance is currently installed on a Raspberry Pi or Linux node. The script collects structured information about the host, network baseline, storage, Python environment, bot directory layout, runtime files, systemd integration, known maintenance scripts, and profile state.

The script does **not** repair, migrate, restart, or modify the bot.

Its output is a JSON report that can be:

- reviewed manually,
- uploaded to OPSCON,
- compared across nodes,
- used by future JR-Agent logic,
- used to validate the One-Liner installer output,
- used as a migration baseline.

---

## 2. Core Role in the JR-Bot Ecosystem

The Structure Audit answers one central question:

> How is this JR-Bot currently built and installed?

It is not a network deep-dive and it is not a boot report.

### Related Audit / Report Types

| Tool | Purpose |
|---|---|
| `audit_jr-bot-structure.sh` | Directory structure, runtime files, Python, systemd, profile detection |
| `audit_jr-bot-network-health.sh` | Network stack, WLAN/DHCP, routes, DNS, connectivity, network services |
| `jrbot_boot_report.sh` | Post-boot state report after a reboot |
| `reboot.sh` | Controlled maintenance reboot script |

Use the Structure Audit when the question is about:

- bot installation layout,
- missing folders,
- missing maintenance scripts,
- legacy vs. template state,
- systemd runner style,
- Python runtime readiness,
- local configuration file type,
- storage size and filesystem basics,
- whether a bot matches the expected One-Liner target structure.

---

## 3. Security Model

The script is intentionally read-only.

It does not:

- create files,
- delete files,
- modify config,
- restart services,
- stop services,
- install packages,
- change permissions,
- expose secret values.

### Secret Handling

The script checks only whether expected keys exist. It does not include their values in the JSON output.

Examples of checked keys:

- `PROJECT_NAME`
- `BOT_NAME`
- `INSTANCE_NAME`
- `SERVER_BASE`
- `SERVER_TOKEN`
- `PING_TOKEN`

### Security Flags in JSON

The generated JSON includes:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
