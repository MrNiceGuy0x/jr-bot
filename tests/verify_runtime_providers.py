#!/usr/bin/env python3
"""Native provider contract vectors; imported by the private MariaDB harness."""
import argparse
import concurrent.futures
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
try:
    import requests
except ModuleNotFoundError:
    import types
    requests = types.ModuleType('requests')
    requests.RequestException = RuntimeError
    requests.Session = lambda: (_ for _ in ()).throw(AssertionError('NETWORK_FORBIDDEN'))
    sys.modules['requests'] = requests
import job_runner as jr

NOW = datetime(2026, 10, 8, 12, tzinfo=timezone.utc)
RUNNER = '11111111-1111-4111-8111-111111111111'
SESSION = '22222222-2222-4222-8222-222222222222'
RUN = '33333333-3333-4333-8333-333333333333'


def job(**updates):
    value = dict(job_id='j1', job_key='jrbot_heartbeat', job_revision=1,
                 job_type='system', payload={'action': 'system.jrbot_heartbeat'},
                 schedule={'kind': 'once'}, start_at=jr._provider_stamp(NOW),
                 max_attempts=2, retry_delay_seconds=5, lease_seconds=30,
                 catch_up='coalesce_latest', enabled=True)
    value.update(updates)
    return value


def report(lease, **updates):
    value = {k: lease[k] for k in ('job_id', 'job_key', 'job_revision', 'dispatch_id', 'scheduled_for', 'attempt')}
    value.update(protocol=jr.RUNTIME_PROTOCOL, instance='ggb', runner_id=RUNNER,
                 session_id=SESSION, run_id=RUN, started_at=jr._provider_stamp(NOW),
                 finished_at=jr._provider_stamp(NOW), outcome='succeeded',
                 retryable=False, message='synthetic provider test', result={})
    value.update(updates)
    return value


def rejected(function, code=None):
    try:
        function()
    except Exception as exc:
        if code is not None:
            assert str(exc) == code, (str(exc), code)
        return
    raise AssertionError('invalid operation accepted')


def normalize(value):
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, str):
        try:
            if uuid.UUID(value).version == 4:
                return '<uuid-v4>'
        except ValueError:
            pass
    return value


