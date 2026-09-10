# Boot Report Audit

**Script:** `audits/audit_jr-bot-boot-report.sh`
**Script version:** `0.3.0`
**Schema:** `jrbot-boot-report-audit-v1`
**Public v1 storage:** local only

## Purpose

The Boot Report Audit captures a read-only snapshot of host, boot, storage, network, systemd and recent journal state. It is intended for post-boot diagnostics and reproducible node-health evidence.

The collector does not transmit reports.

## Default storage

For instance `demo`:

```text
/opt/bots/demo/reports/audits/
```

Example file:

```text
audit_jr-bot-boot-report-demo-YYYYMMDD_HHMMSS.json
```

Reports are retained locally.

## Usage

```bash
./audits/audit_jr-bot-boot-report.sh   --instance demo   --path /opt/bots/demo   --mode target   --print-summary
```

The script can infer its bot path when installed under `<bot-path>/audits/`. The instance can then be inferred from the bot-path basename.

Supported options:

```text
--instance <name>
--path <bot-path>
--legacy
--mode <auto|legacy|target|hybrid|migrate|test|boot>
--output <file>
--print-summary
--print-json
--wifi-iface <iface>
--eth-iface <iface>
```

`--output` is a local filesystem override for diagnostics/testing. It is not a remote storage integration.

## Instance contract

Instance names are trimmed, lowercased and strictly validated against:

```text
^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$
```

Invalid characters are rejected rather than rewritten.

## Profile detection

The collector can distinguish legacy, target and hybrid layouts. Target signals include:

```text
/opt/bots/<instance>
audits/
scripts/
src/job_runner.py
config/config.ini
```

Legacy detection remains diagnostic-only and is useful when inspecting older installations.

## Security

The report declares:

```json
{
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

Recognized credential-like values in collected text are redacted. Audit output may still contain operationally sensitive host, network, service and journal metadata, so generated JSON should be protected as local operational data.

## systemd

The public boot-audit service should execute the local collector only:

```text
jrbot-boot-report-audit@<instance>.service
```

It must not depend on a report uploader or external audit service.
