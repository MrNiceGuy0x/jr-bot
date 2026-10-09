#!/usr/bin/env python3
"""Relational DefinitionSource vectors shared by native SQLite/MariaDB tests."""
import concurrent.futures
import json
import sqlite3
import sys
import tempfile
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'))
try: import requests
except ModuleNotFoundError:
    import types
    requests=types.ModuleType('requests');requests.RequestException=RuntimeError
    requests.Session=lambda:(_ for _ in ()).throw(AssertionError('NETWORK_FORBIDDEN'))
    sys.modules['requests']=requests
import job_runner as jr
NOW=datetime(2026,10,9,12,tzinfo=timezone.utc)
RUNNER='11111111-1111-4111-8111-111111111111'
SESSION='22222222-2222-4222-8222-222222222222'
RUN='33333333-3333-4333-8333-333333333333'


def source(**updates):
    row=dict(id=1,bot_name='GGB',job_key='ping',job_type='ping',enabled=1,
        schedule_type='interval',interval_min=3,run_at_utc=None,cron_expr=None,
        next_run_utc='2026-09-29 12:00:00',grace_sec=60,job_group='heartbeat',
        config_json='[]',locked_by=None,locked_until_utc=None)
    row.update(updates);return row


def inventory():
    meta=json.dumps(dict(system_job=True,required=True,locked=True,created_by='synthetic',description='synthetic'))
    return [source(),source(id=2,job_key='notifi_hour',job_type='http',enabled=0,schedule_type='cron',interval_min=None,cron_expr='0 * * * *',config_json='{"url":"https://example.invalid/disabled"}',job_group='test'),
        source(id=3,job_key='manual_reboot',job_type='shell',enabled=0,schedule_type='once',config_json='{"cmd":"disabled"}',job_group='maintenance'),
        source(id=4,job_key='Guild Overview',job_type='http',schedule_type='cron',interval_min=None,cron_expr='0 1 * * *',config_json=json.dumps({'url':jr.GGB_OVERVIEW_URL}),job_group='default'),
        source(id=5,job_key='Guild Collection',job_type='http',enabled=0,config_json='{"url":"https://example.invalid/disabled"}'),
        source(id=6,job_key='structure_audit',job_type='shell',enabled=0,config_json='{"cmd":"disabled","command":"disabled","description":"synthetic"}'),
        source(id=7,job_key='network_health_audit',job_type='shell',enabled=0,config_json='{"cmd":"disabled","command":"disabled","description":"synthetic"}'),
        source(id=8,job_key='jrbot_heartbeat',interval_min=1,grace_sec=120,job_group='system',config_json=meta)]


def report(lease,**updates):
    value={k:lease[k] for k in ('job_id','job_key','job_revision','dispatch_id','scheduled_for','attempt')}
    value.update(protocol=jr.RUNTIME_PROTOCOL,instance='ggb',runner_id=RUNNER,session_id=SESSION,run_id=RUN,
        started_at=jr._provider_stamp(NOW),finished_at=jr._provider_stamp(NOW),outcome='succeeded',retryable=False,message='synthetic',result={})
    value.update(updates);return value


def rejected(fn,code=None):
    try: fn()
    except Exception as exc:
        if code is not None: assert str(exc)==code,(str(exc),code)
        return
    raise AssertionError('invalid operation accepted')


def normalize(value):
    if isinstance(value,dict):return {k:normalize(v) for k,v in value.items()}
    if isinstance(value,list):return [normalize(v) for v in value]
    if isinstance(value,str):
        try:
            if uuid.UUID(value).version==4:return '<uuid-v4>'
        except ValueError:pass
    return value


def lease(p):return p.call('lease',{'lease_request_id':str(uuid.uuid4())})['lease']


