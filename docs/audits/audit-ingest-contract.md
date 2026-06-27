# JR-Bot Audit Ingest Contract Handbook

**Status:** Active / audit layer contract ready for closed-repo transfer
**Handbook Version:** 1.0
**Contract Version:** D7.6
**Project:** JR-Bot / OPSCON
**Recommended Repository Path:** `docs/audits/audit-ingest-contract.md`
**Related Runtime Scripts:** `audits/audit_jr-bot-boot-report.sh`, `audits/audit_jr-bot-network-health.sh`, `audits/audit_jr-bot-structure.sh`
**Related Handbooks:** `docs/audits/audit_jr-bot-boot-report.md`, `docs/audits/audit_jr-bot-network-health.md`, `docs/audits/audit_jr-bot-structure.md`
**Scope:** Shared OPSCON ingest contract for all JR-Bot audit uploads
**Last Updated:** 2026-06-27

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Role in the JR-Bot / OPSCON Audit Layer](#2-role-in-the-jr-bot--opscon-audit-layer)
3. [Contract Summary](#3-contract-summary)
4. [Audit Types Covered](#4-audit-types-covered)
5. [Runtime Script Mapping](#5-runtime-script-mapping)
6. [Endpoint Mapping](#6-endpoint-mapping)
7. [Schema Mapping](#7-schema-mapping)
8. [OPSCON Storage Model](#8-opscon-storage-model)
9. [Instance-Scoped Security Model](#9-instance-scoped-security-model)
10. [Server-Side Security Assets](#10-server-side-security-assets)
11. [Bot-Side Token Model](#11-bot-side-token-model)
12. [Token Lookup Order](#12-token-lookup-order)
13. [HTTP Method Contract](#13-http-method-contract)
14. [Instance Validation Contract](#14-instance-validation-contract)
15. [Token Transport Contract](#15-token-transport-contract)
16. [D7.6 Runtime Upload Hardening](#16-d76-runtime-upload-hardening)
17. [Upload Payload Contract](#17-upload-payload-contract)
18. [JSON Safety Contract](#18-json-safety-contract)
19. [Schema Validation Contract](#19-schema-validation-contract)
20. [OPSCON Ingest Validation Order](#20-opscon-ingest-validation-order)
21. [Storage Write Contract](#21-storage-write-contract)
22. [Expected Success Response](#22-expected-success-response)
23. [Expected Error Responses](#23-expected-error-responses)
24. [Pending Report Behavior](#24-pending-report-behavior)
25. [Boot Report Upload-Pending Contract](#25-boot-report-upload-pending-contract)
26. [Public Ingest Endpoint Rules](#26-public-ingest-endpoint-rules)
27. [Public vs Closed Repository Boundary](#27-public-vs-closed-repository-boundary)
28. [Public Repository Safety Rules](#28-public-repository-safety-rules)
29. [Closed OPSCON Repository Contents](#29-closed-opscon-repository-contents)
30. [Onboarding Requirements](#30-onboarding-requirements)
31. [Rotation and Future Token Hardening](#31-rotation-and-future-token-hardening)
32. [Agent Interpretation Rules](#32-agent-interpretation-rules)
33. [Validation Checklist](#33-validation-checklist)
34. [Closed-Repo Transfer Checklist](#34-closed-repo-transfer-checklist)
35. [Recommended Future Development](#35-recommended-future-development)
36. [Short Agent Summary](#36-short-agent-summary)

---

## 1. Purpose

This document defines the shared OPSCON ingest contract for the JR-Bot audit layer.

It is the common reference for how JR-Bot audit scripts upload reports to OPSCON and how OPSCON must authenticate, validate and store those reports.

The contract applies to:

```text
audit_jr-bot-boot-report
audit_jr-bot-network-health
audit_jr-bot-structure
```

It defines:

- audit type names,
- endpoint names,
- expected JSON schemas,
- runtime script paths,
- bot-side token lookup,
- server-side token-hash location,
- instance validation,
- upload payload fields,
- header-based token transport,
- D7.6 curl hardening,
- latest-plus-history storage,
- public repository safety rules,
- closed OPSCON repository transfer requirements.

This handbook is intentionally cross-cutting. The individual audit handbooks remain the deeper documentation for each audit script.

---

## 2. Role in the JR-Bot / OPSCON Audit Layer

The JR-Bot audit layer has three runtime scripts and one shared ingest contract.

| Layer | Responsibility |
|---|---|
| Runtime script | Create read-only JSON report on a bot host. |
| Runtime upload | Upload report to the correct OPSCON endpoint. |
| OPSCON ingest endpoint | Authenticate, validate and store the report. |
| OPSCON storage | Keep one latest report plus timestamped history. |
| Handbooks | Document runtime behavior, storage, security and validation. |

The individual audit scripts answer different operational questions:

| Audit Type | Question |
|---|---|
| `audit_jr-bot-boot-report` | Did the node come back correctly after boot? |
| `audit_jr-bot-network-health` | Is the node network-healthy? |
| `audit_jr-bot-structure` | Is the bot installation structurally correct? |

This contract answers the shared integration question:

> How do all audit reports enter OPSCON safely and consistently?

---

## 3. Contract Summary

The current contract is:

```text
POST only
multipart file upload
instance required
strict instance validation
token sent via X-OPSCON-INGEST-TOKEN
token hash stored per audit type and per instance
server compares sha256(token) against stored hash
JSON must match expected schema
JSON must declare read-only and secret-redaction safety flags
latest report is overwritten
history report is appended
public ingest must not auto-create _security
public ingest must not auto-create ingest_token_sha256
```

The current bot-side token strategy is:

```text
one central per-bot fallback token file:
  /opt/bots/{instance}/config/report_upload.token
```

Audit-specific token files are supported as future or optional hardening.

---

## 4. Audit Types Covered

The contract covers these audit types:

| Audit Type | Runtime Version Reference | Schema |
|---|---:|---|
| `audit_jr-bot-boot-report` | `0.2.2` | `jrbot-boot-report-audit-v1` |
| `audit_jr-bot-network-health` | `0.2.1` | `jrbot-network-health-audit-v1` |
| `audit_jr-bot-structure` | `0.2.0` | `jrbot-structure-audit-v1` |

The `audit_type` string is part of the storage contract and must remain stable unless an intentional migration is performed.

---

## 5. Runtime Script Mapping

Current target runtime scripts:

```text
audits/audit_jr-bot-boot-report.sh
audits/audit_jr-bot-network-health.sh
audits/audit_jr-bot-structure.sh
```

Target local paths on a JR-Bot node:

```text
/opt/bots/{instance}/audits/audit_jr-bot-boot-report.sh
/opt/bots/{instance}/audits/audit_jr-bot-network-health.sh
/opt/bots/{instance}/audits/audit_jr-bot-structure.sh
```

Legacy paths may exist during migration, but they are not the canonical target.

---

## 6. Endpoint Mapping

Current OPSCON endpoints:

| Audit Type | Endpoint |
|---|---|
| `audit_jr-bot-boot-report` | `/OPSCON/api/jrbot_audit_boot_report_ingest.php` |
| `audit_jr-bot-network-health` | `/OPSCON/api/jrbot_audit_network_health_ingest.php` |
| `audit_jr-bot-structure` | `/OPSCON/api/jrbot_audit_structure_ingest.php` |

Full URLs:

```text
https://opscon.blenk.co.at/api/jrbot_audit_boot_report_ingest.php
https://opscon.blenk.co.at/api/jrbot_audit_network_health_ingest.php
https://opscon.blenk.co.at/api/jrbot_audit_structure_ingest.php
```

The endpoint name must match the audit type and storage folder.

---

## 7. Schema Mapping

Expected schema per audit type:

| Audit Type | Expected Schema |
|---|---|
| `audit_jr-bot-boot-report` | `jrbot-boot-report-audit-v1` |
| `audit_jr-bot-network-health` | `jrbot-network-health-audit-v1` |
| `audit_jr-bot-structure` | `jrbot-structure-audit-v1` |

The ingest endpoint must reject a report if:

```text
JSON is invalid
schema is missing
schema does not match the endpoint
security flags are invalid
instance inside JSON conflicts with posted instance
```

---

## 8. OPSCON Storage Model

Current storage root:

```text
/OPSCON/data/
```

Per audit type:

```text
/OPSCON/data/audit_jr-bot-boot-report/
/OPSCON/data/audit_jr-bot-network-health/
/OPSCON/data/audit_jr-bot-structure/
```

Per instance:

```text
/OPSCON/data/{audit_type}/{instance}/
```

Latest report:

```text
/OPSCON/data/{audit_type}/{instance}/{audit_type}-{instance}.json
```

History report:

```text
/OPSCON/data/{audit_type}/{instance}/history/{audit_type}-{instance}-YYYYMMDD_HHMMSS.json
```

Concrete TRX examples:

```text
/OPSCON/data/audit_jr-bot-boot-report/trx/audit_jr-bot-boot-report-trx.json
/OPSCON/data/audit_jr-bot-network-health/trx/audit_jr-bot-network-health-trx.json
/OPSCON/data/audit_jr-bot-structure/trx/audit_jr-bot-structure-trx.json
```

---

## 9. Instance-Scoped Security Model

The valid security model is audit-type-specific and instance-specific.

Correct model:

```text
/OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
```

Invalid legacy/global model:

```text
/OPSCON/data/{audit_type}/_security/ingest_token_sha256
```

Reason:

```text
A global hash per audit type would force all bots to share the same upload token for that audit type.
The current model allows each bot instance to have its own token identity while still using the same endpoint code.
```

---

## 10. Server-Side Security Assets

For every valid audit type and instance, OPSCON must have:

```text
/OPSCON/data/{audit_type}/{instance}/_security/
/OPSCON/data/{audit_type}/{instance}/_security/.htaccess
/OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
```

Recommended `.htaccess` content:

```apache
Require all denied
```

The hash file must contain:

```text
{sha256_ORIGINAL_UPLOAD_TOKEN}
```

Rules:

```text
no quotes
no PHP code
no spaces before or after
no cleartext token
no comments
one hash value only
```

The original upload token must exist only on the bot host or in a trusted secret provisioning process.

---

## 11. Bot-Side Token Model

The current validated bot-side model uses one central fallback token file per bot instance:

```text
/opt/bots/{instance}/config/report_upload.token
```

Recommended permissions:

```bash
sudo chown {instance}:{instance} /opt/bots/{instance}/config/report_upload.token
sudo chmod 600 /opt/bots/{instance}/config/report_upload.token
```

Example for TRX:

```bash
sudo chown trx:trx /opt/bots/trx/config/report_upload.token
sudo chmod 600 /opt/bots/trx/config/report_upload.token
```

This central token is sufficient for the current local-network JR-Bot threat model.

Audit-specific token files remain supported as optional future hardening.

---

## 12. Token Lookup Order

Boot Report:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_boot_report.token
{bot_path}/config/boot_report_upload.token
{bot_path}/config/report_upload.token
```

Network Health:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_network_health.token
{bot_path}/config/network_health_upload.token
{bot_path}/config/report_upload.token
```

Structure:

```text
REPORT_UPLOAD_TOKEN
{bot_path}/config/audit_structure.token
{bot_path}/config/structure_upload.token
{bot_path}/config/report_upload.token
```

The common fallback is:

```text
{bot_path}/config/report_upload.token
```

No token file may be committed to GitHub.

---

## 13. HTTP Method Contract

Every audit ingest endpoint must accept only:

```text
POST
```

Rejected methods should return a structured JSON error such as:

```json
{
  "success": false,
  "code": "METHOD_NOT_ALLOWED",
  "message": "Only POST is allowed."
}
```

The endpoint must not accept report upload via `GET`.

---

## 14. Instance Validation Contract

The `instance` field is required.

It must be read before token lookup and before any file path is constructed.

Recommended regex:

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
trx.example
trx/test
trx/../../x
```

Invalid instances must be rejected before any storage path is used.

Recommended error:

```json
{
  "success": false,
  "code": "INVALID_INSTANCE",
  "message": "Invalid instance."
}
```

---

## 15. Token Transport Contract

The current hardened runtime sends the token in the HTTP header:

```text
X-OPSCON-INGEST-TOKEN: {token}
```

The old multipart form field is deprecated:

```text
token={token}
```

The endpoint may keep temporary backward-compatible support for multipart `token` during migration.

The runtime scripts should use only the header-based token transport.

The endpoint should return the token source in successful response metadata:

```json
"token_source": "header"
```

---

## 16. D7.6 Runtime Upload Hardening

The previous unsafe pattern was:

```text
curl ... -F "token=${TOKEN}" ...
```

That may expose the cleartext token through local process inspection tools:

```text
ps aux
systemctl status
/proc/{pid}/cmdline
```

Required current pattern:

```text
curl --config {temporary_curl_config}
```

Runtime requirements:

```text
create temporary curl config with mktemp
chmod 600 the temporary curl config
send X-OPSCON-INGEST-TOKEN header from the curl config
define connect-timeout = 10
define max-time = 60
delete the temporary curl config after upload
do not print token
do not echo token
do not place token in a visible process argument
```

Timeout contract:

```text
connect-timeout = 10
max-time = 60
```

Remaining sensitive assets:

```text
/opt/bots/{instance}/config/report_upload.token
temporary curl config while the upload is running
OPSCON server-side _security/ingest_token_sha256
server logs, if misconfigured
old Git history, if secrets were ever committed
```

---

## 17. Upload Payload Contract

The runtime upload sends multipart form data:

```text
instance={instance}
mode={mode}
audit_file=@{json_file};type=application/json
```

Required fields:

| Field | Required | Meaning |
|---|---:|---|
| `instance` | Yes | Bot instance, for example `trx`. |
| `mode` | Recommended | Runtime mode marker, for example `target`, `legacy`, `upload-pending`. |
| `audit_file` | Yes | Uploaded JSON report file. |

Deprecated field:

```text
token
```

The token must be transported by header.

---

## 18. JSON Safety Contract

Uploaded reports must declare the safety block.

Required common fields:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

Additional audit-specific safety fields are allowed.

Example for Network Health:

```json
"security": {
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false,
  "network_passwords_redacted": true
}
```

The endpoint should reject a report if:

```text
read_only is not true
secrets_redacted is not true
secret_values_included is not false
```

Recommended error:

```json
{
  "success": false,
  "code": "UNSAFE_REPORT",
  "message": "Report does not satisfy the safety contract."
}
```

---

## 19. Schema Validation Contract

Each endpoint must validate that the uploaded report uses the expected schema.

| Endpoint | Expected Schema |
|---|---|
| `jrbot_audit_boot_report_ingest.php` | `jrbot-boot-report-audit-v1` |
| `jrbot_audit_network_health_ingest.php` | `jrbot-network-health-audit-v1` |
| `jrbot_audit_structure_ingest.php` | `jrbot-structure-audit-v1` |

Recommended error:

```json
{
  "success": false,
  "code": "SCHEMA_MISMATCH",
  "message": "Unexpected audit schema."
}
```

---

## 20. OPSCON Ingest Validation Order

The endpoint must validate in this order:

1. Allow only `POST`.
2. Read `instance` from request.
3. Strictly validate `instance`.
4. Resolve audit type from endpoint.
5. Resolve instance directory.
6. Read instance-specific hash file:
   ```text
   /OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
   ```
7. Read token from `X-OPSCON-INGEST-TOKEN`.
8. Optionally read legacy multipart `token` during migration only.
9. Compare `sha256(token)` against stored hash using constant-time comparison.
10. Validate `audit_file` exists in upload.
11. Parse uploaded JSON.
12. Validate `schema`.
13. Validate `instance` consistency between POST and JSON, if present.
14. Validate `security` flags.
15. Add `opscon_ingest` metadata.
16. Create runtime storage directories if needed.
17. Write latest report.
18. Write history report.
19. Return structured JSON response.

The endpoint must reject before writing any report if authentication or validation fails.

---

## 21. Storage Write Contract

After successful authentication and validation, the endpoint writes:

```text
latest:
  /OPSCON/data/{audit_type}/{instance}/{audit_type}-{instance}.json

history:
  /OPSCON/data/{audit_type}/{instance}/history/{audit_type}-{instance}-YYYYMMDD_HHMMSS.json
```

The endpoint may create:

```text
/OPSCON/data/{audit_type}/{instance}/history/
```

The endpoint must not create:

```text
/OPSCON/data/{audit_type}/{instance}/_security/
/OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
```

The reason is simple:

```text
_security is a trust anchor.
Public upload endpoints must never provision trust anchors for arbitrary instances.
```

---

## 22. Expected Success Response

Successful response shape:

```json
{
  "success": true,
  "message": "JR-Bot audit stored successfully.",
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

Required success fields:

| Field | Meaning |
|---|---|
| `success` | Must be `true`. |
| `instance` | Accepted instance. |
| `mode` | Posted mode marker. |
| `audit_type` | Accepted audit type. |
| `expected_schema` | Schema expected by endpoint. |
| `stored_file` | Latest report path. |
| `history_file` | History report path. |
| `token_scope` | Must be `instance`. |
| `token_source` | Should be `header`. |
| `received_at_utc` | Server-side receive timestamp. |

---

## 23. Expected Error Responses

Recommended error codes:

| Code | Meaning |
|---|---|
| `METHOD_NOT_ALLOWED` | Request method is not POST. |
| `INVALID_INSTANCE` | Instance is missing or invalid. |
| `INGEST_NOT_CONFIGURED` | Instance security hash is missing, empty or invalid. |
| `MISSING_TOKEN` | No token was supplied. |
| `INVALID_TOKEN` | Supplied token does not match stored hash. |
| `MISSING_AUDIT_FILE` | `audit_file` was not uploaded. |
| `INVALID_JSON` | Uploaded file is not valid JSON. |
| `SCHEMA_MISMATCH` | Uploaded schema does not match endpoint. |
| `UNSAFE_REPORT` | Safety flags are invalid. |
| `INSTANCE_MISMATCH` | Posted instance differs from JSON instance. |
| `WRITE_FAILED` | Storage write failed after validation. |

Recommended error response shape:

```json
{
  "success": false,
  "code": "INVALID_TOKEN",
  "message": "Invalid or missing audit token."
}
```

Error responses must not reveal:

```text
stored hash
expected hash
token length
full server path if not needed
cleartext token
```

---

## 24. Pending Report Behavior

Runtime scripts should create a local JSON file before upload.

Recommended pending directory:

```text
/opt/bots/{instance}/reports/pending/
```

Pending filename pattern:

```text
{audit_type}-{instance}-YYYYMMDD_HHMMSS.json
```

Examples:

```text
audit_jr-bot-boot-report-trx-YYYYMMDD_HHMMSS.json
audit_jr-bot-network-health-trx-YYYYMMDD_HHMMSS.json
audit_jr-bot-structure-trx-YYYYMMDD_HHMMSS.json
```

Expected behavior:

```text
upload success -> local temporary report deleted unless --keep-local or --output
upload failure -> local report remains for retry/debugging
```

The Boot Report has the most important pending behavior because it may run before network is ready.

---

## 25. Boot Report Upload-Pending Contract

The Boot Report has a strict retry mode:

```text
--mode upload-pending
```

Contract:

```text
upload-pending only uploads existing pending boot reports
upload-pending never creates a new boot report
```

This matters because a retry timer must not create artificial boot reports every 15 minutes.

Expected behavior:

```text
no new JSON report is created
existing pending boot reports are uploaded
successful uploads are deleted
failed uploads remain pending
```

This is a hard runtime requirement.

---

## 26. Public Ingest Endpoint Rules

A public ingest endpoint may:

```text
accept POST uploads
read instance
authenticate by token hash
validate JSON
create history directory
write latest report
write history report
return structured JSON
```

A public ingest endpoint must not:

```text
auto-create _security
auto-create ingest_token_sha256
accept GET uploads
store cleartext tokens
return stored hashes
execute uploaded content
trust JSON before authentication
trust instance before validation
write outside the audit storage root
```

---

## 27. Public vs Closed Repository Boundary

The public `jr-bot` repository may contain the validated audit scripts and documentation as long as it contains no secrets.

The closed OPSCON repository may contain the operational OPSCON integration code and endpoint implementation details.

The closed repository is the correct destination for:

```text
PHP ingest endpoints
OPSCON admin/onboarding helpers
server-side provisioning tools
private deployment notes
World4You-specific deployment scripts
closed production runbooks
```

Even in the closed repository, cleartext production tokens should not be committed.

The closed repository reduces exposure, but it does not remove the need for secret hygiene.

---

## 28. Public Repository Safety Rules

The public repository must never contain:

```text
cleartext ingest tokens
SHA256 ingest token hashes
production .env files
generated local token files
generated pending audit JSON files
private OPSCON security files
local temporary curl config files
server-side production-only secrets
```

The public repository may contain:

```text
audits/audit_jr-bot-boot-report.sh
audits/audit_jr-bot-network-health.sh
audits/audit_jr-bot-structure.sh
docs/audits/audit_jr-bot-boot-report.md
docs/audits/audit_jr-bot-network-health.md
docs/audits/audit_jr-bot-structure.md
docs/audits/audit-ingest-contract.md
placeholder token names
example config templates without secrets
```

Allowed placeholders:

```text
{ORIGINAL_UPLOAD_TOKEN}
{sha256_ORIGINAL_UPLOAD_TOKEN}
{instance}
{bot_path}
{audit_type}
{json_file}
```

Never use real tokens or real hashes in examples.

---

## 29. Closed OPSCON Repository Contents

The closed OPSCON repository should contain the final operational OPSCON layer, including:

```text
api/jrbot_audit_boot_report_ingest.php
api/jrbot_audit_network_health_ingest.php
api/jrbot_audit_structure_ingest.php
docs/audits/audit-ingest-contract.md
docs/audits/audit_jr-bot-boot-report.md
docs/audits/audit_jr-bot-network-health.md
docs/audits/audit_jr-bot-structure.md
deployment notes
server-side onboarding scripts
admin UI integration notes
```

It should not contain:

```text
cleartext tokens
real ingest_token_sha256 files
production _security directories copied from server
temporary upload files
generated report history
```

If a real hash must be provisioned, it should be created on the server by a trusted process, not stored as source code.

---

## 30. Onboarding Requirements

Before a bot can upload audit reports, OPSCON must have security assets for each enabled audit type.

For each bot instance and audit type:

```text
/OPSCON/data/{audit_type}/{instance}/_security/.htaccess
/OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
```

For a central per-bot token, the same original token may be hashed into each audit type's instance security file.

Example for TRX:

```text
/OPSCON/data/audit_jr-bot-boot-report/trx/_security/ingest_token_sha256
/OPSCON/data/audit_jr-bot-network-health/trx/_security/ingest_token_sha256
/OPSCON/data/audit_jr-bot-structure/trx/_security/ingest_token_sha256
```

The bot host must have:

```text
/opt/bots/trx/config/report_upload.token
```

with:

```text
owner: trx:trx
mode: 600
```

---

## 31. Rotation and Future Token Hardening

Current validated model:

```text
one central per-bot upload token
same token accepted across enabled audit types for that instance
server stores per-audit/per-instance SHA256 hash
```

Optional next hardening step:

```text
one token per audit type
```

This would use:

```text
audit_boot_report.token
audit_network_health.token
audit_structure.token
```

A true one-time-token model is not compatible with static `ingest_token_sha256` files alone.

A one-time or rotating token model would require one of:

```text
server-side rotating state
TOTP/HOTP shared secret
short-lived challenge-response
asymmetric signed payloads
OPSCON-issued upload session token
```

This is optional future hardening and not required for the current JR-Bot local-network threat model.

---

## 32. Agent Interpretation Rules

Agents must treat this contract as the shared integration source of truth.

Important rules:

```text
security path is per audit type and per instance
bot-side token fallback is report_upload.token
token transport is X-OPSCON-INGEST-TOKEN
public endpoint must not auto-create _security
schema must match endpoint
read-only safety flags are mandatory
latest plus history storage is mandatory
```

Agents must not infer that a missing `_security` directory should be auto-created by the public endpoint.

If `_security` or `ingest_token_sha256` is missing, the correct result is:

```text
INGEST_NOT_CONFIGURED
```

---

## 33. Validation Checklist

Repository validation:

```bash
git status --short
git diff --check
```

Runtime script checks:

```bash
bash -n audits/audit_jr-bot-boot-report.sh
bash -n audits/audit_jr-bot-network-health.sh
bash -n audits/audit_jr-bot-structure.sh
```

Contract grep checks:

```bash
grep -R "X-OPSCON-INGEST-TOKEN" audits docs/audits
grep -R "report_upload.token" audits docs/audits
grep -R "ingest_token_sha256" docs/audits
grep -R "upload-pending" audits/audit_jr-bot-boot-report.sh docs/audits
```

Secret grep checks:

```bash
grep -R -n -E "[a-f0-9]{64}" .
grep -R -n -i "cleartext token\|password=\|psk=\|secret=" .
```

The grep for 64-character hex strings must be interpreted carefully because placeholder examples may exist. Real production hashes must not exist in the repository.

---

## 34. Closed-Repo Transfer Checklist

Before copying the audit layer into the closed OPSCON repository:

1. Confirm public repo `main` is clean.
2. Confirm all three audit scripts exist under `audits/`.
3. Confirm all three individual handbooks exist under `docs/audits/`.
4. Confirm this contract exists under `docs/audits/audit-ingest-contract.md`.
5. Confirm `git diff --check` is clean.
6. Confirm no real token is present.
7. Confirm no real SHA256 token hash is present.
8. Confirm Boot Report `upload-pending` contract is documented.
9. Confirm instance-scoped `_security` model is documented.
10. Confirm closed repo target paths are defined.
11. Copy only source scripts, docs and safe templates.
12. Do not copy runtime `reports/pending/`.
13. Do not copy OPSCON production `_security/`.
14. Do not copy local token files.
15. Do not copy temporary curl config files.
16. Re-run secret grep in the closed repo after copy.

Recommended copy set:

```text
audits/
docs/audits/
```

Optional later copy set:

```text
api/
admin/onboarding/
deployment/
```

depending on the closed repository structure.

---

## 35. Recommended Future Development

### Contract Version D7.7

Possible improvements:

- Explicit PHP shared helper for ingest validation.
- Central `AuditIngestContract.php`.
- Unit tests for instance validation.
- Unit tests for schema mismatch handling.
- Unit tests for `INGEST_NOT_CONFIGURED`.
- Endpoint self-test mode without accepting uploads.
- OPSCON admin UI for provisioning instance `_security`.

### Contract Version D8.0

Possible improvements:

- Audit-specific tokens by default.
- Token rotation support.
- Optional signed report payloads.
- Optional asymmetric bot identity keys.
- Optional replay detection by report id or boot id.
- Central audit registry for schemas, endpoints and storage roots.

---

## 36. Short Agent Summary

This file is the shared ingest contract for the JR-Bot audit layer.

It covers:

```text
audit_jr-bot-boot-report
audit_jr-bot-network-health
audit_jr-bot-structure
```

Current endpoint model:

```text
/OPSCON/api/jrbot_audit_boot_report_ingest.php
/OPSCON/api/jrbot_audit_network_health_ingest.php
/OPSCON/api/jrbot_audit_structure_ingest.php
```

Current storage model:

```text
/OPSCON/data/{audit_type}/{instance}/
/OPSCON/data/{audit_type}/{instance}/history/
/OPSCON/data/{audit_type}/{instance}/_security/ingest_token_sha256
```

Current bot-side token fallback:

```text
/opt/bots/{instance}/config/report_upload.token
```

Current token transport:

```text
X-OPSCON-INGEST-TOKEN
```

Current upload payload:

```text
instance={instance}
mode={mode}
audit_file=@{json_file};type=application/json
```

Current security rule:

```text
Public ingest endpoints must not auto-create _security or ingest_token_sha256.
```

Current Boot Report retry rule:

```text
--mode upload-pending only uploads existing pending boot reports.
--mode upload-pending never creates a new report.
```

This handbook belongs in GitHub:

```text
docs/audits/audit-ingest-contract.md
```

It should also be copied into the closed OPSCON repository before the final OPSCON private/closed repo transfer.
