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

## F04, Variante A — isolierter Schema-Guard (2026-10-18)

Status dieses Abschnitts: implementierter isolierter Kandidat, **native Nachweise ausstehend**. Keine automatische Migration und keine Runtime-Aktivierung. Ausgangscheckpoint Public `622ce53a3f87bdb7b89901c7d6c36196b385f948` / Private `4bec1b8ab25eb6660c8e726a56b0571c1b6ab8ff`, Tag `checkpoint/logging-foundation-v2-20261018`.

`SQLiteFoundation.operation()` ruft innerhalb seiner eigenen `BEGIN IMMEDIATE`-Transaktion vor dem ersten Zustands-/Jobwrite `schema_guard_sqlite()` auf. `user_version=2` und aktive SQLite-CHECK-Durchsetzung sind erforderlich. Tabellen-/Trigger-/FK-/Indexmetadaten werden gelesen; es gibt keinen positiven Cache über Operationen hinweg. Abweichung führt zu `PROVIDER_SCHEMA_INVALID`, nicht nachweisbare Metadaten zu `PROVIDER_SCHEMA_UNVERIFIABLE`; die Operation rollt ohne Reparatur zurück.

### Präziser SQLite-Vertrag

Erkannt werden ausschließlich die sechs v2-Basistabellen der bestehenden `LocalDbProvider.prepare()`- plus `migrate_sqlite()`-Baseline. Ihre vollständigen Deklarationen werden tokenweise verglichen: Whitespace, Kommentare und einfache zitierte Identifier dürfen variieren, Stringliteralwerte und Constraint-Gruppierung bleiben erhalten. Keine bloße CHECK-Teilstringsuche. Das nach `ALTER ADD COLUMN` mögliche Einfügen von `log_mode` vor oder nach dem vorhandenen UNIQUE-Tabellenconstraint und von `document` vor oder nach dem Requests-Primary-Key wird ausdrücklich unterstützt. Andere DDL-Formen, zusätzliche Spalten/Constraints, STRICT/WITHOUT ROWID und nicht klassifizierbare Varianten werden konservativ abgewiesen, selbst wenn einzelne davon funktional ähnlich sein könnten.

| Tabelle | Verbindliche Identität / CHECK-Baseline |
|---|---|
| `tbl_jobs` | INTEGER-Autoincrement-PK `id`, UNIQUE `(bot_name,job_key)`; vorhandene Typ-/Längen-/Enum-/Bool-CHECKs und `log_mode`-CHECK |
| `tbl_job_log` | INTEGER-Autoincrement-PK `id`, UNIQUE `(instance,dispatch_id)`; Bool- und Identitäts-/Outcome-Kopplungs-CHECK |
| `jrbot_provider_state` | bestehender TEXT-PK `instance`; TEXT-NOT-NULL-Dokument |
| `jrbot_provider_dispatches` | PK `(instance,dispatch_id)`, Dokument/Status wie Baseline |
| `jrbot_provider_requests` | PK `(instance,request_key)`, nullable `dispatch_id`/`document` |
| `jrbot_manual_requests` | PK `(instance,request_id)`, UNIQUE `(instance,active_job_id)`, State-CHECK |

Alle vorhandenen Unique-Indizes müssen genau den bekannten Schlüsseln entsprechen: vollständig, aufsteigend, BINARY, nicht partiell, keine Expressions. Zusätzliche gewöhnliche nicht-eindeutige Vollspaltenindizes sind erlaubt; zusätzliche Unique-, Ausdrucks-, Partial- oder abweichende Collation-Indizes nicht. Unbekannte Trigger auf den sechs Tabellen sowie sichtbare eingehende/ausgehende Fremdschlüssel werden verweigert. SQL-Identifier aus dem Katalog werden sicher zitiert.

**Variante-A-Grenze:** SQLite besitzt in dieser bestehenden Baseline keinen SQL-`JSON_VALID`-CHECK für State-/Dispatch-/Manual-Dokumente und keinen SQL-CHECK `active_job_id IS NULL OR active_job_id=job_id`. Die vorhandenen JSON-Parser und Übergangsfunktionen werden nicht durch zusätzliche DB-Constraints ersetzt. Der Guard belegt deshalb die erkannte SQLite-Baseline, **keine identische MySQL-Constraint-Ausstattung und keine Integrität gegen direkte Fremdschreibzugriffe**. Eine solche Angleichung benötigt einen separaten Migrationsvertrag. Der bestehende nullable TEXT-Primary-Key der State-Tabelle wird als bekannte Baseline akzeptiert; daraus folgt keine zusätzliche NOT-NULL-Garantie für direkte Fremdschreiber.

### Geplante Nachweise

19 zusätzliche SQLite-Testmethoden decken Baseline, jede fehlende Tabelle, View-Ersatz, Spalte/Typ/Default/Nullfähigkeit/Collation, Trigger, zusätzliche/partielle/Expression-Unique-Indizes, erlaubten Performanceindex, Version, Fremdschlüssel, Literal-/Gruppierungsschutz, Metadatenverweigerung und ausgeschaltete CHECKs ab. Ausführung erst im nativen Gate. Der bestehende Rollback-Test bleibt erhalten: Eine testlokale Connection-Delegation provoziert den Logfehler nach dem echten Guard und vor dem Loginsert; ein Fehler-Trigger wäre seit F04 bereits korrekt im Guard abgefangen worden.

F05 unverändert offen: keine neue TTL, keine Löschung, kein Tombstone-/Sessionlebenszyklus, keine Kapazitätserhöhung. Auch das bestehende Vollzustandsladen und seine Grenzen sind durch diesen Guard nicht gelöst. Startfrist zwei Pollintervalle und Ausführungslease bleiben unverändert. Unbekannte Schemas werden nicht auf eigene Faust migriert.
