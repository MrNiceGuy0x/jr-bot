# JR-Bot Structure Audit Handbook

**Status:** Active / TRX validated
**Handbook Version:** 1.3
**Current Public Runtime Script Version Reference:** 0.2.0
**Target Runtime Hardening Level:** D7.6-compatible / validated on TRX
**Project:** JR-Bot / OPSCON
**Recommended Repository Path:** `docs/audits/audit_jr-bot-structure.md`
**Legacy Runtime Script Path:** `tools/audit_jr-bot-structure.sh`
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
19. [JSON Block: `network`](#19-json-block-network)
20. [JSON Block: `storage`](#20-json-block-storage)
21. [JSON Block: `paths`](#21-json-block-paths)
22. [JSON Block: `runtime_structure`](#22-json-block-runtime_structure)
23. [JSON Block: `files`](#23-json-block-files)
24. [JSON Block: `python`](#24-json-block-python)
25. [JSON Block: `systemd`](#25-json-block-systemd)
26. [Boot Report Detection](#26-boot-report-detection)
27. [Profile Detection](#27-profile-detection)
28. [Summary Interpretation](#28-summary-interpretation)
29. [Findings and Deviations](#29-findings-and-deviations)
30. [Known Finding and Deviation Codes](#30-known-finding-and-deviation-codes)
31. [Target One-Liner Layout](#31-target-one-liner-layout)
32. [Legacy and Hybrid Layout Context](#32-legacy-and-hybrid-layout-context)
33. [TRX Validation Result](#33-trx-validation-result)
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

The current target repository path is:

```text
audits/audit_jr-bot-structure.sh
```

The old legacy repository path was:

```text
tools/audit_jr-bot-structure.sh
```

The old `tools/` location must not be used as the target path anymore.

Current validated runtime version reference:

```text
0.2.0
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

Validated OPSCON ingest endpoint version:

```text
1.2
```

### Migration Note

The repository has been migrated from:

```text
tools/
```

to:

```text
audits/
```

Current target state:

```text
audits/audit_jr-bot-structure.sh
```

The Structure Audit now follows the same target folder model as Network Health and Boot Report:

```text
audits/audit_jr-bot-network-health.sh
audits/audit_jr-bot-boot-report.sh
audits/audit_jr-bot-structure.sh
```

### Runtime Validation State

The Structure Audit has been validated on TRX with the D7.6-compatible upload model:

- default OPSCON upload endpoint,
- environment token fallback,
- token-file fallback,
- token sent via `X-OPSCON-INGEST-TOKEN`,
- no visible `curl -F "token=..."` process argument,
- temporary curl config via `mktemp`,
- `chmod 600` on temporary curl config,
- hard curl timeouts:
  - `connect-timeout = 10`,
  - `max-time = 60`.

The runtime also detects the new Boot Report audit path:

```text
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh
```

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

The Structure Audit writes a JSON file locally first.

Current validated behavior on TRX:

```text
/tmp/audit_jr-bot-structure-{instance}-YYYYMMDD_HHMMSS.json
```

The temporary file is deleted after a successful upload unless `--keep-local` or `--output` was used.

Target pending output for future retry-capable operation:

```text
{bot_path}/reports/pending/audit_jr-bot-structure-{instance}-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

Target behavior for One-Liner runtime:

- write a local report first,
- upload to OPSCON if configured,
- delete local temporary report after successful upload unless `--keep-local` or `--output` was used,
- keep report for debugging or retry if upload fails.

## 8. OPSCON Endpoint

Current endpoint:

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
```

Full URL:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

Validated endpoint version:

```text
1.2
```

Expected storage base:

```text
/OPSCON/data/audit_jr-bot-structure/
```

The endpoint must use the instance-scoped ingest-token contract described below.

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
{sha256_ORIGINAL_UPLOAD_TOKEN}
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
  "token_source": "header",
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
| `token_source` | Should be `header` for the hardened runtime. |
| `received_at_utc` | Server-side receive timestamp. |

## 16. Expected JSON Root Structure

Runtime version `0.2.0` currently generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-structure-audit-v1",
  "script_version": "0.2.0",
  "instance": "trx",
  "mode": "target",
  "created_at_utc": "2026-06-27T00:00:00Z",
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

The exact field names may evolve with runtime updates, but the schema name must remain stable for `jrbot-structure-audit-v1` unless a schema migration is intentionally performed.

The `opscon_ingest` block is not generated by the runtime script.

It is added by the OPSCON ingest endpoint after successful upload.

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

## 19. JSON Block: `network`

The `network` block provides a compact local network baseline.

Typical fields:

- hostname IP output,
- all IPv4 addresses,
- primary IPv4 address,
- primary network interface,
- default gateway,
- default route,
- SSH service state.

This does not replace the Network Health Audit. It is included to help interpret the node structure and systemd accessibility.

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

## 21. JSON Block: `paths`

The `paths` block reports important top-level runtime paths.

Validated TRX examples:

```text
/opt/bots/trx
/opt/bots/trx/config
/opt/bots/trx/src
/opt/bots/trx/logs
/opt/bots/trx/state
/opt/bots/trx/tmp
/opt/bots/trx/venv
/opt/bots/trx/data
```

For each path, the audit reports whether it exists.

## 22. JSON Block: `runtime_structure`

The `runtime_structure` block is the main structural evidence block.

It contains:

- detected profile,
- expected layout,
- requested mode,
- top-level entries,
- known directories,
- known scripts,
- tree snapshot,
- deviations.

Validated TRX profile:

```text
profile_detected: template
expected_layout: one_liner_v0_3_target
mode_requested: target
```

The Tree Snapshot captures the relevant runtime layout while omitting very large or noisy subtrees, such as full virtual environment content.

## 23. JSON Block: `files`

The `files` block reports important runtime files.

Examples:

```text
/opt/bots/{instance}/config/config.ini
/opt/bots/{instance}/.env
/opt/bots/{instance}/src/job_runner.py
/opt/bots/{instance}/requirements.txt
/opt/bots/{instance}/install_info.txt
```

For sensitive files, only metadata and key presence should be collected.

Token content must never be included.

## 24. JSON Block: `python`

The `python` block describes Python and venv readiness.

Typical checks:

- system Python version,
- venv Python availability,
- venv pip availability,
- venv Python version,
- `requests` import,
- `dotenv` import.

Validated TRX state:

```text
system_python: Python 3.11.2
venv_python_exists: true
venv_pip_exists: true
requests_import: true
dotenv_import: true
```

## 25. JSON Block: `systemd`

The `systemd` block describes service and timer integration.

Expected target units may include:

```text
bot-runner@{instance}.service
bot-runner@{instance}.timer
```

For each unit, the audit may collect:

- active state,
- load state,
- sub state,
- enabled state when available,
- template existence,
- legacy unit existence.

Validated TRX state:

```text
bot-runner@trx.timer: enabled and active
bot-runner@trx.service: loaded but inactive/dead when not currently running
legacy trx-runner units: absent
```

The Structure Audit must not restart, stop, reload or enable systemd units.

## 26. Boot Report Detection

The Structure Audit must detect the Boot Report audit under the current target path:

```text
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh
```

This path is the primary target candidate.

Legacy candidates may still be checked for migration context:

```text
/opt/bots/{instance}/maintenance/jrbot_boot_report.sh
/opt/bots/{instance}/scripts/maintenance/jrbot_boot_report.sh
/opt/bots/{instance}/scripts/system/jrbot_boot_report.sh
/opt/bots/{instance}/jrbot_boot_report.sh
```

A validated TRX report must show:

```text
boot_report_script_detected: true
```

and the deviation code below must be absent:

```text
BOOT_REPORT_SCRIPT_MISSING
```

This detection was fixed after the `audits/` migration so that the Structure Audit no longer reports the Boot Report as missing when it exists under `audits/audit_jr-bot-boot-report.sh`.

## 27. Profile Detection

The `profile_detected` field classifies the installation.

Expected profile states:

| Profile | Meaning |
|---|---|
| `target` | Matches the current One-Liner target layout. |
| `template` | Matches the current systemd-template based One-Liner runtime pattern. |
| `legacy` | Older DMR/GGB style layout. |
| `hybrid` | Transitional structure with both legacy and target elements. |
| `unknown` | Path exists but does not match a known profile. |

The profile should be based on directory layout, config style, systemd units, and runtime files.

## 28. Summary Interpretation

The `summary` block contains the high-level interpretation.

Validated structure:

```json
"summary": {
  "ok_basic_structure": true,
  "profile_detected": "template",
  "deviation_count": 1,
  "checks": {
    "install_dir_exists": true,
    "job_runner_exists": true,
    "config_or_env_exists": true,
    "venv_python_exists": true,
    "systemd_timer_known": true,
    "storage_root_available": true,
    "storage_bot_available": true,
    "scripts_dir_exists": true,
    "maintenance_available": false,
    "reports_dir_exists": true,
    "boot_report_script_detected": true,
    "reboot_script_detected": true
  }
}
```

Important interpretation rule:

```text
deviation != failure
```

For example, `MAINTENANCE_DIR_MISSING` is expected for the current TRX target layout because the legacy `maintenance/` directory is no longer the primary target location.

## 29. Findings and Deviations

Findings or deviations are observations.

They must be interpreted in the context of the selected layout and migration phase.

Example deviation:

```json
{
  "level": "warning",
  "code": "MAINTENANCE_DIR_MISSING",
  "message": "No maintenance directory detected.",
  "path": "/opt/bots/trx/maintenance"
}
```

This is expected for the current TRX target structure and should not block the Structure Audit.

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
deviation != failure
```

For example, a legacy layout can produce warnings without meaning the current bot is broken.

## 30. Known Finding and Deviation Codes

Recommended finding and deviation codes:

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
| `MISSING_RUNTIME_DIR` | warning | Legacy or older runtime directory expectation is missing. |
| `MISSING_VENV` | warning | Python virtual environment is missing. |
| `MISSING_CONFIG` | warning | No supported config file found. |
| `SECRET_VALUE_EXPOSURE_RISK` | critical | Secret values appear in report content. |
| `SYSTEMD_UNIT_MISSING` | warning | Expected systemd unit missing. |
| `SYSTEMD_UNIT_NOT_ENABLED` | warning | Expected unit exists but is not enabled. |
| `SCRIPT_NOT_EXECUTABLE` | warning | Expected script exists but lacks executable bit. |
| `BOOT_REPORT_SCRIPT_MISSING` | warning | No boot report audit script was detected in any known path. |
| `MAINTENANCE_DIR_MISSING` | warning | Legacy maintenance directory is absent. Expected for the current TRX target layout. |
| `TARGET_READY` | ok | Node appears ready for target-layout operation. |

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
├── docs/
│   ├── audits/
│   └── scripts/
├── logs/
├── reports/
│   └── pending/
├── scripts/
│   ├── cancel_reboot.sh
│   ├── cancel_shutdown.sh
│   ├── check_disk.sh
│   ├── check_memory.sh
│   ├── reboot.sh
│   ├── shutdown.sh
│   ├── ssh_start.sh
│   ├── ssh_status.sh
│   ├── ssh_stop.sh
│   └── uptime_info.sh
├── src/
│   └── job_runner.py
├── state/
├── tmp/
├── venv/
├── install_info.txt
└── requirements.txt
```

Example for TRX:

```text
/opt/bots/trx/
├── audits/
├── config/
├── docs/
├── logs/
├── reports/
│   └── pending/
├── scripts/
├── src/
├── state/
├── tmp/
└── venv/
```

Important target-layout rule:

```text
scripts/ is flat for operative scripts.
audits/ contains audit, diagnostic and report scripts.
maintenance/ is legacy and not required in the current TRX target layout.
tools/ is legacy and must not be used as the target path.
```

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

## 33. TRX Validation Result

Structure runtime validation is completed for TRX.

Validation target:

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
Target runtime script: /opt/bots/trx/audits/audit_jr-bot-structure.sh
```

Validated runtime result:

```text
Script version: 0.2.0
Schema: jrbot-structure-audit-v1
Mode: target
OPSCON endpoint: jrbot_audit_structure_ingest.php
OPSCON endpoint version: 1.2
Token scope: instance
Token source: header
Upload result: success
Local pending count after upload: 0
Temporary local report deleted after successful upload: yes
```

Validated command:

```bash
sudo -u trx /opt/bots/trx/audits/audit_jr-bot-structure.sh   --instance trx   --path /opt/bots/trx
```

Validated OPSCON response pattern:

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
  "token_source": "header",
  "received_at_utc": "YYYY-MM-DDTHH:MM:SSZ"
}
```

Validated Structure summary:

```text
ok_basic_structure: true
profile_detected: template
deviation_count: 1
boot_report_script_detected: true
reboot_script_detected: true
```

Resolved validation issue:

```text
BOOT_REPORT_SCRIPT_MISSING: resolved
```

Remaining warning:

```text
MAINTENANCE_DIR_MISSING
```

Interpretation:

```text
MAINTENANCE_DIR_MISSING is expected for the current TRX target layout because maintenance/ is legacy and operative scripts now live flat under scripts/.
```

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

### Version 0.2.1

Possible improvements:

- Rename legacy/deviation messages so target-layout expected absences are not shown as warnings.
- Add explicit target-layout readiness score.
- Add more detailed systemd template validation.
- Add expected owner/group checks.
- Add executable-bit checks for all known scripts.
- Add local latest-copy option under `reports/`.
- Add optional compact `--agent-summary` output.
- Add optional comparison mode with previous local report.

### Version 0.3.0

Possible improvements:

- Stable machine-readable recommendation categories.
- Optional signed report metadata.
- Explicit public-vs-OPSCON runtime profile.
- Optional dry-run validation for installer-generated layouts.

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

Never use real tokens or real token hashes in examples.

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
audit script detection
Boot Report audit detection
storage basics
legacy/hybrid/template/target profile state
structure deviations and summary checks
```

Current runtime version reference:

```text
0.2.0
```

Legacy runtime path:

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

Validated TRX result:

```text
upload successful
token_scope: instance
token_source: header
boot_report_script_detected: true
pending_count: 0
```

This handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-structure.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/{instance}/docs/audits/audit_jr-bot-structure.md
```
