# jr-bot

Universal JR-Bot installer and runtime toolkit for self-hosted automation, scheduled tasks and node monitoring.

## Public v1 scope

The public v1 baseline is generic and self-contained. Runtime state, logs and audit reports are stored locally on the node.

Audit reports are written under:

```text
/opt/bots/<instance>/reports/audits/
```

The public v1 audit layer has no remote audit upload, external audit database or provider-specific storage integration. A future release may add an optional provider-neutral export/storage interface, but it is not part of the v1 contract.

## Runtime layout

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

The runtime user and instance name are intentionally separated from the administrator account. The recommended install root is `/opt/bots/<instance>`.

## Audits

The repository ships three read-only audit collectors:

- `audit_jr-bot-boot-report.sh`
- `audit_jr-bot-network-health.sh`
- `audit_jr-bot-structure.sh`

They redact sensitive values, generate JSON locally and do not transmit audit reports.

## Installer

Run `install_jr-bot.sh` from a neutral administrator account on a supported Debian/Raspberry Pi OS host. The installer creates or uses a dedicated runtime user, prepares the runtime tree, installs the public scripts/audits and can enable systemd units.

The job-runner backend configuration is separate from audit storage. Public-v1 local-only audit persistence does not prevent a JR-Bot runtime from connecting to a user-configured project API.
