# JR-Bot Boot Report Audit

## Minimal Script Header

```text
Script: audits/audit_jr-bot-boot-report.sh
Project: JR-Bot / OPSCON
Type: Hybrid boot report audit script
Status: Active migration
Version: 0.2.1
Schema: jrbot-boot-report-audit-v1
Default endpoint: <OPSCON_BASE_URL>/api/jrbot_audit_boot_report_ingest.php
Local pending path: <bot-path>/reports/pending/
```

## 1. Purpose

`audits/audit_jr-bot-boot-report.sh` creates a boot-time audit report for a JR-Bot instance.

The script is part of the unified JR-Bot audit architecture and replaces the older legacy boot-report flow over time. It is designed as a hybrid migration script so that both legacy installations and the new One-Liner target architecture can be detected and reported.

The script is read-only. It collects boot, network, service and installation-state information, writes a local JSON report, and uploads pending reports to OPSCON when network connectivity and a valid upload token are available.

## 2. Migration Goal

Legacy boot-report flow:

```text
maintenance/jrbot_boot_report.sh
<OPSCON_BASE_URL>/api/jrbot_boot_report_ingest.php
/OPSCON/data/jrbot_reports/<instance>/boot/
```

New unified audit flow:

```text
audits/audit_jr-bot-boot-report.sh
<OPSCON_BASE_URL>/api/jrbot_audit_boot_report_ingest.php
/OPSCON/data/audit_jr-bot-boot-report/<instance>/
/OPSCON/data/audit_jr-bot-boot-report/<instance>/history/
```

The legacy flow must remain untouched until migration testing is complete.

## 3. Supported Modes

The script supports these modes:

```text
auto
legacy
target
hybrid
migrate
test
```

### auto

Default mode. The script detects the installation profile from the available directory and file markers.

### legacy

Used for older JR-Bot installations with a legacy maintenance directory and legacy boot-report script.

### target

Used for the new One-Liner target architecture.

### hybrid

Used when both legacy and target markers are present. This is expected during migration.

### migrate

Used for controlled migration phases where an installation is intentionally between old and new architecture.

### test

Used for manual test runs and endpoint validation.

## 4. Profile Detection

The script reports two important fields:

```json
{
  "profile_detected": "legacy|target|hybrid|unknown",
  "install_profile": "legacy|target|hybrid|unknown"
}
```

Typical marker logic:

```text
legacy markers:
- <bot-path>/maintenance/
- <bot-path>/maintenance/jrbot_boot_report.sh
- legacy environment/config markers
- legacy home-based bot layout

target markers:
- <bot-path>/audits/
- <bot-path>/scripts/
- <bot-path>/src/job_runner.py
- <bot-path>/config/config.ini
- One-Liner target layout
```

If both legacy and target markers are detected, the profile is reported as `hybrid`.

## 5. Local Pending Workflow

The script writes generated reports to:

```text
<bot-path>/reports/pending/
```

If upload is disabled or fails, the report remains local.

On a later successful run, the script retries pending boot-report audit JSON files and deletes each local file only after OPSCON confirms a successful upload.

This workflow is important for boot scenarios where network connectivity is not yet available.

## 6. Upload Flow

The script uploads reports using multipart form data:

```text
upload token field: <upload-token>
instance=<instance>
mode=<mode>
audit_file=@<json-file>
```

The upload token is not hardcoded in the script.

Token lookup order:

```text
REPORT_UPLOAD_TOKEN environment variable
<bot-path>/config/audit_boot_report.token
<bot-path>/config/boot_report_upload.token
<bot-path>/config/report_upload.token
```

During migration, reusing the existing report upload token is supported if OPSCON stores the matching SHA256 hash for the new endpoint.

## 7. OPSCON Endpoint

The new endpoint is:

```text
<OPSCON_BASE_URL>/api/jrbot_audit_boot_report_ingest.php
```

Expected OPSCON storage model:

```text
/OPSCON/data/audit_jr-bot-boot-report/
├── _security/
│   ├── .htaccess
│   └── ingest_token_sha256
└── <instance>/
    ├── audit_jr-bot-boot-report-<instance>.json
    └── history/
        └── audit_jr-bot-boot-report-<instance>-YYYYMMDD_HHMMSS.json
```

The endpoint stores one current JSON per instance and one historical JSON per upload.

If multiple uploads arrive in the same second, the endpoint appends a random suffix to the history filename to prevent overwriting existing history files.

## 8. JSON Schema

Primary schema:

```text
jrbot-boot-report-audit-v1
```

The report contains at minimum:

```json
{
  "schema": "jrbot-boot-report-audit-v1",
  "script_version": "0.2.0",
  "instance": "<instance>",
  "mode_requested": "auto",
  "profile_detected": "hybrid",
  "install_profile": "hybrid",
  "created_at_utc": "YYYY-MM-DDTHH:MM:SSZ",
  "security": {
    "read_only": true,
    "secrets_redacted": true,
    "secret_values_included": false
  },
  "summary": {
    "health_state": "ok|warning|critical|unknown"
  }
}
```