def contract_vectors(make):
    frames = []
    with make() as p:
        p.call('put_job', job(payload={'action': 'system.jrbot_heartbeat', 'empty': {}, 'args': [1, {'nested': {}}]}))
        request = str(uuid.uuid4())
        lease = p.call('lease', {'lease_request_id': request})['lease']
        assert lease['attempt'] == 1 and lease['job_revision'] == 1
        assert p.call('lease', {'lease_request_id': request})['lease'] == lease
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        rejected(lambda: p.call('renew', {'dispatch_id': lease['dispatch_id'], 'run_id': RUN}, runner=str(uuid.uuid4())), 'DISPATCH_BINDING_MISMATCH')
        assert p.call('renew', {'dispatch_id': lease['dispatch_id'], 'run_id': RUN})['lease_expires_at'] == '2026-10-08T12:00:30Z'
        rejected(lambda: p.call('report', report(lease, instance='other')), 'REPORT_INVALID')
        rejected(lambda: p.call('report', report(lease, job_revision=2)), 'DISPATCH_BINDING_MISMATCH')
        rejected(lambda: p.call('report', report(lease, result=[])))
        assert p.call('report', report(lease))['result_state'] == 'recorded'
        assert p.call('report', report(lease))['result_state'] == 'already_recorded'
        rejected(lambda: p.call('report', report(lease, message='changed')), 'REPORT_CONFLICT')
        rejected(lambda: p.call('renew', {'dispatch_id': lease['dispatch_id'], 'run_id': RUN}), 'DISPATCH_STALE')
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        p.now += timedelta(days=1)
        assert p.call('report', report(lease))['result_state'] == 'already_recorded'
        frames.append(normalize(lease))
    with make() as p:
        p.call('put_job', job())
        first = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        p.now += timedelta(seconds=31)
        rejected(lambda: p.call('renew', {'dispatch_id': first['dispatch_id'], 'run_id': RUN}), 'DISPATCH_STALE')
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        p.now += timedelta(seconds=5)
        second = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        assert second['attempt'] == 2 and second['dispatch_id'] != first['dispatch_id']
        assert second['scheduled_for'] == first['scheduled_for']
        rejected(lambda: p.call('report', report(first)), 'DISPATCH_STALE')
        p.now += timedelta(seconds=31)
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        frames.append(normalize(second))
    with make() as p:
        p.call('put_job', job())
        first = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        p.call('put_job', job(job_revision=2, payload={'action': 'system.jrbot_heartbeat', 'new': True}))
        assert first['job_revision'] == 1
        p.call('report', report(first, outcome='failed', retryable=True))
        p.now += timedelta(seconds=5)
        retry = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        assert retry['job_revision'] == 1 and retry['attempt'] == 2
        p.call('report', report(retry, outcome='rejected'))
        replacement = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        assert replacement['job_revision'] == 2
        frames.append(normalize(replacement))
    with make() as p:
        p.call('put_job', job(schedule={'kind': 'interval', 'seconds': 60}, start_at='2026-10-08T11:50:00Z'))
        lease = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        assert lease['scheduled_for'] == '2026-10-08T12:00:00Z'
        p.call('report', report(lease, outcome='failed', retryable=False))
        p.now += timedelta(seconds=60)
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']['scheduled_for'] == '2026-10-08T12:01:00Z'
        frames.append(normalize(lease))
    with make() as p:
        p.call('put_job', job(schedule={'kind': 'interval', 'seconds': 60}, start_at='2026-10-08T11:50:00Z', catch_up='skip_missed'))
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        p.now += timedelta(seconds=60)
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is not None
    with make() as p:
        p.call('put_job', job(enabled=False))
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'] is None
        rejected(lambda: p.call('put_job', job()), 'JOB_REVISION_CONFLICT')
        rejected(lambda: p.call('put_job', job(job_id='j2')), 'JOB_KEY_CONFLICT')
        for bad in [job(job_revision=True), job(max_attempts=0), job(schedule={'kind': 'cron', 'expression': '61 * * * *', 'timezone': 'UTC'}), job(catch_up='replay_all'), job(payload=[]), job(job_type='shell')]:
            rejected(lambda bad=bad: p.call('put_job', bad))
    with make() as p:
        p.call('presence', {})
        assert p.presence() == ('ggb', '2026-10-08T12:00:00Z', 'yellow')
        p.set_alert_state()
        p.now += timedelta(seconds=1)
        p.call('presence', {})
        assert p.presence() == ('ggb', '2026-10-08T12:00:01Z', 'red')
        rejected(lambda: p.call('presence', {'instance': 'other'}))
        assert p.foreign_presence_count() == 0
    with make() as p:
        p.call('put_job', job(schedule={'kind': 'cron', 'expression': '0 * * * *', 'timezone': 'Europe/Vienna'}, start_at='2026-10-08T11:00:01Z'))
        lease = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        assert lease['scheduled_for'] == '2026-10-08T12:00:00Z'
        frames.append(normalize(lease))
    with make() as p:
        p.call('put_job', job(schedule={'kind': 'cron', 'expression': '* * * * *', 'timezone': 'UTC'}, start_at='2025-01-01T00:00:00Z'))
        assert p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']['scheduled_for'] == '2026-10-08T12:00:00Z'
    return frames


class LocalFixture:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory()
        base = Path(self.temp.name) / 'ggb'
        (base / 'state').mkdir(parents=True)
        self.cfg = jr.RuntimeConfig('ggb', 'standalone', 'local_pi', base, '', 'none')
        jr.LocalDbProvider.prepare(self.cfg)
        self.now = NOW
        self.provider = jr.LocalDbProvider(self.cfg, RUNNER, SESSION, clock=lambda: self.now)
    def __enter__(self): return self
    def __exit__(self, *args): self.temp.cleanup()
    def call(self, op, data, runner=RUNNER, session=SESSION):
        p = jr.LocalDbProvider(self.cfg, runner, session, clock=lambda: self.now)
        return p._operation(op, data)
    def db(self): return sqlite3.connect(self.provider.path)
    def presence(self):
        with self.db() as db:
            return db.execute('SELECT bot_name,last_seen,last_status FROM tbl_bot_status').fetchone()
    def set_alert_state(self):
        with self.db() as db:
            db.execute("UPDATE tbl_bot_status SET last_status='red',last_alert_at='2026-10-08T00:00:00Z'")
    def foreign_presence_count(self):
        with self.db() as db:
            return db.execute("SELECT COUNT(*) FROM tbl_bot_status WHERE bot_name!='ggb'").fetchone()[0]


