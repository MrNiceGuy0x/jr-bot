# JR-Bot / OPSCON Audit Ingest Contract

Status: Active
Scope: JR-Bot public runtime, OPSCON audit ingest, OPSCON onboarding
Security level: Public documentation without secrets

---

## 1. Purpose

This document defines the mandatory contract between JR-Bot audit scripts and OPSCON audit ingest endpoints.

It exists to prevent regressions in audit report path handling, upload retry behavior, token lookup order, per-instance security isolation, and public/private secret separation.

---

## 2. Supported audit types

- audit_jr-bot-boot-report
- audit_jr-bot-network-health
- audit_jr-bot-structure

Each audit type has its own OPSCON storage root:

```text
/OPSCON/data/<audit-type>/
```

Example:

```text
/OPSCON/data/audit_jr-bot-boot-report/
```

---

## 3. Mandatory instance-specific storage layout

Audit reports and ingest security material must be stored per bot instance.

Correct layout:

```text
/OPSCON/data/<audit-type>/<instance>/
/OPSCON/data/<audit-type>/<instance>/_security/
/OPSCON/data/<audit-type>/<instance>/_security/ingest_token_sha256
```

Example for TRX boot reports:

```text
/OPSCON/data/audit_jr-bot-boot-report/trx/_security/ingest_token_sha256
```

Forbidden layout:

```text
/OPSCON/data/<audit-type>/_security/ingest_token_sha256
```

A global audit-type token would force all JR-Bot instances of the same audit type to share one upload token. This breaks per-instance isolation.

---

## 4. Public ingest validation order

Every public OPSCON audit ingest endpoint must follow this order:

1. Accept POST only.
2. Read instance from the request.
3. Normalize and validate instance.
4. Resolve the instance directory.
5. Read the expected token hash from the instance-specific _security directory.
6. Read the upload token from POST data or a supported request header.
7. Compare hash(sha256, token) with ingest_token_sha256 using constant-time comparison.
8. Validate the uploaded audit JSON.
9. Store the report under the instance-specific audit directory.
10. Update latest.json only after successful authentication and validation.

The endpoint must not validate the token before the instance is known.

---

## 5. Instance validation

The instance value must be treated as untrusted input.

Recommended validation:

```text
^[a-z0-9][a-z0-9_-]{0,63}$
```

The endpoint must reject empty names, path traversal, slashes, backslashes, dots as path components, whitespace-only values, and resolved paths outside the audit storage root.

---

## 6. Security directory creation rule

Public ingest endpoints must never auto-create _security directories.

Forbidden behavior:

```text
POST /api/jrbot_audit_*_ingest.php
-> creates /OPSCON/data/<audit-type>/<instance>/_security/
```

Allowed behavior:

- OPSCON admin/onboarding tooling may create _security.
- apps.php, monitor.php, or a future internal OPSCON onboarding endpoint may provision instance directories.
- Public ingest may create non-security report directories only after successful authentication.

---

## 7. Token handling

The public JR-Bot repository must never contain real upload tokens, token hashes, .env files, config.ini credentials, report_upload.token, or ingest_token_sha256.

The server stores only the SHA-256 hash:

```text
/OPSCON/data/<audit-type>/<instance>/_security/ingest_token_sha256
```

The bot stores the clear upload token locally, normally under:

```text
<bot-path>/config/audit_boot_report.token
<bot-path>/config/boot_report_upload.token
<bot-path>/config/report_upload.token
```

Recommended permissions:

```text
chmod 600 <token-file>
chown <instance>:<instance> <token-file>
```

---

## 8. Upload retry behavior

--mode upload-pending is a retry-only mode.

Mandatory rule:

```text
--mode upload-pending must never create a new audit report.
```

For boot reports, the systemd retry service calls:

```text
audit_jr-bot-boot-report.sh --instance <instance> --path <bot-path> --mode upload-pending
```

Expected behavior:

1. Find existing pending reports.
2. Try to upload existing pending reports.
3. Delete successfully uploaded reports unless --keep-local is set.
4. Keep failed reports locally.
5. Exit without generating a new report.

This prevents unbounded pending report growth when OPSCON rejects uploads or is temporarily unavailable.

---

## 9. Normal report-producing behavior

Normal report-producing modes may create a new report and then attempt to upload all pending reports.

Current report-producing modes:

```text
auto
legacy
target
hybrid
migrate
test
boot
```

Compatibility aliases may exist, but they must not break retry-only behavior.

---

## 10. OPSCON ingest endpoints

Boot report endpoint:

```text
/OPSCON/api/jrbot_audit_boot_report_ingest.php
/OPSCON/data/audit_jr-bot-boot-report/
```

Network health endpoint:

```text
/OPSCON/api/jrbot_audit_network_health_ingest.php
/OPSCON/data/audit_jr-bot-network-health/
```

Structure endpoint:

```text
/OPSCON/api/jrbot_audit_structure_ingest.php
/OPSCON/data/audit_jr-bot-structure/
```

Each endpoint must use the same instance-specific security model.

---

## 11. Failure behavior

Recommended HTTP status codes:

```text
405 Method Not Allowed     non-POST request
400 Bad Request            invalid instance or malformed request
403 Forbidden              missing/invalid token or missing instance security hash
422 Unprocessable Entity   invalid audit JSON
500 Internal Server Error  storage/write failure after successful authentication
200 OK                     accepted report
```

The endpoint must not reveal whether a specific instance exists, whether a hash file exists, or which part of token validation failed.

---

## 12. Public repository requirements

The public repository may document placeholders only:

```text
<sha256(REPORT_UPLOAD_TOKEN)>
<REPORT_UPLOAD_TOKEN>
<instance>
<audit-type>
```

The repository .gitignore must protect at least:

```text
report_upload.token
*.token
*.secret
.env
config.ini
ingest_token_sha256
OPSCON/data/**/_security/**
audits/*.pre-d7-backup
```

---

## 13. D7 regression checks

Before enabling a retry timer on a bot instance, verify:

```text
bash -n audits/audit_jr-bot-boot-report.sh
```

Verify that upload-pending does not create a new report:

```text
before=$(find <bot-path>/reports/pending -maxdepth 1 -type f -name "*.json" | wc -l)
audits/audit_jr-bot-boot-report.sh --instance <instance> --path <bot-path> --mode upload-pending
after=$(find <bot-path>/reports/pending -maxdepth 1 -type f -name "*.json" | wc -l)
test "$before" = "$after"
```

Only start or restart the retry timer after the corresponding OPSCON ingest endpoint uses instance-specific token validation.
