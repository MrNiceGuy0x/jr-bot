# JR-Bot Boot Report Audit Handbook

**Status:** Active / TRX validated
**Handbook Version:** 1.0
**Runtime Script Version Reference:** 0.2.2
**Target Runtime Hardening Level:** D7.6-compatible / validated on TRX
**Project:** JR-Bot / OPSCON
**Recommended Repository Path:** `docs/audits/audit_jr-bot-boot-report.md`
**Related Runtime Script:** `audits/audit_jr-bot-boot-report.sh`
**Legacy Runtime Script Path:** `maintenance/jrbot_boot_report.sh`
**Expected JSON Schema:** `jrbot-boot-report-audit-v1`
**Audit Type:** `audit_jr-bot-boot-report`
**Job Key:** `audit_jr-bot-boot-report`
**Last Updated:** 2026-06-27

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON System](#2-role-in-the-jr-bot--opscon-system)
3. [Current Runtime Status](#3-current-runtime-status)
4. [Repository Path Migration](#4-repository-path-migration)
5. [Security Principles](#5-security-principles)
6. [Typical Usage](#6-typical-usage)
7. [Parameters](#7-parameters)
8. [Runtime Output and Pending Behavior](#8-runtime-output-and-pending-behavior)
9. [Upload-Pending Mode Contract](#9-upload-pending-mode-contract)
10. [OPSCON Endpoint](#10-opscon-endpoint)
11. [OPSCON Storage Structure](#11-opscon-storage-structure)
12. [Instance-Scoped Token and Hash Security Model](#12-instance-scoped-token-and-hash-security-model)
13. [Token Lookup Order](#13-token-lookup-order)
14. [Default Upload Endpoint](#14-default-upload-endpoint)
15. [D7.6 Runtime Upload Hardening](#15-d76-runtime-upload-hardening)
16. [Expected Upload Payload](#16-expected-upload-payload)
17. [Expected OPSCON Response](#17-expected-opscon-response)
18. [JSON Root Structure](#18-json-root-structure)
19. [JSON Block: `security`](#19-json-block-security)
20. [JSON Block: `bot_context`](#20-json-block-bot_context)
21. [JSON Block: `commands_available`](#21-json-block-commands_available)
22. [JSON Block: `host`](#22-json-block-host)
23. [JSON Block: `storage`](#23-json-block-storage)
24. [JSON Block: `network`](#24-json-block-network)
25. [JSON Block: `services`](#25-json-block-services)
26. [JSON Block: `journals`](#26-json-block-journals)
27. [JSON Block: `summary`](#27-json-block-summary)
28. [Health State Interpretation](#28-health-state-interpretation)
29. [Profile and Mode Detection](#29-profile-and-mode-detection)
30. [Known Checks and Signals](#30-known-checks-and-signals)
31. [Target One-Liner Layout](#31-target-one-liner-layout)
32. [Systemd Integration](#32-systemd-integration)
33. [Validated TRX Runtime State](#33-validated-trx-runtime-state)
34. [Legacy Context: DMR and GGB](#34-legacy-context-dmr-and-ggb)
35. [Repository Documentation Structure](#35-repository-documentation-structure)
36. [Local Documentation for Future JR-Agents](#36-local-documentation-for-future-jr-agents)
37. [Cleanup of Legacy OPSCON Structure](#37-cleanup-of-legacy-opscon-structure)
38. [Recommended Interpretation for Agents](#38-recommended-interpretation-for-agents)
39. [Recommended Future Development](#39-recommended-future-development)
40. [Public Repository Safety Rules](#40-public-repository-safety-rules)
41. [Short Agent Summary](#41-short-agent-summary)

---

## 1. Purpose

`audit_jr-bot-boot-report.sh` is the boot-time read-only audit script for JR-Bot Raspberry Pi nodes.

Its primary purpose is to capture the system state shortly after a reboot, power recovery or timer-triggered boot cycle.

The report focuses on the early operational state that matters most when checking whether a bot returned correctly after boot:

- host and Raspberry Pi baseline,
- boot time and boot id,
- current and previous boot journal evidence,
- local storage state,
- network baseline,
- Wi-Fi state,
- gateway reachability,
- DNS resolution,
- SSH service state,
- bot runner timer and service state,
- Boot Report service context,
- local pending report handling,
- OPSCON upload success/failure behavior.

The script does not repair, restart, enable, disable, install packages, migrate files or alter the runtime state.

It creates a JSON report under the bot's pending report directory and then attempts to upload pending Boot Reports to OPSCON.

---

## 2. Role in the JR-Bot / OPSCON System

The Boot Report Audit complements the Structure and Network Health audits.

| Script | Primary Purpose |
|--|--|
| `audits/audit_jr-bot-boot-report.sh` | Captures the early post-boot state and uploads pending boot reports. |
| `audits/audit_jr-bot-network-health.sh` | Performs deep network diagnostics, routes, DNS, WLAN and service analysis. |
| `audits/audit_jr-bot-structure.sh` | Audits bot layout, files, Python, systemd and runtime structure. |
| `scripts/reboot.sh` | Performs controlled runtime reboot operations, if configured. |

Use the Boot Report Audit when the question is:

> Did this JR-Bot node come back correctly after boot?

It is especially useful for:

- power outage validation,
- post-reboot diagnostics,
- confirming that WLAN and default route came back,
- confirming SSH availability,
- confirming bot timer availability,
- catching DNS or gateway timing problems immediately after boot,
- retrying pending Boot Reports after network becomes available.

It is not a full replacement for Network Health. If the Boot Report shows network warnings, run Network Health next.

---

## 3. Current Runtime Status

The current runtime script version covered by this handbook is:

```text
0.2.2
```

The current target repository path is:

```text
audits/audit_jr-bot-boot-report.sh
```

The target runtime path on a One-Liner bot is:

```text
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh
```

Example for TRX:

```text
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh
```

The expected schema is:

```text
jrbot-boot-report-audit-v1
```

The audit type is:

```text
audit_jr-bot-boot-report
```

The current OPSCON ingest endpoint is:

```text
https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php
```

Runtime version `0.2.2` includes the critical upload-pending guard:

```text
--mode upload-pending only uploads existing pending reports.
--mode upload-pending never creates a new report.
```

Runtime version `0.2.2` also uses D7.6-compatible upload hardening:

- default OPSCON upload endpoint,
- environment token fallback,
- token-file fallback,
- upload token no longer passed as visible `curl -F "token=..."` command-line argument,
- upload token sent through `X-OPSCON-INGEST-TOKEN`,
- temporary curl config file created via `mktemp`,
- temporary curl config file restricted with `chmod 600`,
- temporary curl config file removed after use,
- upload timeout contract:
  - `connect-timeout = 10`,
  - `max-time = 60`.

Recommended repository verification:

```bash
grep 'SCRIPT_VERSION=' audits/audit_jr-bot-boot-report.sh
grep 'SCHEMA_VERSION=' audits/audit_jr-bot-boot-report.sh
grep 'jrbot_audit_boot_report_ingest.php' audits/audit_jr-bot-boot-report.sh
grep 'X-OPSCON-INGEST-TOKEN' audits/audit_jr-bot-boot-report.sh
grep 'curl --config' audits/audit_jr-bot-boot-report.sh
grep 'upload-pending' audits/audit_jr-bot-boot-report.sh
bash -n audits/audit_jr-bot-boot-report.sh
```

Expected result:

```text
SCRIPT_VERSION="0.2.2"
SCHEMA_VERSION="jrbot-boot-report-audit-v1"
```

---

## 4. Repository Path Migration

The current target repository layout uses `audits/` for audit scripts.

Correct target path:

```text
audits/audit_jr-bot-boot-report.sh
```

Legacy or older possible runtime paths:

```text
maintenance/jrbot_boot_report.sh
scripts/maintenance/jrbot_boot_report.sh
scripts/system/jrbot_boot_report.sh
jrbot_boot_report.sh
```

These older names and locations may still be detected by Structure Audit for migration context, but the target source of truth is:

```text
audits/audit_jr-bot-boot-report.sh
```

The Boot Report Audit should be committed together with this handbook:

```text
audits/audit_jr-bot-boot-report.sh
docs/audits/audit_jr-bot-boot-report.md
```

---

## 5. Security Principles

The script is read-only by design.

It does not repair, restart, enable, disable, install or uninstall anything.

### Security Rules

- No system changes are made.
- Secrets are redacted before output.
- Wi-Fi PSK values are not printed.
- Password-like values are redacted.
- Token-like values are redacted.
- Upload to OPSCON uses a runtime token.
- The original token is not stored in GitHub.
- The SHA256 token hash is not stored in GitHub.
- Uploaded JSON is not executed.
- The public ingest endpoint must not auto-create `_security`.
- The public ingest endpoint must not auto-create `ingest_token_sha256`.
- Token validation is instance-scoped.

### Redacted Patterns

The runtime redacts values matching keys such as:

```text
psk=
password=
passwd=
passphrase=
token=
secret=
private_key=
```

### Security Flags in JSON

The JSON report contains:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

The OPSCON ingest endpoint should reject reports where these security flags do not match the expected safe values.

---

## 6. Typical Usage

### Target Layout Boot Report

```bash
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh \
  --instance {instance} \
  --path /opt/bots/{instance} \
  --mode target
```

Example for TRX:

```bash
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode target
```

### Automatic Path and Instance Detection

When executed from its target path, the script can infer the bot path and instance:

```bash
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh --mode target
```

### Print Summary

```bash
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode target \
  --print-summary
```

### Create Local Report Without Upload

```bash
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode target \
  --no-upload \
  --print-summary
```

### Upload Existing Pending Reports Only

```bash
/opt/bots/trx/audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode upload-pending
```

This mode must never create a new report.

### Legacy Audit for DMR

```bash
./audits/audit_jr-bot-boot-report.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --mode legacy \
  --print-summary
```

### Legacy/Hybrid Audit for GGB

```bash
./audits/audit_jr-bot-boot-report.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --mode auto \
  --print-summary
```

### Manual Upload Override

The default endpoint and token lookup should be used for unattended runtime execution.

For manual debugging only:

```bash
./audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode target \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php \
  --token {ORIGINAL_UPLOAD_TOKEN}
```

The original token must never be committed to GitHub.

---

## 7. Parameters

| Parameter | Required | Description |
|--|--:|--|
| `--instance {name}` | No if detectable | Bot instance name, for example `dmr`, `ggb`, `trx`. |
| `--path {bot_path}` | No if detectable | Bot installation path. |
| `--legacy` | No | Compatibility shortcut. Current runtime maps this to auto-detection. |
| `--mode {mode}` | No | Mode marker: `auto`, `legacy`, `target`, `hybrid`, `migrate`, `test`, `boot`, `upload-pending`. |
| `--push-url {url}` | No | OPSCON boot report ingest endpoint override. |
| `--token {token}` | No | Original upload token for manual debugging. |
| `--no-upload` | No | Create local report only; do not upload. |
| `--keep-local` | No | Keep local report even after successful upload. |
| `--print-json` | No | Print full JSON to stdout. |
| `--print-summary` | No | Print compact summary. |
| `--wifi-iface {iface}` | No | Wi-Fi interface. Default: `wlan0`. |
| `--eth-iface {iface}` | No | Ethernet interface. Default: `eth0`. |
| `-h`, `--help` | No | Show help. |

---

## 8. Runtime Output and Pending Behavior

The script writes the JSON file locally first.

Default local pending output:

```text
{bot_path}/reports/pending/audit_jr-bot-boot-report-{instance}-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-boot-report-trx-20260627_131800.json
```

Default behavior:

1. Create a new Boot Report under `reports/pending/`.
2. Validate the generated JSON.
3. Print optional JSON or summary output.
4. Attempt to upload all pending Boot Reports for the instance.
5. Delete successfully uploaded reports locally unless `--keep-local` was used.
6. Leave failed reports pending for retry.

If upload fails, the local report remains available for retry or debugging.

---

## 9. Upload-Pending Mode Contract

`--mode upload-pending` is a strict retry mode.

It is intended for a timer or service such as:

```text
jrbot-report-upload@{instance}.service
jrbot-report-upload@{instance}.timer
```

The contract is:

```text
--mode upload-pending only uploads existing pending boot reports.
--mode upload-pending never creates a new report.
```

This is critical because a retry service running every 15 minutes must not create artificial boot events.

Expected behavior in upload-pending mode:

```text
No new report file is created.
Only files already present under reports/pending/ are uploaded.
Successfully uploaded pending reports are deleted.
Failed uploads remain pending.
Exit is non-disruptive for timer usage.
```

Recommended validation:

```bash
before="$(find /opt/bots/trx/reports/pending -maxdepth 1 -type f -name 'audit_jr-bot-boot-report-trx-*.json' | wc -l)"
sudo -u trx /opt/bots/trx/audits/audit_jr-bot-boot-report.sh \
  --instance trx \
  --path /opt/bots/trx \
  --mode upload-pending
after="$(find /opt/bots/trx/reports/pending -maxdepth 1 -type f -name 'audit_jr-bot-boot-report-trx-*.json' | wc -l)"
echo "before=$before after=$after"
```

If no pending files existed before, the result must remain:

```text
before=0 after=0
```

---

## 10. OPSCON Endpoint

Current endpoint:

```text
/OPSCON/api/jrbot_audit_boot_report_ingest.php
```

Full URL:

```text
https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php
```

Expected storage base:

```text
/OPSCON/data/audit_jr-bot-boot-report/
```

The endpoint must use the instance-scoped ingest-token contract described below.

---

## 11. OPSCON Storage Structure

Current required structure:

```text
/OPSCON/data/
`-- audit_jr-bot-boot-report/
    |-- dmr/
    |   |-- _security/
    |   |   |-- .htaccess
    |   |   `-- ingest_token_sha256
    |   |-- audit_jr-bot-boot-report-dmr.json
    |   `-- history/
    |       `-- audit_jr-bot-boot-report-dmr-YYYYMMDD_HHMMSS.json
    |
    |-- ggb/
    |   |-- _security/
    |   |   |-- .htaccess
    |   |   `-- ingest_token_sha256
    |   |-- audit_jr-bot-boot-report-ggb.json
    |   `-- history/
    |       `-- audit_jr-bot-boot-report-ggb-YYYYMMDD_HHMMSS.json
    |
    `-- trx/
        |-- _security/
        |   |-- .htaccess
        |   `-- ingest_token_sha256
        |-- audit_jr-bot-boot-report-trx.json
        `-- history/
            `-- audit_jr-bot-boot-report-trx-YYYYMMDD_HHMMSS.json
```

This is not the current valid model:

```text
/OPSCON/data/audit_jr-bot-boot-report/_security/ingest_token_sha256
```

The valid model is instance-specific:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
```

### What the Public Ingest Endpoint May Create

After successful authentication and validation, the public ingest endpoint may create runtime storage folders such as:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/history/
```

### What the Public Ingest Endpoint Must Not Create

The public ingest endpoint must not create:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
```

These security assets must be provisioned by a trusted server-side onboarding process, OPSCON admin UI, or manual server-side setup.

---

## 12. Instance-Scoped Token and Hash Security Model

The current endpoint must not store the original token in PHP.

Instead, it reads a SHA256 hash from the instance-specific security path:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
```

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-boot-report/trx/_security/ingest_token_sha256
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
   /OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
   ```
6. Read token from header or request.
7. Compare `sha256(token)` against stored hash using constant-time comparison.
8. Validate uploaded JSON.
9. Verify expected schema:
   ```text
   jrbot-boot-report-audit-v1
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

## 13. Token Lookup Order

Boot Report runtime version `0.2.2` supports automatic token lookup.

Lookup order:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_boot_report.token
{bot_path}/config/boot_report_upload.token
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

### Token Strategy

The current validated strategy uses a central per-bot fallback token file:

```text
/opt/bots/{instance}/config/report_upload.token
```

This keeps onboarding simple and consistent across all audit scripts.

Optional future hardening may use audit-specific token files:

```text
/opt/bots/{instance}/config/audit_boot_report.token
/opt/bots/{instance}/config/audit_network_health.token
/opt/bots/{instance}/config/audit_structure.token
```

Do not commit any token file to GitHub.

---

## 14. Default Upload Endpoint

Boot Report runtime version `0.2.2` has this default OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php
```

It can be overridden by CLI argument:

```bash
--push-url {url}
```

For normal runtime operation, the default endpoint should be used.

Manual `--push-url` should be reserved for debugging, staging, or endpoint migration.

---

## 15. D7.6 Runtime Upload Hardening

Runtime version `0.2.2` uses the hardened upload behavior.

### Previous Unsafe Runtime Pattern

```text
curl ... -F "token=${TOKEN}" ...
```

This could temporarily expose the cleartext token through local process inspection tools such as:

```text
ps aux
systemctl status
/proc/{pid}/cmdline
```

### Current Hardened Runtime Pattern

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

The ingest token is sent as an HTTP header:

```text
X-OPSCON-INGEST-TOKEN: {token}
```

The OPSCON ingest endpoint must accept this header.

### Upload Timeout Contract

Every Boot Report upload must define hard curl timeouts:

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

## 16. Expected Upload Payload

The runtime upload sends the following form fields:

```text
instance={instance}
mode={mode}
audit_file=@{json_file};type=application/json
```

The token is sent through:

```text
X-OPSCON-INGEST-TOKEN: {token}
```

The old multipart token field is deprecated for runtime usage:

```text
token={token}
```

The OPSCON endpoint may keep backward-compatible support for the multipart token field during migration, but the runtime script should use the header-based model.

---

## 17. Expected OPSCON Response

Successful OPSCON response example:

```json
{
  "success": true,
  "message": "JR-Bot boot report audit stored successfully.",
  "instance": "trx",
  "mode": "target",
  "audit_type": "audit_jr-bot-boot-report",
  "expected_schema": "jrbot-boot-report-audit-v1",
  "stored_file": "/data/audit_jr-bot-boot-report/trx/audit_jr-bot-boot-report-trx.json",
  "history_file": "/data/audit_jr-bot-boot-report/trx/history/audit_jr-bot-boot-report-trx-YYYYMMDD_HHMMSS.json",
  "token_scope": "instance",
  "token_source": "header",
  "received_at_utc": "YYYY-MM-DDTHH:MM:SSZ"
}
```

Important response fields:

| Field | Meaning |
|--|--|
| `success` | Upload result. |
| `instance` | Accepted instance name. |
| `audit_type` | Must be `audit_jr-bot-boot-report`. |
| `expected_schema` | Must be `jrbot-boot-report-audit-v1`. |
| `stored_file` | Latest report path. |
| `history_file` | Historical report path. |
| `token_scope` | Should be `instance`. |
| `token_source` | Should be `header` for the hardened runtime. |
| `received_at_utc` | Server-side receive timestamp. |

---

## 18. JSON Root Structure

The script generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-boot-report-audit-v1",
  "script_version": "0.2.2",
  "instance": "trx",
  "mode": "target",
  "mode_requested": "target",
  "profile_detected": "target",
  "install_profile": "target",
  "compatibility": {},
  "created_at_utc": "2026-06-27T13:18:00Z",
  "security": {},
  "bot_context": {},
  "commands_available": {},
  "host": {},
  "storage": {},
  "network": {},
  "services": {},
  "journals": {},
  "summary": {}
}
```

The `opscon_ingest` block is not generated by the runtime script.

It is added by the OPSCON ingest endpoint after successful upload.

Example server-side block:

```json
"opscon_ingest": {
  "received_at_utc": "2026-06-27T13:18:20Z",
  "endpoint": "jrbot_audit_boot_report_ingest.php",
  "endpoint_version": "1.1",
  "mode_posted": "target",
  "audit_type": "audit_jr-bot-boot-report",
  "accepted_schema": "jrbot-boot-report-audit-v1",
  "storage_model": "single-current-file-plus-history",
  "token_scope": "instance",
  "token_source": "header"
}
```

---

## 19. JSON Block: `security`

The `security` block documents that the report is safe to store and inspect.

Example:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

Interpretation:

| Field | Expected | Meaning |
|--|--:|--|
| `read_only` | `true` | The script made no changes. |
| `secrets_redacted` | `true` | Secret-looking values were redacted. |
| `secret_values_included` | `false` | Secret values are not included. |

The OPSCON ingest endpoint should reject reports that do not match this safety contract.

---

## 20. JSON Block: `bot_context`

The `bot_context` block connects the boot report to the bot installation.

Example:

```json
"bot_context": {
  "install_path": "/opt/bots/trx",
  "install_path_exists": true,
  "audits_path": "/opt/bots/trx/audits",
  "audits_path_exists": true,
  "scripts_path": "/opt/bots/trx/scripts",
  "scripts_path_exists": true,
  "src_job_runner_path": "/opt/bots/trx/src/job_runner.py",
  "src_job_runner_exists": true,
  "config_ini_path": "/opt/bots/trx/config/config.ini",
  "config_ini_exists": true,
  "legacy_maintenance_path": "/opt/bots/trx/maintenance",
  "legacy_maintenance_exists": false,
  "reports_path": "/opt/bots/trx/reports",
  "reports_pending_dir": "/opt/bots/trx/reports/pending",
  "reports_pending_dir_exists": true
}
```

This block helps agents understand whether the Boot Report was run against the intended bot installation path.

---

## 21. JSON Block: `commands_available`

The `commands_available` block lists whether required diagnostic commands exist.

Example:

```json
"commands_available": {
  "systemctl": true,
  "journalctl": true,
  "ip": true,
  "iw": true,
  "wpa_cli": true,
  "rfkill": true,
  "curl": true,
  "getent": true,
  "lsblk": true,
  "df": true
}
```

If a command is missing, the report may still be valid but less complete.

---

## 22. JSON Block: `host`

The `host` block describes the host system.

Typical fields:

- `hostname`,
- `platform`,
- `machine`,
- `kernel`,
- `raspberry_pi_model`,
- `memory_total_mb`,
- `boot_time`,
- `uptime_pretty`,
- `boot_id`,
- `os_release`.

The `boot_id` is especially useful for determining whether two reports came from the same boot session.

---

## 23. JSON Block: `storage`

The `storage` block describes filesystem and block-device state.

Typical fields:

- root filesystem via `df -hT /`,
- bot filesystem via `df -hT {bot_path}`,
- block devices via `lsblk -J`.

This helps diagnose SD-card issues, disk-full conditions and unexpected USB/storage states after boot.

---

## 24. JSON Block: `network`

The `network` block captures early boot networking state.

It includes:

- `hostname -I`,
- JSON output of `ip -j addr show`,
- parsed IPv4 addresses,
- route table,
- parsed default route,
- `ip route get 1.1.1.1`,
- gateway ping,
- DNS lookup for `google.com`,
- Wi-Fi state,
- Ethernet state,
- `/etc/resolv.conf`.

Important checks derived from this block:

```text
has_ipv4
has_default_route
gateway_ping_ok
dns_ok
```

A healthy target node should generally have:

```text
IPv4 address present
default route present
gateway ping successful
DNS lookup successful
```

A short DNS warning immediately after boot can indicate boot-time resolver timing rather than a permanent network failure.

---

## 25. JSON Block: `services`

The `services` block describes important service states.

Checked units include:

```text
systemd-networkd.service
NetworkManager.service
wpa_supplicant.service
wpa_supplicant@wlan0.service
dhcpcd.service
systemd-resolved.service
networking.service
ssh.service
bot-runner@{instance}.timer
bot-runner@{instance}.service
jrbot-boot-report@{instance}.service
{instance}-runner.timer
{instance}-runner.service
```

The most important boot checks are:

```text
ssh_active
bot_timer_active
```

Expected target state:

```text
ssh.service active
bot-runner@{instance}.timer active
bot-runner@{instance}.service may be inactive/dead if no job is currently running
legacy {instance}-runner units absent
```

---

## 26. JSON Block: `journals`

The `journals` block captures current and previous boot evidence.

Included evidence:

- `journalctl --list-boots`,
- current boot warnings,
- previous boot warnings,
- current boot logs for relevant units,
- previous boot logs for relevant units.

This is useful when diagnosing:

- power-loss recovery,
- WLAN reconnect timing,
- systemd ordering problems,
- failed boot report service runs,
- bot runner timer failures.

The script limits journal output to avoid excessive report size.

---

## 27. JSON Block: `summary`

The `summary` block contains the high-level boot health interpretation.

Example:

```json
"summary": {
  "health_state": "warning",
  "checks": {
    "has_ipv4": true,
    "has_default_route": true,
    "gateway_ping_ok": true,
    "dns_ok": false,
    "ssh_active": true,
    "bot_timer_active": true
  }
}
```

The Boot Report intentionally keeps this summary compact.

For deeper diagnostics, inspect the detailed `network`, `services` and `journals` blocks or run Network Health.

---

## 28. Health State Interpretation

Possible `health_state` values:

| Value | Meaning |
|--|--|
| `ok` | Required boot/network checks passed. |
| `warning` | At least one important check failed, but IPv4 and default route exist. |
| `critical` | IPv4 or default route is missing. |

Current rule:

```text
critical:
  has_ipv4=false OR has_default_route=false

warning:
  gateway_ping_ok=false OR dns_ok=false OR bot_timer_active=false

ok:
  all key checks are true
```

Important:

```text
warning != boot failure
```

Example:

```text
dns_ok=false shortly after boot may indicate resolver timing, especially if later Network Health is ok.
```

---

## 29. Profile and Mode Detection

The runtime supports multiple profile states:

| Profile | Meaning |
|--|--|
| `target` | New One-Liner layout, for example `/opt/bots/trx`. |
| `legacy` | Older DMR/GGB style layout, for example `/home/ggb/bots/ggb`. |
| `hybrid` | Transitional layout with both legacy and target markers. |
| `unknown` | Path exists but no clear profile markers are detected. |

Supported mode markers:

```text
auto
legacy
target
hybrid
migrate
test
boot
upload-pending
```

`mode_requested` stores what was requested.

`profile_detected` stores what the script detected.

`install_profile` stores the interpreted runtime profile.

---

## 30. Known Checks and Signals

| Check | Meaning |
|--|--|
| `has_ipv4` | At least one IPv4 address was detected. |
| `has_default_route` | A default route exists. |
| `gateway_ping_ok` | Gateway ping returned success. |
| `dns_ok` | `getent hosts google.com` returned success. |
| `ssh_active` | `ssh.service` is active. |
| `bot_timer_active` | Template or legacy bot runner timer is active. |

Recommended interpretation:

| Signal | Meaning |
|--|--|
| `has_ipv4=false` | Critical boot/network problem. |
| `has_default_route=false` | Critical routing problem. |
| `gateway_ping_ok=false` | Router or WLAN routing may not be ready. |
| `dns_ok=false` | DNS may not be ready or configured. |
| `ssh_active=false` | Remote administration may be unavailable. |
| `bot_timer_active=false` | Bot job runner may not start automatically. |

---

## 31. Target One-Liner Layout

The current One-Liner target layout for a JR-Bot instance is:

```text
/opt/bots/{instance}/
|-- audits/
|   |-- audit_jr-bot-boot-report.sh
|   |-- audit_jr-bot-network-health.sh
|   `-- audit_jr-bot-structure.sh
|-- config/
|   |-- config.ini
|   `-- report_upload.token
|-- docs/
|   |-- audits/
|   `-- scripts/
|-- logs/
|-- reports/
|   `-- pending/
|-- scripts/
|-- src/
|   `-- job_runner.py
|-- state/
|-- tmp/
|-- venv/
|-- install_info.txt
`-- requirements.txt
```

Target Boot Report runtime path:

```text
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh
```

Target pending report path:

```text
/opt/bots/{instance}/reports/pending/
```

---

## 32. Systemd Integration

The Boot Report is intended to run after boot through a dedicated systemd service/timer or as part of an OPSCON audit workflow.

Recommended service names:

```text
jrbot-boot-report@{instance}.service
jrbot-report-upload@{instance}.service
jrbot-report-upload@{instance}.timer
```

Runtime bot job runner units:

```text
bot-runner@{instance}.service
bot-runner@{instance}.timer
```

The retry/upload service should use:

```text
--mode upload-pending
```

and must never create a new Boot Report.

Recommended timer behavior:

```text
Boot Report service:
  run once shortly after boot

Upload retry service:
  retry existing pending reports periodically
  do not create new reports
```

---

## 33. Validated TRX Runtime State

Boot Report runtime validation has been observed on TRX.

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
Runtime script: /opt/bots/trx/audits/audit_jr-bot-boot-report.sh
Runtime version: 0.2.2
```

Validated behavior:

```text
bash syntax check successful
Boot Report generated after boot
report written under /opt/bots/trx/reports/pending/
OPSCON upload successful
OPSCON accepted instance-scoped token
OPSCON stored latest report
OPSCON stored history report
local uploaded report deleted after successful upload
upload-pending mode guarded against creating new boot reports
```

Observed TRX boot summary:

```text
health_state: warning
has_ipv4: true
has_default_route: true
gateway_ping_ok: true
dns_ok: false
ssh_active: true
bot_timer_active: true
```

Interpretation:

```text
The Boot Report script worked.
The Pi was reachable and had IPv4/default route/gateway/SSH/timer.
The warning was caused by DNS not being ready during the boot-time check window.
```

Validated OPSCON ingest traits:

```text
endpoint: jrbot_audit_boot_report_ingest.php
endpoint_version: 1.1
token_scope: instance
token_source: header
storage_model: single-current-file-plus-history
```

---

## 34. Legacy Context: DMR and GGB

DMR and GGB may still use legacy or hybrid paths during migration.

Known legacy paths:

```text
/home/dmr/bots/DMR
/home/ggb/bots/ggb
```

Expected One-Liner target path pattern:

```text
/opt/bots/{instance}
```

### DMR Context

Known target assignment:

```text
DMR -> 192.168.178.201
```

Possible legacy command:

```bash
./audits/audit_jr-bot-boot-report.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --mode legacy
```

### GGB Context

Known target assignment:

```text
GGB -> 192.168.178.202
```

Possible legacy/hybrid command:

```bash
./audits/audit_jr-bot-boot-report.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --mode auto
```

Legacy does not automatically mean broken.

It means that the node predates the current One-Liner target structure or is in migration.

---

## 35. Repository Documentation Structure

Recommended target GitHub repository structure:

```text
jr-bot/
|-- install_jr-bot.sh
|-- audits/
|   |-- audit_jr-bot-boot-report.sh
|   |-- audit_jr-bot-network-health.sh
|   `-- audit_jr-bot-structure.sh
|-- docs/
|   |-- architecture.md
|   `-- audits/
|       |-- audit-ingest-contract.md
|       |-- audit_jr-bot-boot-report.md
|       |-- audit_jr-bot-network-health.md
|       `-- audit_jr-bot-structure.md
|-- runtime/
|   |-- src/
|   |-- scripts/
|   |-- requirements.txt
|   `-- templates/
`-- systemd/
    `-- templates/
```

This handbook belongs in the repository at:

```text
docs/audits/audit_jr-bot-boot-report.md
```

The runtime script belongs in:

```text
audits/audit_jr-bot-boot-report.sh
```

---

## 36. Local Documentation for Future JR-Agents

If a future JR-Agent runs locally on a bot, it should be able to read this handbook locally.

Recommended local structure:

```text
/opt/bots/{instance}/docs/audits/
|-- audit-ingest-contract.md
|-- audit_jr-bot-boot-report.md
|-- audit_jr-bot-network-health.md
`-- audit_jr-bot-structure.md
```

For legacy bots:

```text
/home/dmr/bots/DMR/docs/audits/audit_jr-bot-boot-report.md
/home/ggb/bots/ggb/docs/audits/audit_jr-bot-boot-report.md
```

Recommended local audits:

```text
/opt/bots/{instance}/audits/
|-- audit_jr-bot-boot-report.sh
|-- audit_jr-bot-network-health.sh
`-- audit_jr-bot-structure.sh
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

## 37. Cleanup of Legacy OPSCON Structure

After DMR, GGB and TRX jobs have been moved to the current endpoint, old boot-report endpoints and old data folders can be removed or archived if they exist.

### Current

```text
/OPSCON/api/jrbot_audit_boot_report_ingest.php
/OPSCON/data/audit_jr-bot-boot-report/
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
WHERE config_json LIKE '%jrbot_boot_report%'
   OR config_json LIKE '%jrbot_audit_boot_report_ingest.php%'
   OR config_json LIKE '%audit_jr-bot-boot-report%';
```

### Safe Archive Option

```text
/OPSCON/data/_archive/audit_jr-bot-boot-report_legacy_YYYYMMDD/
```

Permanent deletion should happen only after a successful control period.

---

## 38. Recommended Interpretation for Agents

Agents must not interpret every warning as a boot failure.

Important rule:

```text
warning != failure
```

Recommended inspection order:

1. `schema`
2. `script_version`
3. `instance`
4. `mode_requested`
5. `profile_detected`
6. `install_profile`
7. `security`
8. `created_at_utc`
9. `host.boot_time`
10. `host.boot_id`
11. `summary.health_state`
12. `summary.checks`
13. `network.default_route`
14. `network.ipv4_addresses`
15. `network.gateway_ping`
16. `network.dns_google`
17. `services.units.ssh.service`
18. `services.unit_candidates`
19. `services.units.bot-runner@{instance}.timer`
20. `journals.current_boot_warnings`
21. `journals.previous_boot_warnings`
22. `opscon_ingest`

If `summary.health_state` is `warning`, inspect which check failed.

If only `dns_ok=false` is false shortly after boot, compare with Network Health after the node has been online for a few minutes.

---

## 39. Recommended Future Development

### Version 0.2.3

Possible improvements:

- Add explicit `primary_ipv4` field.
- Add explicit `default_gateway` field.
- Add DNS retry window for early boot timing.
- Add optional project-host DNS test.
- Add optional project HTTPS test.
- Add parsed Wi-Fi signal level.
- Add explicit service status for `jrbot-boot-report@{instance}.service`.
- Add local latest-copy option under `reports/`.

### Version 0.3.0

Possible improvements:

- Add signed report metadata.
- Add boot-session deduplication by `boot_id`.
- Add optional `--agent-summary` compact output.
- Add machine-readable recommendation categories.
- Add comparison mode against previous boot report.
- Add explicit public-vs-OPSCON runtime profile.

### Future Token Hardening

Possible future token models:

| Model | Notes |
|--|--|
| One shared per-bot upload token | Current validated model. Simple and sufficient for TRX. |
| One token per audit script | Stronger separation. More setup and onboarding overhead. |
| One-time upload token / OTP | Requires server-side state or challenge-response. Static hash files alone are not enough. |

A pure OTP model cannot work with only a static server-side `ingest_token_sha256`, because the server must know or derive the next expected one-time value.

Possible OTP-compatible designs would require one of:

- server-side rotating state,
- TOTP/HOTP shared secret,
- short-lived challenge-response,
- signed payloads with asymmetric keys,
- OPSCON-issued upload session token.

This is optional future hardening and not required for the current local-network JR-Bot threat model.

---

## 40. Public Repository Safety Rules

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
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
```

Correct bot-side token fallback location:

```text
/opt/bots/{instance}/config/report_upload.token
```

The public repository may contain:

```text
audits/audit_jr-bot-boot-report.sh
docs/audits/audit_jr-bot-boot-report.md
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
```

Never use real tokens or real token hashes in examples.

---

## 41. Short Agent Summary

`audit_jr-bot-boot-report.sh` is the boot-time diagnostic tool for JR-Bot nodes.

It is read-only and safe.

It checks:

```text
boot time
boot id
host baseline
storage baseline
IPv4
default route
gateway ping
DNS
Wi-Fi state
SSH state
bot runner timer state
current boot journals
previous boot journals
pending report upload state
```

Current runtime version:

```text
0.2.2
```

Current target runtime path:

```text
audits/audit_jr-bot-boot-report.sh
```

Legacy runtime paths may include:

```text
maintenance/jrbot_boot_report.sh
scripts/maintenance/jrbot_boot_report.sh
scripts/system/jrbot_boot_report.sh
jrbot_boot_report.sh
```

Current schema:

```text
jrbot-boot-report-audit-v1
```

Current OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php
```

Current OPSCON storage path:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/
```

Current instance-scoped token-hash path:

```text
/OPSCON/data/audit_jr-bot-boot-report/{instance}/_security/ingest_token_sha256
```

Healthy current assignments:

```text
DMR -> 192.168.178.201
GGB -> 192.168.178.202
TRX -> 192.168.178.203
```

Normal upload uses the central per-bot fallback token if no audit-specific token exists:

```text
/opt/bots/{instance}/config/report_upload.token
```

The token is sent via:

```text
X-OPSCON-INGEST-TOKEN
```

and no longer as a visible `curl -F "token=..."` command-line argument.

Critical runtime contract:

```text
--mode upload-pending only uploads existing pending reports.
--mode upload-pending never creates a new report.
```

This handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-boot-report.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/{instance}/docs/audits/audit_jr-bot-boot-report.md
```
