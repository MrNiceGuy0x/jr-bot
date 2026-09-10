# JR-Bot Local Audit Storage Contract

**Status:** Public v1 baseline
**Scope:** `audit_jr-bot-boot-report.sh`, `audit_jr-bot-network-health.sh`, `audit_jr-bot-structure.sh`

## Contract

Public-v1 audits are read-only collectors and persist their JSON output locally on the JR-Bot node.

Default directory:

```text
/opt/bots/<instance>/reports/audits/
```

Default file naming:

```text
audit_jr-bot-boot-report-<instance>-YYYYMMDD_HHMMSS.json
audit_jr-bot-network-health-<instance>-YYYYMMDD_HHMMSS.json
audit_jr-bot-structure-<instance>-YYYYMMDD_HHMMSS.json
```

The audit layer does not provide a remote destination, upload URL, upload credential, external database connector or retry uploader in public v1.

## Instance contract

Instance input is normalized only by trimming surrounding whitespace and converting ASCII uppercase letters to lowercase. Invalid characters are not rewritten.

Canonical grammar:

```text
^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$
```

This means:

- 1 to 32 ASCII characters
- first character is `a-z`
- interior characters may use `a-z`, `0-9`, `_`, `-`
- final character must be alphanumeric
- invalid input is rejected

## Local report permissions

Audit collectors use a restrictive process umask and create the default report directory for the runtime user. Generated reports can contain host, network, service and journal metadata and should be treated as sensitive operational data.

## Output override

The audit commands may support `--output <file>` for explicit local diagnostics or testing. This is a filesystem output override, not a network/export integration.

## Security invariants

The collectors must:

- remain read-only with respect to inspected system configuration
- redact recognized secret values before placing text in JSON
- never include credential values intentionally
- never transmit audit reports in public v1
- remain usable without any external audit service
