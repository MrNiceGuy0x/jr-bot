# Security Policy

Do not open a public issue containing secrets, credentials, private infrastructure details or sensitive audit output. Report security concerns privately to the repository owner.

Never commit runtime secrets or machine-specific confidential data, including:

- `.env` files
- deployed `config.ini` files containing credentials
- API tokens or private keys
- real private-network IP/MAC mappings
- unredacted Wi-Fi credentials
- generated audit reports from production nodes
- local state, logs or runtime caches containing sensitive values

The public v1 audit collectors are local-only and must not contain remote audit-upload endpoints, upload credentials or provider-specific remote-storage logic.
