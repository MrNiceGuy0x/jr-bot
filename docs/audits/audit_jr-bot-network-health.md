# JR-Bot Network Health Audit Handbook

**Status:** Active  
**Handbook Version:** 1.2  
**Runtime Script Version Reference:** 0.2.1  
**Project:** JR-Bot / OPSCON  
**Recommended Repository Path:** `docs/audits/audit_jr-bot-network-health.md`  
**Related Runtime Script:** `audits/audit_jr-bot-network-health.sh`  
**Legacy Runtime Script Path:** `tools/audit_jr-bot-network-health.sh`  
**Expected JSON Schema:** `jrbot-network-health-audit-v1`  
**Audit Type:** `audit_jr-bot-network-health`  
**Last Updated:** 2026-06-27  

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON System](#2-role-in-the-jr-bot--opscon-system)
3. [Current Runtime Status](#3-current-runtime-status)
4. [Repository Path Migration: `tools/` to `audits/`](#4-repository-path-migration-tools-to-audits)
5. [Security Principles](#5-security-principles)
6. [Typical Usage](#6-typical-usage)
7. [Parameters](#7-parameters)
8. [Runtime Output Location](#8-runtime-output-location)
9. [OPSCON Endpoint](#9-opscon-endpoint)
10. [OPSCON Storage Structure](#10-opscon-storage-structure)
11. [Instance-Scoped Token and Hash Security Model](#11-instance-scoped-token-and-hash-security-model)
12. [Token Lookup Order](#12-token-lookup-order)
13. [Default Upload Endpoint](#13-default-upload-endpoint)
14. [D7.6 Runtime Upload Hardening](#14-d76-runtime-upload-hardening)
15. [Expected Upload Payload](#15-expected-upload-payload)
16. [Expected OPSCON Response](#16-expected-opscon-response)
17. [JSON Root Structure](#17-json-root-structure)
18. [JSON Block: `security`](#18-json-block-security)
19. [JSON Block: `host`](#19-json-block-host)
20. [JSON Block: `bot_context`](#20-json-block-bot_context)
21. [JSON Block: `commands_available`](#21-json-block-commands_available)
22. [JSON Block: `network`](#22-json-block-network)
23. [JSON Block: `wifi`](#23-json-block-wifi)
24. [JSON Block: `network_manager_cli`](#24-json-block-network_manager_cli)
25. [JSON Block: `network_services`](#25-json-block-network_services)
26. [JSON Block: `network_config_files`](#26-json-block-network_config_files)
27. [JSON Block: `systemd_integrity`](#27-json-block-systemd_integrity)
28. [JSON Block: `package_versions`](#28-json-block-package_versions)
29. [JSON Block: `connectivity`](#29-json-block-connectivity)
30. [JSON Block: `raw_reference_commands`](#30-json-block-raw_reference_commands)
31. [JSON Block: `analysis`](#31-json-block-analysis)
32. [Findings and Recommendations](#32-findings-and-recommendations)
33. [Known Finding Codes](#33-known-finding-codes)
34. [Target Network Baseline](#34-target-network-baseline)
35. [Validated TRX Runtime State](#35-validated-trx-runtime-state)
36. [Legacy Context: DMR and GGB](#36-legacy-context-dmr-and-ggb)
37. [Repository Documentation Structure](#37-repository-documentation-structure)
38. [Local Documentation for Future JR-Agents](#38-local-documentation-for-future-jr-agents)
39. [Cleanup of Legacy OPSCON Structure](#39-cleanup-of-legacy-opscon-structure)
40. [Recommended Interpretation for Agents](#40-recommended-interpretation-for-agents)
41. [Recommended Future Development](#41-recommended-future-development)
42. [Public Repository Safety Rules](#42-public-repository-safety-rules)
43. [Short Agent Summary](#43-short-agent-summary)

---

## 1. Purpose

`audit_jr-bot-network-health.sh` is the deep read-only network and node health audit script for JR-Bot Raspberry Pi nodes.

The script collects a detailed snapshot of the current network state, Wi-Fi state, systemd network services, package versions, DNS configuration, route configuration, connectivity and relevant systemd integrity information.

The purpose is not to repair the node.

The purpose is to provide a reproducible, safe and machine-readable diagnostic report that can be compared across JR-Bot nodes such as DMR, GGB and TRX.

The script is especially useful when diagnosing:

- Raspberry Pi nodes that do not come back online after a power outage.
- WLAN reconnection problems.
- DHCP lease or static Fritzbox assignment issues.
- Missing default routes.
- Broken DNS resolution.
- Failed `systemd-networkd`.
- Broken `libsystemd-shared-252.so` resolution.
- Differences between DMR, GGB and TRX network stacks.
- Whether a previous repair actually remained stable after reboot.
- Whether a One-Liner installed node has the expected network baseline.
- Whether OPSCON audit upload works under the current instance-scoped token model.

---

## 2. Role in the JR-Bot / OPSCON System

The Network Health Audit is one of several diagnostic tools in the JR-Bot ecosystem.

It answers this question:

> Is the node currently healthy from a network and network-service perspective?

It complements the structure audit and the boot report audit.

### Separation from Other Scripts

| Script | Purpose |
|---|---|
| `audits/audit_jr-bot-structure.sh` | Checks file layout, bot profile, Python venv, systemd runner units and runtime structure. |
| `audits/audit_jr-bot-network-health.sh` | Checks network interfaces, routes, DNS, services, WLAN, systemd-networkd integrity and connectivity. |
| `audits/audit_jr-bot-boot-report.sh` | Collects boot-state shortly after reboot and reports it to OPSCON. |
| `maintenance/reboot.sh` or equivalent runtime maintenance script | Performs a controlled reboot through a maintenance job, if present. |

The Network Health Audit should be used when:

- The Pi is online but its past boot or reconnect behavior is suspicious.
- A node has changed IP address.
- A Fritzbox static assignment was changed.
- WLAN signal quality needs to be compared.
- `systemd-networkd` or `wpa_supplicant` behavior must be inspected.
- A previous offline case needs evidence-based analysis.
- A bot should be validated before or after One-Liner migration.
- A bot should be validated before enabling automated audit upload.

---

## 3. Current Runtime Status

The current runtime script version covered by this handbook is:

```text
0.2.1
```

The intended runtime script path in the repository is:

```text
audits/audit_jr-bot-network-health.sh
```

The current public `main` branch may still contain a legacy copy under:

```text
tools/audit_jr-bot-network-health.sh
```

That `tools/` file is legacy and must be migrated or replaced by the current `audits/` runtime version.

The runtime script path on a target One-Liner bot is:

```text
/opt/bots/{instance}/audits/audit_jr-bot-network-health.sh
```

Example for TRX:

```text
/opt/bots/trx/audits/audit_jr-bot-network-health.sh
```

The expected schema is:

```text
jrbot-network-health-audit-v1
```

The audit type is:

```text
audit_jr-bot-network-health
```

The current OPSCON ingest endpoint is:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

Runtime version `0.2.1` includes D7.6 upload hardening:

- Default OPSCON upload endpoint.
- Environment token fallback.
- Token-file fallback.
- Upload token no longer passed as visible `curl -F "token=..."` command-line argument.
- Upload token sent through `X-OPSCON-INGEST-TOKEN`.
- Temporary curl config file created via `mktemp`.
- Temporary curl config file restricted with `chmod 600`.
- Temporary curl config file removed after use.
- Upload timeout contract:
  - `connect-timeout = 10`
  - `max-time = 60`

Recommended repository verification after migration:

```bash
grep 'SCRIPT_VERSION=' audits/audit_jr-bot-network-health.sh
grep 'jrbot_audit_network_health_ingest.php' audits/audit_jr-bot-network-health.sh
grep 'X-OPSCON-INGEST-TOKEN' audits/audit_jr-bot-network-health.sh
grep 'curl --config' audits/audit_jr-bot-network-health.sh
bash -n audits/audit_jr-bot-network-health.sh
```

Expected result:

```text
SCRIPT_VERSION="0.2.1"
```

---

## 4. Repository Path Migration: `tools/` to `audits/`

The current target repository layout uses `audits/` for audit scripts.

Correct target path:

```text
audits/audit_jr-bot-network-health.sh
```

Legacy path still visible on the public `main` branch:

```text
tools/audit_jr-bot-network-health.sh
```

The `tools/` file is an older legacy copy and should not be treated as the final runtime source.

Required cleanup options:

1. Move the current hardened script into `audits/audit_jr-bot-network-health.sh`.
2. Remove the legacy `tools/audit_jr-bot-network-health.sh` file.
3. Update all docs, installer references and runtime install logic to use `audits/`.

Recommended Git commands for the repository cleanup:

```bash
git mkdir -p audits 2>/dev/null || true
git mv tools/audit_jr-bot-network-health.sh audits/audit_jr-bot-network-health.sh
```

If `audits/audit_jr-bot-network-health.sh` already exists locally with the correct D7.6 version, remove the legacy file instead:

```bash
git rm tools/audit_jr-bot-network-health.sh
git add audits/audit_jr-bot-network-health.sh
```

After cleanup, `main` should no longer expose the Network Health audit as the primary runtime script under `tools/`.

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
- Network config files are sanitized.
- Upload to OPSCON uses a runtime token.
- The original token is not stored in GitHub.
- The SHA256 token hash is not stored in GitHub.
- Uploaded JSON is not executed.
- The public ingest endpoint must not auto-create `_security`.
- The public ingest endpoint must not auto-create `ingest_token_sha256`.
- Token validation is instance-scoped.

### Redacted Patterns

The script redacts values matching keys such as:

```text
psk=
password=
passwd=
passphrase=
token=
secret=
private_key=
key=
```

### Security Flags in JSON

The JSON report contains:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false,
  "network_passwords_redacted": true
}
```

The OPSCON ingest endpoint should reject reports where these security flags do not match the expected safe values.

---

## 6. Typical Usage

### Target Layout Audit Without Explicit Upload Parameters

Runtime version `0.2.1` supports unattended upload without explicitly passing `--push-url` or `--token`, as long as a valid local token file exists.

```bash
/opt/bots/{instance}/audits/audit_jr-bot-network-health.sh \
  --instance {instance} \
  --path /opt/bots/{instance}
```

Example for TRX:

```bash
/opt/bots/trx/audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx
```

### Local Audit With Summary

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --print-summary
```

### Local Audit With Project Test URL

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --gateway 192.168.178.1 \
  --test-url https://trax.blenk.co.at \
  --print-summary
```

### Legacy Audit for DMR

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --gateway 192.168.178.1 \
  --test-url https://domera.blenk.co.at \
  --print-summary
```

### Legacy/Hybrid Audit for GGB

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --gateway 192.168.178.1 \
  --test-url https://spl.blenk.co.at \
  --print-summary
```

### Manual Upload Override

The default endpoint and token lookup should be used for unattended runtime execution.

For manual debugging only, the endpoint and token can still be overridden:

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
  --token {ORIGINAL_UPLOAD_TOKEN}
```

The original token must never be committed to GitHub.

### Local Debug Output File

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --output /opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-local-debug.json \
  --print-summary
```

When `--output` is used, the output file is kept after upload.

---

## 7. Parameters

| Parameter | Required | Description |
|---|---:|---|
| `--instance {name}` | Yes | Bot instance name, for example `dmr`, `ggb`, `trx`. |
| `--path {bot_path}` | Yes | Bot installation path. |
| `--legacy` | No | Marks the audit as legacy-context. Used for older DMR/GGB structures. |
| `--push-url {url}` | No | OPSCON network health ingest endpoint override. |
| `--token {token}` | No | Original upload token for manual debugging. |
| `--output {file}` | No | Local JSON output path. File will be kept. |
| `--keep-local` | No | Keep generated local JSON after successful upload. |
| `--print-json` | No | Print full JSON to stdout. |
| `--print-summary` | No | Print compact summary of findings and recommendations. |
| `--test-url {url}` | No | Optional HTTPS URL to test. |
| `--gateway {ip}` | No | Optional gateway override. |
| `--wifi-iface {iface}` | No | Wi-Fi interface. Default: `wlan0`. |
| `--eth-iface {iface}` | No | Ethernet interface. Default: `eth0`. |
| `-h`, `--help` | No | Show help. |

---

## 8. Runtime Output Location

The script writes the JSON file locally first.

Default local pending output:

```text
{bot_path}/reports/pending/audit_jr-bot-network-health-{instance}-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-20260627_091753.json
```

After a successful upload, the local temporary report is deleted unless one of the following was used:

```text
--keep-local
--output {file}
```

If upload fails, the local report remains available for retry or debugging.

---

## 9. OPSCON Endpoint

Current endpoint:

```text
/OPSCON/api/jrbot_audit_network_health_ingest.php
```

Full URL:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

Legacy endpoint:

```text
/OPSCON/api/jrbot_network_health_ingest.php
```

The legacy endpoint stored reports under:

```text
/OPSCON/data/jrbot_network_health/
```

The current endpoint stores reports under:

```text
/OPSCON/data/audit_jr-bot-network-health/
```

The current endpoint must use the instance-scoped ingest-token contract described below.

---

## 10. OPSCON Storage Structure

Current required structure:

```text
/OPSCON/data/
└── audit_jr-bot-network-health/
    ├── dmr/
    │   ├── _security/
    │   │   ├── .htaccess
    │   │   └── ingest_token_sha256
    │   ├── audit_jr-bot-network-health-dmr.json
    │   └── history/
    │       └── audit_jr-bot-network-health-dmr-YYYYMMDD_HHMMSS.json
    │
    ├── ggb/
    │   ├── _security/
    │   │   ├── .htaccess
    │   │   └── ingest_token_sha256
    │   ├── audit_jr-bot-network-health-ggb.json
    │   └── history/
    │       └── audit_jr-bot-network-health-ggb-YYYYMMDD_HHMMSS.json
    │
    └── trx/
        ├── _security/
        │   ├── .htaccess
        │   └── ingest_token_sha256
        ├── audit_jr-bot-network-health-trx.json
        └── history/
            └── audit_jr-bot-network-health-trx-YYYYMMDD_HHMMSS.json
```

This is not the current valid model:

```text
/OPSCON/data/audit_jr-bot-network-health/_security/ingest_token_sha256
```

The valid model is instance-specific:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
```

### What the Public Ingest Endpoint May Create

After successful authentication and validation, the public ingest endpoint may create runtime storage folders such as:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/history/
```

### What the Public Ingest Endpoint Must Not Create

The public ingest endpoint must not create:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
```

These security assets must be provisioned by a trusted server-side onboarding process, OPSCON admin UI, or manual server-side setup.

---

## 11. Instance-Scoped Token and Hash Security Model

The current endpoint does not store the original token in PHP.

Instead, it reads a SHA256 hash from the instance-specific security path:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
```

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-network-health/trx/_security/ingest_token_sha256
```

Example hash-file content:

```text
{sha256(ORIGINAL_UPLOAD_TOKEN)}
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
   /OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
   ```
6. Read token from header or request.
7. Compare `sha256(token)` against stored hash using constant-time comparison.
8. Validate uploaded JSON.
9. Verify expected schema:
   ```text
   jrbot-network-health-audit-v1
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

## 12. Token Lookup Order

Network Health runtime version `0.2.1` supports automatic token lookup.

Lookup order:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_network_health.token
{bot_path}/config/network_health_upload.token
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

## 13. Default Upload Endpoint

Network Health runtime version `0.2.1` has a default OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

It can be overridden by environment variable:

```text
NETWORK_HEALTH_AUDIT_PUSH_URL
```

or CLI argument:

```bash
--push-url {url}
```

For normal runtime operation, the default endpoint should be used.

Manual `--push-url` should be reserved for debugging, staging, or endpoint migration.

---

## 14. D7.6 Runtime Upload Hardening

Runtime version `0.2.1` hardened the upload behavior.

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

Every Network Health upload must define hard curl timeouts:

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

## 15. Expected Upload Payload

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

## 16. Expected OPSCON Response

Successful OPSCON response example:

```json
{
  "success": true,
  "message": "JR-Bot network health audit stored successfully.",
  "instance": "trx",
  "mode": "target",
  "audit_type": "audit_jr-bot-network-health",
  "expected_schema": "jrbot-network-health-audit-v1",
  "stored_file": "/data/audit_jr-bot-network-health/trx/audit_jr-bot-network-health-trx.json",
  "history_file": "/data/audit_jr-bot-network-health/trx/history/audit_jr-bot-network-health-trx-YYYYMMDD_HHMMSS.json",
  "token_scope": "instance",
  "received_at_utc": "YYYY-MM-DDTHH:MM:SSZ"
}
```

Important response fields:

| Field | Meaning |
|---|---|
| `success` | Upload result. |
| `instance` | Accepted instance name. |
| `audit_type` | Must be `audit_jr-bot-network-health`. |
| `expected_schema` | Must be `jrbot-network-health-audit-v1`. |
| `stored_file` | Latest report path. |
| `history_file` | Historical report path. |
| `token_scope` | Should be `instance`. |
| `received_at_utc` | Server-side receive timestamp. |

---

## 17. JSON Root Structure

The script generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-network-health-audit-v1",
  "script_version": "0.2.1",
  "instance": "trx",
  "mode": "target",
  "created_at_utc": "2026-06-27T09:17:53Z",
  "security": {},
  "host": {},
  "bot_context": {},
  "commands_available": {},
  "network": {},
  "wifi": {},
  "network_manager_cli": {},
  "network_services": {},
  "network_config_files": {},
  "systemd_integrity": {},
  "package_versions": {},
  "connectivity": {},
  "raw_reference_commands": {},
  "analysis": {}
}
```

The `opscon_ingest` block is not generated by the runtime script.

It is added by the OPSCON ingest endpoint after successful upload.

---

## 18. JSON Block: `security`

The `security` block documents that the report is safe to store and inspect.

Example:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false,
  "network_passwords_redacted": true
}
```

Interpretation:

| Field | Expected | Meaning |
|---|---:|---|
| `read_only` | `true` | The script made no changes. |
| `secrets_redacted` | `true` | Secret-looking values were redacted. |
| `secret_values_included` | `false` | Secret values are not included. |
| `network_passwords_redacted` | `true` | Wi-Fi passwords are not printed. |

The OPSCON ingest endpoint should reject reports that do not match this safety contract.

---

## 19. JSON Block: `host`

The `host` block describes the host system.

Typical fields:

- `hostname`
- `platform`
- `machine`
- `kernel`
- `raspberry_pi_model`
- `memory_total_mb`
- `boot_time`
- `os_release`
- `cpuinfo_excerpt`

Example:

```json
"host": {
  "hostname": "raspberrypi",
  "platform": "Linux-6.12.47+rpt-rpi-v7-armv7l-with-glibc2.36",
  "machine": "armv7l",
  "raspberry_pi_model": "Raspberry Pi 3 Model B Rev 1.2",
  "memory_total_mb": 921,
  "boot_time": "2026-05-27 17:56:27"
}
```

The `boot_time` is important when checking whether an audit was produced before or after a reboot.

---

## 20. JSON Block: `bot_context`

The `bot_context` block connects the network report to the bot installation.

Example:

```json
"bot_context": {
  "install_path": "/opt/bots/trx",
  "install_path_exists": true,
  "mode": "target"
}
```

Important fields:

| Field | Meaning |
|---|---|
| `install_path` | Expected bot installation directory. |
| `install_path_exists` | Whether the directory exists. |
| `mode` | Requested mode, for example `legacy` or `target`. |

This block helps agents understand whether the audit was run against the intended bot installation path.

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
  "iwconfig": true,
  "wpa_cli": true,
  "networkctl": true,
  "nmcli": true,
  "rfkill": true,
  "curl": true,
  "getent": true,
  "ldd": true,
  "dpkg_query": true
}
```

If a command is missing, the report may still be valid but less complete.

Important commands:

| Command | Purpose |
|---|---|
| `ip` | Interfaces, addresses and routes. |
| `systemctl` | Service state. |
| `journalctl` | Recent service logs. |
| `iw` | Wi-Fi link details. |
| `iwconfig` | Wi-Fi quality and signal. |
| `wpa_cli` | WPA supplicant status. |
| `networkctl` | systemd-networkd link status. |
| `nmcli` | NetworkManager status, if present. |
| `rfkill` | Radio block state. |
| `curl` | HTTPS test and upload. |
| `getent` | DNS resolution. |
| `ldd` | Shared-library resolution. |
| `dpkg-query` | Package version checks. |

---

## 22. JSON Block: `network`

The `network` block is one of the most important blocks.

It includes:

- Wi-Fi interface name.
- Ethernet interface name.
- `hostname -I`.
- JSON output of `ip -j addr show`.
- Plain output of `ip addr show`.
- Parsed IPv4 addresses.
- `ip route`.
- `ip route get 1.1.1.1`.
- Parsed default route.

Example:

```json
"network": {
  "wifi_interface": "wlan0",
  "eth_interface": "eth0",
  "hostname_I": {},
  "ip_addr_json": {},
  "ip_addr_plain": {},
  "ipv4_addresses": [],
  "ip_route": {},
  "ip_route_get_1_1_1_1": {},
  "default_route": {}
}
```

### Important Fields

| Field | Meaning |
|---|---|
| `hostname_I.stdout` | Quick IP overview. |
| `ipv4_addresses` | Parsed IPv4 addresses. |
| `default_route.present` | Whether default route exists. |
| `default_route.gateway` | Gateway IP. |
| `default_route.interface` | Interface used by default route. |
| `default_route.source` | Source IP used for outbound traffic. |

### Healthy Example

```json
"default_route": {
  "present": true,
  "raw": "default via 192.168.178.1 dev wlan0 proto dhcp src 192.168.178.203 metric 1024",
  "gateway": "192.168.178.1",
  "interface": "wlan0",
  "source": "192.168.178.203"
}
```

---

## 23. JSON Block: `wifi`

The `wifi` block contains Wi-Fi-specific diagnostics.

It collects:

- `ip link show wlan0`
- `iw dev wlan0 link`
- `iw dev`
- `iwconfig wlan0`
- `rfkill list`
- `wpa_cli -i wlan0 status`
- `networkctl status wlan0`

Example:

```json
"wifi": {
  "interface": "wlan0",
  "ip_link": {},
  "iw_link": {},
  "iw_dev": {},
  "iwconfig": {},
  "rfkill": {},
  "wpa_cli_status": {},
  "networkctl_status": {}
}
```

### Important Wi-Fi Fields

| Field | Meaning |
|---|---|
| `iw_link.stdout` | Access point, SSID, frequency, signal, bitrate. |
| `iwconfig.stdout` | Link quality, signal level, retries, power management. |
| `rfkill.stdout` | Whether WLAN is soft/hard blocked. |
| `wpa_cli_status.stdout` | WPA state and assigned IP. |
| `networkctl_status.stdout` | systemd-networkd view of wlan0. |

### Healthy Wi-Fi Indicators

```text
wpa_state=COMPLETED
ip_address=192.168.178.203
State: routable (configured)
Online state: online
Address: 192.168.178.203
Gateway: 192.168.178.1
```

### Signals Worth Watching

| Value | Meaning |
|---|---|
| `signal: -60 dBm` | Good signal for Raspberry Pi WLAN. |
| `signal: -68 dBm` | Still acceptable, but weaker. |
| `Tx excessive retries: 0` | Excellent. |
| `Tx excessive retries: >10` | Watch, but not automatically critical. |
| `Power Management:on` | Common on Raspberry Pi; may be reviewed if reconnect issues continue. |

---

## 24. JSON Block: `network_manager_cli`

This block checks `nmcli`, if available.

Example when NetworkManager is installed but not running:

```json
"network_manager_cli": {
  "available": true,
  "device_status": {
    "returncode": 8,
    "stderr": "Error: NetworkManager is not running."
  },
  "connections": {
    "returncode": 8,
    "stderr": "Error: NetworkManager is not running."
  }
}
```

This is not automatically a problem.

For the current JR-Bot design, the preferred network stack is:

```text
systemd-networkd + wpa_supplicant
```

NetworkManager may be disabled or masked.

For the One-Liner target, the preferred state is:

```text
NetworkManager.service disabled
```

`disabled` is preferred over `masked` because it is easier to reverse.

---

## 25. JSON Block: `network_services`

The `network_services` block collects systemd service information for relevant services.

Checked units:

```text
systemd-networkd.service
NetworkManager.service
wpa_supplicant.service
wpa_supplicant@wlan0.service
dhcpcd.service
systemd-resolved.service
networking.service
ssh.service
```

For each unit, the script collects:

- `LoadState`
- `ActiveState`
- `SubState`
- `UnitFileState`
- `Result`
- `ExecMainCode`
- `ExecMainStatus`
- `FragmentPath`
- `Description`
- `systemctl status`
- `systemctl cat`
- recent journal output

### Healthy Target

```text
systemd-networkd.service       enabled + active + running
wpa_supplicant@wlan0.service   enabled + active + running
ssh.service                    enabled + active + running
NetworkManager.service         disabled or masked, intentionally inactive
dhcpcd.service                 not-found / unused
systemd-resolved.service       not-found / unused, if resolv.conf is static
networking.service             not-found / unused
```

### Important Note

`NetworkManager.service = inactive` is not an error if the node is intentionally using `systemd-networkd`.

`dhcpcd.service = not-found` is not an error if the node is intentionally using `systemd-networkd` DHCP.

---

## 26. JSON Block: `network_config_files`

The `network_config_files` block reads sanitized network configuration files.

Checked files include:

```text
/etc/systemd/network/25-wlan0.network
/etc/systemd/network/20-wlan0.network
/etc/systemd/network/10-wlan0.network
/etc/systemd/network/25-eth0.network
/etc/systemd/network/20-eth0.network
/etc/systemd/network/10-eth0.network
/etc/network/interfaces
/etc/dhcpcd.conf
/etc/resolv.conf
/run/systemd/resolve/resolv.conf
/etc/hostname
/etc/hosts
/etc/systemd/network/*.network
/etc/systemd/network/*.link
/etc/wpa_supplicant/*.conf
/etc/NetworkManager/NetworkManager.conf
/etc/NetworkManager/system-connections/*
```

Sensitive values are redacted.

Unreadable files are reported as unreadable instead of forcing sudo access.

Example healthy WLAN networkd config:

```ini
[Match]
Name=wlan0

[Network]
DHCP=yes
IPv6AcceptRA=yes
```

### Important Interpretation

If `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` is unreadable, that is expected under non-root execution and not automatically an issue.

The script should not require root just to read Wi-Fi secrets.

---

## 27. JSON Block: `systemd_integrity`

The `systemd_integrity` block checks whether `systemd-networkd` and its shared libraries resolve correctly.

It collects:

- Metadata for `/lib/systemd/systemd-networkd`.
- `ldd /lib/systemd/systemd-networkd`.
- `/lib/systemd/systemd-networkd --version`.
- Missing shared libraries.
- Candidate locations for missing libraries.
- Known `libsystemd-shared-252.so` paths.

Important fields:

```json
"systemd_integrity": {
  "systemd_networkd_binary": {},
  "systemd_networkd_libraries": {},
  "systemd_networkd_version_command": {},
  "missing_libraries_detected": [],
  "library_candidates": {},
  "systemd_shared_library_candidates": [],
  "specific_paths": {}
}
```

### Why This Matters

GGB previously had a `systemd-networkd` failure related to missing or unresolved `libsystemd-shared-252.so`.

The script explicitly checks this class of issue.

### Healthy Example

```json
"missing_libraries_detected": []
```

If missing libraries are detected, the finding `MISSING_SHARED_LIBRARY` becomes critical.

---

## 28. JSON Block: `package_versions`

The `package_versions` block checks relevant package versions using `dpkg-query`.

Checked packages:

```text
systemd
libsystemd0
wpasupplicant
network-manager
dhcpcd5
raspberrypi-net-mods
isc-dhcp-client
wireless-tools
iw
rfkill
curl
ca-certificates
```

Example:

```json
"systemd": {
  "installed": true,
  "version": "252.39-1~deb12u1+rpi1",
  "architecture": "armhf"
}
```

This helps compare package state across DMR, GGB and TRX.

---

## 29. JSON Block: `connectivity`

The `connectivity` block performs practical network checks.

It includes:

- Gateway ping.
- DNS resolution for `google.com`.
- DNS resolution for the optional project host.
- Optional HTTPS HEAD request to `--test-url`.

Example:

```json
"connectivity": {
  "gateway": "192.168.178.1",
  "gateway_ping": {},
  "dns_getent_google": {},
  "dns_getent_project_host": {},
  "https_test": {}
}
```

### Healthy Indicators

```text
gateway_ping.returncode = 0
dns_getent_google.returncode = 0
dns_getent_project_host.returncode = 0
https_test.returncode = 0
```

### Recommended Test URLs

| Bot | Test URL |
|---|---|
| DMR | `https://domera.blenk.co.at` |
| GGB | `https://spl.blenk.co.at` |
| TRX | `https://trax.blenk.co.at` |

---

## 30. JSON Block: `raw_reference_commands`

This block stores additional diagnostic command outputs.

Included commands:

```text
ls -la /lib/systemd
ls -la /usr/lib/arm-linux-gnueabihf/systemd
find /usr /lib -name libsystemd-shared-*.so
find /etc/systemd/network -maxdepth 2 -type f -print
```

The block exists for deeper manual comparison.

It is especially useful when:

- `systemd-networkd` is failed.
- Shared libraries are missing.
- `/etc/systemd/network/*.network` files differ between bots.
- A symlink repair was used on one node but not another.

---

## 31. JSON Block: `analysis`

The `analysis` block contains the high-level interpretation.

Example:

```json
"analysis": {
  "health_state": "ok",
  "critical_count": 0,
  "warning_count": 0,
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

## 32. Findings and Recommendations

The script creates findings and recommendations in the `analysis` block.

Findings are observations.

Recommendations are suggested actions.

Example:

```json
"findings": [
  {
    "level": "ok",
    "code": "NETWORK_HEALTH_OK",
    "message": "Keine kritischen Netzwerkprobleme erkannt.",
    "evidence": null
  }
],
"recommendations": []
```

### Finding Levels

| Level | Meaning |
|---|---|
| `ok` | Healthy state observed. |
| `info` | Informational difference or expected inactive component. |
| `warning` | Potential problem or deviation from ideal state. |
| `critical` | Actual network health problem. |

### Important Rule

```text
finding != failure
```

For example:

```text
NETWORKMANAGER_INACTIVE = info
DHCPCD_NOT_FOUND = info
```

These are expected in a systemd-networkd-based JR-Bot network stack.

---

## 33. Known Finding Codes

| Code | Level | Meaning |
|---|---|---|
| `NO_IPV4` | critical | No IPv4 address found on a global interface. |
| `NO_DEFAULT_ROUTE` | critical | No default route found. |
| `SYSTEMD_NETWORKD_FAILED` | critical | `systemd-networkd` is failed. |
| `NETWORKMANAGER_INACTIVE` | info | NetworkManager is not active. Expected if networkd is used. |
| `DHCPCD_NOT_FOUND` | info | `dhcpcd.service` is not installed/found. Expected if networkd is used. |
| `WPA_SUPPLICANT_ACTIVE` | ok | `wpa_supplicant` is active. |
| `MISSING_SHARED_LIBRARY` | critical | Missing shared library detected in `ldd` or journal. |
| `GATEWAY_UNREACHABLE` | critical | Gateway ping failed. |
| `DNS_RESOLUTION_FAILED` | warning | DNS lookup failed. |
| `NO_WLAN_NETWORKD_CONFIG_DETECTED` | warning | No systemd-networkd `.network` file for WLAN detected. |
| `WLAN_NETWORKD_NO_DHCP_YES` | warning | WLAN `.network` file exists but lacks `DHCP=yes`. |
| `NETWORK_HEALTH_OK` | ok | No critical or warning findings detected. |

---

## 34. Target Network Baseline

The preferred JR-Bot network baseline is:

```text
systemd-networkd + wpa_supplicant
```

Expected target services:

```text
systemd-networkd.service       enabled + active + running
wpa_supplicant@wlan0.service   enabled + active + running
ssh.service                    enabled + active + running
NetworkManager.service         disabled
dhcpcd.service                 not-found / unused
systemd-resolved.service       not-found / unused, unless intentionally used
networking.service             not-found / unused
```

Expected WLAN config:

```text
/etc/systemd/network/25-wlan0.network
```

Expected content:

```ini
[Match]
Name=wlan0

[Network]
DHCP=yes
IPv6AcceptRA=yes
```

Healthy current IP assignments:

```text
DMR → 192.168.178.201
GGB → 192.168.178.202
TRX → 192.168.178.203
```

Recommended project test URLs:

```text
DMR → https://domera.blenk.co.at
GGB → https://spl.blenk.co.at
TRX → https://trax.blenk.co.at
```

---

## 35. Validated TRX Runtime State

D7.6 was validated on the TRX Pi.

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
Runtime script: /opt/bots/trx/audits/audit_jr-bot-network-health.sh
Runtime version: 0.2.1
```

Validated behavior:

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

Validated OPSCON response fields included:

```text
success=true
instance=trx
mode=target
audit_type=audit_jr-bot-network-health
expected_schema=jrbot-network-health-audit-v1
token_scope=instance
```

---

## 36. Legacy Context: DMR and GGB

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
DMR → 192.168.178.201
```

DMR may still run in legacy mode:

```bash
./audits/audit_jr-bot-network-health.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy
```

### GGB Context

Known target assignment:

```text
GGB → 192.168.178.202
```

GGB previously required a repair involving `systemd-networkd` library resolution.

The Network Health Audit specifically checks:

```text
/lib/systemd/systemd-networkd
ldd /lib/systemd/systemd-networkd
libsystemd-shared-252.so
missing_libraries_detected
```

If the repair regresses, the script should detect it as a critical issue.

### NetworkManager Difference

Possible valid states:

```text
NetworkManager.service = disabled
NetworkManager.service = masked
```

For the future target state, `disabled` is preferred over `masked`.

---

## 37. Repository Documentation Structure

Recommended target GitHub repository structure:

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
docs/audits/audit_jr-bot-network-health.md
```

The legacy `tools/` directory should not remain the canonical location for audit runtime scripts.

---

## 38. Local Documentation for Future JR-Agents

If a future JR-Agent runs locally on a bot, it should be able to read this handbook locally.

Recommended local structure:

```text
/opt/bots/{instance}/docs/audits/
├── audit-ingest-contract.md
├── audit_jr-bot-boot-report.md
├── audit_jr-bot-network-health.md
└── audit_jr-bot-structure.md
```

For legacy bots:

```text
/home/dmr/bots/DMR/docs/audits/audit_jr-bot-network-health.md
/home/ggb/bots/ggb/docs/audits/audit_jr-bot-network-health.md
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

## 39. Cleanup of Legacy OPSCON Structure

After DMR, GGB and TRX jobs have been moved to the new endpoint, the old endpoint and old data folder can be removed or archived.

### Old

```text
/OPSCON/api/jrbot_network_health_ingest.php
/OPSCON/data/jrbot_network_health/
```

### New

```text
/OPSCON/api/jrbot_audit_network_health_ingest.php
/OPSCON/data/audit_jr-bot-network-health/
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
WHERE config_json LIKE '%jrbot_network_health_ingest.php%'
   OR config_json LIKE '%jrbot_network_health%';
```

Also check for the new endpoint:

```sql
SELECT
    id,
    bot_name,
    job_key,
    config_json
FROM tbl_jobs
WHERE config_json LIKE '%jrbot_audit_network_health_ingest.php%';
```

### Safe Archive Option

```text
/OPSCON/data/_archive/jrbot_network_health_legacy_YYYYMMDD/
```

Permanent deletion should happen only after a successful control period.

---

## 40. Recommended Interpretation for Agents

Agents must not interpret every finding as a failure.

Important rule:

```text
finding != failure
```

Examples:

```text
NETWORKMANAGER_INACTIVE = info, expected if systemd-networkd is used
DHCPCD_NOT_FOUND = info, expected if systemd-networkd DHCP is used
WPA_SUPPLICANT_ACTIVE = ok
NETWORK_HEALTH_OK = ok
```

Agents should inspect in this order:

1. `analysis.health_state`
2. `analysis.critical_count`
3. `analysis.warning_count`
4. `analysis.findings`
5. `network.default_route`
6. `network.ipv4_addresses`
7. `wifi.wpa_cli_status`
8. `wifi.networkctl_status`
9. `network_services.systemd-networkd.service`
10. `network_services.wpa_supplicant@wlan0.service`
11. `connectivity.gateway_ping`
12. `connectivity.dns_getent_project_host`
13. `connectivity.https_test`
14. `systemd_integrity.missing_libraries_detected`
15. `package_versions.systemd`
16. `package_versions.libsystemd0`

If `health_state` is `ok`, the node is currently network-healthy.

If a node still fails after power loss despite `health_state: ok`, investigate:

- Boot timing.
- Power supply.
- SD card integrity.
- WLAN reconnect timing.
- systemd ordering.
- Firmware / Pi hardware behavior.
- Whether the boot report catches the failure window.
- Whether the failure happens before the network-health audit can run.

---

## 41. Recommended Future Development

### Version 0.2.2

Possible improvements:

- Add `--print-summary` output to include primary IPv4 and default route.
- Add explicit `primary_ipv4` field.
- Add explicit `primary_mac` field with optional redaction mode.
- Add Wi-Fi RSSI classification.
- Add `power_management_on` parsed boolean.
- Add `ap_bssid` parsed field.
- Add `ssid` parsed field.
- Add `ip_expected` optional argument.

### Version 0.2.3

Possible improvements:

- Add comparison mode with previous local report.
- Add optional expected IP check:
  - DMR expected `192.168.178.201`
  - GGB expected `192.168.178.202`
  - TRX expected `192.168.178.203`
- Add optional expected gateway check.
- Add optional expected SSID check.

### Version 0.3.0

Possible improvements:

- Machine-readable recommendation categories.
- One-Liner network baseline validation.
- Agent-readable summary block.
- Optional local latest copy under `reports/`.
- Optional `--agent-summary` compact output.
- Support for Ethernet-first nodes.
- Optional signed report metadata.
- Explicit retry/upload-pending mode, if needed.

---

## 42. Public Repository Safety Rules

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
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
```

Correct bot-side token fallback location:

```text
/opt/bots/{instance}/config/report_upload.token
```

The public repository may contain:

```text
audits/audit_jr-bot-network-health.sh
docs/audits/audit_jr-bot-network-health.md
docs/audits/audit-ingest-contract.md
example config templates without secrets
placeholder token names
```

Recommended placeholders:

```text
{ORIGINAL_UPLOAD_TOKEN}
{sha256(ORIGINAL_UPLOAD_TOKEN)}
{instance}
{bot_path}
```

Never use real tokens in examples.

---

## 43. Short Agent Summary

`audit_jr-bot-network-health.sh` is the main network diagnostic tool for JR-Bot nodes.

It is read-only and safe.

It checks:

```text
IPv4
default route
gateway ping
DNS
HTTPS reachability
WLAN status
wpa_supplicant
systemd-networkd
NetworkManager state
dhcpcd state
systemd shared libraries
network config files
package versions
recent network service logs
```

Current runtime version:

```text
0.2.1
```

Current target runtime path:

```text
audits/audit_jr-bot-network-health.sh
```

Legacy runtime path still visible on current public `main` until repository cleanup:

```text
tools/audit_jr-bot-network-health.sh
```

Current schema:

```text
jrbot-network-health-audit-v1
```

Current OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

Current OPSCON storage path:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/
```

Current instance-scoped token-hash path:

```text
/OPSCON/data/audit_jr-bot-network-health/{instance}/_security/ingest_token_sha256
```

Healthy current assignments:

```text
DMR → 192.168.178.201
GGB → 192.168.178.202
TRX → 192.168.178.203
```

Healthy target stack:

```text
systemd-networkd.service       enabled + active
wpa_supplicant@wlan0.service   enabled + active
ssh.service                    enabled + active
NetworkManager.service         disabled
dhcpcd.service                 unused / not-found
```

Since runtime version `0.2.1`, normal upload no longer requires explicit `--push-url` or `--token` if the bot has a valid local token file:

```text
/opt/bots/{instance}/config/report_upload.token
```

The token is sent via:

```text
X-OPSCON-INGEST-TOKEN
```

and no longer as a visible `curl -F "token=..."` command-line argument.

This handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-network-health.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/{instance}/docs/audits/audit_jr-bot-network-health.md
```
