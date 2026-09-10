# Network Health Audit

**Script:** `audits/audit_jr-bot-network-health.sh`
**Script version:** `0.3.0`
**Schema:** `jrbot-network-health-audit-v1`
**Public v1 storage:** local only

## Purpose

The Network Health Audit performs deep read-only diagnostics of a JR-Bot node's network stack. It collects interface, route, resolver, service, package, journal and connectivity evidence and produces findings/recommendations in JSON.

The collector does not transmit reports.

## Default storage

```text
/opt/bots/<instance>/reports/audits/
```

Example:

```text
audit_jr-bot-network-health-demo-YYYYMMDD_HHMMSS.json
```

## Usage

```bash
./audits/audit_jr-bot-network-health.sh   --instance demo   --path /opt/bots/demo   --print-summary
```

Supported options:

```text
--instance <name>
--path <bot-path>
--legacy
--mode <auto|target|legacy|hybrid>
--output <file>
--print-json
--print-summary
--test-url <url>
--gateway <ip>
--wifi-iface <iface>
--eth-iface <iface>
```

If `--path` is omitted, `/opt/bots/<instance>` is used.

`--test-url` is an optional connectivity probe selected by the user. It is not an audit destination and no report data is sent to it.

## Instance contract

```text
^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$
```

Input is only trimmed and lowercased before strict validation.

## Diagnostics

The collector can inspect, where available:

- IPv4/IPv6 interfaces and routes
- resolver state
- `systemd-networkd`
- NetworkManager
- `wpa_supplicant`
- `dhcpcd`
- `systemd-resolved`
- SSH service state
- Wi-Fi state through `iw`, `rfkill`, `networkctl` and `nmcli`
- relevant package versions
- recent service journal excerpts
- default-gateway reachability
- DNS resolution
- an optional user-selected HTTPS test URL

## Security

Network configuration text is sanitized before inclusion. The report declares:

```json
{
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false,
  "network_passwords_redacted": true
}
```

Generated reports can contain private addressing and host metadata and should not be committed to the repository.
