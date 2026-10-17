# Local SQLite lifecycle — source checkpoint 2026-10-17

Status: implemented behavior described from public HEAD a90bda2c3908bc6ea443a22f55dd7a3532e1ae82. This document does not authorize preparation, migration, activation or job execution.

## Authority and explicit preparation

`src/job_runner.py` owns `SQLITE_JOBS_DDL`, `LocalDbProvider.prepare()` and `LocalDbProvider._operation()`. DATABASE_MODE=local_pi selects SQLite; external selects the remote HTTPS provider and does not fall back to SQLite. The local authority is `<base_dir>/state/local_db/runtime.sqlite3`, canonically `/opt/bots/<instance>/state/local_db/runtime.sqlite3`.

Preparation is explicitly selected through the runner's `--prepare-local-db` option, using the canonical runtime configuration and authorized instance user. It does not run a job or activate systemd. Neither reviewed installer contains a call to this preparation option: selecting local_pi/configuring an instance is not evidence that SQLite tables have been prepared. Installer integration is an open implementation item, not an automatic step established by this documentation.

For a missing DB, preparation checks scoped symlinks, creates the parent with requested mode 0700, reserves the DB exclusively with requested mode 0600 and performs DDL in BEGIN IMMEDIATE. Existing parent permissions are not repaired by mkdir(exist_ok=True). Runtime rejects DB ownership different from the effective user and group/world-writable DB mode. These checks do not constitute a complete parent-directory security audit.

## Tables created by the current preparation

| Table | Responsibility |
| --- | --- |
| tbl_jobs | Relational job definitions and last-result/schedule/lock projections |
| tbl_bot_status | Latest self-presence |
| jrbot_provider_state | Instance state, definition fingerprints and occurrences |
| jrbot_provider_dispatches | Durable per-dispatch status and result document |
| jrbot_provider_requests | Request deduplication |

`tbl_jobs` has PRIMARY KEY(id), UNIQUE(bot_name,job_key), CHECK constraints and idx_due/idx_locked/idx_schedule. `tbl_job_log` and `log_mode` are NOT created. Private sql/shared SQL is MySQL-family SQL and must not be executed against this SQLite DB.

Preparation does not insert standard jobs. An existing DB is inspected, never replaced/reseeded. Normal runtime opens mode=rw and refuses a missing authority. No versioned schema-upgrade engine is established by this path. State document version=1 is not a general database migration version. Preparation failure rolls back DDL but can leave the reserved DB file; do not assume a subsequent invocation repairs a partial preparation. Diagnose before retry or removal.

## Transaction and timeout behavior

Each local operation uses BEGIN IMMEDIATE, validates required primary/unique keys, loads relational definitions and dispatch state, performs a transition and persists projections and history in one transaction. An accepted report updates tbl_jobs only under the matching dispatch lock. It does not append tbl_job_log.

Expired active leases are marked expired when a transition evaluates them. Completion/retry handling follows the occurrence policy. An expired dispatch without a report does not synthesize last_run/last_ok/message or an execution log. No independent background timeout sweeper is established here. A lease expiry alone is not proof that a command did not run.

## Proposed extension — not implemented

Per-job log_mode: all (default), errors_only, none. Execution enablement and job_group remain independent. A future candidate must address native SQLite creation and guarded migration, external schema migration, configuration/UI validation, policy snapshot at dispatch, atomic result/log persistence, duplicate reports and late report/timeout semantics. Unknown execution outcome must not be rewritten as a fabricated successful or failed command execution. Explicit heartbeat assignment replaces name/type guessing. No existing DMR/TRX installation is migrated by this document.

Required isolated checks: fresh preparation, existing authority, partial preparation, guarded upgrade and backup, duplicate/concurrent reports, rollback, expiry/late reports, all logging modes and compatibility. Live schema and deployed behavior require separate fresh evidence.
