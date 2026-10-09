# Runtime Provider Authority — WP-PRV-01

DATABASE_MODE selects exactly one productive Job/Result/Presence provider family.
MANAGEMENT_MODE remains orthogonal. R2/P2 authorities remain higher.

| Mode | Authority | Access |
| --- | --- | --- |
| local_pi | SQLite at state/local_db/runtime.sqlite3 below the canonical instance root | Python sqlite3; no runtime tokens |
| external | MariaDB behind the Project Handler | Pi uses HTTPS only; mysqli stays server-side |

## Storage and transactions

The version-1 jrbot_provider_state document owns definitions and current
occurrences. SQLite BEGIN IMMEDIATE or MariaDB SELECT FOR UPDATE serializes all
scheduler transitions for an instance. Durable per-identity rows in
jrbot_provider_dispatches and jrbot_provider_requests retain dispatch snapshots,
terminal results and request deduplication. Only the active set and requested
historical identity are hydrated per operation. History does not grow the job
document and is not silently deleted. These tables belong to one DB authority.

Definitions require enabled, revision, canonical system/script/http type, object
payload, start_at, schedule, lease/retry policy and catch-up policy. put_job is
an explicit trusted administrative API. Increasing revision preserves an active
occurrence's immutable definition through retries and schedules the replacement
after that occurrence. Legacy tables/seeds are not imported or converted.

once, interval and five-field cron with explicit IANA timezone are supported.
Numeric lists/ranges/steps use conventional day-of-month/day-of-week OR if both
fields are restricted. Timezone round-tripping skips spring gaps and preserves
both UTC occurrences of an autumn fold. Catch-up selects the latest occurrence
directly. coalesce_latest and skip_missed are supported; replay_all is rejected.

One active dispatch per job; UUIDv4 request/dispatch/run identities; immutable
snapshots; finite attempts; provider-clock expiry/retry/receipt time. Renew binds
the run. Reports validate snapshot and runner/session/run bindings; identical
duplicates succeed, conflicting or stale reports fail. The trusted clock hook
exists for tests/embedding and is never supplied by config or client payload.

Self-presence writes the bound instance and provider receipt time only. Existing
last_status/last_alert_at survive. No artificial monitoring GREEN or credential
output. Capability authorization remains the existing common D-R2-010 executor.

## Explicit preparation and failure

Run the canonical runner with --config and --prepare-local-db as the authorized
instance user. Preparation creates an empty local authority and exits without
activation or Legacy seeding. Existing valid state is checked without replacing
definitions/history. Normal run_once never creates or migrates the DB. The local
provider ships inside the existing job_runner.py payload and needs no DB package.

Missing/invalid storage, DB errors, locks and capacity violations fail closed.
The job-state document is bounded to 4 MiB; historical identities have separate
rows. Backup and explicit retention/maintenance are operator responsibilities.
No local/remote scheduler fallback or automatic destructive cleanup exists.

The private schema is applied explicitly from
sql/shared/004_runtime_provider_authority.sql. CREATE TABLE IF NOT EXISTS does
not certify an incompatible pre-existing schema. prepareInstance() initializes
only the trusted instance. The core contains no connection credentials or DDL.
Its caller must resolve and authorize the instance before construction; client
fields never supply this trusted context. put_job/inspect must not become public
runtime routes. HTTP routing, role/token checks and response-envelope integration
remain WP-RUN-02. Installer/UI readiness is not upgraded by provider-test PASS.

## Verification boundary

Public tests use native SQLite transactions, parallel connections, failure/
rollback, preparation idempotency, result/snapshot binding and Europe/Vienna DST.
Private tests reuse those contract vectors and compare PHP against SQLite.
--pure explicitly reports native MariaDB NOT_EXECUTED. Native mode requires a
private /tmp socket, synthetic_prv DB and explicit synthetic-test marker; no
World4You, real credentials or systemd activation. Tests use isolated fixture
copies, never a live instance authority.

Provider PASS is not HTTP/TLS/authentication acceptance, final installer
readiness, GGB ALIVE, WLAN-only proof or Go-Live acceptance.
