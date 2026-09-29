# Generic systemd Deployment Contract

**Work package:** WP-FND-03
**Authority:** Public `jr-bot` generic runtime contract
**Activation:** deferred

## Canonical templates

```text
/etc/systemd/system/bot-runner@.service
/etc/systemd/system/bot-runner@.timer
```

Public `jr-bot` is the canonical source authority. Private managed deployments
must consume the same generic units and must not maintain a divergent runner
service or timer implementation.

## Frozen runner service

```ini
[Service]
Type=oneshot
User=%i
Group=%i
WorkingDirectory=/opt/bots/%i
ExecStart=/opt/bots/%i/venv/bin/python /opt/bots/%i/src/job_runner.py --config /opt/bots/%i/config/config.ini
```

`%i` is the canonical runtime instance identity. No config key or project name
may override this identity. `ExecStart` invokes the per-instance virtual
environment Python directly; no shell wrapper is part of the Target launcher.

## Generic timer relationship

The generic timer must target:

```ini
Unit=bot-runner@%i.service
```

The current Public timer contains `OnBootSec=90s`, `OnUnitActiveSec=60s`,
`AccuracySec=15s`, and `Persistent=true`. WP-FND-03 preserves these values as
baseline bytes only. It does not freeze timer cadence, catch-up behavior, or
`Persistent=` policy.

## Installation and activation boundary

These are separate state transitions:

```text
install templates
!= enable runner
!= start productive runtime
```

WP-FND-03 may install templates, set normal unit-file ownership/mode, reload the
systemd manager configuration, and verify unit structure. It must not enable or
start the generic runner timer.

Existing boot-audit behavior is a separate audit concern and is not authority
for generic runner activation.

## Security boundary

Runtime or audit token plaintext must not be transported through systemd
`Environment=`, `EnvironmentFile=`, or the runner process argv. WP-FND-03 does
not redesign systemd sandbox hardening.

## Explicit exclusions

WP-FND-03 does not implement or decide:

- timer cadence or `Persistent=` policy;
- productive `job_runner.py` protocol/provider behavior;
- provider due/lease/catch-up semantics;
- capability dispatch;
- credential issuance, delivery, proof, or activation;
- GGB/TRX/DMR-specific runner units;
- productive GGB deployment;
- systemd sandbox-hardening redesign.
