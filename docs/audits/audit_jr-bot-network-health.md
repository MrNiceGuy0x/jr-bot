# JR-Bot Network Health Audit Handbook

**Status:** Active  
**Handbook Version:** 1.1  
**Runtime Script Version Reference:** 0.2.1  
**Project:** JR-Bot / OPSCON  
**Recommended Repository Path:** `docs/audits/audit_jr-bot-network-health.md`  
**Related Runtime Script:** `audits/audit_jr-bot-network-health.sh`  
**Expected JSON Schema:** `jrbot-network-health-audit-v1`  
**Audit Type:** `audit_jr-bot-network-health`  
**Last Updated:** 2026-06-27  
**Security Level:** Public documentation without secrets

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON System](#2-role-in-the-jr-bot--opscon-system)
3. [Current Runtime Status](#3-current-runtime-status)
4. [Security Principles](#4-security-principles)
5. [Runtime Usage](#5-runtime-usage)
6. [Supported Parameters](#6-supported-parameters)
7. [Output and Pending File Behavior](#7-output-and-pending-file-behavior)
8. [OPSCON Endpoint](#8-opscon-endpoint)
9. [Mandatory OPSCON Storage Layout](#9-mandatory-opscon-storage-layout)
10. [Instance-Scoped Token and Hash Model](#10-instance-scoped-token-and-hash-model)
11. [Runtime Token Lookup Order](#11-runtime-token-lookup-order)
12. [D7.6 Runtime Upload Hardening](#12-d76-runtime-upload-hardening)
13. [Expected Upload Request](#13-expected-upload-request)
14. [Public Ingest Validation Contract](#14-public-ingest-validation-contract)
15. [JSON Root Structure](#15-json-root-structure)
16. [JSON Block: `security`](#16-json-block-security)
17. [JSON Block: `host`](#17-json-block-host)
18. [JSON Block: `bot_context`](#18-json-block-bot_context)
19. [JSON Block: `commands_available`](#19-json-block-commands_available)
20. [JSON Block: `network`](#20-json-block-network)
21. [JSON Block: `wifi`](#21-json-block-wifi)
22. [JSON Block: `network_manager_cli`](#22-json-block-network_manager_cli)
23. [JSON Block: `network_services`](#23-json-block-network_services)
24. [JSON Block: `network_config_files`](#24-json-block-network_config_files)
25. [JSON Block: `systemd_integrity`](#25-json-block-systemd_integrity)
26. [JSON Block: `package_versions`](#26-json-block-package_versions)
27. [JSON Block: `connectivity`](#27-json-block-connectivity)
28. [JSON Block: `raw_reference_commands`](#28-json-block-raw_reference_commands)
29. [JSON Block: `analysis`](#29-json-block-analysis)
30. [JSON Block: `opscon_ingest`](#30-json-block-opscon_ingest)
31. [Findings and Recommendations](#31-findings-and-recommendations)
32. [Known Finding Codes](#32-known-finding-codes)
33. [Target Runtime State](#33-target-runtime-state)
34. [TRX Validation State](#34-trx-validation-state)
35. [Repository and Local Documentation Layout](#35-repository-and-local-documentation-layout)
36. [Deprecated Legacy References](#36-deprecated-legacy-references)
37. [Public Repository Safety Rules](#37-public-repository-safety-rules)
38. [Recommended Future Development](#38-recommended-future-development)
39. [Short Agent Summary](#39-short-agent-summary)

---

## 1. Purpose

`audits/audit_jr-bot-network-health.sh` is the deep read-only network and node health audit script for JR-Bot Raspberry Pi nodes.

The script collects a detailed snapshot of the current network state, Wi-Fi state, systemd network services, package versions, DNS configuration, route configuration, connectivity, and relevant systemd integrity information.

The purpose is not to repair the node.

The purpose is to provide a reproducible, safe, machine-readable diagnostic report that can be compared across JR-Bot nodes such as DMR, GGB, and TRX.

The script is especially useful when diagnosing:

- Raspberry Pi nodes that do not come back online after a power outage.
- WLAN reconnection problems.
- DHCP lease or static Fritzbox assignment issues.
- Missing default routes.
- Broken DNS resolution.
- Failed `systemd-networkd`.
- Broken `libsystemd-shared-252.so` resolution.
- Differences between DMR, GGB, and TRX network stacks.
- Whether a previous repair remained stable after reboot.
- Whether a One-Liner installed node has the expected network baseline.

---

## 2. Role in the JR-Bot / OPSCON System

The Network Health Audit is one of the three JR-Bot audit/report pipelines:

| Audit Script | Purpose | OPSCON Audit Type |
|---|---|---|
| `audits/audit_jr-bot-structure.sh` | Checks file layout, bot profile, Python venv, systemd runner units, and runtime structure. | `audit_jr-bot-structure` |
| `audits/audit_jr-bot-network-health.sh` | Checks network interfaces, routes, DNS, services, WLAN, systemd-networkd integrity, and connectivity. | `audit_jr-bot-network-health` |
| `audits/audit_jr-bot-boot-report.sh` | Creates a boot-time diagnostic snapshot after reboot and uploads pending boot reports. | `audit_jr-bot-boot-report` |

The Network Health Audit answers this question:

> Is the node currently healthy from a network and network-service perspective?

Use it when:

- The Pi is online but past boot or reconnect behavior is suspicious.
- A node changed IP address.
- Fritzbox static assignment was changed.
- WLAN signal quality must be compared.
- `systemd-networkd` or `wpa_supplicant` behavior must be inspected.
- A previous offline case needs evidence-based analysis.
- A bot should be validated before or after One-Liner migration.

---

## 3. Current Runtime Status

Current intended runtime script:

```text
audits/audit_jr-bot-network-health.sh
```

Current intended script version:

```text
0.2.1
```

Current expected schema:

```text
jrbot-network-health-audit-v1
```

Current OPSCON endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

Current OPSCON storage root:

```text
/OPSCON/data/audit_jr-bot-network-health/
```

Important architecture state:

```text
tools/ is deprecated for audit scripts.
audits/ is the active runtime and repository path for audit scripts.
```

---

## 4. Security Principles

The script is read-only by design.

It does not repair, restart, enable, disable, install, or uninstall anything.

Security rules:

- No system changes are made.
- Secrets are redacted before output.
- Wi-Fi PSK values are not printed.
- Password-like values are redacted.
- Token-like values are redacted.
- Network config files are sanitized.
- Upload to OPSCON is controlled by runtime token authentication.
- The cleartext upload token is never stored in GitHub.
- The SHA-256 token hash is never stored in GitHub.
- Uploaded JSON is stored as data and is not executed.

Redacted key patterns include:

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

The JSON report contains a security contract:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false,
  "network_passwords_redacted": true
}
```

The OPSCON ingest endpoint should reject reports where these safety flags do not match the expected values.

---

## 5. Runtime Usage

### Target Layout: Local Audit With Optional Upload

```bash
/opt/bots/<instance>/audits/audit_jr-bot-network-health.sh \
  --instance <instance> \
  --path /opt/bots/<instance>
```

Example for TRX:

```bash
/opt/bots/trx/audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx
```

Since runtime version `0.2.1`, the script has a default OPSCON push URL and supports unattended upload without explicitly passing `--push-url` or `--token`, as long as a valid local token file exists.

### Local Audit Without Upload Side Effects

To create a kept local debug file, use `--output`:

```bash
/opt/bots/trx/audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --output /opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-local-debug.json \
  --print-summary
```

### Legacy Layout Example

```bash
/home/dmr/bots/DMR/audits/audit_jr-bot-network-health.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --gateway 192.168.178.1 \
  --test-url https://domera.blenk.co.at \
  --print-summary
```

### Manual Debug Upload With Explicit Overrides

Explicit `--push-url` and `--token` remain available for controlled manual debugging, but should not be used in systemd production units because CLI arguments can be exposed locally.

```bash
audits/audit_jr-bot-network-health.sh \
  --instance trx \
  --path /opt/bots/trx \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
  --token <REPORT_UPLOAD_TOKEN>
```

---

## 6. Supported Parameters

| Parameter | Required | Description |
|---|---:|---|
| `--instance <name>` | Yes | Bot instance name, for example `dmr`, `ggb`, or `trx`. |
| `--path <bot-path>` | Yes | Bot installation path. |
| `--legacy` | No | Marks the audit as legacy context. Used for older DMR/GGB structures. |
| `--push-url <url>` | No | OPSCON network health ingest endpoint override. |
| `--token <token>` | No | Upload token for manual debugging. Avoid in systemd units. |
| `--output <file>` | No | Local JSON output path. File will be kept. |
| `--keep-local` | No | Keep generated local JSON after successful upload. |
| `--print-json` | No | Print full JSON to stdout. |
| `--print-summary` | No | Print compact summary of findings and recommendations. |
| `--test-url <url>` | No | Optional HTTPS URL to test. |
| `--gateway <ip>` | No | Optional gateway override. |
| `--wifi-iface <iface>` | No | Wi-Fi interface. Default: `wlan0`. |
| `--eth-iface <iface>` | No | Ethernet interface. Default: `eth0`. |
| `-h`, `--help` | No | Show help. |

---

## 7. Output and Pending File Behavior

Default local pending output:

```text
<bot-path>/reports/pending/audit_jr-bot-network-health-<instance>-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-20260627_091753.json
```

After a successful upload, the local temporary report is deleted unless `--keep-local` or `--output` was used.

If the upload fails, the local JSON remains available for debugging or later retry.

---

## 8. OPSCON Endpoint

Current endpoint:

```text
/OPSCON/api/jrbot_audit_network_health_ingest.php
```

Full URL:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

Deprecated legacy endpoint:

```text
/OPSCON/api/jrbot_network_health_ingest.php
```

Deprecated legacy storage:

```text
/OPSCON/data/jrbot_network_health/
```

The legacy endpoint and legacy storage path must not be used for new runtime jobs.

---

## 9. Mandatory OPSCON Storage Layout

The active security model is instance-scoped.

Correct layout:

```text
/OPSCON/data/audit_jr-bot-network-health/
└── <instance>/
    ├── _security/
    │   ├── .htaccess
    │   └── ingest_token_sha256
    ├── audit_jr-bot-network-health-<instance>.json
    └── history/
        └── audit_jr-bot-network-health-<instance>-YYYYMMDD_HHMMSS.json
```

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-network-health/trx/_security/ingest_token_sha256
/OPSCON/data/audit_jr-bot-network-health/trx/audit_jr-bot-network-health-trx.json
/OPSCON/data/audit_jr-bot-network-health/trx/history/
```

Forbidden layout:

```text
/OPSCON/data/audit_jr-bot-network-health/_security/ingest_token_sha256
```

Reason:

```text
A global audit-type token would force all JR-Bot instances of the same audit type to share one upload token.
This breaks per-instance isolation.
```

Public ingest endpoints must not auto-create `_security` directories or `ingest_token_sha256` files.

Allowed creation path:

```text
OPSCON admin / onboarding tooling
future internal OPSCON provision endpoint
apps.php / monitor.php provisioning workflow
manual server-side setup during migration
```

---

## 10. Instance-Scoped Token and Hash Model

The server stores only the SHA-256 hash of the upload token.

Instance-specific hash file:

```text
/OPSCON/data/audit_jr-bot-network-health/<instance>/_security/ingest_token_sha256
```

Example placeholder content:

```text
<sha256(REPORT_UPLOAD_TOKEN)>
```

Important rules:

- The file contains only the hash.
- No quotes.
- No PHP code.
- No spaces before or after.
- The original token is passed by the bot during upload.
- The original token must not be committed to GitHub.
- The hash file must not be committed to GitHub.
- The `_security` directory must be protected by `.htaccess`.

Recommended `_security/.htaccess`:

```apache
Require all denied
```

Recommended server-side permissions:

```text
_security/              0750
_security/.htaccess     0640
ingest_token_sha256     0640
```

---

## 11. Runtime Token Lookup Order

Network Health runtime version `0.2.1` supports automatic token lookup.

Lookup order:

```text
REPORT_UPLOAD_TOKEN
<bot-path>/config/audit_network_health.token
<bot-path>/config/network_health_upload.token
<bot-path>/config/report_upload.token
```

Example TRX fallback file:

```text
/opt/bots/trx/config/report_upload.token
```

The token file must exist only on the bot host and must not be committed to the public repository.

Recommended local permissions:

```bash
chmod 600 /opt/bots/<instance>/config/report_upload.token
chown <instance>:<instance> /opt/bots/<instance>/config/report_upload.token
```

---

## 12. D7.6 Runtime Upload Hardening

Runtime version `0.2.1` hardened the upload behavior.

Previous unsafe runtime pattern:

```text
curl ... -F "token=${TOKEN}" ...
```

This could temporarily expose the cleartext token through local process inspection tools such as:

```text
ps aux
systemctl status
/proc/<pid>/cmdline
```

Required hardened runtime pattern:

```text
curl --config <temporary-curl-config>
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
X-OPSCON-INGEST-TOKEN: <token>
```

The OPSCON ingest endpoint must accept this header.

Every Network Health upload must define hard curl timeouts:

```text
connect-timeout = 10
max-time = 60
```

This prevents upload calls from hanging indefinitely.

---

## 13. Expected Upload Request

The runtime upload sends these form fields:

```text
instance=<instance>
mode=<mode>
audit_file=@<json-file>;type=application/json
```

The token is sent through this request header:

```text
X-OPSCON-INGEST-TOKEN: <token>
```

The old multipart token field is deprecated for regular runtime usage.

For compatibility, the OPSCON endpoint may still accept a POST field named `token`, but production runtime scripts should prefer the header-based upload path.

---

## 14. Public Ingest Validation Contract

The public OPSCON Network Health ingest endpoint must follow this order:

1. Accept POST only.
2. Read `instance` from the request.
3. Normalize and strictly validate `instance`.
4. Resolve the instance directory.
5. Read the expected token hash from the instance-specific `_security` directory.
6. Read the upload token from supported request headers or POST data.
7. Compare `hash('sha256', token)` with `ingest_token_sha256` using constant-time comparison.
8. Read uploaded audit JSON from `audit_file` or supported debug fallback.
9. Validate JSON syntax.
10. Validate schema: `jrbot-network-health-audit-v1`.
11. Validate security flags.
12. Compare POST/header `instance` with JSON `instance` if the JSON instance is present.
13. Store the report under the instance-specific audit directory.
14. Write current JSON and history JSON only after successful authentication and validation.

Recommended instance regex:

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
```

If the instance directory, `_security` directory, or hash file is missing, empty, or invalid, the endpoint must reject the upload with:

```json
{
  "success": false,
  "code": "INGEST_NOT_CONFIGURED"
}
```

---

## 15. JSON Root Structure

The script generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-network-health-audit-v1",
  "script_version": "0.2.1",
  "instance": "trx",
  "mode": "target",
  "created_at_utc": "YYYY-MM-DDTHH:MM:SSZ",
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
  "analysis": {},
  "opscon_ingest": {}
}
```

---

## 16. JSON Block: `security`

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

---

## 17. JSON Block: `host`

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

The `boot_time` is important when checking whether an audit was produced before or after a reboot.

---

## 18. JSON Block: `bot_context`

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

---

## 19. JSON Block: `commands_available`

The `commands_available` block lists whether required diagnostic commands exist.

Important commands:

| Command | Purpose |
|---|---|
| `ip` | Interfaces, addresses, and routes. |
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

If a command is missing, the report may still be valid but less complete.

---

## 20. JSON Block: `network`

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

Important fields:

| Field | Meaning |
|---|---|
| `hostname_I.stdout` | Quick IP overview. |
| `ipv4_addresses` | Parsed IPv4 addresses. |
| `default_route.present` | Whether a default route exists. |
| `default_route.gateway` | Gateway IP. |
| `default_route.interface` | Interface used by default route. |
| `default_route.source` | Source IP used for outbound traffic. |

Healthy example:

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

## 21. JSON Block: `wifi`

The `wifi` block contains Wi-Fi-specific diagnostics.

It collects:

- `ip link show wlan0`
- `iw dev wlan0 link`
- `iw dev`
- `iwconfig wlan0`
- `rfkill list`
- `wpa_cli -i wlan0 status`
- `networkctl status wlan0`

Healthy indicators:

```text
wpa_state=COMPLETED
ip_address=192.168.178.203
State: routable (configured)
Online state: online
Address: 192.168.178.203
Gateway: 192.168.178.1
```

Signals worth watching:

| Value | Meaning |
|---|---|
| `signal: -60 dBm` | Good signal for Raspberry Pi WLAN. |
| `signal: -68 dBm` | Still acceptable, but weaker. |
| `Tx excessive retries: 0` | Excellent. |
| `Tx excessive retries: >10` | Watch, but not automatically critical. |
| `Power Management:on` | Common on Raspberry Pi; review only if reconnect issues continue. |

---

## 22. JSON Block: `network_manager_cli`

This block checks `nmcli`, if available.

NetworkManager being inactive is not automatically a problem.

For the current JR-Bot design, the preferred network stack is:

```text
systemd-networkd + wpa_supplicant
```

For the One-Liner target, the preferred state is:

```text
NetworkManager.service disabled
```

`disabled` is preferred over `masked` because it is easier to reverse.

---

## 23. JSON Block: `network_services`

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
- `DropInPaths`
- `Description`
- `systemctl status`
- `systemctl cat`
- recent journal output

Healthy target:

```text
systemd-networkd.service       enabled + active + running
wpa_supplicant@wlan0.service   enabled + active + running
ssh.service                    enabled + active + running
NetworkManager.service         disabled, intentionally inactive
dhcpcd.service                 not-found / unused
systemd-resolved.service       not-found / unused, if resolv.conf is static
networking.service             not-found / unused
```

---

## 24. JSON Block: `network_config_files`

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

---

## 25. JSON Block: `systemd_integrity`

The `systemd_integrity` block checks whether `systemd-networkd` and its shared libraries resolve correctly.

It collects:

- Metadata for `/lib/systemd/systemd-networkd`.
- `ldd /lib/systemd/systemd-networkd`.
- `/lib/systemd/systemd-networkd --version`.
- Missing shared libraries.
- Candidate locations for missing libraries.
- Known `libsystemd-shared-252.so` paths.

Why this matters:

GGB previously had a `systemd-networkd` failure related to missing or unresolved `libsystemd-shared-252.so`. The Network Health Audit explicitly checks this class of issue.

Healthy example:

```json
"missing_libraries_detected": []
```

If missing libraries are detected, the finding `MISSING_SHARED_LIBRARY` becomes critical.

---

## 26. JSON Block: `package_versions`

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

This helps compare package state across DMR, GGB, and TRX.

---

## 27. JSON Block: `connectivity`

The `connectivity` block performs practical network checks.

It includes:

- Gateway ping.
- DNS resolution for `google.com`.
- DNS resolution for the optional project host.
- Optional HTTPS HEAD request to `--test-url`.

Healthy indicators:

```text
gateway_ping.returncode = 0
dns_getent_google.returncode = 0
dns_getent_project_host.returncode = 0
https_test.returncode = 0
```

Recommended test URLs:

| Bot | Test URL |
|---|---|
| DMR | `https://domera.blenk.co.at` |
| GGB | `https://spl.blenk.co.at` |
| TRX | `https://trax.blenk.co.at` |

---

## 28. JSON Block: `raw_reference_commands`

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

## 29. JSON Block: `analysis`

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

Important rule:

```text
info findings do not make health_state warning
ok findings do not make health_state warning
```

---

## 30. JSON Block: `opscon_ingest`

The `opscon_ingest` block is added by the OPSCON endpoint after successful ingest.

Example:

```json
"opscon_ingest": {
  "received_at_utc": "YYYY-MM-DDTHH:MM:SSZ",
  "source_ip": "<redacted or server-observed IP>",
  "user_agent": "curl/<version>",
  "endpoint": "jrbot_audit_network_health_ingest.php",
  "mode_posted": "target",
  "audit_type": "audit_jr-bot-network-health",
  "storage_model": "single-current-file-plus-history"
}
```

A successful endpoint response should include:

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

---

## 31. Findings and Recommendations

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

Finding levels:

| Level | Meaning |
|---|---|
| `ok` | Healthy state observed. |
| `info` | Informational difference or expected inactive component. |
| `warning` | Potential problem or deviation from ideal state. |
| `critical` | Actual network health problem. |

Important rule:

```text
finding != failure
```

Examples:

```text
NETWORKMANAGER_INACTIVE = info
DHCPCD_NOT_FOUND = info
```

These are expected in a systemd-networkd-based JR-Bot network stack.

---

## 32. Known Finding Codes

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

## 33. Target Runtime State

Expected TRX target path:

```text
/opt/bots/trx
```

Expected TRX IP assignment:

```text
TRX -> 192.168.178.203
```

Expected network stack:

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

Expected OPSCON target:

```text
/OPSCON/data/audit_jr-bot-network-health/trx/audit_jr-bot-network-health-trx.json
/OPSCON/data/audit_jr-bot-network-health/trx/history/
```

Expected TRX test URL:

```text
https://trax.blenk.co.at
```

---

## 34. TRX Validation State

D7.6 was validated on the TRX Pi.

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
```

Validated behavior:

```text
bash syntax check successful
upload successful without --push-url
upload successful without --token
default OPSCON push URL used
token loaded from local config/report_upload.token
OPSCON accepted instance-scoped token
local pending file deleted after successful upload
pending_count=0
```

Validated runtime version:

```text
audit_jr-bot-network-health.sh: 0.2.1
```

---

## 35. Repository and Local Documentation Layout

Recommended repository structure:

```text
jr-bot/
├── install_jr-bot.sh
├── audits/
│   ├── audit_jr-bot-structure.sh
│   ├── audit_jr-bot-network-health.sh
│   └── audit_jr-bot-boot-report.sh
├── scripts/
│   ├── reboot.sh
│   ├── shutdown.sh
│   ├── cancel_reboot.sh
│   ├── cancel_shutdown.sh
│   ├── check_disk.sh
│   ├── check_memory.sh
│   ├── uptime_info.sh
│   ├── ssh_status.sh
│   ├── ssh_start.sh
│   └── ssh_stop.sh
├── src/
│   └── job_runner.py
├── templates/
│   ├── config.ini.template
│   ├── bot-runner@.service.template
│   └── bot-runner@.timer.template
└── docs/
    ├── architecture.md
    └── audits/
        ├── audit-ingest-contract.md
        ├── audit_jr-bot-structure.md
        ├── audit_jr-bot-network-health.md
        └── audit_jr-bot-boot-report.md
```

This handbook belongs in the repository at:

```text
docs/audits/audit_jr-bot-network-health.md
```

Recommended local documentation path:

```text
/opt/bots/<instance>/docs/audits/audit_jr-bot-network-health.md
```

---

## 36. Deprecated Legacy References

The following references are deprecated and must not be used as target state:

```text
tools/audit_jr-bot-network-health.sh
/OPSCON/api/jrbot_network_health_ingest.php
/OPSCON/data/jrbot_network_health/
/OPSCON/data/audit_jr-bot-network-health/_security/ingest_token_sha256
```

Current target references:

```text
audits/audit_jr-bot-network-health.sh
/OPSCON/api/jrbot_audit_network_health_ingest.php
/OPSCON/data/audit_jr-bot-network-health/<instance>/_security/ingest_token_sha256
/OPSCON/data/audit_jr-bot-network-health/<instance>/audit_jr-bot-network-health-<instance>.json
/OPSCON/data/audit_jr-bot-network-health/<instance>/history/
```

Before deleting any legacy OPSCON structure, check jobs and configs for old endpoint references.

Example SQL check:

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

New endpoint check:

```sql
SELECT
    id,
    bot_name,
    job_key,
    config_json
FROM tbl_jobs
WHERE config_json LIKE '%jrbot_audit_network_health_ingest.php%';
```

Safe archive option:

```text
/OPSCON/data/_archive/jrbot_network_health_legacy_YYYYMMDD/
```

Permanent deletion should happen only after a successful control period.

---

## 37. Public Repository Safety Rules

The public repository must never contain:

```text
cleartext ingest tokens
SHA256 ingest token hashes
production .env files
production config.ini files
generated local token files
generated pending audit JSON files
server-side _security directories
```

Recommended `.gitignore` protection:

```gitignore
# JR-Bot / OPSCON secrets
.env
*.env
config.ini
**/config/config.ini
report_upload.token
**/config/report_upload.token
ingest_token_sha256
**/ingest_token_sha256
*.token
*.secret
*.key
*.pem

# Runtime data
reports/
**/reports/
data/
**/data/
tmp/
**/tmp/
state/
**/state/
logs/
**/logs/

# Generated audit reports
audit_jr-bot-structure-*.json
audit_jr-bot-network-health-*.json
audit_jr-bot-boot-report-*.json
*.local.json

# Python
venv/
.venv/
__pycache__/
*.pyc
```

---

## 38. Recommended Future Development

Possible future improvements:

### Version 0.2.2

- Add compact `--print-summary` line for primary IPv4 and default route.
- Add explicit `primary_ipv4` field.
- Add explicit `primary_mac` field with optional redaction mode.
- Add Wi-Fi RSSI classification.
- Add parsed `power_management_on` boolean.
- Add parsed `ap_bssid` field.
- Add parsed `ssid` field.
- Add optional `--expected-ip` argument.

### Version 0.2.3

- Add comparison mode with previous local report.
- Add optional expected gateway check.
- Add optional expected SSID check.
- Add optional expected network stack validation.

### Version 0.3.0

- Machine-readable recommendation categories.
- One-Liner network baseline validation.
- Agent-readable summary block.
- Optional local current copy under `reports/`.
- Optional `--agent-summary` compact output.
- Support for Ethernet-first nodes.

---

## 39. Short Agent Summary

`audits/audit_jr-bot-network-health.sh` is the main network diagnostic tool for JR-Bot nodes.

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

Healthy current assignments:

```text
DMR -> 192.168.178.201
GGB -> 192.168.178.202
TRX -> 192.168.178.203
```

Healthy target stack:

```text
systemd-networkd.service       enabled + active
wpa_supplicant@wlan0.service   enabled + active
ssh.service                    enabled + active
NetworkManager.service         disabled
dhcpcd.service                 unused / not-found
```

The OPSCON endpoint is:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

The instance-scoped OPSCON security path is:

```text
/OPSCON/data/audit_jr-bot-network-health/<instance>/_security/ingest_token_sha256
```

The current report path is:

```text
/OPSCON/data/audit_jr-bot-network-health/<instance>/audit_jr-bot-network-health-<instance>.json
```

The handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-network-health.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/<instance>/docs/audits/audit_jr-bot-network-health.md
```