def local_checks():
    # Native lock arbitration across independent connections and worker threads.
    with LocalFixture() as p:
        p.call('put_job', job())
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            leases = list(pool.map(lambda _: p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease'], range(8)))
        assert sum(v is not None for v in leases) == 1
        before = p.call('inspect', {})
        jr.LocalDbProvider.prepare(p.cfg)
        assert p.call('inspect', {}) == before
        with p.db() as db:
            db.execute('BEGIN IMMEDIATE')
            rejected(lambda: p.call('lease', {'lease_request_id': str(uuid.uuid4())}))
            db.rollback()
        assert p.call('inspect', {}) == before
        real = jr.LocalDbProvider(p.cfg, RUNNER, SESSION).write_self_presence()
        assert abs((jr._provider_time(real['server_time']) - datetime.now(timezone.utc)).total_seconds()) < 5
    with LocalFixture() as p:
        for management in ('standalone', 'opscon_managed'):
            cfg = jr.RuntimeConfig('ggb', management, 'local_pi', p.cfg.base_dir, '', 'none')
            assert jr.run_once(cfg) == 0
        p.call('put_job', job(start_at=jr._provider_stamp(datetime.now(timezone.utc)-timedelta(seconds=1))))
        assert jr.run_once(p.cfg) == 0
        assert p.presence()[0] == 'ggb'
        external = jr.RuntimeConfig('ggb', 'standalone', 'external', p.cfg.base_dir, 'https://example.invalid/handler', 'none')
        rejected(lambda: jr.LocalDbProvider(external, RUNNER, SESSION))
        rejected(lambda: jr.LocalDbProvider.prepare(external))
    with tempfile.TemporaryDirectory() as td:
        base=Path(td)/'ggb';base.mkdir()
        cfg=jr.RuntimeConfig('ggb','standalone','local_pi',base,'','none')
        rejected(lambda: jr.run_once(cfg))
        assert not (base/'state/local_db/runtime.sqlite3').exists()
        (base/'state').symlink_to(Path(td))
        rejected(lambda: jr.LocalDbProvider.prepare(cfg))
    with LocalFixture() as p:
        p.call('put_job', job())
        old = p.call('lease', {'lease_request_id': str(uuid.uuid4())})['lease']
        p.call('report', report(old))
        for _ in range(100):
            p.call('lease', {'lease_request_id': str(uuid.uuid4())})
        assert p.call('report', report(old))['result_state'] == 'already_recorded'
        with p.db() as db:
            document = json.loads(db.execute('SELECT document FROM jrbot_provider_state').fetchone()[0])
            assert document['dispatches'] == {} and document['requests'] == {}
            assert db.execute('SELECT COUNT(*) FROM jrbot_provider_requests').fetchone()[0] >= 101
    with LocalFixture() as p:
        with p.db() as db:
            db.execute('ALTER TABLE tbl_bot_status RENAME TO old_status')
            db.execute('CREATE TABLE tbl_bot_status(bot_name TEXT,last_seen TEXT,last_status TEXT)')
        rejected(lambda:p.call('presence',{}),'PROVIDER_SCHEMA_INVALID')
    dst = [('2026-03-29T00:00:00Z', '2026-03-30T00:30:00Z'),
           ('2026-10-25T00:00:00Z', '2026-10-25T00:30:00Z'),
           ('2026-10-25T00:30:00Z', '2026-10-25T01:30:00Z')]
    for start, expected in dst:
        assert jr._provider_stamp(jr.provider_cron_next('30 2 * * *', 'Europe/Vienna', jr._provider_time(start))) == expected
    rejected(lambda: jr.provider_cron_next('* * * * *', 'Not/AZone', NOW))


if __name__ == '__main__':
    frames = contract_vectors(LocalFixture)
    local_checks()
    print('SQLITE_NATIVE_PROVIDER_CONTRACT_CONCURRENCY_DST_PREPARATION=PASS')
    print('EQUIVALENCE_VECTORS=' + json.dumps(frames, sort_keys=True, separators=(',', ':')))