## 9. Security Requirements

The script and endpoint must follow these rules:

```text
- No plaintext token in GitHub.
- No token hash in GitHub.
- No private IP addresses in documentation.
- No SSID, MAC, BSSID or hardware serials in documentation.
- No local user-specific absolute paths in documentation.
- No secret values in generated JSON.
- Generated JSON must declare security.secret_values_included=false.
- Generated JSON must declare security.secrets_redacted=true.
- Generated JSON must declare security.read_only=true.
```

The endpoint must verify the token by hashing the provided token and comparing it to the stored SHA256 hash.

The endpoint must store the SHA256 hash outside public access, for example:

```text
/OPSCON/data/audit_jr-bot-boot-report/_security/ingest_token_sha256
```

The `_security` directory must be protected by `.htaccess`.

## 10. Manual Test Command

Manual test without upload:

```bash
bash <bot-path>/audits/audit_jr-bot-boot-report.sh \
  --instance <instance> \
  --path <bot-path> \
  --mode auto \
  --no-upload \
  --print-summary
```

Manual test with upload:

```bash
bash <bot-path>/audits/audit_jr-bot-boot-report.sh \
  --instance <instance> \
  --path <bot-path> \
  --mode auto \
  --print-summary
```

Expected successful summary:

```text
JR-Bot Boot Report Audit Summary
Instance:      <instance>
Script:        0.2.0
Mode:          auto
Profile:       legacy|target|hybrid
Install:       legacy|target|hybrid
Health state:  ok
Upload-Zusammenfassung: success=1, failed=0
Boot report audit completed.
```

## 11. systemd Migration Unit

The new parallel systemd template is:

```text
systemd/jrbot-boot-report-audit@.service
```

Runtime installation path:

```text
/etc/systemd/system/jrbot-boot-report-audit@.service
```

This unit is intentionally separate from the legacy unit.

Legacy unit:

```text
jrbot-boot-report@.service
```

New audit unit:

```text
jrbot-boot-report-audit@.service
```

The new audit unit must remain disabled until migration testing is complete.

Manual systemd test:

```bash
sudo systemctl daemon-reload

sudo systemctl start jrbot-boot-report-audit@<instance>.service

sudo systemctl status jrbot-boot-report-audit@<instance>.service --no-pager

sudo journalctl -u jrbot-boot-report-audit@<instance>.service -n 120 --no-pager -l
```

Check that the new unit is not enabled:

```bash
systemctl is-enabled jrbot-boot-report-audit@<instance>.service || true
```

Expected during migration:

```text
disabled
```

## 12. Migration Status

Validated migration steps:

```text
D1   New OPSCON endpoint created and tested.
D1.1 UTF-8 BOM handling added.
D1.2 History filename collision protection added.
D2   Hybrid Bash script added under audits/.
D3   Manual dry-run and upload test completed.
D3.1 Endpoint collision test completed.
D4   Parallel systemd unit created, manually tested and kept disabled.
D5   Documentation added.
```

## 13. Production Enablement Rule

The new boot-report audit unit must not be enabled automatically until these conditions are met:

```text
- Manual script test succeeds.
- Manual upload test succeeds.
- Pending retry behavior succeeds.
- systemd manual start succeeds.
- OPSCON current and history files are written correctly.
- Legacy unit rollback path is still available.
```

Only after those checks should production activation be considered.

## 14. Rollback

Rollback is simple during migration because the legacy unit remains untouched.

If the new audit unit causes problems:

```bash
sudo systemctl disable jrbot-boot-report-audit@<instance>.service
sudo systemctl reset-failed jrbot-boot-report-audit@<instance>.service
```

The legacy boot-report unit can remain active independently.

## 15. Related Repository Files

```text
audits/audit_jr-bot-boot-report.sh
systemd/jrbot-boot-report-audit@.service
docs/audits/audit_jr-bot-boot-report.md
```

---

## D7.3 / D7.4 Regression Contract

The boot report audit follows the shared JR-Bot / OPSCON audit ingest contract:

```text
docs/audits/audit-ingest-contract.md
```

Critical D7 rules:

- `--mode upload-pending` is retry-only.
- `--mode upload-pending` must never create a new boot report.
- `jrbot-report-upload@.service` may call `--mode upload-pending` on a timer.
- In upload-pending mode, the script must upload only existing files from `<bot-path>/reports/pending/`.
- Public OPSCON ingest endpoints must use instance-specific token validation.
- Token hashes must be stored under `/OPSCON/data/<audit-type>/<instance>/_security/ingest_token_sha256`.
- Public ingest endpoints must not auto-create `_security`.
- The retry timer must not be started until the corresponding OPSCON ingest endpoint has been corrected.

Regression check:

```text
before=$(find <bot-path>/reports/pending -maxdepth 1 -type f -name "*.json" | wc -l)
audits/audit_jr-bot-boot-report.sh --instance <instance> --path <bot-path> --mode upload-pending
after=$(find <bot-path>/reports/pending -maxdepth 1 -type f -name "*.json" | wc -l)
test "$before" = "$after"
```
