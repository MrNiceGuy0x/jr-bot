# WP-CAP-01 Capability Framework + Execution Security

Public `jr-bot` is the canonical authority for capability descriptors and execution security. Private/managed integrations may consume this contract but must not implement a second capability core.

A capability is selected by stable `capability_id` + `revision`. The local descriptor fixes the absolute script path, SHA-256 digest, interpreter, deterministic argument policy, timeout, stdout/stderr bounds, secret bindings and retry class. Remote input may provide only values admitted by the descriptor; it cannot select an executable, interpreter, working directory, raw argv, environment, secrets, retry semantics or new policy.

Execution uses an argv vector with `shell=False`. Arbitrary shell payloads (`sh -c`, `bash -c`, `eval`, `powershell -Command`, `cmd.exe /c`) are not a capability mechanism. Existing maintenance scripts are not dispatchable merely because they exist. `config/capabilities.d/` and `scripts/capabilities/` are empty contract roots in WP-CAP-01; productive capabilities require a later explicit authorization.

HTTP-specific SSRF/DNS/redirect/proxy/TLS hardening belongs to WP-CAP-02. Provider, provisioning, productive runner, runtime protocol, deployment, real credentials and live OPSCON mutation are outside WP-CAP-01.