def contract_vectors(make):
    frames=[]
    with make() as p:
        p.seed(inventory());before=p.rows()
        acquired=[lease(p) for _ in range(4)]
        assert [x['job_id'] for x in acquired if x] == ['1','4','8']
        assert acquired[-1] is None
        for x in acquired[:3]:
            assert x['attempt']==x['max_attempts']==1
            assert p.call('report',report(x))['result_state']=='recorded'
            assert p.call('report',report(x))['result_state']=='already_recorded'
            rejected(lambda:p.call('report',report(x,message='conflict')),'REPORT_CONFLICT')
            frames.append(normalize(x))
        after=p.rows()
        for r in after:
            if r['enabled']==0:assert r==next(v for v in before if v['id']==r['id'])
            else:
                assert r['locked_by'] is None and r['last_ok']==1
                assert jr._source_stamp(r['next_run_utc'])>jr._provider_stamp(NOW)
        assert lease(p) is None
        state=p.call('inspect',{});assert len(state['sources'])==8 and len(state['jobs'])==3
        assert p.call('inspect',{})==state
        p.now+=timedelta(minutes=1);assert lease(p)['job_id']=='8'
    with make() as p:
        p.seed([source()]);request=str(uuid.uuid4());data={'lease_request_id':request}
        first=p.call('lease',data)['lease'];assert p.call('lease',data)['lease']==first
        rejected(lambda:p.call('renew',{'dispatch_id':first['dispatch_id'],'run_id':RUN},runner=str(uuid.uuid4())),'DISPATCH_BINDING_MISMATCH')
        p.call('renew',{'dispatch_id':first['dispatch_id'],'run_id':RUN})
        rejected(lambda:p.call('report',report(first,job_revision=2)),'DISPATCH_BINDING_MISMATCH')
        rejected(lambda:p.call('report',report(first,instance='other')),'REPORT_INVALID')
        p.now+=timedelta(seconds=61)
        rejected(lambda:p.call('report',report(first)),'DISPATCH_STALE')
        assert lease(p) is None # no auto retry of an expired occurrence
        assert p.rows()[0]['locked_by'] is None
        p.now+=timedelta(seconds=120);assert lease(p)['scheduled_for']=='2026-10-09T12:03:00Z'
    with make() as p:
        row=source();p.seed([row]);first=lease(p)
        row['interval_min']=5;p.seed([row]);state=p.call('inspect',{})
        assert state['jobs']['1']['definition']['job_revision']==2
        assert state['jobs']['1']['occurrence']['definition']['job_revision']==1
        p.call('report',report(first));replacement=lease(p)
        assert replacement['job_revision']==2;frames.append(normalize(replacement))
        row['enabled']=0;p.seed([row]);assert lease(p) is None
        p.call('report',report(replacement));assert p.rows()[0]['enabled']==0
        p.seed([]);assert lease(p) is None
    with make() as p:
        p.seed([source(bot_name='TRX')]);assert lease(p) is None
        p.call('presence',{});assert p.presence()==('GGB','2026-10-09T12:00:00Z','yellow')
        p.set_alert_state();p.now+=timedelta(seconds=1);p.call('presence',{})
        assert p.presence()==('GGB','2026-10-09T12:00:01Z','red')
        rejected(lambda:p.call('put_job',{}),'DEFINITION_SOURCE_ONLY')
        rejected(lambda:p.call('presence',{'instance':'other'}),'PRESENCE_SCOPE_INVALID')
    # Supplied TRX/DMR inventories are comparison data, not authorized targets.
    base=inventory()
    dmr=[dict(base[i], id=identity, bot_name='DMR') for i,identity in ((0,1),(1,5),(2,6),(6,7),(5,8),(7,10))]
    trx=[dict(base[7], id=1, bot_name='TRX')]
    for rows,count in ((dmr,6),(trx,1)):
        with make() as p:
            p.seed(rows);before=p.rows();assert len(before)==count
            assert lease(p) is None and p.rows()==before
            assert p.call('inspect',{})['jobs']=={}
    for bad in [source(config_json='{}'),source(next_run_utc=None),source(job_type='shell'),source(enabled=1,schedule_type='once'),source(config_json='[1]')]:
        with make() as p:
            p.seed([bad]);rejected(lambda:lease(p))
    with make() as p:
        p.seed([source(locked_by='legacy-runner',locked_until_utc='2026-10-09 12:05:00')]);assert lease(p) is None
        assert p.rows()[0]['locked_by']=='legacy-runner'
    with make() as p:
        row=inventory()[3];p.seed([row]);x=lease(p)
        assert x['scheduled_for']=='2026-10-09T01:00:00Z'
        assert x['payload']=={'action':'guild_overview_refresh'}
        p.call('report',report(x,outcome='failed',retryable=True));assert lease(p) is None
        assert p.rows()[0]['last_ok']==0
    return frames


