# Security Policy

Do not open a public issue containing secrets, credentials, private infrastructure details or sensitive audit output. Report security concerns privately to the repository owner.

Never commit runtime secrets or machine-specific confidential data, including:

- `.env` files
- deployed `config.ini` files
- `config/secrets/server.token`
- `config/secrets/ping.token`
- API tokens or private keys
- real private-network IP/MAC mappings
- unredacted Wi-Fi credentials
- generated audit reports from production nodes
- local state, logs or runtime caches containing sensitive values

## Runtime configuration and secrets

`config/config.ini` is the canonical non-secret runtime configuration authority.
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

Canonical runtime-token paths are:

```text
config/secrets/server.token
config/secrets/ping.token
```

`config/secrets/` is `root:<instance>` mode `0750`; token files are
`root:<instance>` mode `0640`. Updates are staged in the destination filesystem
and use atomic rename/replacement.

The Public Structure Audit may report secret-file path, existence, ownership and
mode only. It must never emit secret content, secret hashes, prefixes/suffixes or
other recoverable derivatives.

The public v1 audit collectors are local-only and must not contain remote audit-upload endpoints, upload credentials or provider-specific remote-storage logic.
