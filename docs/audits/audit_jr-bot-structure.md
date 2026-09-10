# Structure Audit

**Script:** `audits/audit_jr-bot-structure.sh`
**Script version:** `0.3.0`
**Schema:** `jrbot-structure-audit-v1`
**Public v1 storage:** local only

## Purpose

The Structure Audit validates JR-Bot runtime layout, important files, runtime-user expectations, Python/venv state and systemd integration without changing the inspected node.

The collector does not transmit reports.

## Target runtime layout

```text
/opt/bots/<instance>/
├── audits/
├── config/
├── docs/
│   ├── audits/
│   └── scripts/
├── logs/
├── reports/
│   └── audits/
├── scripts/
├── src/
├── state/
├── tmp/
└── venv/
```

The audit also records legacy layout signals for migration diagnostics, but legacy paths are not the public-v1 target.

## Standard scripts

The target flat `scripts/` set is:

```text
cancel_shutdown.sh
check_disk.sh
check_memory.sh
reboot.sh
shutdown.sh
ssh_start.sh
ssh_status.sh
ssh_stop.sh
tail_runner_log.sh
uptime_info.sh
```

## Usage

```bash
./audits/audit_jr-bot-structure.sh   --instance demo   --path /opt/bots/demo
```

Supported options:

```text
--instance <name>
--path <bot-path>
--legacy
--mode <auto|target|legacy|hybrid>
--output <file>
--print-json
--tree-depth <n>
```

If `--path` is omitted, `/opt/bots/<instance>` is used.

## Instance contract

```text
^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$
```

Input is trimmed and lowercased. Invalid input is rejected instead of rewritten.

## Configuration safety

The audit may report whether expected configuration keys exist, but must not intentionally emit secret values. Production `config.ini`, `.env`, keys and generated reports are local runtime data and must not be committed.

## systemd checks

The audit understands the generic runner template model:

```text
bot-runner@.service
bot-runner@.timer
bot-runner@<instance>.service
bot-runner@<instance>.timer
```

and the local boot-audit service:

```text
jrbot-boot-report-audit@<instance>.service
```

## Security

The JSON report declares:

```json
{
  "read_only": true,
  "secrets_redacted": true,
  "secret_values_included": false
}
```

The audit is intended to identify drift, not repair it.
