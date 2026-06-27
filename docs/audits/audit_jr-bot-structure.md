# JR-Bot Structure Audit

Status: Contract defined / runtime validation pending
Script: `audits/audit_jr-bot-structure.sh`
Runtime version: pending validation
Schema version: `jrbot-structure-audit-v1`
Audit type: `audit_jr-bot-structure`
OPSCON ingest endpoint: `https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php`

## Purpose

The Structure audit is responsible for documenting and validating the file-system and runtime layout of a JR-Bot instance.

It is intended to verify whether a bot instance follows the expected One-Liner target structure or a supported legacy/hybrid layout.

The audit report is written locally first and can then be uploaded to OPSCON.

## Target layout

The current One-Liner target layout for a JR-Bot instance is:

```text
/opt/bots/<instance>/
├── audits/
├── config/
├── logs/
├── reports/
│   └── pending/
├── scripts/
└── runtime/
```

Example for TRX:

```text
/opt/bots/trx/
├── audits/
├── config/
├── logs/
├── reports/
│   └── pending/
├── scripts/
└── runtime/
```

## Expected runtime command

Target-layout execution should follow this pattern:

```bash
/opt/bots/<instance>/audits/audit_jr-bot-structure.sh \
  --instance <instance> \
  --path /opt/bots/<instance>
```

Example for TRX:

```bash
/opt/bots/trx/audits/audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx
```

## Expected supported options

The Structure audit should support at least:

```text
--instance <name>       Bot instance name, e.g. trx, dmr, ggb
--path <bot-path>       Bot install path, e.g. /opt/bots/trx
--legacy                Legacy mode for older DMR/GGB structures
--push-url <url>        Optional OPSCON structure ingest endpoint override
--token <token>         Optional OPSCON audit token for manual debugging
--output <file>         Optional output JSON file; file will be kept
--keep-local            Keep generated local JSON after successful upload
--print-json            Print full JSON to stdout
--print-summary         Print compact findings/recommendations summary
-h, --help              Show help
```

If the current runtime script differs, the script must be aligned before rollout.

## Output location

Default local pending output should be:

```text
<bot-path>/reports/pending/audit_jr-bot-structure-<instance>-YYYYMMDD_HHMMSS.json
```

Example:

```text
/opt/bots/trx/reports/pending/audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

After a successful upload, the local temporary report should be deleted unless `--keep-local` or `--output` was used.

## OPSCON storage layout

OPSCON stores Structure audit reports per audit type and per instance.

```text
/OPSCON/data/audit_jr-bot-structure/
└── <instance>/
    ├── _security/
    │   ├── .htaccess
    │   └── ingest_token_sha256
    ├── audit_jr-bot-structure-<instance>.json
    └── history/
        └── audit_jr-bot-structure-<instance>-YYYYMMDD_HHMMSS.json
```

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-structure/trx/_security/ingest_token_sha256
/OPSCON/data/audit_jr-bot-structure/trx/audit_jr-bot-structure-trx.json
/OPSCON/data/audit_jr-bot-structure/trx/history/
```

## Instance-scoped security contract

The ingest token hash must be stored per audit type and per instance:

```text
/OPSCON/data/audit_jr-bot-structure/<instance>/_security/ingest_token_sha256
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

## Expected token lookup order

The Structure audit should use the same D7.6 token lookup model as the other audit scripts.

Recommended lookup order:

```text
REPORT_UPLOAD_TOKEN
<bot-path>/config/audit_structure.token
<bot-path>/config/structure_upload.token
<bot-path>/config/report_upload.token
```

Example TRX fallback file:

```text
/opt/bots/trx/config/report_upload.token
```

The token file must exist only on the bot host and must not be committed to the public repository.

## Expected default upload endpoint

The Structure audit should use this default endpoint:

```text
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

It may be overridden by environment variable:

```text
STRUCTURE_AUDIT_PUSH_URL
```

or CLI argument:

```bash
--push-url <url>
```

## D7.6 Runtime Upload Hardening Requirement

The Structure audit must follow the same hardened upload contract as Boot Report and Network Health.

Forbidden runtime pattern:

```text
curl ... -F "token=${TOKEN}" ...
```

This pattern may expose the cleartext token through local process inspection tools such as:

```text
ps aux
systemctl status
/proc/<pid>/cmdline
```

Required runtime pattern:

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

Every Structure audit upload must define hard curl timeouts:

```text
connect-timeout = 10
max-time = 60
```

This prevents upload calls from hanging indefinitely.

## Expected upload form fields

The runtime upload should send:

```text
instance=<instance>
mode=<mode>
audit_file=@<json-file>;type=application/json
```

The token must be sent through:

```text
X-OPSCON-INGEST-TOKEN: <token>
```

The old multipart token field is deprecated for runtime usage.

## Expected schema

The uploaded JSON must use:

```text
jrbot-structure-audit-v1
```

The OPSCON ingest endpoint should reject mismatching schemas.

## Successful OPSCON response example

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

## Validation status

Structure runtime validation is still pending.

Required validation steps:

```text
1. Provision OPSCON server directory:
   /OPSCON/data/audit_jr-bot-structure/<instance>/

2. Provision instance-scoped security:
   /OPSCON/data/audit_jr-bot-structure/<instance>/_security/
   /OPSCON/data/audit_jr-bot-structure/<instance>/_security/ingest_token_sha256

3. Install or update runtime script on the bot host.

4. Run bash syntax check.

5. Run Structure audit without explicit --push-url and without explicit --token.

6. Verify OPSCON accepted the upload.

7. Verify local pending file handling.

8. Verify no token is visible through process arguments.
```

TRX validation target:

```text
Host: 192.168.178.203
Instance: trx
Path: /opt/bots/trx
Runtime user: trx
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
