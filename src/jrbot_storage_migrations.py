"""Explicit, opt-in runtime/2 foundation. No startup migration or public admin API."""
from __future__ import annotations
import copy
import hashlib
import json
import os
import re
import sqlite3
import stat
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROTOCOL = 'jrbot-runtime/2'
MODES = {'all', 'errors_only', 'none'}
LIMIT = 4 * 1024 * 1024

class FoundationError(ValueError):
    pass

def fail(code):
    raise FoundationError(code)

def stamp(value):
    return value.astimezone(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')

def time(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', value):
        fail('TIME_INVALID')
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        fail('TIME_INVALID')

def ident(value):
    if not isinstance(value, str): fail('IDENTITY_INVALID')
    try: u = uuid.UUID(value)
    except ValueError: fail('IDENTITY_INVALID')
    if u.version != 4 or str(u) != value: fail('IDENTITY_INVALID')
    return value

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)

def validate_history_detail(d):
    if not isinstance(d,dict):fail('RETENTION_RECORD_INVALID')
    lease=d.get('lease')
    if not isinstance(lease,dict):fail('RETENTION_RECORD_INVALID')
    if 'history_detail' not in d:
        if 'payload' not in lease:fail('RETENTION_RECORD_INVALID')
        return
    marker=d['history_detail']
    if (not isinstance(marker,dict) or set(marker)!={'format','state','compacted_at'} or
        type(marker['format']) is not int or marker['format']!=1 or marker['state']!='compacted' or
        d.get('status')!='completed' or 'payload' in lease):fail('RETENTION_RECORD_INVALID')
    try:time(marker['compacted_at'])
    except ValueError:fail('RETENTION_RECORD_INVALID')

def retention_finished(d):
    try:
        report=json.loads(d['report'])
        if not isinstance(report,dict) or canonical(report)!=d['report']:fail('RETENTION_RECORD_INVALID')
        finish=time(report['finished_at'])
        if finish<time(d['issued_at']):fail('RETENTION_RECORD_INVALID')
        return finish
    except (KeyError,TypeError,ValueError):fail('RETENTION_RECORD_INVALID')

def validate_retention_dispatch(d,did):
    validate_history_detail(d)
    if d.get('status')!='completed' or d['lease'].get('dispatch_id')!=did:fail('RETENTION_RECORD_INVALID')
    try:
        report=json.loads(d['report'])
        for key in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt'):
            if type(report[key]) is not type(d['lease'][key]) or report[key]!=d['lease'][key]:fail('RETENTION_RECORD_INVALID')
        if report['run_id']!=d['run']:fail('RETENTION_RECORD_INVALID')
        fields={'dispatch_id','run_id','job_id','job_key','job_revision','scheduled_for','attempt','started_at','finished_at','outcome','message','execution_started'}
        if set(report)!=fields or report['outcome'] not in ('succeeded','failed','rejected') or type(report['execution_started']) is not bool:fail('RETENTION_RECORD_INVALID')
        ident(report['run_id']);ident(report['dispatch_id']);ident(d['runner']);ident(d['session'])
        start,finish=time(report['started_at']),time(report['finished_at'])
        if finish<start or start<time(d['issued_at']) or not isinstance(report['message'],str) or len(report['message'].encode())>512:fail('RETENTION_RECORD_INVALID')
        if not report['execution_started'] and report['outcome']!='rejected':fail('RETENTION_RECORD_INVALID')
        if report['execution_started'] and d['lease']['start_before'] and start>=time(d['lease']['start_before']):fail('RETENTION_RECORD_INVALID')
    except (KeyError,TypeError,ValueError):fail('RETENTION_RECORD_INVALID')
    retention_finished(d)

def initial(instance, poll):
    if not re.fullmatch(r'[a-z][a-z0-9_-]{0,31}', instance): fail('INSTANCE_INVALID')
    if type(poll) is not int or not 1 <= poll <= 86400: fail('POLL_INVALID')
    return dict(version=2, instance=instance, poll_interval_seconds=poll, jobs={}, manual={}, dispatches={}, requests={})

def expire(state, now):
    for r in state['manual'].values():
        if r['state'] == 'pending' and time(r['expires_at']) <= now:
            r.update(state='cancelled', reason='start_deadline_exceeded', warning=True)
    for d in state['dispatches'].values():
        if d['status'] == 'active' and time(d['lease']['lease_expires_at']) <= now:
            d['status'] = 'unknown'
            d['warning'] = True

def busy(state, job):
    return any(d['status'] in ('active', 'unknown') and d['lease']['job_id'] == job
               for d in state['dispatches'].values())

def request_manual(state, data, actor, now):
    if set(data) - {'request_id', 'job_id', 'start_within_seconds'}: fail('REQUEST_INVALID')
    rid = ident(data.get('request_id'))
    jid = data.get('job_id')
    if not isinstance(jid, str) or jid not in state['jobs']: fail('JOB_NOT_FOUND')
    if not isinstance(actor, dict) or set(actor) != {'context', 'user_id'}: fail('ACTOR_INVALID')
    if not isinstance(actor['context'], str) or not re.fullmatch(r'[a-z][a-z0-9_-]{0,31}', actor['context']): fail('ACTOR_INVALID')
    if actor['user_id'] is not None and (type(actor['user_id']) is not int or actor['user_id'] < 1): fail('ACTOR_INVALID')
    if actor['user_id'] is None and actor['context'] != 'local': fail('ACTOR_INVALID')
    window = data.get('start_within_seconds', 2 * state['poll_interval_seconds'])
    if type(window) is not int or not 1 <= window <= 2 * state['poll_interval_seconds']: fail('DEADLINE_INVALID')
    binding = canonical(dict(job_id=jid, actor=actor, window=window))
    if rid in state['manual']:
        r = state['manual'][rid]
        if r['binding'] != binding: fail('REQUEST_CONFLICT')
        return copy.deepcopy(r)
    if state['jobs'][jid].get('externally_blocked', False) or busy(state, jid) or any(r['job_id'] == jid and r['state'] == 'pending' for r in state['manual'].values()): fail('JOB_BUSY')
    job = state['jobs'][jid]
    r = dict(request_id=rid, job_id=jid, job_revision=job['definition']['job_revision'],
             actor=copy.deepcopy(actor), requested_at=stamp(now), expires_at=stamp(now + timedelta(seconds=window)),
             poll_interval_seconds=state['poll_interval_seconds'], state='pending', reason=None,
             dispatch_id=None, binding=binding, warning=False)
    state['manual'][rid] = r
    return copy.deepcopy(r)

def ready(state, now, excluded):
    # Time order across independent jobs; same-job scheduled priority is handled below.
    candidates = []
    for jid, job in state['jobs'].items():
        if jid in excluded or job.get('externally_blocked', False) or busy(state, jid): continue
        definition = job['definition']
        due = time(job['next_for']) if definition['enabled'] and job['next_for'] else None
        regular_due = due is not None and due <= now
        pending = [r for r in state['manual'].values() if r['job_id'] == jid and r['state'] == 'pending']
        for r in pending:
            if r['job_revision'] != definition['job_revision']:
                r.update(state='cancelled', reason='definition_changed')
            elif regular_due:
                r.update(state='cancelled', reason='scheduled_due')
            else:
                candidates.append((time(r['requested_at']), 'manual', jid, r['request_id']))
        if regular_due: candidates.append((due, 'scheduled', jid, ''))
    return sorted(candidates)

def transition(state, operation, data, runner, session, now, new_id=None):
    ident(runner); ident(session)
    if state.get('version') != 2: fail('PROTOCOL_INSTANCE_MISMATCH')
    for record in state['dispatches'].values():validate_history_detail(record)
    expire(state, now)
    response = dict(protocol=PROTOCOL, ok=True, server_time=stamp(now))
    if operation == 'lease':
        if set(data) != {'lease_request_id', 'exclude_job_ids'}: fail('REQUEST_INVALID')
        req = ident(data['lease_request_id'])
        excluded = data['exclude_job_ids']
        if not isinstance(excluded, list) or len(excluded) > 8 or any(not isinstance(x, str) or not re.fullmatch(r'[1-9][0-9]{0,9}', x) for x in excluded) or len(set(excluded)) != len(excluded): fail('EXCLUSION_INVALID')
        key = runner + '/' + session + '/' + req
        binding = canonical(excluded)
        if key in state['requests']:
            old = state['requests'][key]
            if old['binding'] != binding: fail('REQUEST_CONFLICT')
            d = state['dispatches'].get(old['dispatch_id'])
            if d is not None and d['status'] != 'active': fail('DISPATCH_STALE')
            return dict(response, lease=copy.deepcopy(d['lease']) if d else None)
        candidates = ready(state, now, excluded)
        if not candidates:
            state['requests'][key] = dict(binding=binding, dispatch_id=None)
            return dict(response, lease=None)
        due, trigger, jid, rid = candidates[0]
        job = state['jobs'][jid]; definition = job['definition']
        dispatch = ident(new_id or str(uuid.uuid4()))
        if dispatch in state['dispatches']: fail('DISPATCH_CONFLICT')
        scheduled_for = stamp(due)
        actor = None; start_before = None
        if trigger == 'manual':
            r = state['manual'][rid]
            r.update(state='dispatched', dispatch_id=dispatch)
            actor = copy.deepcopy(r['actor']); start_before = r['expires_at']
        else:
            from job_runner import _provider_next, provider_cron_next
            schedule = definition['schedule']
            if schedule['kind'] == 'interval':
                seconds = schedule['seconds']; latest = due + timedelta(seconds=int((now-due).total_seconds() // seconds)*seconds)
                job['next_for'] = stamp(latest+timedelta(seconds=seconds)); scheduled_for = stamp(latest)
            elif schedule['kind'] == 'cron':
                latest = max(due, provider_cron_next(schedule['expression'], schedule['timezone'], now, previous=True))
                job['next_for'] = stamp(_provider_next(schedule, latest)); scheduled_for = stamp(latest)
            else: job['next_for'] = None
        lease = {k: copy.deepcopy(definition[k]) for k in ('job_id','job_key','job_revision','job_type','payload','max_attempts')}
        lease.update(dispatch_id=dispatch, scheduled_for=scheduled_for, attempt=1,
                     lease_expires_at=stamp(now+timedelta(seconds=definition['lease_seconds'])),
                     trigger=trigger, request_id=rid or None, start_before=start_before)
        state['dispatches'][dispatch] = dict(lease=lease, status='active', runner=runner, session=session,
            run=None, issued_at=stamp(now), report=None, late_evidence=None, actor=actor, log_mode=job['log_mode'], lease_seconds=definition['lease_seconds'], warning=False)
        state['requests'][key] = dict(binding=binding, dispatch_id=dispatch)
        return dict(response, lease=copy.deepcopy(lease))
    if operation not in ('renew','report'): fail('OPERATION_INVALID')
    did = ident(data.get('dispatch_id')); run = ident(data.get('run_id'))
    d = state['dispatches'].get(did)
    if not d: fail('DISPATCH_STALE')
    if d['runner'] != runner or d['session'] != session or d['run'] not in (None, run): fail('DISPATCH_BINDING_MISMATCH')
    if operation == 'renew':
        if set(data) != {'dispatch_id','run_id'}: fail('REQUEST_INVALID')
        if d['status'] != 'active': fail('DISPATCH_STALE')
        if d['run'] is None and d['lease']['start_before'] and time(d['lease']['start_before']) <= now: fail('START_DEADLINE_EXCEEDED')
        d['run'] = run
        # Never extend start_before: renew only execution lease.
        seconds = d['lease_seconds']
        d['lease']['lease_expires_at'] = stamp(now+timedelta(seconds=seconds))
        return dict(response, lease_expires_at=d['lease']['lease_expires_at'])
    fields = {'dispatch_id','run_id','job_id','job_key','job_revision','scheduled_for','attempt','started_at','finished_at','outcome','message','execution_started'}
    if set(data) != fields: fail('REPORT_INVALID')
    if d['run'] != run: fail('DISPATCH_BINDING_MISMATCH')
    for k in ('job_id','job_key','job_revision','scheduled_for','attempt'):
        if type(data[k]) is not type(d['lease'][k]) or data[k] != d['lease'][k]: fail('DISPATCH_BINDING_MISMATCH')
    if data['outcome'] not in ('succeeded','failed','rejected') or type(data['execution_started']) is not bool: fail('REPORT_INVALID')
    start, finish = time(data['started_at']), time(data['finished_at'])
    if finish < start or finish > now or start < time(d['issued_at']): fail('REPORT_INVALID')
    if not isinstance(data['message'], str) or len(data['message'].encode()) > 512: fail('REPORT_INVALID')
    if not data['execution_started'] and data['outcome'] != 'rejected': fail('REPORT_INVALID')
    if data['execution_started'] and d['lease']['start_before'] and start >= time(d['lease']['start_before']): fail('START_DEADLINE_EXCEEDED')
    body = canonical(data)
    if d['report'] is not None:
        if body != d['report']: fail('REPORT_CONFLICT')
        return dict(response, result_state='already_recorded')
    if d['status'] == 'unknown':
        if d['late_evidence'] is not None and d['late_evidence'] != body: fail('REPORT_CONFLICT')
        d['late_evidence'] = body
        return dict(response, result_state='recovery_evidence_only')
    if d['status'] != 'active': fail('DISPATCH_STALE')
    d.update(report=body, status='completed')
    r = state['manual'].get(d['lease']['request_id'])
    if r and not data['execution_started']: r.update(reason='not_started')
    return dict(response, result_state='recorded')

DDL_MANUAL = '''CREATE TABLE jrbot_manual_requests (
 instance TEXT NOT NULL, request_id TEXT NOT NULL, job_id TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('pending','dispatched','cancelled')),
 active_job_id TEXT, document TEXT NOT NULL,
 PRIMARY KEY(instance,request_id), UNIQUE(instance,active_job_id))'''
DDL_LOG = '''CREATE TABLE tbl_job_log (
 id INTEGER PRIMARY KEY AUTOINCREMENT, job_id INTEGER NOT NULL, bot_name TEXT NOT NULL,
 ran_at TEXT NOT NULL, duration_ms INTEGER, ok INTEGER NOT NULL CHECK(ok IN(0,1)),
 message TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 instance TEXT, dispatch_id TEXT, outcome TEXT,
 CHECK((instance IS NULL AND dispatch_id IS NULL AND outcome IS NULL) OR
 (instance IS NOT NULL AND dispatch_id IS NOT NULL AND outcome IS NOT NULL AND outcome IN('succeeded','failed','rejected'))),
 UNIQUE(instance,dispatch_id))'''

def migrate_sqlite(db, instance, poll):
    """Explicit caller-owned transaction only; no connection/path discovery."""
    if not db.in_transaction: fail('MIGRATION_TRANSACTION_REQUIRED')
    version = db.execute('PRAGMA user_version').fetchone()[0]
    if version != 0: fail('SCHEMA_VERSION_UNSUPPORTED')
    cols = {r[1] for r in db.execute('PRAGMA table_info(tbl_jobs)')}
    if not cols or 'log_mode' in cols: fail('SCHEMA_PARTIAL')
    old = db.execute('SELECT document FROM jrbot_provider_state WHERE instance=?',(instance,)).fetchone()
    if not old: fail('STATE_MISSING')
    state = json.loads(old[0])
    if state.get('version') != 1: fail('SCHEMA_PARTIAL')
    if db.execute("SELECT 1 FROM jrbot_provider_dispatches WHERE instance=? AND status IN('active','unknown') LIMIT 1",(instance,)).fetchone(): fail('ACTIVE_DISPATCH_CUTOVER_REQUIRED')
    if db.execute('SELECT 1 FROM jrbot_provider_dispatches WHERE instance=? LIMIT 1',(instance,)).fetchone(): fail('HISTORY_CUTOVER_REQUIRED')
    # Complete log-object preflight before the first schema write.
    log_cols = {r[1] for r in db.execute('PRAGMA table_info(tbl_job_log)')}
    indexes = []
    if log_cols:
        if log_cols != {'id','job_id','bot_name','ran_at','duration_ms','ok','message','created_at'}: fail('SCHEMA_PARTIAL')
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='jrbot_log_legacy_v2_upgrade'").fetchone(): fail('SCHEMA_PARTIAL')
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='trigger' AND tbl_name='tbl_job_log'").fetchone(): fail('SCHEMA_LOG_TRIGGER_REVIEW_REQUIRED')
        # A rename can retarget dependent view SQL. Refuse conservatively.
        for view in db.execute("SELECT sql FROM sqlite_master WHERE type='view'"):
            if re.search(r'(?i)(?<![A-Za-z0-9_])tbl_job_log(?![A-Za-z0-9_])', view[0] or ''): fail('SCHEMA_LOG_VIEW_REVIEW_REQUIRED')
        allowed = {'idx_job_time': ('job_id','ran_at'), 'idx_bot_time': ('bot_name','ran_at')}
        for index in db.execute('PRAGMA index_list(tbl_job_log)').fetchall():
            name = index[1]
            if name not in allowed or index[2] != 0 or index[3] != 'c' or index[4] != 0: fail('SCHEMA_UNRECOGNIZED_INDEX')
            parts = [r for r in db.execute('PRAGMA index_xinfo('+name+')') if r[5] == 1]
            if tuple(r[2] for r in parts) != allowed[name] or any(r[1] < 0 or r[3] != 0 or r[4] != 'BINARY' for r in parts): fail('SCHEMA_UNRECOGNIZED_INDEX')
            indexes.append((name, allowed[name]))
        for table in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',table[0]):fail('SCHEMA_PARTIAL')
            if any(f[2]=='tbl_job_log' for f in db.execute('PRAGMA foreign_key_list('+table[0]+')')): fail('SCHEMA_LOG_FK_REVIEW_REQUIRED')
    db.execute("ALTER TABLE tbl_jobs ADD COLUMN log_mode TEXT NOT NULL DEFAULT 'all' CHECK(log_mode IN('all','errors_only','none'))")
    if log_cols:
        db.execute('ALTER TABLE tbl_job_log RENAME TO jrbot_log_legacy_v2_upgrade')
        db.execute(DDL_LOG)
        db.execute('INSERT INTO tbl_job_log(id,job_id,bot_name,ran_at,duration_ms,ok,message,created_at) SELECT id,job_id,bot_name,ran_at,duration_ms,ok,message,created_at FROM jrbot_log_legacy_v2_upgrade')
        db.execute('DROP TABLE jrbot_log_legacy_v2_upgrade')
        for name, columns in indexes:
            db.execute('CREATE INDEX '+name+' ON tbl_job_log('+','.join(columns)+')')
    else:
        db.execute(DDL_LOG)
    db.execute(DDL_MANUAL)
    db.execute('ALTER TABLE jrbot_provider_requests ADD COLUMN document TEXT')
    db.execute('UPDATE jrbot_provider_state SET document=? WHERE instance=?',(canonical(initial(instance,poll)),instance))
    db.execute('PRAGMA user_version=2')

def checked_path(path):
    path = Path(path).absolute()
    if any(p.is_symlink() for p in [path,*path.parents]): fail('DB_SYMLINK')
    s = path.stat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_mode & 0o022: fail('DB_UNSAFE')
    return path

# F04: a deliberately narrow, token-exact schema language, not a DDL repairer.
# String literals retain their value/case; quoted identifiers and whitespace may vary.
_SCHEMA_TOKEN = re.compile(r"\s+|--[^\n]*(?:\n|$)|/\*.*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|`(?:``|[^`])*`|\[[^\]]*\]|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[(),;=]", re.S)

def _schema_tokens(sql):
    tokens, pos = [], 0
    while pos < len(sql):
        match = _SCHEMA_TOKEN.match(sql, pos)
        if not match: fail('PROVIDER_SCHEMA_INVALID')
        text = match.group(); pos = match.end()
        if text.isspace() or text.startswith(('--', '/*')): continue
        if text[0] == "'": tokens.append(('literal', text[1:-1].replace("''", "'")))
        elif text[0] in ('"', '`', '['):
            name = text[1:-1]
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name): fail('PROVIDER_SCHEMA_INVALID')
            tokens.append(('word', name.lower()))
        elif re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', text): tokens.append(('word', text.lower()))
        else: tokens.append(('symbol', text))
    return tokens

def _schema_body(sql, name):
    tokens = _schema_tokens(sql)
    w = lambda x: ('word', x)
    if tokens[:2] != [w('create'), w('table')]: fail('PROVIDER_SCHEMA_INVALID')
    at = 2
    if tokens[at:at+3] == [w('if'), w('not'), w('exists')]: at += 3
    if tokens[at:at+2] != [w(name), ('symbol', '(')]: fail('PROVIDER_SCHEMA_INVALID')
    body, depth = [], 1
    for token in tokens[at+2:]:
        if depth == 0:
            if token != ('symbol', ';'): fail('PROVIDER_SCHEMA_INVALID')
            continue
        if token == ('symbol', '('): depth += 1
        if token == ('symbol', ')'): depth -= 1
        if depth: body.append(token)
    if depth: fail('PROVIDER_SCHEMA_INVALID')
    return body

def schema_guard_sqlite(db):
    """Only reads metadata. Caller owns BEGIN IMMEDIATE; never migrates or caches."""
    import sqlite3
    from job_runner import SQLITE_JOBS_DDL
    try:
        if db.execute('PRAGMA user_version').fetchone()[0] != 2: fail('PROVIDER_SCHEMA_INVALID')
        enabled = db.execute('PRAGMA ignore_check_constraints').fetchone()
        if enabled is None: fail('PROVIDER_SCHEMA_UNVERIFIABLE')
        if enabled[0] != 0: fail('PROVIDER_SCHEMA_INVALID')
        templates = {
            'tbl_jobs': SQLITE_JOBS_DDL[:-1] + ", log_mode TEXT NOT NULL DEFAULT 'all' CHECK(log_mode IN('all','errors_only','none')))",
            'tbl_job_log': DDL_LOG,
            'jrbot_manual_requests': DDL_MANUAL,
            'jrbot_provider_state': 'CREATE TABLE jrbot_provider_state(instance TEXT PRIMARY KEY, document TEXT NOT NULL)',
            'jrbot_provider_dispatches': 'CREATE TABLE jrbot_provider_dispatches(instance TEXT NOT NULL, dispatch_id TEXT NOT NULL, status TEXT NOT NULL, document TEXT NOT NULL, PRIMARY KEY(instance,dispatch_id))',
            'jrbot_provider_requests': 'CREATE TABLE jrbot_provider_requests(instance TEXT NOT NULL, request_key TEXT NOT NULL, dispatch_id TEXT, document TEXT, PRIMARY KEY(instance,request_key))',
        }
        # ALTER ADD COLUMN appends after an existing table constraint. Both exact
        # known orderings are equivalent here; no arbitrary expression rewriting.
        requests_alt = 'CREATE TABLE jrbot_provider_requests(instance TEXT NOT NULL, request_key TEXT NOT NULL, dispatch_id TEXT, PRIMARY KEY(instance,request_key), document TEXT)'
        known = set(templates)
        objects = db.execute('SELECT type,name,tbl_name,sql FROM sqlite_master').fetchall()
        for obj in objects:
            if obj[0] == 'trigger' and obj[2].lower() in known: fail('PROVIDER_SCHEMA_INVALID')
        unique = {
            'tbl_jobs': {('bot_name','job_key')}, 'tbl_job_log': {('instance','dispatch_id')},
            'jrbot_manual_requests': {('instance','request_id'),('instance','active_job_id')},
            'jrbot_provider_state': {('instance',)},
            'jrbot_provider_dispatches': {('instance','dispatch_id')},
            'jrbot_provider_requests': {('instance','request_key')},
        }
        for name, template in templates.items():
            found = [o for o in objects if o[1].lower() == name]
            if len(found) != 1 or found[0][0] != 'table' or not found[0][3]: fail('PROVIDER_SCHEMA_INVALID')
            accepted = [_schema_body(template, name)]
            if name == 'jrbot_provider_requests': accepted.append(_schema_body(requests_alt, name))
            if name == 'tbl_jobs':
                before_unique = SQLITE_JOBS_DDL.replace(
                    ', UNIQUE(bot_name,job_key)',
                    ", log_mode TEXT NOT NULL DEFAULT 'all' CHECK(log_mode IN('all','errors_only','none')), UNIQUE(bot_name,job_key)")
                accepted.append(_schema_body(before_unique, name))
            if _schema_body(found[0][3], name) not in accepted: fail('PROVIDER_SCHEMA_INVALID')
            observed = []
            for index in db.execute('PRAGMA index_list("'+name+'")').fetchall():
                iname = index[1].replace('"','""')
                parts = [r for r in db.execute('PRAGMA index_xinfo("'+iname+'")') if r[5] == 1]
                if index[4] or not parts or any(p[1] < 0 or p[3] != 0 or p[4] != 'BINARY' for p in parts): fail('PROVIDER_SCHEMA_INVALID')
                if index[2]: observed.append(tuple(p[2].lower() for p in parts))
            if len(observed) != len(unique[name]) or set(observed) != unique[name]: fail('PROVIDER_SCHEMA_INVALID')
        # Incoming foreign keys can add write side effects; none are part of this
        # explicitly recognized baseline contract. Quote catalog names safely.
        for obj in objects:
            if obj[0] != 'table': continue
            quoted = obj[1].replace('"','""')
            for foreign in db.execute('PRAGMA foreign_key_list("'+quoted+'")'):
                if obj[1].lower() in known or foreign[2].lower() in known: fail('PROVIDER_SCHEMA_INVALID')
    except sqlite3.Error:
        fail('PROVIDER_SCHEMA_UNVERIFIABLE')

class SQLiteFoundation:
    """Opt-in v2 provider; v1 LocalDbProvider and main() remain untouched."""
    def __init__(self, path, instance, runner, session):
        self.path=checked_path(path);self.instance=instance;self.runner=ident(runner);self.session=ident(session)

    def _load_work(self, db, state, operation, data, jobs):
        """Open work is never truncated; historical identity lookups use the PK."""
        manual_active = {}
        state.update(manual={}, dispatches={}, requests={})
        def manual(rows):
            for row in rows:
                state['manual'][row[0]] = json.loads(row[1]); manual_active[row[0]] = row[2]
        def dispatch(rows):
            for row in rows:
                d = json.loads(row[1])
                if d['status'] != row[2]: fail('RETENTION_RECORD_INVALID')
                validate_history_detail(d); state['dispatches'][row[0]] = d
        if operation == 'inspect':
            manual(db.execute('SELECT request_id,document,active_job_id FROM jrbot_manual_requests WHERE instance=?',(self.instance,)))
            dispatch(db.execute('SELECT dispatch_id,document,status FROM jrbot_provider_dispatches WHERE instance=?',(self.instance,)))
            receipts = db.execute('SELECT request_key,document,dispatch_id FROM jrbot_provider_requests WHERE instance=?',(self.instance,)).fetchall()
            if max(len(state['manual']),len(state['dispatches']),len(receipts)) > 10000: fail('STATE_CAPACITY')
        else:
            manual(db.execute('SELECT request_id,document,active_job_id FROM jrbot_manual_requests WHERE instance=? AND active_job_id IS NOT NULL',(self.instance,)))
            dispatch(db.execute("SELECT dispatch_id,document,status FROM jrbot_provider_dispatches WHERE instance=? AND status IN ('active','unknown')",(self.instance,)))
            receipts = []
            if operation == 'request_manual':
                rid = ident(data.get('request_id'))
                manual(db.execute('SELECT request_id,document,active_job_id FROM jrbot_manual_requests WHERE instance=? AND request_id=?',(self.instance,rid)))
            elif operation == 'lease':
                key = self.runner+'/'+self.session+'/'+ident(data.get('lease_request_id'))
                receipts = db.execute('SELECT request_key,document,dispatch_id FROM jrbot_provider_requests WHERE instance=? AND request_key=?',(self.instance,key)).fetchall()
            elif operation in ('renew','report'):
                did = ident(data.get('dispatch_id'))
                dispatch(db.execute('SELECT dispatch_id,document,status FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?',(self.instance,did)))
            else: fail('OPERATION_INVALID')
        for key,body,did in receipts:
            state['requests'][key] = json.loads(body) if body is not None else dict(binding='__legacy_v1__',dispatch_id=did)
        # Close only references reachable from open work, the request, and locks.
        wanted_d = {r['dispatch_id'] for r in state['requests'].values() if r['dispatch_id'] is not None}
        wanted_d.update(r['locked_by'] for r in jobs if r.get('locked_by'))
        checked_d, checked_m = set(), set()
        while True:
            wanted_d.update(r['dispatch_id'] for r in state['manual'].values() if r.get('dispatch_id'))
            todo = wanted_d-set(state['dispatches'])-checked_d
            for did in todo:
                dispatch(db.execute('SELECT dispatch_id,document,status FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?',(self.instance,did)))
                checked_d.add(did)
            wanted_m = {d['lease']['request_id'] for d in state['dispatches'].values() if d['lease'].get('request_id')}
            more = wanted_m-set(state['manual'])-checked_m
            for rid in more:
                manual(db.execute('SELECT request_id,document,active_job_id FROM jrbot_manual_requests WHERE instance=? AND request_id=?',(self.instance,rid)))
                checked_m.add(rid)
            if not todo and not more: break
        for record in state['requests'].values():
            if record['dispatch_id'] is not None and record['dispatch_id'] not in state['dispatches']: fail('RETENTION_RECORD_INVALID')
        for r in state['manual'].values():
            if r.get('dispatch_id') is not None and r['dispatch_id'] not in state['dispatches']: fail('RETENTION_RECORD_INVALID')
        for d in state['dispatches'].values():
            if d['lease'].get('request_id') is not None and d['lease']['request_id'] not in state['manual']: fail('RETENTION_RECORD_INVALID')
        return manual_active

    def operation(self, operation, data, *, now, actor=None):
        from job_runner import _source_job, JOB_DEFINITION_FIELDS, _db_bot, ProviderStateError
        now=time(now);checked_path(self.path)
        db=sqlite3.connect(self.path.as_uri()+'?mode=rw',uri=True);db.row_factory=sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE');schema_guard_sqlite(db)
            row=db.execute('SELECT document FROM jrbot_provider_state WHERE instance=?',(self.instance,)).fetchone()
            if not row: fail('STATE_MISSING')
            old_body=row[0];state=json.loads(old_body)
            if state.get('version')!=2 or state.get('instance')!=self.instance: fail('PROTOCOL_INSTANCE_MISMATCH')
            rows=[dict(r) for r in db.execute('SELECT * FROM tbl_jobs WHERE bot_name=? COLLATE BINARY ORDER BY id',(_db_bot(self.instance),))]
            manual_active=self._load_work(db,state,operation,data,rows)
            before=copy.deepcopy(state)
            seen=set()
            for row in rows:
                jid=str(row['id']);seen.add(jid)
                if row['log_mode'] not in MODES:fail('LOG_MODE_INVALID')
                old=state['jobs'].get(jid)
                lock_owner=row.get('locked_by');lock_until=row.get('locked_until_utc')
                foreign_lock=bool(lock_owner and lock_owner not in state['dispatches'] and
                    (not lock_until or time(lock_until.replace(' ','T')+'Z')>now))
                if old:old['externally_blocked']=foreign_lock
                fp=hashlib.sha256(canonical([row[k] for k in JOB_DEFINITION_FIELDS]+[row['log_mode']]).encode()).hexdigest()
                if old and old['fingerprint']==fp:
                    if old['projected_next']!=row['next_run_utc']:fail('SCHEDULE_EXTERNAL_CHANGE')
                    continue
                mapped=dict(row,enabled=1)
                try:definition=_source_job(mapped,self.instance,old['definition']['job_revision']+1 if old else 1)
                except ProviderStateError:
                    if not row['enabled'] and not old:continue
                    raise
                definition['enabled']=bool(row['enabled'])
                state['jobs'][jid]=dict(definition=definition,next_for=definition['start_at'],log_mode=row['log_mode'],fingerprint=fp,projected_next=row['next_run_utc'],externally_blocked=foreign_lock)
            for jid in set(state['jobs'])-seen:
                if busy(state,jid):continue
                for req in state['manual'].values():
                    if req['job_id']==jid and req['state']=='pending':req.update(state='cancelled',reason='job_deleted')
                del state['jobs'][jid]
            expire(state,now)
            if operation=='request_manual':result=request_manual(state,data,actor,now)
            elif operation=='inspect':result=copy.deepcopy(state)
            else:result=transition(state,operation,data,self.runner,self.session,now)
            relational={str(r['id']):r for r in rows}
            for jid,job in state['jobs'].items():
                next_sql=job['next_for'].replace('T',' ').removesuffix('Z') if job['next_for'] else None
                if jid in relational and relational[jid]['next_run_utc']!=next_sql:
                    db.execute('UPDATE tbl_jobs SET next_run_utc=? WHERE id=? AND bot_name=? COLLATE BINARY',(next_sql,int(jid),_db_bot(self.instance)))
                job['projected_next']=next_sql
            for did,d in state['dispatches'].items():
                old=before['dispatches'].get(did)
                if old==d:continue
                lease=d['lease'];jid=int(lease['job_id'])
                if old is None:
                    if db.execute('SELECT 1 FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?',(self.instance,did)).fetchone():fail('DISPATCH_CONFLICT')
                    db.execute('UPDATE tbl_jobs SET locked_by=?,locked_until_utc=?,last_dispatch_utc=? WHERE id=? AND bot_name=? COLLATE BINARY',(did,lease['lease_expires_at'].replace('T',' ').removesuffix('Z'),stamp(now).replace('T',' ').removesuffix('Z'),jid,_db_bot(self.instance)))
                if d['status']=='completed' and (old is None or old['status']!='completed'):
                    report=json.loads(d['report'])
                    if report['execution_started']:
                        duration=min(int((time(report['finished_at'])-time(report['started_at'])).total_seconds()*1000),2147483647);ok=int(report['outcome']=='succeeded')
                        db.execute('UPDATE tbl_jobs SET last_run_utc=?,last_ok=?,last_message=?,last_duration_ms=? WHERE id=? AND bot_name=? COLLATE BINARY',(report['finished_at'].replace('T',' ').removesuffix('Z'),ok,report['message'],duration,jid,_db_bot(self.instance)))
                        if d['log_mode']=='all' or d['log_mode']=='errors_only' and not ok:
                            db.execute('INSERT INTO tbl_job_log(job_id,bot_name,ran_at,duration_ms,ok,message,instance,dispatch_id,outcome)VALUES(?,?,?,?,?,?,?,?,?)',(jid,_db_bot(self.instance),report['finished_at'].replace('T',' ').removesuffix('Z'),duration,ok,report['message'],self.instance,did,report['outcome']))
                    db.execute('UPDATE tbl_jobs SET locked_by=NULL,locked_until_utc=NULL WHERE id=? AND bot_name=? COLLATE BINARY AND locked_by=?',(jid,_db_bot(self.instance),did))
                db.execute('INSERT INTO jrbot_provider_dispatches VALUES(?,?,?,?) ON CONFLICT(instance,dispatch_id) DO UPDATE SET status=excluded.status,document=excluded.document',(self.instance,did,d['status'],canonical(d)))
            changes=[]
            for rid,req in state['manual'].items():
                active=req['job_id'] if req['state']=='pending' or req['state']=='dispatched' and state['dispatches'][req['dispatch_id']]['status'] in ('active','unknown') else None
                if before['manual'].get(rid)!=req or manual_active.get(rid)!=active:
                    changes.append((rid,req,active))
            # Release only guards belonging to changed, now terminal requests.
            for rid,req,active in changes:
                if active is None and manual_active.get(rid) is not None:
                    db.execute('UPDATE jrbot_manual_requests SET active_job_id=NULL WHERE instance=? AND request_id=?',(self.instance,rid))
            for rid,req,active in changes:
                db.execute('INSERT INTO jrbot_manual_requests VALUES(?,?,?,?,?,?) ON CONFLICT(instance,request_id) DO UPDATE SET state=excluded.state,active_job_id=excluded.active_job_id,document=excluded.document',(self.instance,rid,req['job_id'],req['state'],active,canonical(req)))
            for key,record in state['requests'].items():
                if key not in before['requests']:
                    db.execute('INSERT INTO jrbot_provider_requests(instance,request_key,dispatch_id,document) VALUES(?,?,?,?)',(self.instance,key,record['dispatch_id'],canonical(record)))
            stored=dict(state,manual={},dispatches={},requests={});body=canonical(stored)
            if len(body.encode())>LIMIT:fail('STATE_CAPACITY')
            if body!=old_body:db.execute('UPDATE jrbot_provider_state SET document=? WHERE instance=?',(body,self.instance))
            db.commit();return result
        except Exception:
            db.rollback();raise
        finally:db.close()

    def maintain(self, *, now, dispatch_after=None, log_after=0):
        now=time(now)
        if dispatch_after is not None:ident(dispatch_after)
        if type(log_after) is not int or not 0<=log_after<=9223372036854775807:fail('RETENTION_CURSOR_INVALID')
        checked_path(self.path);db=sqlite3.connect(self.path.as_uri()+'?mode=rw',uri=True);db.row_factory=sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE');schema_guard_sqlite(db)
            row=db.execute('SELECT document FROM jrbot_provider_state WHERE instance=?',(self.instance,)).fetchone()
            if not row:fail('STATE_MISSING')
            state=json.loads(row[0])
            if state.get('version')!=2 or state.get('instance')!=self.instance:fail('PROTOCOL_INSTANCE_MISMATCH')
            dispatches=db.execute("SELECT dispatch_id,status,document FROM jrbot_provider_dispatches WHERE instance=? AND status='completed' AND dispatch_id>? ORDER BY dispatch_id COLLATE BINARY LIMIT 100",(self.instance,dispatch_after or '')).fetchall()
            logs=db.execute('SELECT id,dispatch_id,ran_at FROM tbl_job_log WHERE instance=? AND dispatch_id IS NOT NULL AND outcome IS NOT NULL AND id>? ORDER BY id LIMIT 100',(self.instance,log_after)).fetchall()
            result=dict(dispatch_after=dispatch_after,log_after=log_after,dispatch_done=len(dispatches)<100,log_done=len(logs)<100,dispatch_visited=len(dispatches),log_visited=len(logs),dispatch_compacted=0,logs_deleted=0)
            for row in dispatches:
                did=ident(row['dispatch_id']);result['dispatch_after']=did;d=json.loads(row['document'])
                validate_retention_dispatch(d,did)
                if 'history_detail' in d:continue
                if retention_finished(d)>now-timedelta(days=30):continue
                if self._retention_protected(db,d):continue
                del d['lease']['payload'];d['history_detail']=dict(format=1,state='compacted',compacted_at=stamp(now))
                db.execute('UPDATE jrbot_provider_dispatches SET document=? WHERE instance=? AND dispatch_id=?',(canonical(d),self.instance,did));result['dispatch_compacted']+=1
            for row in logs:
                result['log_after']=row['id']
                try:ran=time(row['ran_at'].replace(' ','T')+'Z')
                except (ValueError,TypeError,AttributeError):fail('RETENTION_RECORD_INVALID')
                if ran>now-timedelta(days=90):continue
                drow=db.execute('SELECT status,document FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?',(self.instance,row['dispatch_id'])).fetchone()
                if not drow:continue
                d=json.loads(drow['document'])
                if d.get('status')!=drow['status']:fail('RETENTION_RECORD_INVALID')
                validate_history_detail(d)
                if drow['status']!='completed':continue
                validate_retention_dispatch(d,row['dispatch_id'])
                if retention_finished(d)>now or self._retention_protected(db,d):continue
                db.execute('DELETE FROM tbl_job_log WHERE instance=? AND id=?',(self.instance,row['id']));result['logs_deleted']+=1
            db.commit();return result
        except Exception:
            db.rollback();raise
        finally:db.close()

    def _retention_protected(self, db, d):
        rid=d['lease'].get('request_id')
        if rid is None:return False
        row=db.execute('SELECT document,active_job_id FROM jrbot_manual_requests WHERE instance=? AND request_id=?',(self.instance,rid)).fetchone()
        if not row:fail('RETENTION_RECORD_INVALID')
        r=json.loads(row['document'])
        if r.get('dispatch_id')!=d['lease']['dispatch_id'] or r.get('job_id')!=d['lease']['job_id']:fail('RETENTION_RECORD_INVALID')
        return row['active_job_id'] is not None or r.get('state')=='pending'
