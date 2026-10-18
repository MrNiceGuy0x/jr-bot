# Opt-in runtime/2 logging and manual-request foundation

Status: isolated candidate only. NOT installed, not a runtime release. main()/run_once() remain runtime/1. No startup migration, no HTTP manual-administration route, no audit execution, no tiering in Public.

## Corrective R1, 18.10.2026 – PREPARED_NOT_EXECUTED

Basis ist der historische Kandidat A819A71D1CB892C583266209904C8488E2E2421F97FEC692DA7C03741AEE0E99. Dessen bestandene SQLite/PHP/MariaDB/MySQL/HTTP-Nachweise bleiben historische Nachweise und validieren nicht automatisch diese geänderten Bytes. Für diesen Korrekturkandidaten wurden noch keine Testfälle oder Migrationen ausgeführt.

F01: start_before begrenzt nur die erste run_id-Bindung. Eine spätere Verlängerung derselben gebundenen run_id bleibt bei aktiver Ausführungslease zulässig, ohne start_before zu verändern. Unknown und fremde run_id bleiben gesperrt.

F02: SQLite prüft Logschemaobjekte vor dem ersten Write. Trigger und konservativ erkannte abhängige Views werden verweigert; nur exakt erkannte, nicht eindeutige/partielle, aufsteigende BINARY-Indizes idx_job_time(job_id,ran_at) und idx_bot_time(bot_name,ran_at) werden nach dem Tabellenumbau wiederhergestellt. Bekannte Namen allein reichen nicht als Freigabe.

F03: Die v2-Eingangsprüfung verlangt bei jedem vorhandenen erforderlichen UUID-Feld einen String und kanonische lowercase UUIDv4. null, andere Typen und Großschreibung werden kontrolliert abgelehnt. runtime/1 und sein bisheriges Normalisierungsverhalten bleiben unberührt. Das ist keine neue Benutzerautorisierung.

Neue Tests sind lediglich vorbereitet: drei Public-Renewfälle, vier SQLite-Migrationstestmethoden mit Index-Unterfällen, fünf PHP/Public-Paritätsassertionen und 80 direkte PHP-Envelope-Vektoren (drei gültige, 77 ungültige). Direkte Envelopeprüfungen sind kein HTTP-400-/DB-Unverändertheitsnachweis; ein begrenztes echtes HTTP-Gate ist vor Handlerabnahme zusätzlich erforderlich.

F04-Schemavoraussetzung, F05-Retention, Bestands-Cutover, private Rechte/UI, Audit und Installerintegration bleiben offen und werden hier nicht implementiert. Keine Produktübernahme, kein automatischer Test-/Migrationsstart.

## API and invariants

`foundation_v2_provider(path, instance, runner_id, session_id)` returns an explicit SQLiteFoundation. Caller-owned schema upgrade is `migrate_sqlite(connection, instance, poll)` inside BEGIN IMMEDIATE; it refuses unknown/partial versions and any retained v1 dispatch history. This is deliberately narrower than a production cutover; a history-preserving cutover is still needed before deployment. No automatic activation.

SQLite table state version=2 plus PRAGMA user_version=2 select the opt-in protocol. Opening v2 state through v1 fails closed. Internal `request_manual` requires trusted context/user identity; it is not an authorization system and must not be exposed directly to a browser. Private authorization comes in a later slice.

Start deadline is two trusted poll intervals by default, optionally shortened. At `now >= expires_at` no dispatch/start is allowed. Poll policy is a preparation parameter, never a Runner request parameter. Pure tests use server-controlled clocks. `foundation_v2_start_allowed` rejects uncertain clocks and rechecks the deadline; real runner integration is deferred.

Pending manual requests are retained as cancelled with reason on expiry, deletion, definition change or same-job regular priority. A manual run never alters regular next_run. A confirmed started result updates last-run and optional execution log atomically. A not-started rejection does not replace last-run or invent duration. Unknown outcomes remain job-blocking and accept late reports only as evidence for future explicit recovery. No recovery write endpoint or history cleanup in this slice.

Logging snapshots all/errors_only/none at dispatch. Request and actor provenance is persisted in request/dispatch records; log identity uses instance/dispatch_id. Duplicate result is idempotent, conflicting result rejected. Timestamp wire precision is seconds; duration_ms is derived accordingly, not claimed as millisecond-resolution measurement. Last-run relational timestamps use UTC SQL-format.

## Schema

`tbl_jobs.log_mode`; new local `tbl_job_log` with unique instance/dispatch_id; `jrbot_manual_requests` with an active-job guard; nullable document metadata added to existing `jrbot_provider_requests` WITHOUT changing its dispatch UUID field into JSON. Dispatch/request documents are durable per identity; only jobs/policy remain in the central state document. No retention deletion or invented user table. Old local log fixtures with the exact recognized columns are rebuilt transactionally to enforce the same all-null/all-present identity constraint; unknown columns/indexes or inbound foreign keys require explicit review. Full production cutover remains a later gate.

Source mappings stay limited to supported existing ping/heartbeat/Guild HTTP jobs. Disabled supported mappings can be manually requested. Arbitrary legacy shell/once mappings are not silently enabled; audit mapping is a separate slice. Existing foreign relational locks are respected. Loaded v2 histories are capacity-limited and fail closed; archival/retention policy is not implemented.

## Available validation

Run from the isolated Public root with bytecode disabled:

- `PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_logging_manual_requests.py`
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_storage_migrations.py`
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_runtime_providers.py`

These suites create only new TemporaryDirectory SQLite fixtures; Requests is replaced by a network-forbidden stub only when missing. They do not test real HTTP or production scheduling. Tests cover deadline, manual disabled jobs, idempotency/conflict, rollback, log-mode snapshot, locks, provenance injection rejection, unknown outcomes, deterministic readiness and schema/backup handling. Full PHP/MySQL/HTTP parity and adversarial concurrency remain required.

## Deferred

Bounded real invocation (8 leases/45 seconds), real v2 transport client, private tier/CSRF/bootstrap, audit capabilities, installers/Apps-Prepare, productive DB migration and explicit recovery. Protocol v2 currently travels through the existing handler runtime routes; URI /jrbot/v1 identifies the existing handler surface, not a permission to silently change runtime/1 bodies. No live target was called.
