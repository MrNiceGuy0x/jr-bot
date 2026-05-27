# JR-Bot Network Health Audit Handbook

**Status:** Active  
**Handbook Version:** 1.0  
**Script Version Reference:** 0.1.1  
**Project:** JR-Bot / OPSCON  
**Recommended Repository Path:** `docs/audits/audit_jr-bot-network-health.md`  
**Related Runtime Script:** `tools/audit_jr-bot-network-health.sh`  
**Expected JSON Schema:** `jrbot-network-health-audit-v1`  
**Last Updated:** 2026-05-27  

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON System](#2-role-in-the-jr-bot--opscon-system)
3. [Current Repository Status](#3-current-repository-status)
4. [Security Principles](#4-security-principles)
5. [Typical Usage](#5-typical-usage)
6. [Parameters](#6-parameters)
7. [OPSCON Endpoint](#7-opscon-endpoint)
8. [OPSCON Storage Structure](#8-opscon-storage-structure)
9. [Token and Hash Security Model](#9-token-and-hash-security-model)
10. [JSON Root Structure](#10-json-root-structure)
11. [JSON Block: `security`](#11-json-block-security)
12. [JSON Block: `host`](#12-json-block-host)
13. [JSON Block: `bot_context`](#13-json-block-bot_context)
14. [JSON Block: `commands_available`](#14-json-block-commands_available)
15. [JSON Block: `network`](#15-json-block-network)
16. [JSON Block: `wifi`](#16-json-block-wifi)
17. [JSON Block: `network_manager_cli`](#17-json-block-network_manager_cli)
18. [JSON Block: `network_services`](#18-json-block-network_services)
19. [JSON Block: `network_config_files`](#19-json-block-network_config_files)
20. [JSON Block: `systemd_integrity`](#20-json-block-systemd_integrity)
21. [JSON Block: `package_versions`](#21-json-block-package_versions)
22. [JSON Block: `connectivity`](#22-json-block-connectivity)
23. [JSON Block: `raw_reference_commands`](#23-json-block-raw_reference_commands)
24. [JSON Block: `analysis`](#24-json-block-analysis)
25. [JSON Block: `opscon_ingest`](#25-json-block-opscon_ingest)
26. [Findings and Recommendations](#26-findings-and-recommendations)
27. [Known Finding Codes](#27-known-finding-codes)
28. [Current State: DMR](#28-current-state-dmr)
29. [Current State: GGB](#29-current-state-ggb)
30. [Planned Target State: TRX / One-Liner v0.3](#30-planned-target-state-trx--one-liner-v03)
31. [Repository Documentation Structure](#31-repository-documentation-structure)
32. [Local Documentation for Future JR-Agents](#32-local-documentation-for-future-jr-agents)
33. [Cleanup of Legacy OPSCON Structure](#33-cleanup-of-legacy-opscon-structure)
34. [Recommended Interpretation for Agents](#34-recommended-interpretation-for-agents)
35. [Recommended Future Development](#35-recommended-future-development)
36. [Short Agent Summary](#36-short-agent-summary)

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

---

## 2. Role in the JR-Bot / OPSCON System

The Network Health Audit is one of several diagnostic tools in the JR-Bot ecosystem.

It answers this question:

> Is the node currently healthy from a network and network-service perspective?

It complements the structure audit.

### Separation from Other Scripts

| Script | Purpose |
|---|---|
| `audit_jr-bot-structure.sh` | Checks file layout, bot profile, Python venv, systemd runner units and runtime structure. |
| `audit_jr-bot-network-health.sh` | Checks network interfaces, routes, DNS, services, WLAN, systemd-networkd integrity and connectivity. |
| `jrbot_boot_report.sh` | Collects boot-state shortly after reboot and reports it to OPSCON. |
| `reboot.sh` | Performs a controlled reboot through a maintenance job. |

The Network Health Audit should be used when:

- The Pi is online but its past boot/reconnect behavior is suspicious.
- A node has changed IP address.
- A Fritzbox static assignment was changed.
- WLAN signal quality needs to be compared.
- `systemd-networkd` or `wpa_supplicant` behavior must be inspected.
- A previous offline case needs evidence-based analysis.
- A bot should be validated before or after One-Liner migration.

---

## 3. Current Repository Status

The intended script version for this handbook is:

```text
0.1.1
```

The intended OPSCON endpoint is:

```text
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
```

The intended OPSCON storage folder is:

```text
/OPSCON/data/audit_jr-bot-network-health/
```

At the time this handbook was prepared, the GitHub raw view of `tools/audit_jr-bot-network-health.sh` still showed a compressed legacy file with only a few physical lines and `SCRIPT_VERSION="0.1.0"`.

Therefore, before relying on the repository version, check that GitHub shows the updated file with real line breaks and version `0.1.1`.

Expected after correct upload:

```text
tools/audit_jr-bot-network-health.sh
SCRIPT_VERSION="0.1.1"
Endpoint: jrbot_audit_network_health_ingest.php
```

Recommended verification after upload:

```bash
curl -fsSL https://raw.githubusercontent.com/MrNiceGuy0x/jr-bot/main/tools/audit_jr-bot-network-health.sh   -o /tmp/audit_jr-bot-network-health.sh

grep 'SCRIPT_VERSION=' /tmp/audit_jr-bot-network-health.sh
grep 'jrbot_audit_network_health_ingest.php' /tmp/audit_jr-bot-network-health.sh
bash -n /tmp/audit_jr-bot-network-health.sh
wc -l /tmp/audit_jr-bot-network-health.sh
```

---

## 4. Security Principles

The script is read-only by design.

It does not repair, restart, enable, disable, install or uninstall anything.

### Security Rules

- No system changes are made.
- Secrets are redacted before output.
- Wi-Fi PSK values are not printed.
- Password-like values are redacted.
- Token-like values are redacted.
- Network config files are sanitized.
- Upload to OPSCON is optional.
- Upload uses a token supplied at runtime.
- The original token is not stored in GitHub.
- The OPSCON endpoint stores only JSON.
- Uploaded JSON is not executed.

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

The OPSCON ingest endpoint rejects reports where these security flags do not match the expected safe values.

---

## 5. Typical Usage

### Local Audit Without Upload

```bash
./audit_jr-bot-network-health.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --print-summary
```

### Legacy Audit for DMR

```bash
./audit_jr-bot-network-health.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --gateway 192.168.178.1 \
  --test-url https://domera.blenk.co.at \
  --print-summary
```

### Target/Hybrid Audit for GGB

```bash
./audit_jr-bot-network-health.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --gateway 192.168.178.1 \
  --test-url https://spl.blenk.co.at \
  --print-summary
```

### OPSCON Upload for DMR

```bash
./audit_jr-bot-network-health.sh \
  --instance dmr \
  --path /home/dmr/bots/DMR \
  --legacy \
  --gateway 192.168.178.1 \
  --test-url https://domera.blenk.co.at \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
  --token <ORIGINAL_UPLOAD_TOKEN>
```

### OPSCON Upload for GGB

```bash
./audit_jr-bot-network-health.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --gateway 192.168.178.1 \
  --test-url https://spl.blenk.co.at \
  --push-url https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php \
  --token <ORIGINAL_UPLOAD_TOKEN>
```

### Local Debug Output File

```bash
./audit_jr-bot-network-health.sh \
  --instance ggb \
  --path /home/ggb/bots/ggb \
  --output ~/audit_jr-bot-network-health-ggb-local-debug.json \
  --print-summary
```

---

## 6. Parameters

| Parameter | Required | Description |
|---|---:|---|
| `--instance <name>` | Yes | Bot instance name, for example `dmr`, `ggb`, `trx`. |
| `--path <bot-path>` | Yes | Bot installation path. |
| `--legacy` | No | Marks the audit as legacy-context. Used for older DMR/GGB structures. |
| `--push-url <url>` | No | OPSCON network health ingest endpoint. |
| `--token <token>` | No | Original upload token for OPSCON. |
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

## 7. OPSCON Endpoint

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

The legacy endpoint used a fixed token inside PHP and stored reports under:

```text
/OPSCON/data/jrbot_network_health/
```

The new endpoint uses a hash-token model and stores reports under:

```text
/OPSCON/data/audit_jr-bot-network-health/
```

---

## 8. OPSCON Storage Structure

Recommended current structure:

```text
/OPSCON/data/
└── audit_jr-bot-network-health/
    ├── _security/
    │   ├── .htaccess
    │   └── ingest_token_sha256
    │
    ├── dmr/
    │   ├── audit_jr-bot-network-health-dmr.json
    │   └── history/
    │       └── audit_jr-bot-network-health-dmr-YYYYMMDD_HHMMSS.json
    │
    ├── ggb/
    │   ├── audit_jr-bot-network-health-ggb.json
    │   └── history/
    │       └── audit_jr-bot-network-health-ggb-YYYYMMDD_HHMMSS.json
    │
    └── trx/
        ├── audit_jr-bot-network-health-trx.json
        └── history/
            └── audit_jr-bot-network-health-trx-YYYYMMDD_HHMMSS.json
```

The `<instance>` folders can be created automatically by the API on first successful upload.

The required folders before first upload are:

```text
/OPSCON/data/audit_jr-bot-network-health/
/OPSCON/data/audit_jr-bot-network-health/_security/
```

The required security file is:

```text
/OPSCON/data/audit_jr-bot-network-health/_security/ingest_token_sha256
```

---

## 9. Token and Hash Security Model

The new endpoint does not store the original token in PHP.

Instead, it reads a SHA256 hash from:

```text
/OPSCON/data/audit_jr-bot-network-health/_security/ingest_token_sha256
```

Example content:

```text
9bdfb23776a56168e8cec2f98b6a28a323b80968ff20fd1851ee5c1e330667b6
```

Important:

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

---

## 10. JSON Root Structure

The script generates JSON with this high-level structure:

```json
{
  "schema": "jrbot-network-health-audit-v1",
  "script_version": "0.1.1",
  "instance": "dmr",
  "mode": "legacy",
  "created_at_utc": "2026-05-27T17:03:43Z",
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

## 11. JSON Block: `security`

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

## 12. JSON Block: `host`

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

## 13. JSON Block: `bot_context`

The `bot_context` block connects the network report to the bot installation.

Example:

```json
"bot_context": {
  "install_path": "/home/dmr/bots/DMR",
  "install_path_exists": true,
  "mode": "legacy"
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

## 14. JSON Block: `commands_available`

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

## 15. JSON Block: `network`

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
  "raw": "default via 192.168.178.1 dev wlan0 proto dhcp src 192.168.178.201 metric 1024 ",
  "gateway": "192.168.178.1",
  "interface": "wlan0",
  "source": "192.168.178.201"
}
```

---

## 16. JSON Block: `wifi`

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
ip_address=192.168.178.201
State: routable (configured)
Online state: online
Address: 192.168.178.201
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

## 17. JSON Block: `network_manager_cli`

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

For the One-Liner target, the preferred state should be decided explicitly:

```text
NetworkManager.service disabled
```

`disabled` is preferred over `masked` because it is easier to reverse.

---

## 18. JSON Block: `network_services`

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

## 19. JSON Block: `network_config_files`

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

```text
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

## 20. JSON Block: `systemd_integrity`

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

## 21. JSON Block: `package_versions`

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

## 22. JSON Block: `connectivity`

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

## 23. JSON Block: `raw_reference_commands`

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

## 24. JSON Block: `analysis`

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

## 25. JSON Block: `opscon_ingest`

The `opscon_ingest` block is added by the OPSCON endpoint.

Example:

```json
"opscon_ingest": {
  "received_at_utc": "2026-05-27T17:03:51Z",
  "source_ip": "78.142.65.122",
  "user_agent": "curl/7.88.1",
  "endpoint": "jrbot_audit_network_health_ingest.php",
  "mode_posted": "legacy",
  "audit_type": "audit_jr-bot-network-health",
  "storage_model": "single-current-file-plus-history"
}
```

This block confirms that the report was successfully uploaded and stored by OPSCON.

---

## 26. Findings and Recommendations

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

## 27. Known Finding Codes

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

## 28. Current State: DMR

State date: 2026-05-27

DMR currently has a healthy network state.

### Key Facts

```text
instance: dmr
mode: legacy
script_version: 0.1.1
health_state: ok
critical_count: 0
warning_count: 0
```

### Current IP Assignment

```text
DMR → 192.168.178.201
```

Evidence fields:

```text
hostname_I: 192.168.178.201
wlan0 inet: 192.168.178.201/24
default route source: 192.168.178.201
wpa_cli_status ip_address: 192.168.178.201
```

### Services

Healthy state:

```text
systemd-networkd.service       enabled + active + running
wpa_supplicant.service         enabled + active + running
wpa_supplicant@wlan0.service   enabled + active + running
ssh.service                    enabled + active + running
```

Expected inactive/unused:

```text
NetworkManager.service         masked + inactive
dhcpcd.service                 not-found
systemd-resolved.service       not-found
networking.service             not-found
```

### Connectivity

Healthy state:

```text
Gateway ping: successful
DNS google.com: successful
DNS domera.blenk.co.at: successful
HTTPS domera.blenk.co.at: HTTP 200
```

### Wi-Fi

Current DMR Wi-Fi values:

```text
SSID: home-gateway
Interface: wlan0
Frequency: 2437 MHz
Signal: -63 dBm
Link Quality: 47/70
Tx excessive retries: 0
Power Management: on
```

### Assessment

DMR is currently healthy.

The Fritzbox IP assignment is now correct:

```text
192.168.178.201
```

DMR remains a legacy bot in structure, but from a network health perspective it is stable.

---

## 29. Current State: GGB

State date: 2026-05-27

GGB also has a healthy network state based on the latest successful Network Health Audit.

### Key Facts

```text
instance: ggb
script_version: 0.1.1
health_state: ok
critical_count: 0
warning_count: 0
```

### Current IP Assignment

```text
GGB → 192.168.178.202
```

### Services

Expected healthy state:

```text
systemd-networkd.service       enabled + active + running
wpa_supplicant.service         active
wpa_supplicant@wlan0.service   enabled + active + running
ssh.service                    enabled + active + running
```

### Notable Difference From DMR

DMR:

```text
NetworkManager.service = masked
```

GGB:

```text
NetworkManager.service = disabled
```

Both are functional because both nodes use:

```text
systemd-networkd + wpa_supplicant
```

For the future target state, `disabled` is preferred over `masked`.

### GGB Repair Context

GGB previously required a repair involving `systemd-networkd` library resolution.

The Network Health Audit specifically checks:

```text
/lib/systemd/systemd-networkd
ldd /lib/systemd/systemd-networkd
libsystemd-shared-252.so
missing_libraries_detected
```

If the repair regresses, the script should detect it as a critical issue.

---

## 30. Planned Target State: TRX / One-Liner v0.3

TRX is the planned clean One-Liner target bot.

Expected IP assignment:

```text
TRX → 192.168.178.203
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

Expected OPSCON upload target:

```text
/OPSCON/data/audit_jr-bot-network-health/trx/audit_jr-bot-network-health-trx.json
/OPSCON/data/audit_jr-bot-network-health/trx/history/
```

Expected TRX test URL:

```text
https://trax.blenk.co.at
```

---

## 31. Repository Documentation Structure

Recommended GitHub repository structure:

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
docs/audits/audit_jr-bot-network-health.md
```

---

## 32. Local Documentation for Future JR-Agents

If a future JR-Agent runs locally on a bot, it should be able to read this handbook locally.

Recommended local structure:

```text
/opt/bots/<instance>/docs/audits/
├── audit_jr-bot-structure.md
├── audit_jr-bot-network-health.md
└── jrbot_boot_report.md
```

For legacy bots:

```text
/home/dmr/bots/DMR/docs/audits/audit_jr-bot-network-health.md
/home/ggb/bots/ggb/docs/audits/audit_jr-bot-network-health.md
```

Recommended local tools:

```text
/opt/bots/<instance>/tools/
├── audit_jr-bot-structure.sh
├── audit_jr-bot-network-health.sh
└── jrbot_boot_report.sh
```

Recommended local reports:

```text
/opt/bots/<instance>/reports/
├── audit_jr-bot-structure-current.json
├── audit_jr-bot-network-health-current.json
└── boot-report-current.json
```

---

## 33. Cleanup of Legacy OPSCON Structure

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

## 34. Recommended Interpretation for Agents

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
- firmware / Pi hardware behavior.
- whether the boot report catches the failure window.

---

## 35. Recommended Future Development

### Version 0.1.2

Possible improvements:

- Add `--print-summary` output to include primary IPv4 and default route.
- Add explicit `primary_ipv4` field.
- Add explicit `primary_mac` field with optional redaction mode.
- Add Wi-Fi RSSI classification.
- Add `power_management_on` parsed boolean.
- Add `ap_bssid` parsed field.
- Add `ssid` parsed field.
- Add `ip_expected` optional argument.

### Version 0.1.3

Possible improvements:

- Add comparison mode with previous local report.
- Add optional expected IP check:
  - DMR expected `192.168.178.201`
  - GGB expected `192.168.178.202`
  - TRX expected `192.168.178.203`
- Add optional expected gateway check.
- Add optional expected SSID check.

### Version 0.2.0

Possible improvements:

- Machine-readable recommendation categories.
- One-Liner network baseline validation.
- Agent-readable summary block.
- Optional local copy under `reports/`.
- Optional `--agent-summary` compact output.
- Support for Ethernet-first nodes.

---

## 36. Short Agent Summary

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

Healthy current assignments:

```text
DMR → 192.168.178.201
GGB → 192.168.178.202
TRX → 192.168.178.203 planned
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

The OPSCON storage path is:

```text
/OPSCON/data/audit_jr-bot-network-health/
```

The handbook belongs in GitHub:

```text
docs/audits/audit_jr-bot-network-health.md
```

Later it should also exist locally on each bot:

```text
/opt/bots/<instance>/docs/audits/audit_jr-bot-network-health.md
```
