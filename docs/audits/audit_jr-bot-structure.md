# JR-Bot Structure Audit Handbook

**Status:** Active / runtime hardening pending  
**Handbook Version:** 1.2  
**Current Public Runtime Script Version Reference:** 0.1.6  
**Target Runtime Hardening Level:** D7.6-compatible  
**Project:** JR-Bot / OPSCON  
**Recommended Repository Path:** `docs/audits/audit_jr-bot-structure.md`  
**Current Legacy Runtime Script Path:** `tools/audit_jr-bot-structure.sh`  
**Target Runtime Script Path:** `audits/audit_jr-bot-structure.sh`  
**Expected JSON Schema:** `jrbot-structure-audit-v1`  
**Audit Type:** `audit_jr-bot-structure`  
**Last Updated:** 2026-06-27  

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON Ecosystem](#2-role-in-the-jr-bot--opscon-ecosystem)
3. [Current Repository and Runtime Status](#3-current-repository-and-runtime-status)
4. [Security Model](#4-security-model)
5. [Typical Usage](#5-typical-usage)
6. [Parameters](#6-parameters)
7. [Runtime Output Location](#7-runtime-output-location)
8. [OPSCON Endpoint](#8-opscon-endpoint)
9. [OPSCON Storage Structure](#9-opscon-storage-structure)
10. [Instance-Scoped Token and Hash Security Model](#10-instance-scoped-token-and-hash-security-model)
11. [Expected Token Lookup Order](#11-expected-token-lookup-order)
12. [Expected Default Upload Endpoint](#12-expected-default-upload-endpoint)
13. [D7.6 Runtime Upload Hardening Requirement](#13-d76-runtime-upload-hardening-requirement)
14. [Expected Upload Payload](#14-expected-upload-payload)
15. [Expected OPSCON Response](#15-expected-opscon-response)
16. [Expected JSON Root Structure](#16-expected-json-root-structure)
17. [JSON Block: `security`](#17-json-block-security)
18. [JSON Block: `host`](#18-json-block-host)
19. [JSON Block: `bot_context`](#19-json-block-bot_context)
20. [JSON Block: `storage`](#20-json-block-storage)
21. [JSON Block: `directory_layout`](#21-json-block-directory_layout)
22. [JSON Block: `runtime_files`](#22-json-block-runtime_files)
23. [JSON Block: `config_state`](#23-json-block-config_state)
24. [JSON Block: `python_runtime`](#24-json-block-python_runtime)
25. [JSON Block: `systemd`](#25-json-block-systemd)
26. [JSON Block: `maintenance_scripts`](#26-json-block-maintenance_scripts)
27. [JSON Block: `profile_detection`](#27-json-block-profile_detection)
28. [JSON Block: `analysis`](#28-json-block-analysis)
29. [Findings and Recommendations](#29-findings-and-recommendations)
30. [Known Finding Codes](#30-known-finding-codes)
31. [Target One-Liner Layout](#31-target-one-liner-layout)
32. [Legacy and Hybrid Layout Context](#32-legacy-and-hybrid-layout-context)
33. [TRX Validation Target](#33-trx-validation-target)
34. [Repository Documentation Structure](#34-repository-documentation-structure)
35. [Local Documentation for Future JR-Agents](#35-local-documentation-for-future-jr-agents)
36. [Cleanup of Legacy OPSCON Structure](#36-cleanup-of-legacy-opscon-structure)
37. [Recommended Interpretation for Agents](#37-recommended-interpretation-for-agents)
38. [Recommended Future Development](#38-recommended-future-development)
39. [Public Repository Safety Rules](#39-public-repository-safety-rules)
40. [Short Agent Summary](#40-short-agent-summary)

---

## 1. Purpose

`audit_jr-bot-structure.sh` is the central read-only structure audit script for JR-Bot nodes.

Its purpose is to create a reliable, machine-readable inventory of how a JR-Bot node is installed, configured and integrated into the operating system.

The script inspects:

- host and Raspberry Pi baseline information,
- install path and bot context,
- storage and filesystem basics,
- bot directory layout,
- runtime files,
- known scripts and maintenance scripts,
- config file presence,
- secret-key presence without secret values,
- Python and virtual environment state,
- systemd service and timer integration,
- legacy, hybrid or target-layout profile state,
- deviations from the expected One-Liner layout.

The script does not repair, migrate, restart or modify the bot.

It only collects information and optionally uploads the generated JSON report to OPSCON.

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
| `audits/audit_jr-bot-structure.sh` | Audits bot structure, files, directories, Python, systemd and runtime layout. |
| `audits/audit_jr-bot-network-health.sh` | Audits network stack, WLAN, DHCP, routes, DNS, connectivity and network services. |
| `audits/audit_jr-bot-boot-report.sh` | Reports the system state shortly after boot. |
| `maintenance/reboot.sh` or equivalent runtime script | Performs controlled node reboots from maintenance jobs, if present. |

The Structure Audit is the correct tool when the main question is:

> How is this JR-Bot node currently built?

Use the Structure Audit when the question is about:

- bot installation layout,
- missing folders,
- missing maintenance scripts,
- legacy vs. target state,
- systemd runner style,
- Python runtime readiness,
- local configuration file type,
- storage size and filesystem basics,
- whether a bot matches the expected One-Liner target structure.

It is not intended as a deep network diagnostic tool and does not replace the Network Health Audit.

---

## 3. Current Repository and Runtime Status

The current public `main` state may still contain the Structure Audit runtime script under the legacy path:

```text
tools/audit_jr-bot-structure.sh
```

The intended target path is:

```text
audits/audit_jr-bot-structure.sh
```

The current public runtime version reference is:

```text
0.1.6
```

The expected schema is:

```text
jrbot-structure-audit-v1
```

The audit type is:

```text
audit_jr-bot-structure
```

The current OPSCON ingest endpoint is:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

### Migration Note

The repository is being migrated from:

```text
tools/
```

to:

```text
audits/
```

Current target state:

```text
tools/audit_jr-bot-structure.sh       legacy location, to be removed or migrated
audits/audit_jr-bot-structure.sh      target location
```

The Network Health Audit has already been moved to `audits/`.

The Structure Audit should follow the same cleanup pattern when its D7.6-compatible runtime version is ready and validated.

### Required Before Rollout

Before Structure Audit is considered production-ready for unattended OPSCON upload, it must be aligned with the D7.6 upload-hardening contract:

- default OPSCON upload endpoint,
- environment token fallback,
- token-file fallback,
- token sent via `X-OPSCON-INGEST-TOKEN`,
- no visible `curl -F "token=..."` process argument,
- temporary curl config via `mktemp`,
- `chmod 600` on temporary curl config,
- hard curl timeouts:
  - `connect-timeout = 10`
  - `max-time = 60`.

---

## 4. Security Model

The script is designed to be read-only and safe for recurring execution.

### Security Principles

- No system files are modified.
- No services are restarted.
- No packages are installed or removed.
- Secret values are not printed.
- Config files are not uploaded in full.
- Only the presence of expected config keys is reported.
- Upload to OPSCON is optional.
- Runtime upload uses a token supplied by environment, local token file or explicit debug argument.
- Temporary local reports are removed after successful upload unless explicitly kept.
- The public ingest endpoint must not auto-create `_security`.
- The public ingest endpoint must not auto-create `ingest_token_sha256`.

### Secret Handling

The script checks whether expected keys exist, but it must not include their values in the JSON report.

Examples of checked keys:

```text
SERVER_BASE
SERVER_TOKEN
PING_TOKEN
OPSCON_BASE_URL
OPSCON_INGEST_TOKEN
BOT_INSTANCE
BOT_MODE
```

Only boolean key-presence information should be stored.

Example:

```json
"contains_keys": {
  "SERVER_BASE": true,
  "SERVER_TOKEN": true,
  "PING_TOKEN": false
}
```

The script must not upload actual values for token-like or password-like configuration keys.

### Security Flags in JSON

The JSON report should contain:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

The OPSCON ingest endpoint should reject reports that do not match this safety contract.

---

## 5. Typical Usage

### Target Layout Audit

```bash
/opt/bots/{instance}/audits/audit_jr-bot-structure.sh \
  --instance {instance} \
  --path /opt/bots/{instance}
```

Example for TRX:

```bash
/opt/bots/trx/audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx
```

### Local Summary

```bash
./audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx \
  --print-summary
```

### Legacy Audit for DMR

```bash
./audits/audit_jr-bot-structure.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --print-summary
```

### Legacy/Hybrid Audit for GGB

```bash
./audits/audit_jr-bot-structure.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --print-summary
```

### Manual Upload Override

For normal unattended runtime operation, the default endpoint and token lookup should be used after D7.6 hardening is implemented.

For manual debugging only:

```bash
./audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php \
  --token {ORIGINAL_UPLOAD_TOKEN}
```

The original token must never be committed to GitHub.

### Local Debug Output File

```bash
./audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx \
  --output /opt/bots/trx/reports/pending/audit_jr-bot-structure-trx-local-debug.json \
  --print-summary
```

When `--output` is used, the output file should be kept.

---

## 6. Parameters

Expected supported options:

| Parameter | Required | Description |
|---|---:|---|
| `--instance {name}` | Yes | Bot instance name, for example `dmr`, `ggb`, `trx`. |
| `--path {bot_path}` | Yes | Bot installation path. |
| `--legacy` | No | Marks the audit as legacy-context. Used for older DMR/GGB structures. |
| `--push-url {url}` | No | OPSCON structure ingest endpoint override. |
| `--token {token}` | No | Original upload token for manual debugging. |
| `--output {file}` | No | Local JSON output path. File will be kept. |
| `--keep-local` | No | Keep generated local JSON after successful upload. |
| `--print-json` | No | Print full JSON to stdout. |
| `--print-summary` | No | Print compact findings/recommendations summary, if supported by runtime version. |
| `--tree-depth {n}` | No | Runtime tree snapshot depth, if supported by runtime version. |
| `-h`, `--help` | No | Show help. |

If the current runtime script differs from this table, the runtime script should be aligned before rollout.

---

## 7. Runtime Output Location

The Structure Audit should write the JSON file locally first.

Target pending output:

```text
{bot_path}/reports/pending/audit_jr-bot-structure-{instance}-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

Current older runtime versions may still use `/tmp` as default output.

Target behavior for One-Liner runtime:

- write reports under `{bot_path}/reports/pending/`,
- upload to OPSCON if configured,
- delete local temporary report after successful upload unless `--keep-local` or `--output` was used,
- keep report for debugging or retry if upload fails.

---

## 8. OPSCON Endpoint

Current endpoint:

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
```

Full URL:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

Expected storage base:

```text
/OPSCON/data/audit_jr-bot-structure/
```

The endpoint must use the instance-scoped ingest-token contract described below.

---

## 9. OPSCON Storage Structure

Current required structure:

```text
/OPSCON/data/
└── audit_jr-bot-structure/
    ├── dmr/
    │   ├── _security/
    │   │   ├── .htaccess
    │   │   └── ingest_token_sha256
    │   ├── audit_jr-bot-structure-dmr.json
    │   └── history/
    │       └── audit_jr-bot-structure-dmr-YYYYMMDD_HHMMSS.json
    │
    ├── ggb/
    │   ├── _security/
    │   │   ├── .htaccess
    │   │   └── ingest_token_sha256
    │   ├── audit_jr-bot-structure-ggb.json
    │   └── history/
    │       └── audit_jr-bot-structure-ggb-YYYYMMDD_HHMMSS.json
    │
    └── trx/
        ├── _security/
        │   ├── .htaccess
        │   └── ingest_token_sha256
        ├── audit_jr-bot-structure-trx.json
        └── history/
            └── audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

Important:

```text
/OPSCON/data/audit_jr-bot-structure/_security/ingest_token_sha256
```

is not the current valid model.

The valid model is instance-specific:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
```

### What the Public Ingest Endpoint May Create

After successful authentication and validation, the public ingest endpoint may create runtime storage folders such as:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/history/
```

### What the Public Ingest Endpoint Must Not Create

The public ingest endpoint must not create:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
```

These security assets must be provisioned by a trusted server-side onboarding process, OPSCON admin UI, or manual server-side setup.

---

## 10. Instance-Scoped Token and Hash Security Model

The current endpoint must not store the original token in PHP.

Instead, it reads a SHA256 hash from the instance-specific security path:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
```

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-structure/trx/_security/ingest_token_sha256
```

Example hash-file content:

```text
9bdfb23776a56168e8cec2f98b6a28a323b80968ff20fd1851ee5c1e330667b6
```

Important:

- The file contains only the SHA256 hash.
- No quotes.
- No PHP code.
- No spaces before or after.
- No cleartext token.
- The original token is passed by the bot during upload.
- The original token must not be committed to GitHub.
- The hash file must not be committed to GitHub.
- The `_security` directory must be protected by `.htaccess`.

Recommended `_security/.htaccess`:

```apache
Require all denied
```

### Public Ingest Validation Order

The ingest endpoint must process uploads in this order:

1. Allow only `POST`.
2. Read `instance` from request.
3. Strictly validate `instance`.
4. Resolve instance directory.
5. Read instance-specific hash file:
   ```text
   /OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
   ```
6. Read token from header or request.
7. Compare `sha256(token)` against stored hash using constant-time comparison.
8. Validate uploaded JSON.
9. Verify expected schema:
   ```text
   jrbot-structure-audit-v1
   ```
10. Store latest report.
11. Store history report.
12. Return JSON response.

If the instance directory, `_security` directory, or hash file is missing, empty or invalid, the upload must be rejected with:

```json
{
  "success": false,
  "code": "INGEST_NOT_CONFIGURED"
}
```

### Instance Validation

The instance name must be strictly validated before any token lookup or file write.

Recommended pattern:

```text
^[a-z0-9][a-z0-9_-]{0,63}$
```

Valid examples:

```text
trx
ggb
dmr
jrbot-01
jrbot_01
```

Invalid examples:

```text
../trx
TRX
trx/../../x
trx.example
trx/test
```

---

## 11. Expected Token Lookup Order

The Structure Audit should use the same D7.6 token lookup model as the other audit scripts.

Recommended lookup order:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_structure.token
{bot_path}/config/structure_upload.token
{bot_path}/config/report_upload.token
```

Example TRX fallback file:

```text
/opt/bots/trx/config/report_upload.token
```

The token file must exist only on the bot host.

The token file must not be committed to the public repository.

Recommended file permissions on the bot host:

```bash
sudo chown {instance}:{instance} /opt/bots/{instance}/config/report_upload.token
sudo chmod 600 /opt/bots/{instance}/config/report_upload.token
```

Example for TRX:

```bash
sudo chown trx:trx /opt/bots/trx/config/report_upload.token
sudo chmod 600 /opt/bots/trx/config/report_upload.token
```

---

## 12. Expected Default Upload Endpoint

The Structure Audit should use this default endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

Recommended environment override:

```text
STRUCTURE_AUDIT_PUSH_URL
```

Recommended CLI override:

```bash
--push-url {url}
```

For normal runtime operation, the default endpoint should be used after D7.6 hardening is implemented.

Manual `--push-url` should be reserved for debugging, staging, or endpoint migration.

---

## 13. D7.6 Runtime Upload Hardening Requirement

The Structure Audit must follow the same hardened upload contract as Boot Report and Network Health.

### Previous Unsafe Runtime Pattern

```text
curl ... -F "token=${TOKEN}" ...
```

This may expose the cleartext token through local process inspection tools such as:

```text
ps aux
systemctl status
/proc/{pid}/cmdline
```

### Required Hardened Runtime Pattern

```text
curl --config {temporary_curl_config}
```

The temporary curl config file must be:

```text
created with mktemp
chmod 600
used only for the current upload
removed immediately after the curl call
```

The ingest token must be sent as an HTTP header:

```text
X-OPSCON-INGEST-TOKEN: {token}
```

The OPSCON ingest endpoint must accept this header.

### Upload Timeout Contract

Every Structure Audit upload must define hard curl timeouts:

```text
connect-timeout = 10
max-time = 60
```

This prevents upload calls from hanging indefinitely.

### Important Security Note

D7.6 significantly reduces local token exposure, but it does not make leaks impossible.

Remaining sensitive assets:

```text
/opt/bots/{instance}/config/report_upload.token
temporary curl config file during active upload
OPSCON server-side _security/ingest_token_sha256
server logs, if misconfigured
old Git history, if secrets were ever committed
```

---

## 14. Expected Upload Payload

The runtime upload should send the following form fields:

```text
instance={instance}
mode={mode}
audit_file=@{json_file};type=application/json
```

The token must be sent through:

```text
X-OPSCON-INGEST-TOKEN: {token}
```

The old multipart token field is deprecated for runtime usage:

```text
token={token}
```

The OPSCON endpoint may keep backward-compatible support for the multipart token field during migration, but the runtime script should use the header-based model.

---

## 15. Expected OPSCON Response

Successful OPSCON response example:

```json
{
  "success": true,
  "message": "JR-Bot structure audit stored successfully.",
  "instance": "trx",
  "mode": "target",
  "audit_type": "audit_jr-bot-structure",
  "expected_schema": "jrbot-structure-audit-v1",
  "stored_file": "/data/audit_jr-bot-structure/trx/audit_jr-bot-structure-trx.json",
  "history_file": "/data/audit_jr-bot-structure/trx/history/audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json",
  "token_scope": "instance",
  "received_at_utc": "YYYY-MM-DDTHH:MM:SSZ"
}
```

Important response fields:

| Field | Meaning |
|---|---|
| `success` | Upload result. |
| `instance` | Accepted instance name. |
| `audit_type` | Must be `audit_jr-bot-structure`. |
| `expected_schema` | Must be `jrbot-structure-audit-v1`. |
| `stored_file` | Latest report path. |
| `history_file` | Historical report path. |
| `token_scope` | Should be `instance`. |
| `received_at_utc` | Server-side receive timestamp. |

---

## 16. Expected JSON Root Structure

The script should generate JSON with this high-level structure:

```json
{
  "schema": "jrbot-structure-audit-v1",
  "script_version": "0.1.6",
  "instance": "trx",
  "mode": "target",
  "created_at_utc": "2026-06-27T00:00:00Z",
  "security": {},
  "host": {},
  "bot_context": {},
  "storage": {},
  "directory_layout": {},
  "runtime_files": {},
  "config_state": {},
  "python_runtime": {},
  "systemd": {},
  "maintenance_scripts": {},
  "profile_detection": {},
  "analysis": {}
}
```

The exact field names may evolve with runtime updates, but the schema name must remain stable for `jrbot-structure-audit-v1` unless a schema migration is intentionally performed.

The `opscon_ingest` block is not generated by the runtime script.

It is added by the OPSCON ingest endpoint after successful upload.

---

## 17. JSON Block: `security`

The `security` block documents that the report is safe to store and inspect.

Expected example:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

Interpretation:

| Field | Expected | Meaning |
|---|---:|---|
| `read_only` | `true` | The script made no changes. |
| `secrets_redacted` | `true` | Secret-looking values were redacted or not included. |
| `secret_values_included` | `false` | Secret values are not included. |

The OPSCON ingest endpoint should reject reports that do not match this safety contract.

---

## 18. JSON Block: `host`

The `host` block describes the host system.

Typical fields:

- hostname,
- platform,
- machine architecture,
- kernel,
- Raspberry Pi model,
- OS release,
- uptime or boot time,
- basic CPU and memory facts.

This helps compare DMR, GGB and TRX at the system level.

---

## 19. JSON Block: `bot_context`

The `bot_context` block connects the structure report to the bot installation.

Expected fields:

| Field | Meaning |
|---|---|
| `install_path` | Expected bot installation directory. |
| `install_path_exists` | Whether the directory exists. |
| `instance` | Bot instance name. |
| `mode` | Requested mode, for example `legacy` or `target`. |

Example:

```json
"bot_context": {
  "install_path": "/opt/bots/trx",
  "install_path_exists": true,
  "instance": "trx",
  "mode": "target"
}
```

---

## 20. JSON Block: `storage`

The `storage` block should describe filesystem and disk state.

Typical checks:

- root filesystem usage,
- bot filesystem usage,
- block devices,
- mount points,
- free space,
- available space under `{bot_path}`,
- whether the bot path is on the expected filesystem.

This block is useful for diagnosing SD-card pressure and disk-full conditions.

---

## 21. JSON Block: `directory_layout`

The `directory_layout` block should report expected directories.

Target directories:

```text
/opt/bots/{instance}/
/opt/bots/{instance}/audits/
/opt/bots/{instance}/config/
/opt/bots/{instance}/logs/
/opt/bots/{instance}/reports/
/opt/bots/{instance}/reports/pending/
/opt/bots/{instance}/runtime/
/opt/bots/{instance}/scripts/
```

For each directory, the audit should report at least:

- exists,
- is directory,
- owner,
- group,
- permissions,
- whether it matches the target expectation.

---

## 22. JSON Block: `runtime_files`

The `runtime_files` block should report important runtime files.

Examples:

```text
install_jr-bot.sh
audits/audit_jr-bot-structure.sh
audits/audit_jr-bot-network-health.sh
audits/audit_jr-bot-boot-report.sh
runtime/src/job_runner.py
runtime/requirements.txt
config/config.ini
config/report_upload.token
```

For sensitive files, only metadata should be collected.

Token content must never be included.

---

## 23. JSON Block: `config_state`

The `config_state` block should identify configuration style and expected key presence.

Expected config styles:

```text
config.ini
.env
hybrid
missing
```

Recommended checks:

- `config/config.ini` exists,
- `.env` exists,
- key presence,
- no secret values,
- mode or instance indicators,
- OPSCON base URL presence,
- report upload token file presence.

Example key-presence output:

```json
"contains_keys": {
  "SERVER_BASE": true,
  "SERVER_TOKEN": true,
  "PING_TOKEN": false
}
```

---

## 24. JSON Block: `python_runtime`

The `python_runtime` block should describe Python and venv readiness.

Typical checks:

- system Python availability,
- Python version,
- venv path,
- venv Python executable,
- pip availability,
- requirements file existence,
- whether expected packages appear installed,
- job runner import readiness if safe to test.

Target venv pattern:

```text
/opt/bots/{instance}/runtime/venv/
```

---

## 25. JSON Block: `systemd`

The `systemd` block should describe service and timer integration.

Expected target units may include:

```text
bot-runner@{instance}.service
bot-runner@{instance}.timer
jrbot-boot-report-audit@{instance}.service
jrbot-report-upload@{instance}.service
jrbot-report-upload@{instance}.timer
```

For each unit, the audit should collect:

- load state,
- active state,
- sub state,
- unit file state,
- result,
- fragment path,
- description,
- recent relevant status if safe.

The Structure Audit should not restart or reload systemd units.

---

## 26. JSON Block: `maintenance_scripts`

The `maintenance_scripts` block should report known scripts and operational helpers.

Examples:

```text
scripts/maintenance/reboot.sh
scripts/maintenance/update.sh
scripts/checks/
scripts/system/
audits/
```

The audit should report:

- file exists,
- executable bit,
- owner/group,
- path relative to bot base,
- whether expected maintenance script is missing.

---

## 27. JSON Block: `profile_detection`

The `profile_detection` block should classify the installation.

Expected profile states:

| Profile | Meaning |
|---|---|
| `target` | Matches the current One-Liner target layout. |
| `legacy` | Older DMR/GGB style layout. |
| `hybrid` | Transitional structure with both legacy and target elements. |
| `unknown` | Path exists but does not match a known profile. |

The profile should be based on directory layout, config style, systemd units, and runtime files.

---

## 28. JSON Block: `analysis`

The `analysis` block contains the high-level interpretation.

Expected structure:

```json
"analysis": {
  "health_state": "warning",
  "critical_count": 0,
  "warning_count": 2,
  "findings": [],
  "recommendations": [],
  "comparison_hints": []
}
```

Possible `health_state` values:

| Value | Meaning |
|---|---|
| `ok` | No critical or warning findings. |
| `warning` | At least one warning, no critical findings. |
| `critical` | At least one critical finding. |

Important:

```text
info findings do not make health_state warning
ok findings do not make health_state warning
```

---

## 29. Findings and Recommendations

Findings are observations.

Recommendations are suggested actions.

Example:

```json
"findings": [
  {
    "level": "warning",
    "code": "MISSING_TARGET_DIRECTORY",
    "message": "Expected target directory is missing.",
    "evidence": "/opt/bots/trx/reports/pending"
  }
],
"recommendations": [
  {
    "level": "warning",
    "code": "CREATE_TARGET_DIRECTORY",
    "message": "Create missing target directory during installer or onboarding.",
    "action": "mkdir -p /opt/bots/trx/reports/pending"
  }
]
```

### Finding Levels

| Level | Meaning |
|---|---|
| `ok` | Expected state observed. |
| `info` | Informational difference or expected legacy state. |
| `warning` | Potential deviation from target layout. |
| `critical` | Broken or missing required structure. |

### Important Rule

```text
finding != failure
```

For example, a legacy layout can produce warnings without meaning the current bot is broken.

---

## 30. Known Finding Codes

Recommended finding codes:

| Code | Level | Meaning |
|---|---|---|
| `STRUCTURE_OK` | ok | Expected target structure detected. |
| `LEGACY_LAYOUT_DETECTED` | info | Legacy structure detected. |
| `HYBRID_LAYOUT_DETECTED` | info | Transitional structure detected. |
| `INSTALL_PATH_MISSING` | critical | Requested bot install path does not exist. |
| `MISSING_TARGET_DIRECTORY` | warning | Expected target directory is missing. |
| `MISSING_REPORTS_PENDING` | warning | `reports/pending` is missing. |
| `MISSING_CONFIG_DIR` | warning | `config/` directory is missing. |
| `MISSING_AUDITS_DIR` | warning | `audits/` directory is missing. |
| `MISSING_RUNTIME_DIR` | warning | `runtime/` directory is missing. |
| `MISSING_VENV` | warning | Python virtual environment is missing. |
| `MISSING_CONFIG` | warning | No supported config file found. |
| `SECRET_VALUE_EXPOSURE_RISK` | critical | Secret values appear in report content. |
| `SYSTEMD_UNIT_MISSING` | warning | Expected systemd unit missing. |
| `SYSTEMD_UNIT_NOT_ENABLED` | warning | Expected unit exists but is not enabled. |
| `SCRIPT_NOT_EXECUTABLE` | warning | Expected script exists but lacks executable bit. |
| `TARGET_READY` | ok | Node appears ready for target-layout operation. |

---

## 31. Target One-Liner Layout

The current One-Liner target layout for a JR-Bot instance is:

```text
/opt/bots/{instance}/
├── audits/
│   ├── audit_jr-bot-boot-report.sh
│   ├── audit_jr-bot-network-health.sh
│   └── audit_jr-bot-structure.sh
├── config/
│   ├── config.ini
│   └── report_upload.token
├── logs/
├── reports/
│   └── pending/
├── runtime/
│   ├── src/
│   ├── venv/
│   └── requirements.txt
└── scripts/
    ├── checks/
    ├── maintenance/
    └── system/
```

Example for TRX:

```text
/opt/bots/trx/
├── audits/
├── config/
├── logs/
├── reports/
│   └── pending/
├── runtime/
└── scripts/
```

---

## 32. Legacy and Hybrid Layout Context

Known legacy paths:

```text
/home/dmr/bots/DMR
/home/ggb/bots/ggb
```

Expected One-Liner target path pattern:

```text
/opt/bots/{instance}
```

Legacy does not automatically mean broken.

Legacy means that the node predates the final One-Liner target structure.

The Structure Audit should help determine whether the node can be migrated safely.

### DMR Context

Known target assignment:

```text
DMR → 192.168.178.201
```

Potential legacy command:

```bash
./audits/audit_jr-bot-structure.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy
```

### GGB Context

Known target assignment:

```text
GGB → 192.168.178.202
```

Potential legacy or hybrid command:

```bash
./audits/audit_jr-bot-structure.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb
```

### TRX Context

Known target assignment:

```text
TRX → 192.168.178.203
```

Expected target command:

```bash
/opt/bots/trx/audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx
```

---

## 33. TRX Validation Target

Structure runtime validation is still pending.

TRX validation target:

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
Target runtime script: /opt/bots/trx/audits/audit_jr-bot-structure.sh
```

Required validation steps:

```text
1. Provision OPSCON server directory:
   /OPSCON/data/audit_jr-bot-structure/trx/

2. Provision instance-scoped security:
   /OPSCON/data/audit_jr-bot-structure/trx/_security/
   /OPSCON/data/audit_jr-bot-structure/trx/_security/ingest_token_sha256

3. Install or update runtime script on the bot host.

4. Run bash syntax check.

5. Run Structure Audit without explicit --push-url and without explicit --token.

6. Verify OPSCON accepted the upload.

7. Verify OPSCON stored latest report.

8. Verify OPSCON stored history report.

9. Verify local pending-file handling.

10. Verify no token is visible through process arguments.
```

Expected validated result after completion:

```text
bash syntax check successful
upload successful without --push-url
upload successful without --token
default OPSCON endpoint used
token loaded from local config/report_upload.token
OPSCON accepted instance-scoped token
OPSCON stored latest report
OPSCON stored history report
local pending file deleted after successful upload
pending_count=0
```

---

## 34. Repository Documentation Structure

Recommended GitHub repository structure:

```text
jr-bot/
├── install_jr-bot.sh
├── audits/
│   ├── audit_jr-bot-boot-report.sh
│   ├── audit_jr-bot-network-health.sh
│   └── audit_jr-bot-structure.sh
├── docs/
│   ├── architecture.md
│   └── audits/
│       ├── audit-ingest-contract.md
│       ├── audit_jr-bot-boot-report.md
│       ├── audit_jr-bot-network-health.md
│       └── audit_jr-bot-structure.md
├── runtime/
│   ├── src/
│   ├── scripts/
│   ├── requirements.txt
│   └── templates/
└── systemd/
    └── templates/
```

This handbook belongs in the repository at:

```text
docs/audits/audit_jr-bot-structure.md
```

---

## 35. Local Documentation for Future JR-Agents

If a future JR-Agent runs locally on a bot, it should be able to read this handbook locally.

Recommended local structure:

```text
/opt/bots/{instance}/docs/audits/
├── audit-ingest-contract.md
├── audit_jr-bot-boot-report.md
├── audit_jr-bot-network-health.md
└── audit_jr-bot-structure.md
```

Recommended local audits:

```text
/opt/bots/{instance}/audits/
├── audit_jr-bot-boot-report.sh
├── audit_jr-bot-network-health.sh
└── audit_jr-bot-structure.sh
```

Recommended local reports:

```text
/opt/bots/{instance}/reports/pending/
```

Recommended config token location:

```text
/opt/bots/{instance}/config/report_upload.token
```

---

## 36. Cleanup of Legacy OPSCON Structure

After DMR, GGB and TRX jobs have been moved to the current endpoint, old structure-audit endpoints and old data folders can be removed or archived if they exist.

### Current

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
/OPSCON/data/audit_jr-bot-structure/
```

### Check Before Deleting

Check all project databases for old endpoint references:

```sql
SELECT
    id,
    bot_name,
    job_key,
    config_json
FROM tbl_jobs
WHERE config_json LIKE '%jrbot_structure_ingest.php%'
   OR config_json LIKE '%jrbot_audit_structure_ingest.php%'
   OR config_json LIKE '%audit_jr-bot-structure%';
```

### Safe Archive Option

```text
/OPSCON/data/_archive/audit_jr-bot-structure_legacy_YYYYMMDD/
```

Permanent deletion should happen only after a successful control period.

---

## 37. Recommended Interpretation for Agents

Agents must not interpret every finding as a failure.

Important rule:

```text
finding != failure
```

Examples:

```text
LEGACY_LAYOUT_DETECTED = info
HYBRID_LAYOUT_DETECTED = info
MISSING_TARGET_DIRECTORY = warning
INSTALL_PATH_MISSING = critical
STRUCTURE_OK = ok
```

Agents should inspect in this order:

1. `schema`
2. `script_version`
3. `instance`
4. `mode`
5. `security`
6. `bot_context.install_path_exists`
7. `profile_detection`
8. `directory_layout`
9. `runtime_files`
10. `config_state`
11. `python_runtime`
12. `systemd`
13. `maintenance_scripts`
14. `analysis.health_state`
15. `analysis.critical_count`
16. `analysis.warning_count`
17. `analysis.findings`
18. `analysis.recommendations`

If `health_state` is `ok`, the node appears structurally healthy for the evaluated profile.

If a legacy node has warnings, determine whether the warnings are expected migration differences or actual blockers.

---

## 38. Recommended Future Development

### Version 0.1.7

Possible improvements:

- Move runtime script from `tools/` to `audits/`.
- Normalize default output path to `{bot_path}/reports/pending/`.
- Add default OPSCON endpoint.
- Add token auto-discovery:
  - `REPORT_UPLOAD_TOKEN`
  - `{bot_path}/config/audit_structure.token`
  - `{bot_path}/config/structure_upload.token`
  - `{bot_path}/config/report_upload.token`
- Add hardened curl upload through temporary curl config.
- Add `X-OPSCON-INGEST-TOKEN` header upload.
- Add curl timeouts:
  - `connect-timeout = 10`
  - `max-time = 60`.

### Version 0.1.8

Possible improvements:

- Add explicit target-layout readiness score.
- Add more detailed systemd template validation.
- Add expected owner/group checks.
- Add executable-bit checks for all known scripts.
- Add local latest-copy option under `reports/`.

### Version 0.2.0

Possible improvements:

- Full One-Liner structure baseline validation.
- Agent-readable compact summary block.
- Comparison mode with previous local report.
- Optional `--agent-summary` compact output.
- Optional signed report metadata.
- Stable machine-readable recommendation categories.

---

## 39. Public Repository Safety Rules

The public repository must never contain:

```text
cleartext ingest tokens
SHA256 ingest token hashes
production .env files
generated local token files
generated pending audit JSON files
private OPSCON security files
local temporary curl config files
```

Token files belong only on the bot host.

Token hashes belong only in the OPSCON server-side instance `_security` directory.

Correct server-side hash location:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
```

Correct bot-side token fallback location:

```text
/opt/bots/{instance}/config/report_upload.token
```

The public repository may contain:

```text
audits/audit_jr-bot-structure.sh
docs/audits/audit_jr-bot-structure.md
docs/audits/audit-ingest-contract.md
example config templates without secrets
placeholder token names
```

Recommended placeholders:

```text
{ORIGINAL_UPLOAD_TOKEN}
{sha256_ORIGINAL_UPLOAD_TOKEN}
{instance}
{bot_path}
{json_file}
```

Never use real tokens in examples.

---

## 40. Short Agent Summary

`audit_jr-bot-structure.sh` is the main structure diagnostic tool for JR-Bot nodes.

It is read-only and safe.

It checks:

```text
install path
directory layout
runtime files
config style
secret-key presence without secret values
Python runtime
virtual environment
systemd service/timer integration
maintenance scripts
storage basics
legacy/hybrid/target profile state
structure findings and recommendations
```

Current public runtime version reference:

```text
0.1.6
```

Current legacy runtime path:

```text
tools/audit_jr-bot-structure.sh
```

Target runtime path:

```text
audits/audit_jr-bot-structure.sh
```

Current schema:

```text
jrbot-structure-audit-v1
```

Current OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

Current OPSCON storage path:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/
```

Current instance-scoped token-hash path:

```text
/OPSCON/data/audit_jr-bot-structure/{instance}/_security/ingest_token_sha256
```

Healthy current assignments:

```text
DMR → 192.168.178.201
GGB → 192.168.178.202
TRX → 192.168.178.203
```

Healthy target local runtime path:

```text
/opt/bots/{instance}/audits/audit_jr-bot-structure.sh
```

The Structure Audit still requires the same D7.6 runtime hardening and validation that has already been applied to Network Health.

This handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-structure.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/{instance}/docs/audits/audit_jr-bot-structure.md
```
