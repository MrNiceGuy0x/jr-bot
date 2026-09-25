# Runtime Config and Secret Storage

**Work package:** WP-FND-02
**Scope:** Public generic runtime configuration and local runtime-secret storage
**Provisioning:** outside this work package

## Canonical non-secret configuration

```text
/opt/bots/<instance>/config/config.ini
owner/group: root:<instance>
mode: 0640
```

Mandatory selectors:

```ini
[bot]
MANAGEMENT_MODE = standalone | opscon_managed
DATABASE_MODE = local_pi | external
```

`MANAGEMENT_MODE` and `DATABASE_MODE` are orthogonal. Provider-family selection is
derived only from `DATABASE_MODE`.

## Profile matrix

| DATABASE_MODE | AUTH_MODE | `[server]` | `server.token` | `ping.token` |
| --- | --- | --- | --- | --- |
| `local_pi` | n/a | absent | absent | absent |
| `external` | `none` | required | absent | absent |
| `external` | `server_token` | required | required | absent |
| `external` | `split_ping_token` | required | required | required |

For `DATABASE_MODE=external`:

```ini
[server]
SERVER_BASE = https://handler.example
AUTH_MODE = none | server_token | split_ping_token
```

`SERVER_BASE` is explicit non-secret endpoint metadata. The Public installer does
not derive it from project, bot, instance, website or domain names.

## Runtime-secret namespace

Conditional secret root:

```text
/opt/bots/<instance>/config/secrets/
owner/group: root:<instance>
mode: 0750
```

Canonical files:

```text
server.token   root:<instance> 0640
ping.token     root:<instance> 0640
```

The directory is created only when a selected authentication role requires a
persistent runtime token.

## Atomic local writes

Configuration and secret files are staged in the destination directory and
replaced with same-filesystem rename semantics.

Validation failures occur before the accepted `config.ini` is replaced.
`config.ini` is committed last as the effective configuration switch.

## Secret handling

Runtime token plaintext is forbidden from steady-state:

```text
config.ini
.env
systemd Environment=
systemd EnvironmentFile=
process argv
install metadata
logs
audit reports
support bundles
```

The Structure Audit may report runtime-secret metadata but never content, hashes
or recoverable derivatives.

## Public / Private boundary

This Public contract defines generic local storage behavior. It does not
implement:

```text
OPSCON registry logic
installer-token Claim / Finalize
credential issuance
one-time credential delivery
credential proof / activation
audit credential provisioning
```

A Private integration may supply authoritative values to this same local
contract, but must not create a second generic configuration model.
