# JR-Bot Network Health Audit

Status: Active
Script: `audits/audit_jr-bot-network-health.sh`
Runtime version: `0.2.1`
Schema version: `jrbot-network-health-audit-v1`
Audit type: `audit_jr-bot-network-health`
OPSCON ingest endpoint: `https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php`

## Purpose

The Network Health audit creates a diagnostic JSON report for JR-Bot instances.

It checks the runtime network environment of a bot host, including local network configuration, gateway reachability, DNS/HTTPS availability, relevant systemd units, and related runtime diagnostics.

The report is written locally first and can then be uploaded to OPSCON.

## Runtime command

Typical target-layout execution:

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

Since runtime version `0.2.1`, the script supports unattended upload without explicitly passing `--push-url` or `--token`.

## Supported options

```text
--instance <name>       Bot instance name, e.g. trx, dmr, ggb
--path <bot-path>       Bot install path, e.g. /opt/bots/trx
--legacy                Legacy mode for older DMR/GGB structures
--push-url <url>        Optional OPSCON network health ingest endpoint override
--token <token>         Optional OPSCON audit token for manual debugging
--output <file>         Optional output JSON file; file will be kept
--keep-local            Keep generated local JSON after successful upload
--print-json            Print full JSON to stdout
--print-summary         Print compact findings/recommendations summary
--test-url <url>        Optional HTTPS URL to test
--gateway <ip>          Optional gateway override
--wifi-iface <iface>    Wi-Fi interface, default: wlan0
--eth-iface <iface>     Ethernet interface, default: eth0
-h, --help              Show help
```

## Output location

Default local pending output:

```text
<bot-path>/reports/pending/audit_jr-bot-network-health-<instance>-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-network-health-trx-20260627_091753.json
```

After a successful upload, the local temporary report is deleted unless `--keep-local` or `--output` was used.

## OPSCON storage layout

OPSCON stores Network Health audit reports per audit type and per instance.

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

## Instance-scoped security contract

The ingest token hash must be stored per audit type and per instance:

```text
/OPSCON/data/audit_jr-bot-network-health/<instance>/_security/ingest_token_sha256
```

The public ingest endpoint must not create `_security` or `ingest_token_sha256`.

If the instance directory, `_security` directory, or hash file is missing, empty, or invalid, the ingest endpoint must reject the upload with:

```json
{
  "success": false,
  "code": "INGEST_NOT_CONFIGURED"
}
```

## Instance validation

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
```

## Token lookup order

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

## Default upload endpoint

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
--push-url <url>
```

## D7.6 Runtime Upload Hardening

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

## Upload timeout contract

Every Network Health upload must define hard curl timeouts:

```text
connect-timeout = 10
max-time = 60
```

This prevents upload calls from hanging indefinitely.

## Expected upload form fields

The runtime upload sends:

```text
instance=<instance>
mode=<mode>
audit_file=@<json-file>;type=application/json
```

The token is sent through:

```text
X-OPSCON-INGEST-TOKEN: <token>
```

The old multipart token field is deprecated for runtime usage.

## Expected schema

The uploaded JSON must use:

```text
jrbot-network-health-audit-v1
```

The OPSCON ingest endpoint should reject mismatching schemas.

## Successful OPSCON response example

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

## Validation performed on TRX

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
token loaded from local config/report_upload.token
OPSCON accepted instance-scoped token
local pending file deleted after successful upload
pending_count=0
```

Validated runtime version:

```text
audit_jr-bot-network-health.sh: 0.2.1
```

## Public repository safety rules

The public repository must never contain:

```text
cleartext ingest tokens
SHA256 ingest token hashes
production .env files
generated local token files
generated pending audit JSON files
```

Token files belong only on the bot host.

Token hashes belong only in the OPSCON server-side `_security` directory.
