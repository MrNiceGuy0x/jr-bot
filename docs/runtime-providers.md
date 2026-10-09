# Relational DefinitionSource correction candidate

`tbl_jobs` is the only administrative definition source for SQLite and external
Handler/MariaDB. The locked provider document caches definition fingerprints,
revisions and immutable active occurrences. Dispatch/result/request history
remains durable. Productive `put_job` is rejected (DEFINITION_SOURCE_ONLY).
This is not a migration or credential provisioning authorization.

SQLite preparation creates a native table with the same logical job columns,
PRIMARY KEY(id), UNIQUE(bot_name,job_key), enum-like CHECK constraints and the
existing due/lock/schedule indexes. An existing SQLite authority missing this
table or containing independent document definitions is rejected; preparation
does not rewrite it. A separately approved migration may be required.
MariaDB requires existing InnoDB tbl_jobs and those keys. Additive protocol
storage is tested only in an isolated database. Existing tbl_jobs DDL and rows
are not replaced by the SQL preparation artifact.

The trusted explicit legacy binding maps instance ggb to DB bot GGB; other
instances retain their exact spelling. Client payloads do not choose that
binding. Definition rows are compared byte-exactly. This gate modifies neither
TRX nor DMR production. Comparison fixtures are not unknown live payloads.

GGB ping with exactly [] and canonical jrbot_heartbeat with its five metadata
keys map to system.jrbot_heartbeat, as two separate IDs. Activated Guild Overview
with exactly the supplied URL maps to guild_overview_refresh. Other active
legacy mappings are rejected, disabled rows are preserved without interpreting
or executing their cmd/url payloads. No new once/missed-date workflow is added.

Definitions use fingerprint revisions excluding updated_at and derived fields.
Active occurrences retain their original snapshot while later edits, disable
and deletion affect future acquisition. Last/result projections require the
owned dispatch lock; stale/foreign reports cannot overwrite them. Provider
transactions atomically bind source read, transition, scheduling and projection.
A foreign unexpired legacy lock blocks acquisition. The deployment gate must
still establish one Runtime consumer; this does not make legacy handlers
cooperate with the new state machine.

Both active GGB heartbeats and Guild Overview use coalesce_latest. All legacy
UTC fields and GGB Cron UTC semantics remain unchanged. next_run_utc anchors
acquisition; NULL/invalid active anchors fail explicitly. Run-now changes to
the anchor are detected, but the old Admin interface has no new transactional
trigger contract. It remains unchanged. Disabling does not implicitly start or
stop services; no pause cause is inferred or persisted.

Tests cover native SQLite plus separately required native MariaDB/PHP, using
synthetic fixtures and controlled clocks. No world4you Runtime POST, API GET,
productive database, credentials or systemd operation is allowed by this gate.
Credential persistence, installer publication pins, deployment and activation
remain their separate authorities and Human Gates.
