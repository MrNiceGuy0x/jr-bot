# JR-Bot Structure Audit Handbook

**Status:** Active  
**Handbook Version:** 1.0  
**Script Version Reference:** 0.1.6  
**Project:** JR-Bot / OPSCON  
**Recommended Repository Path:** `docs/audits/audit_jr-bot-structure.md`  
**Last Updated:** 2026-05-27  

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON System](#2-role-in-the-jr-bot--opscon-system)
3. [Security Principles](#3-security-principles)
4. [Typical Usage](#4-typical-usage)
5. [Parameters](#5-parameters)
6. [OPSCON Endpoint](#6-opscon-endpoint)
7. [OPSCON Storage Structure](#7-opscon-storage-structure)
8. [JSON Root Structure](#8-json-root-structure)
9. [JSON Block: `security`](#9-json-block-security)
10. [JSON Block: `host`](#10-json-block-host)
11. [JSON Block: `network`](#11-json-block-network)
12. [JSON Block: `storage`](#12-json-block-storage)
13. [JSON Block: `paths`](#13-json-block-paths)
14. [JSON Block: `runtime_structure`](#14-json-block-runtime_structure)
15. [Profile Detection](#15-profile-detection)
16. [Known Directories](#16-known-directories)
17. [Known Scripts](#17-known-scripts)
18. [Tree Snapshot](#18-tree-snapshot)
19. [Deviations](#19-deviations)
20. [JSON Block: `files`](#20-json-block-files)
21. [JSON Block: `python`](#21-json-block-python)
22. [JSON Block: `systemd`](#22-json-block-systemd)
23. [JSON Block: `summary`](#23-json-block-summary)
24. [JSON Block: `opscon_ingest`](#24-json-block-opscon_ingest)
25. [Current State: DMR](#25-current-state-dmr)
26. [Current State: GGB](#26-current-state-ggb)
27. [Planned Target State: TRX / One-Liner v0.3](#27-planned-target-state-trx--one-liner-v03)
28. [Repository Documentation Structure](#28-repository-documentation-structure)
29. [Local Documentation for Future JR-Agents](#29-local-documentation-for-future-jr-agents)
30. [Cleanup of Legacy OPSCON Structure](#30-cleanup-of-legacy-opscon-structure)
31. [Recommended Interpretation for Agents](#31-recommended-interpretation-for-agents)
32. [Recommended Future Development](#32-recommended-future-development)
33. [Current Project Decision Line](#33-current-project-decision-line)
34. [Short Agent Summary](#34-short-agent-summary)

---

## 1. Purpose

`audit_jr-bot-structure.sh` is the central read-only structure audit script for JR-Bot nodes.

The script checks how a JR-Bot is currently installed on a Raspberry Pi or comparable Linux node. It collects technical information about the host, network, storage, Python environment, bot directory structure, runtime files, systemd integration and known maintenance scripts.

The script does **not** repair, migrate or modify the bot.

Its purpose is a reproducible, safe and machine-readable inventory of the current installation state.

It is especially important for:

- Comparing old and new JR-Bot installations.
- Detecting `legacy`, `template`, `hybrid` and `unknown` profiles.
- Preparing migrations.
- Feeding OPSCON monitoring.
- Supporting future JR-Agent analysis.
- Validating the One-Liner installer.
- Documenting structural deviations in a stable JSON format.

---

## 2. Role in the JR-Bot / OPSCON System

The Structure Audit is one of multiple diagnostic and reporting tools in the JR-Bot ecosystem.

It primarily answers this question:

> How is this JR-Bot currently built and installed?

It is not a deep network diagnostic and not a boot-state report.

### Separation from Other Scripts

| Script | Purpose |
|---|---|
| `audit_jr-bot-structure.sh` | Checks structure, files, directories, Python, systemd and bot profile. |
| `audit_jr-bot-network-health.sh` | Checks network services, WLAN, DHCP, routes, DNS and connectivity. |
| `jrbot_boot_report.sh` | Collects boot-state shortly after restart and reports it to OPSCON. |
| `reboot.sh` | Performs a controlled reboot via a maintenance job. |

The Structure Audit is the right tool when you need to know:

- Which folders exist?
- Which runtime layout is present?
- Is the bot `legacy`, `template`, `hybrid` or `unknown`?
- Are maintenance scripts missing?
- Which systemd units exist?
- Where are the audit scripts stored?
- Is `.env` or `config.ini` used?
- Is the Python virtual environment available and working?

---

## 3. Security Principles

The script is intentionally read-only.

It does not change files, start services, stop services, repair packages or modify the network.

### Security Rules

- No secret values are printed.
- No token values are uploaded from `.env` or `config.ini`.
- Only key presence is reported.
- Configuration files are not dumped.
- The script does not modify the target system.
- The OPSCON upload is optional.
- Temporary local JSON files are deleted after successful upload unless `--keep-local` or `--output` was used.

### Secret Handling

The following keys are checked only for presence:

- `SERVER_BASE`
- `SERVER_TOKEN`
- `PING_TOKEN`
- `BOT_NAME`
- `PROJECT_NAME`
- `INSTANCE_NAME`

The values themselves must never appear in the audit JSON.

---

## 4. Typical Usage

### Local Audit Without Upload

```bash
./audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx
```

### Legacy Audit for DMR

```bash
./audit_jr-bot-structure.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy
```

### Legacy Audit for GGB

```bash
./audit_jr-bot-structure.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --legacy
```

### Audit With OPSCON Upload

```bash
./audit_jr-bot-structure.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php \
  --token <ORIGINAL_UPLOAD_TOKEN>
```

---

## 5. Parameters

| Parameter | Required | Description |
|---|---:|---|
| `--instance <name>` | Yes | Bot instance name, for example `dmr`, `ggb`, `trx`. |
| `--path <path>` | Yes | Bot installation path. |
| `--legacy` | No | Marks the audit as legacy-context. |
| `--push-url <url>` | No | OPSCON ingest endpoint. |
| `--token <token>` | No | Original upload token for OPSCON. |
| `--output <file>` | No | Local JSON output path. File will be kept. |
| `--keep-local` | No | Keep generated local JSON after successful upload. |
| `--print-json` | No | Print generated JSON to stdout. |
| `--tree-depth <n>` | No | Tree snapshot depth. Default: `3`. |

---

## 6. OPSCON Endpoint

The current Structure Audit endpoint is:

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
```

The old general endpoint was:

```text
/OPSCON/api/jrbot_audit_ingest.php
```

The old endpoint was a temporary legacy name. After all jobs are migrated to the new endpoint, the old API file should be removed.

---

## 7. OPSCON Storage Structure

The current target path for Structure Audit reports is:

```text
/OPSCON/data/audit_jr-bot-structure/
```

Recommended structure:

```text
/OPSCON/data/
└── audit_jr-bot-structure/
    ├── _security/
    │   ├── .htaccess
    │   └── ingest_token_sha256
    │
    ├── dmr/
    │   ├── audit_jr-bot-structure-dmr.json
    │   └── history/
    │       └── audit_jr-bot-structure-dmr-YYYYMMDD_HHMMSS.json
    │
    ├── ggb/
    │   ├── audit_jr-bot-structure-ggb.json
    │   └── history/
    │       └── audit_jr-bot-structure-ggb-YYYYMMDD_HHMMSS.json
    │
    └── trx/
        ├── audit_jr-bot-structure-trx.json
        └── history/
            └── audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

### Token Hash

The original upload token is not stored in PHP.

The API validates incoming uploads using this hash file:

```text
/OPSCON/data/audit_jr-bot-structure/_security/ingest_token_sha256
```

The file contains only the SHA256 hash of the original token.

Example:

```text
9bdfb23776a56168e8cec2f98b6a28a323b80968ff20fd1851ee5c1e330667b6
```

The original token is only stored in the job command or provided by the bot during upload.

---

## 8. JSON Root Structure

The script generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-structure-audit-v1",
  "script_version": "0.1.6",
  "instance": "dmr",
  "mode": "legacy",
  "created_at_utc": "2026-05-27T12:20:24Z",
  "security": {},
  "host": {},
  "network": {},
  "storage": {},
  "paths": {},
  "runtime_structure": {},
  "user": {},
  "files": {},
  "python": {},
  "systemd": {},
  "summary": {},
  "opscon_ingest": {}
}
```

---

## 9. JSON Block: `security`

The `security` block documents the script's safety behavior.

Example:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

Interpretation:

- `read_only: true` means the script does not modify the system.
- `secrets_redacted: true` means secrets are not printed.
- `secret_values_included: false` means secret values are not included in the JSON.

---

## 10. JSON Block: `host`

The `host` block contains host and operating system information.

Typical fields:

- `hostname`
- `kernel`
- `architecture`
- `os_pretty_name`
- `os_id`
- `os_version_id`
- `os_version_codename`
- `raspberry_pi_model`
- `cpu_model`
- `cpu_revision`
- `memory_total_mb`
- `boot_time`

Example:

```json
"host": {
  "hostname": "raspberrypi",
  "architecture": "armv7l",
  "os_pretty_name": "Raspbian GNU/Linux 12 (bookworm)",
  "raspberry_pi_model": "Raspberry Pi 3 Model B Rev 1.2",
  "memory_total_mb": 921
}
```

This block is important for identifying the Raspberry Pi generation, OS version and baseline technical environment.

---

## 11. JSON Block: `network`

The `network` block is intentionally a basic network check.

It does not replace the deeper `audit_jr-bot-network-health.sh` script.

Typical fields:

- `hostname_i`
- `all_ipv4`
- `primary_ipv4`
- `primary_interface`
- `default_gateway`
- `default_route`
- `ssh`

Example:

```json
"network": {
  "primary_ipv4": "192.168.178.84",
  "primary_interface": "wlan0",
  "default_gateway": "192.168.178.1",
  "ssh": {
    "service_exists": true,
    "enabled": true,
    "active": true
  }
}
```

If network problems are suspected, run `audit_jr-bot-network-health.sh` in addition to the Structure Audit.

---

## 12. JSON Block: `storage`

The `storage` block checks:

- Root filesystem.
- Bot filesystem.
- Mounted filesystems.
- Block devices via `lsblk`.
- Availability of `df` and `lsblk`.

Important fields:

```json
"storage": {
  "root_filesystem": {},
  "bot_filesystem": {},
  "mounted_filesystems": [],
  "block_devices": {},
  "warnings": []
}
```

This block shows:

- SD card size.
- Free capacity.
- Mount point.
- Filesystem type.
- Usage percentage.

Example:

```text
Root filesystem: 57G total, 52G available, 4% used
Bot filesystem: 57G total, 52G available, 4% used
```

---

## 13. JSON Block: `paths`

The `paths` block checks the classic JR-Bot base folders.

Currently checked:

- `install_dir`
- `config_dir`
- `src_dir`
- `logs_dir`
- `state_dir`
- `tmp_dir`
- `venv_dir`
- `data_dir`

Example:

```json
"paths": {
  "install_dir": {
    "path": "/home/dmr/bots/DMR",
    "exists": true
  },
  "src_dir": {
    "path": "/home/dmr/bots/DMR/src",
    "exists": true
  },
  "state_dir": {
    "path": "/home/dmr/bots/DMR/state",
    "exists": false
  }
}
```

This block represents the basic structure only. The extended runtime structure is documented in `runtime_structure`.

---

## 14. JSON Block: `runtime_structure`

The `runtime_structure` block is the most important extension introduced with version `0.1.6`.

It contains:

- Profile detection.
- Expected target layout.
- Top-level entries.
- Known directories.
- Known scripts.
- Tree snapshot.
- Deviations.

Structure:

```json
"runtime_structure": {
  "profile_detected": "legacy",
  "expected_layout": "one_liner_v0_3_target",
  "mode_requested": "legacy",
  "top_level_entries": [],
  "known_dirs": {},
  "known_scripts": {},
  "tree_snapshot": {},
  "deviations": []
}
```

---

## 15. Profile Detection

The script currently detects the following profiles:

| Profile | Meaning |
|---|---|
| `legacy` | Old bot layout, for example `.env` and legacy systemd units. |
| `template` | Target structure with `config.ini` and `bot-runner@.service` / `bot-runner@.timer`. |
| `hybrid` | Mix of legacy and template signals. |
| `unknown` | No clear profile detected. |

### Legacy

Typical signals:

- `.env` exists.
- `<instance>-runner.service` exists.
- `<instance>-runner.timer` exists.
- No systemd template units.

### Template

Typical signals:

- `config/config.ini` exists.
- `bot-runner@.service` exists.
- `bot-runner@.timer` exists.
- Instance runs through `bot-runner@<instance>.timer`.

### Hybrid

Typical signals:

- `.env` exists.
- `bot-runner@.service` / `bot-runner@.timer` also exist.

GGB is currently an example of a hybrid profile.

---

## 16. Known Directories

The `known_dirs` block checks important runtime folders.

Checked directories:

```text
scripts/
scripts/system/
scripts/checks/
scripts/maintenance/
scripts/docs/
maintenance/
reports/
docs/
tools/
```

Example:

```json
"known_dirs": {
  "scripts_dir": {
    "path": "/home/ggb/bots/ggb/scripts",
    "exists": true
  },
  "maintenance_dir": {
    "path": "/home/ggb/bots/ggb/maintenance",
    "exists": true
  },
  "reports_dir": {
    "path": "/home/ggb/bots/ggb/reports",
    "exists": true
  }
}
```

---

## 17. Known Scripts

The `known_scripts` block checks known maintenance and audit scripts.

Checked paths include:

- `scripts/reboot.sh`
- `maintenance/reboot.sh`
- `scripts/maintenance/reboot.sh`
- `maintenance/jrbot_boot_report.sh`
- `scripts/maintenance/jrbot_boot_report.sh`
- `scripts/system/jrbot_boot_report.sh`
- `tools/audit_jr-bot-structure.sh`
- `<install_path>/audit_jr-bot-structure.sh`
- `$HOME/audit_jr-bot-structure.sh`
- `tools/audit_jr-bot-network-health.sh`
- `<install_path>/audit_jr-bot-network-health.sh`
- `$HOME/audit_jr-bot-network-health.sh`

At the current development stage, the audit scripts may still exist in the user's home directory because maintenance jobs downloaded them with `curl`.

The target location is:

```text
/opt/bots/<instance>/tools/audit_jr-bot-structure.sh
/opt/bots/<instance>/tools/audit_jr-bot-network-health.sh
```

For legacy bots, equivalent paths may be:

```text
/home/<instance>/bots/<instance>/tools/audit_jr-bot-structure.sh
/home/<instance>/bots/<instance>/tools/audit_jr-bot-network-health.sh
```

---

## 18. Tree Snapshot

The tree snapshot documents a limited excerpt from the bot directory.

Default:

```text
max_depth: 3
max_items: 300
```

Excluded large or technical directories include:

- `venv`
- `__pycache__`
- `.git`
- `.cache`

Example DMR snapshot:

```text
/home/dmr/bots/DMR/config
/home/dmr/bots/DMR/logs
/home/dmr/bots/DMR/src
/home/dmr/bots/DMR/.env
/home/dmr/bots/DMR/requirements.txt
/home/dmr/bots/DMR/src/job_runner.py
```

Example GGB snapshot:

```text
/home/ggb/bots/ggb/config
/home/ggb/bots/ggb/logs
/home/ggb/bots/ggb/maintenance
/home/ggb/bots/ggb/reports
/home/ggb/bots/ggb/scripts
/home/ggb/bots/ggb/src
/home/ggb/bots/ggb/state
/home/ggb/bots/ggb/maintenance/jrbot_boot_report.sh
/home/ggb/bots/ggb/scripts/reboot.sh
```

---

## 19. Deviations

`deviations` are structured hints about differences from the current target layout.

Important:

```text
deviation != broken
```

A deviation does not automatically mean that the bot is defective.

Example:

```json
{
  "level": "info",
  "code": "LEGACY_PROFILE_DETECTED",
  "message": "Legacy runner/profile detected. This can be valid for older DMR/GGB bots.",
  "path": ""
}
```

### Current Deviation Codes

| Code | Level | Meaning |
|---|---|---|
| `LEGACY_PROFILE_DETECTED` | info | Old bot layout detected. |
| `HYBRID_PROFILE_DETECTED` | warning | Mix of legacy and template signals detected. |
| `SCRIPTS_DIR_MISSING` | warning | `scripts/` is missing. |
| `MAINTENANCE_DIR_MISSING` | warning | No maintenance directory detected. |
| `REPORTS_DIR_MISSING` | info | `reports/` is missing. |
| `REBOOT_SCRIPT_MISSING` | warning | No `reboot.sh` detected. |
| `BOOT_REPORT_SCRIPT_MISSING` | warning | No `jrbot_boot_report.sh` detected. |
| `NO_SYSTEMD_SERVICE_FOUND` | warning | No known systemd service unit detected. |
| `NO_SYSTEMD_TIMER_FOUND` | warning | No known systemd timer unit detected. |

---

## 20. JSON Block: `files`

The `files` block checks central files.

Checked files:

- `config/config.ini`
- `.env`
- `src/job_runner.py`
- `requirements.txt`
- `install_info.txt`

For `config.ini` and `.env`, the script only checks whether specific keys are present. It does not print the values.

Example:

```json
"env_file": {
  "exists": true,
  "permissions": "644",
  "permissions_ok": false,
  "contains_keys": {
    "SERVER_BASE": true,
    "SERVER_TOKEN": true,
    "BOT_NAME": true,
    "PING_TOKEN": false
  }
}
```

For files containing secrets, `600` is the desired permission target. `644` may work functionally but is not ideal from a security perspective.

---

## 21. JSON Block: `python`

The `python` block checks:

- System Python.
- venv Python.
- venv pip.
- Import of `requests`.
- Import of `dotenv`.

Example:

```json
"python": {
  "system_python": "Python 3.11.2",
  "venv_python_exists": true,
  "venv_pip_exists": true,
  "venv_python": "Python 3.11.2",
  "requests_import": true,
  "dotenv_import": true
}
```

This block indicates whether the runner should generally be executable.

---

## 22. JSON Block: `systemd`

The `systemd` block checks both legacy and template systemd structures.

Checked items:

- `/etc/systemd/system/bot-runner@.service`
- `/etc/systemd/system/bot-runner@.timer`
- `bot-runner@<instance>.service`
- `bot-runner@<instance>.timer`
- `<instance>-runner.service`
- `<instance>-runner.timer`

Example Legacy DMR:

```json
"legacy_service": {
  "exists": true,
  "path": "/etc/systemd/system/dmr-runner.service"
},
"legacy_timer": {
  "exists": true,
  "path": "/etc/systemd/system/dmr-runner.timer"
}
```

Example Template/Hybrid GGB:

```json
"service_template": {
  "exists": true,
  "path": "/etc/systemd/system/bot-runner@.service",
  "permissions": "644"
},
"timer_template": {
  "exists": true,
  "path": "/etc/systemd/system/bot-runner@.timer",
  "permissions": "644"
},
"instance_timer": {
  "name": "bot-runner@ggb.timer",
  "enabled": true,
  "active": true
}
```

---

## 23. JSON Block: `summary`

The `summary` block is intended for quick evaluation.

Example DMR:

```json
"summary": {
  "ok_basic_structure": true,
  "profile_detected": "legacy",
  "deviation_count": 6,
  "checks": {
    "install_dir_exists": true,
    "job_runner_exists": true,
    "config_or_env_exists": true,
    "venv_python_exists": true,
    "systemd_timer_known": true,
    "scripts_dir_exists": false,
    "maintenance_available": false,
    "reports_dir_exists": false,
    "boot_report_script_detected": false,
    "reboot_script_detected": false
  }
}
```

Example GGB:

```json
"summary": {
  "ok_basic_structure": true,
  "profile_detected": "hybrid",
  "deviation_count": 1,
  "checks": {
    "install_dir_exists": true,
    "job_runner_exists": true,
    "config_or_env_exists": true,
    "venv_python_exists": true,
    "systemd_timer_known": true,
    "scripts_dir_exists": true,
    "maintenance_available": true,
    "reports_dir_exists": true,
    "boot_report_script_detected": true,
    "reboot_script_detected": true
  }
}
```

---

## 24. JSON Block: `opscon_ingest`

This block is added by the OPSCON ingest endpoint.

Example:

```json
"opscon_ingest": {
  "received_at_utc": "2026-05-27T12:21:13Z",
  "source_ip": "78.142.65.122",
  "user_agent": "curl/7.88.1",
  "endpoint": "jrbot_audit_structure_ingest.php",
  "mode_posted": "legacy",
  "audit_type": "audit_jr-bot-structure",
  "storage_model": "single-current-file-plus-history"
}
```

This block confirms that the report was successfully received and stored by OPSCON.

---

## 25. Current State: DMR

State date: 2026-05-27

DMR is currently a legacy bot.

### Detected Status

```text
profile_detected: legacy
deviation_count: 6
ok_basic_structure: true
```

### Existing Structure

```text
/home/dmr/bots/DMR/
├── .env
├── config/
├── logs/
├── src/
├── venv/
├── requirements.txt
└── requirements.txt.save
```

### Missing Target Structure

```text
/home/dmr/bots/DMR/scripts/
/home/dmr/bots/DMR/maintenance/
/home/dmr/bots/DMR/reports/
/home/dmr/bots/DMR/docs/
/home/dmr/bots/DMR/tools/
/home/dmr/bots/DMR/state/
/home/dmr/bots/DMR/tmp/
/home/dmr/bots/DMR/data/
```

### Missing Scripts

```text
/home/dmr/bots/DMR/scripts/reboot.sh
/home/dmr/bots/DMR/maintenance/reboot.sh
/home/dmr/bots/DMR/maintenance/jrbot_boot_report.sh
```

### Systemd

DMR still uses legacy systemd units:

```text
/etc/systemd/system/dmr-runner.service
/etc/systemd/system/dmr-runner.timer
```

Not present:

```text
/etc/systemd/system/bot-runner@.service
/etc/systemd/system/bot-runner@.timer
bot-runner@dmr.service
bot-runner@dmr.timer
```

### Assessment

DMR is not broken.

DMR is a working legacy bot with a stable basic structure.

Until the TRX One-Liner migration path is fully tested, the recommended DMR action is only a minimal compatibility fix:

```text
/home/dmr/bots/DMR/scripts/reboot.sh
/home/dmr/bots/DMR/reports/
```

A full migration should be done only after the TRX One-Liner test is successful.

---

## 26. Current State: GGB

State date: 2026-05-27

GGB is currently a hybrid bot.

### Detected Status

```text
profile_detected: hybrid
deviation_count: 1
ok_basic_structure: true
```

### Existing Structure

```text
/home/ggb/bots/ggb/
├── .env
├── config/
├── logs/
├── maintenance/
├── reports/
├── scripts/
├── src/
├── state/
├── venv/
└── requirements.txt
```

### Existing Scripts

```text
/home/ggb/bots/ggb/scripts/reboot.sh
/home/ggb/bots/ggb/maintenance/jrbot_boot_report.sh
```

### Systemd

GGB already uses the template-based systemd logic:

```text
/etc/systemd/system/bot-runner@.service
/etc/systemd/system/bot-runner@.timer
bot-runner@ggb.service
bot-runner@ggb.timer
```

### Why Hybrid?

GGB still has `.env`, but also already has the template systemd units.

Therefore the script detects:

```text
legacy signal: .env
template signal: bot-runner@.service / bot-runner@.timer
result: hybrid
```

### Assessment

GGB is much closer to the target state than DMR.

GGB is a useful reference for:

- Maintenance reboot.
- Boot report.
- Reports directory.
- systemd template operation.
- Structural comparison with TRX.

GGB is not yet a clean final One-Liner target state as long as `config.ini`, `install_info.txt` and `tools/` are missing.

---

## 27. Planned Target State: TRX / One-Liner v0.3

The planned target state for new bots is:

```text
/opt/bots/<instance>/
├── config/
│   └── config.ini
│
├── src/
│   └── job_runner.py
│
├── scripts/
│   ├── system/
│   ├── checks/
│   ├── maintenance/
│   │   └── reboot.sh
│   └── docs/
│
├── tools/
│   ├── audit_jr-bot-structure.sh
│   ├── audit_jr-bot-network-health.sh
│   └── jrbot_boot_report.sh
│
├── docs/
│   ├── architecture.md
│   └── audits/
│       ├── audit_jr-bot-structure.md
│       ├── audit_jr-bot-network-health.md
│       └── jrbot_boot_report.md
│
├── logs/
├── reports/
├── state/
├── tmp/
├── venv/
├── requirements.txt
└── install_info.txt
```

### systemd Target

```text
/etc/systemd/system/bot-runner@.service
/etc/systemd/system/bot-runner@.timer
bot-runner@trx.service
bot-runner@trx.timer
```

### Config Target

```text
/opt/bots/trx/config/config.ini
```

In the final target state, `.env` should no longer be the primary configuration file.

---

## 28. Repository Documentation Structure

Recommended GitHub structure:

```text
jr-bot/
├── installer/
│   └── install_jr-bot.sh
│
├── runtime/
│   ├── src/
│   │   └── job_runner.py
│   ├── scripts/
│   │   ├── system/
│   │   ├── checks/
│   │   ├── maintenance/
│   │   └── docs/
│   ├── requirements.txt
│   └── templates/
│       ├── config.ini.template
│       ├── bot-runner@.service.template
│       └── bot-runner@.timer.template
│
├── tools/
│   ├── audit_jr-bot-structure.sh
│   ├── audit_jr-bot-network-health.sh
│   └── jrbot_boot_report.sh
│
└── docs/
    ├── architecture.md
    └── audits/
        ├── audit_jr-bot-structure.md
        ├── audit_jr-bot-network-health.md
        └── jrbot_boot_report.md
```

This handbook should be stored in the repository at:

```text
docs/audits/audit_jr-bot-structure.md
```

---

## 29. Local Documentation for Future JR-Agents

If a JR-Agent later runs locally on the bot, it should be able to read documentation locally.

Recommended local structure:

```text
/opt/bots/<instance>/docs/audits/
├── audit_jr-bot-structure.md
├── audit_jr-bot-network-health.md
└── jrbot_boot_report.md
```

Additionally, current reports should be locally available or retrievable from OPSCON:

```text
/opt/bots/<instance>/reports/
├── audit_jr-bot-structure-current.json
├── audit_jr-bot-network-health-current.json
└── boot-report-current.json
```

This enables a future JR-Agent to answer:

- What am I?
- How am I installed?
- What is my target state?
- Which deviations are known?
- Which reports exist?
- Which diagnostic scripts may I use?
- Which files must I not modify?

---

## 30. Cleanup of Legacy OPSCON Structure

After all jobs have been moved to the new endpoint, the old structure can be removed.

### Old

```text
/OPSCON/api/jrbot_audit_ingest.php
/OPSCON/data/jrbot_audits/
```

### New

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
/OPSCON/data/audit_jr-bot-structure/
```

### Check Before Deleting

Check all project databases for references to the old endpoint:

```sql
SELECT
    id,
    bot_name,
    job_key,
    config_json
FROM tbl_jobs
WHERE config_json LIKE '%jrbot_audit_ingest.php%'
   OR config_json LIKE '%jrbot_audits%';
```

If this query returns no results, the old API can be removed.

### Delete Old API

```text
/OPSCON/api/jrbot_audit_ingest.php
```

### Delete or Archive Old Data Folder

```text
/OPSCON/data/jrbot_audits/
```

Recommended safe archive path:

```text
/OPSCON/data/_archive/jrbot_audits_legacy_YYYYMMDD/
```

Delete permanently only after a successful control period.

---

## 31. Recommended Interpretation for Agents

An agent must not treat the audit as a simple error list.

Important:

```text
deviation != broken
```

Examples:

- `LEGACY_PROFILE_DETECTED` is expected for DMR.
- `HYBRID_PROFILE_DETECTED` is expected for GGB.
- `SCRIPTS_DIR_MISSING` is a migration hint for an older bot.
- `REBOOT_SCRIPT_MISSING` explains why a maintenance reboot job cannot work.
- `BOOT_REPORT_SCRIPT_MISSING` explains why no boot report can be produced.

An agent should evaluate the following fields first:

1. `summary.ok_basic_structure`
2. `summary.profile_detected`
3. `runtime_structure.deviations`
4. `systemd`
5. `files.config_ini`
6. `files.env_file`
7. `known_scripts`
8. `tree_snapshot`

---

## 32. Recommended Future Development

### Version 0.1.7

Possible improvements:

- Check `config/report_upload.token`.
- Better distinction between `.env` as legacy config and `.env` as allowed supplemental file.
- Detect `install_info.txt` as One-Liner signal.
- Detect `docs/audits/`.
- Detect locally installed handbooks.

### Version 0.1.8

Possible improvements:

- Add a standalone JSON schema documentation file.
- Add machine-readable `recommendations`.
- Add severity schema for migration.
- Add `--print-summary`.

### Version 0.2.0

Possible improvements:

- Full comparison against versioned target profile.
- Support multiple target profiles:
  - `legacy_dmr`
  - `hybrid_ggb`
  - `one_liner_v0_3`
  - `agent_ready_v1`
- Optional comparison with last OPSCON report.
- Optional local report under `reports/`.

---

## 33. Current Project Decision Line

The current project decision is:

1. DMR remains legacy for now.
2. DMR will only be minimally stabilized if necessary.
3. GGB is used as a working hybrid reference bot.
4. TRX will be built cleanly through the new One-Liner.
5. After TRX succeeds, DMR migration or reinstallation will be decided.
6. The Structure Audit remains the central tool for comparing all bots.

---

## 34. Short Agent Summary

`audit_jr-bot-structure.sh` is the main structure diagnostic tool for a JR-Bot.

It does not only check whether files exist. It also identifies the architecture state of the bot.

Important fields:

```text
summary.profile_detected
summary.deviation_count
summary.checks
runtime_structure.known_dirs
runtime_structure.known_scripts
runtime_structure.deviations
systemd
files
python
storage
network
```

A bot can be functional despite deviations.

Examples:

```text
DMR = legacy, functional, but not target structure
GGB = hybrid, mostly modernized, but not final One-Liner target state
TRX = planned clean One-Liner target bot
```

The handbook belongs primarily in the GitHub repository:

```text
docs/audits/audit_jr-bot-structure.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/<instance>/docs/audits/audit_jr-bot-structure.md
```