class LocalFixture:
    def __init__(self):
        self.temp=tempfile.TemporaryDirectory();base=Path(self.temp.name)/'ggb';(base/'state').mkdir(parents=True)
        self.cfg=jr.RuntimeConfig('ggb','standalone','local_pi',base,'','none');jr.LocalDbProvider.prepare(self.cfg)
        self.now=NOW;self.provider=jr.LocalDbProvider(self.cfg,RUNNER,SESSION,clock=lambda:self.now)
    def __enter__(self):return self
    def __exit__(self,*unused):self.temp.cleanup()
    def db(self):return sqlite3.connect(self.provider.path)
    def call(self,op,data,runner=RUNNER,session=SESSION):
        return jr.LocalDbProvider(self.cfg,runner,session,clock=lambda:self.now)._operation(op,data)
    def seed(self,rows):
        with self.db() as db:
            db.execute('DELETE FROM tbl_jobs')
            for r in rows:
                fields=list(r);db.execute('INSERT INTO tbl_jobs('+','.join(fields)+') VALUES ('+','.join('?' for _ in fields)+')',[r[k] for k in fields])
    def rows(self):
        with self.db() as db:
            db.row_factory=sqlite3.Row
            fields=list(source())+['last_dispatch_utc','last_run_utc','last_ok','last_message','last_duration_ms']
            return [dict(r) for r in db.execute('SELECT '+','.join(fields)+' FROM tbl_jobs ORDER BY id')]
    def presence(self):
        with self.db() as db:
            r=db.execute('SELECT bot_name,last_seen,last_status FROM tbl_bot_status').fetchone()
            return (r[0],jr._source_stamp(r[1]),r[2])
    def set_alert_state(self):
        with self.db() as db:db.execute("UPDATE tbl_bot_status SET last_status='red',last_alert_at='2026-10-08 00:00:00'")


def local_checks():
    with LocalFixture() as p:
        p.seed([source()])
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            replies=list(pool.map(lambda _:lease(p),range(8)))
        assert sum(x is not None for x in replies)==1
        before=p.call('inspect',{});jr.LocalDbProvider.prepare(p.cfg);assert p.call('inspect',{})==before
        active=next(x for x in replies if x)
        with p.db() as db:db.execute("CREATE TRIGGER fail_projection BEFORE UPDATE OF last_ok ON tbl_jobs BEGIN SELECT RAISE(ABORT,'rollback'); END")
        rejected(lambda:p.call('report',report(active)))
        assert p.call('inspect',{})==before
        with p.db() as db:db.execute('DROP TRIGGER fail_projection')
        assert p.call('report',report(active))['result_state']=='recorded'
    with LocalFixture() as p:
        p.seed([source()]);first=lease(p);p.call('report',report(first))
        for _ in range(25):lease(p)
        assert p.call('report',report(first))['result_state']=='already_recorded'
        for instant in ('2026-03-29T00:00:00Z','2026-10-25T00:00:00Z'):
            assert jr._provider_stamp(jr.provider_cron_next('0 1 * * *','UTC',jr._provider_time(instant)))==instant[:10]+'T01:00:00Z'
    with LocalFixture() as p:
        with p.db() as db:db.execute('DROP TABLE tbl_jobs')
        rejected(lambda:p.call('lease',{'lease_request_id':str(uuid.uuid4())}),'PROVIDER_SCHEMA_INVALID')

if __name__=='__main__':
    frames=contract_vectors(LocalFixture);local_checks()
    print('SQLITE_RELATIONAL_SOURCE_COALESCE_SNAPSHOT_PROJECTION_ROLLBACK=PASS')
    print('EQUIVALENCE_VECTORS='+json.dumps(frames,sort_keys=True,separators=(',',':')))
