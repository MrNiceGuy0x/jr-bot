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
│   ├── config.ini
│   └── secrets/            # conditional
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

## Runtime configuration authority

The canonical non-secret runtime configuration is:

```text
/opt/bots/<instance>/config/config.ini
```

It uses explicit selectors:

```ini
[bot]
MANAGEMENT_MODE = standalone | opscon_managed
DATABASE_MODE = local_pi | external
```

`DATABASE_MODE=local_pi` has no active `[server]` section and no runtime token files.

`DATABASE_MODE=external` requires:

```ini
[server]
SERVER_BASE = https://handler.example
AUTH_MODE = none | server_token | split_ping_token
```

Runtime token plaintext is not stored in `config.ini`. When required by `AUTH_MODE`,
the canonical files are:

```text
config/secrets/server.token
config/secrets/ping.token
```

The Public repository remains provider-neutral and does not implement OPS-CON
provisioning, installer-token Claim/Finalize, credential issuance, proof or
activation.

See `docs/runtime-config-secrets.md` for the complete WP-FND-02 storage contract.

## Audits

The repository ships three read-only audit collectors:

- `audit_jr-bot-boot-report.sh`
- `audit_jr-bot-network-health.sh`
- `audit_jr-bot-structure.sh`

They redact sensitive values, generate JSON locally and do not transmit audit reports. The Structure Audit may report runtime-secret file metadata, but never secret values or secret hashes.

## Installer

Run `install_jr-bot.sh` from a neutral administrator account on a supported Debian/Raspberry Pi OS host. The installer creates or uses a dedicated runtime user, prepares the runtime tree, writes canonical runtime configuration and conditional runtime-secret files, installs the public scripts/audits and can enable systemd units.

The job-runner backend configuration is separate from audit storage. Public-v1 local-only audit persistence does not prevent a JR-Bot runtime from connecting to a user-configured project API.
