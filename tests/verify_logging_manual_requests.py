#!/usr/bin/env python3
"""Isolated v2 contract tests: no HTTP, no installed audit commands."""
import copy
import json
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
from pathlib import Path
from datetime import datetime,timedelta,timezone
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
# No HTTP dependency is used in these state/storage tests.
try: import requests
except ModuleNotFoundError:
 import types
 requests=types.ModuleType('requests');requests.RequestException=RuntimeError
 requests.Session=lambda:(_ for _ in ()).throw(AssertionError('NETWORK_FORBIDDEN'))
 sys.modules['requests']=requests
import job_runner as jr
import jrbot_storage_migrations as v2

BASE='2026-10-18T00:00:00Z'
def uid():return str(uuid.uuid4())
def at(seconds=0):return v2.stamp(v2.time(BASE)+timedelta(seconds=seconds))

class Foundation(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='jrbot-foundation-new-');self.base=Path(self.tmp.name)/'ggb';self.base.mkdir()
  cfg=jr.RuntimeConfig('ggb','standalone','local_pi',self.base,'','none');jr.LocalDbProvider.prepare(cfg)
  self.path=self.base/'state/local_db/runtime.sqlite3'
  with sqlite3.connect(self.path)as db:
   db.execute('BEGIN IMMEDIATE');v2.migrate_sqlite(db,'ggb',60)
   db.execute("INSERT INTO tbl_jobs(id,bot_name,job_key,job_type,enabled,schedule_type,interval_min,next_run_utc,grace_sec,config_json)VALUES(1,'GGB','ping','ping',0,'interval',1,'2026-10-18 01:00:00',60,'[]')")
  self.p=jr.foundation_v2_provider(self.path,'ggb',uid(),uid())
 def tearDown(self):self.tmp.cleanup()
 def op(self,op,data=None,t=0,actor=None):return self.p.operation(op,data or {},now=at(t),actor=actor)
 def manual(self,**kw):
  data=dict(request_id=uid(),job_id='1');data.update(kw)
  return self.op('request_manual',data,actor=dict(context='ggb',user_id=1))
 def lease(self,t=0,exclude=None,rid=None):return self.op('lease',dict(lease_request_id=rid or uid(),exclude_job_ids=exclude or []),t)['lease']
 def report(self,l,t=1,outcome='succeeded',started=True,run=None):
  run=run or uid();self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run))
  d={k:l[k]for k in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt')}
  d.update(run_id=run,started_at=at(),finished_at=at(t),outcome=outcome,message='confirmed',execution_started=started)
  return self.op('report',d,t),d
 def count(self,table):
  with sqlite3.connect(self.path)as db:return db.execute('SELECT count(*) FROM '+table).fetchone()[0]
 def test_manual_disabled_schedule_unchanged(self):
  r=self.manual();self.assertEqual(r['expires_at'],at(120));l=self.lease();self.assertEqual(l['trigger'],'manual')
  self.report(l)
  with sqlite3.connect(self.path)as db:
   self.assertEqual(db.execute('SELECT enabled,next_run_utc,last_ok FROM tbl_jobs').fetchone(),(0,'2026-10-18 01:00:00',1))
  self.assertEqual(self.count('tbl_job_log'),1)
 def test_request_duplicate_conflict(self):
  rid=uid();a=self.manual(request_id=rid);self.assertEqual(a,self.manual(request_id=rid))
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):self.manual(request_id=rid,start_within_seconds=1)
 def test_pending_busy(self):
  self.manual()
  with self.assertRaisesRegex(v2.FoundationError,'JOB_BUSY'):self.manual()
 def test_deadline_and_no_last_run(self):
  r=self.manual();self.assertIsNone(self.lease(t=120));s=self.op('inspect',t=121)
  self.assertEqual(s['manual'][r['request_id']]['reason'],'start_deadline_exceeded')
  self.assertEqual(self.count('tbl_job_log'),0)
 def test_shorter_window_and_invalid(self):
  r=self.manual(start_within_seconds=2);self.assertEqual(r['expires_at'],at(2))
  with self.assertRaisesRegex(v2.FoundationError,'DEADLINE_INVALID'):self.manual(start_within_seconds=121)
 def test_modes_and_outcomes(self):
  for mode in ('all','errors_only','none'):
   for outcome in ('succeeded','failed','rejected'):
    with self.subTest(mode=mode,outcome=outcome):
     with sqlite3.connect(self.path)as db:db.execute('UPDATE tbl_jobs SET log_mode=?',(mode,))
     before=self.count('tbl_job_log');self.manual();l=self.lease();self.report(l,outcome=outcome)
     self.assertEqual(self.count('tbl_job_log')-before,int(mode=='all'or mode=='errors_only'and outcome!='succeeded'))
 def test_duplicate_report_and_conflict(self):
  self.manual();l=self.lease();_,d=self.report(l)
  self.assertEqual(self.op('report',d,1)['result_state'],'already_recorded');self.assertEqual(self.count('tbl_job_log'),1)
  d['message']='different'
  with self.assertRaisesRegex(v2.FoundationError,'REPORT_CONFLICT'):self.op('report',d,1)
 def test_unknown_blocks_and_late_evidence(self):
  self.manual();l=self.lease();run=uid();self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run))
  s=self.op('inspect',t=61);self.assertEqual(s['dispatches'][l['dispatch_id']]['status'],'unknown')
  self.assertIsNone(self.lease(t=62))
  d={k:l[k]for k in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt')}
  d.update(run_id=run,started_at=at(),finished_at=at(1),outcome='succeeded',message='late',execution_started=True)
  self.assertEqual(self.op('report',d,62)['result_state'],'recovery_evidence_only');self.assertEqual(self.count('tbl_job_log'),0)
 def test_unknown_other_job_available(self):
  self.manual();l=self.lease();self.op('inspect',t=61)
  with sqlite3.connect(self.path)as db:
   db.execute("INSERT INTO tbl_jobs(id,bot_name,job_key,job_type,enabled,schedule_type,interval_min,next_run_utc,grace_sec,config_json)VALUES(2,'GGB','jrbot_heartbeat','ping',1,'interval',1,'2026-10-18 00:01:00',60,?)",(json.dumps(dict(system_job=True,required=True,locked=True,created_by='test',description='fixture')),))
  self.assertEqual(self.lease(t=62)['job_id'],'2')
 def test_same_job_regular_priority(self):
  with sqlite3.connect(self.path)as db:db.execute("UPDATE tbl_jobs SET enabled=1,next_run_utc='2026-10-18 00:00:00'")
  r=self.manual();l=self.lease();self.assertEqual(l['trigger'],'scheduled')
  self.assertEqual(self.op('inspect')['manual'][r['request_id']]['reason'],'scheduled_due')
 def test_definition_change_cancels(self):
  r=self.manual()
  with sqlite3.connect(self.path)as db:db.execute('UPDATE tbl_jobs SET grace_sec=61')
  self.assertIsNone(self.lease());self.assertEqual(self.op('inspect')['manual'][r['request_id']]['reason'],'definition_changed')
 def test_deleted_cancels(self):
  r=self.manual()
  with sqlite3.connect(self.path)as db:db.execute('DELETE FROM tbl_jobs')
  self.assertIsNone(self.lease());self.assertEqual(self.op('inspect')['manual'][r['request_id']]['reason'],'job_deleted')
 def test_no_run_is_not_log(self):
  self.manual();l=self.lease();self.report(l,outcome='rejected',started=False)
  self.assertEqual(self.count('tbl_job_log'),0)
 def test_exclusions(self):
  self.manual();self.assertIsNone(self.lease(exclude=['1']))
  with self.assertRaisesRegex(v2.FoundationError,'EXCLUSION_INVALID'):self.lease(exclude=['1']*9)
 def test_lease_id_binding(self):
  self.manual();rid=uid();l=self.lease(rid=rid);self.assertEqual(l,self.lease(rid=rid))
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):self.lease(rid=rid,exclude=['1'])
 def test_clock_guard(self):
  self.manual();l=self.lease()
  self.assertTrue(jr.foundation_v2_start_allowed(l,at(),at(1)))
  with self.assertRaisesRegex(v2.FoundationError,'CLOCK_UNCERTAIN'):jr.foundation_v2_start_allowed(l,at(),at(10))
  with self.assertRaisesRegex(v2.FoundationError,'START_DEADLINE_EXCEEDED'):jr.foundation_v2_start_allowed(l,at(120),at(120))
 def test_report_actor_injection(self):
  self.manual();l=self.lease();_,d=self.report(l);d['actor']=dict(context='ggb',user_id=99)
  with self.assertRaisesRegex(v2.FoundationError,'REPORT_INVALID'):self.op('report',d,1)
 def test_transaction_rollback(self):
  self.manual();l=self.lease();run=uid();self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run))
  d={k:l[k]for k in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt')};d.update(run_id=run,started_at=at(),finished_at=at(1),outcome='succeeded',message='ok',execution_started=True)
  # Inject a log execute failure after the real metadata preflight and earlier
  # transactional writes. An unknown persistent trigger is now refused by F04.
  connect=sqlite3.connect
  class FailLog:
   def __init__(self,db):object.__setattr__(self,'_db',db)
   def __getattr__(self,name):return getattr(self._db,name)
   def __setattr__(self,name,value):setattr(self._db,name,value)
   def execute(self,sql,*args):
    if sql.startswith('INSERT INTO tbl_job_log'):raise sqlite3.IntegrityError('synthetic rollback')
    return self._db.execute(sql,*args)
  with patch.object(sqlite3,'connect',side_effect=lambda *a,**k:FailLog(connect(*a,**k))):
   with self.assertRaises(sqlite3.IntegrityError):self.op('report',d,1)
  self.assertEqual(self.op('inspect',t=1)['dispatches'][l['dispatch_id']]['status'],'active')
  with sqlite3.connect(self.path)as db:self.assertIsNone(db.execute('SELECT last_ok FROM tbl_jobs').fetchone()[0])

 def add_heartbeat(self,enabled=1,due='2026-10-18 00:01:00'):
  with sqlite3.connect(self.path)as db:
   db.execute("INSERT INTO tbl_jobs(id,bot_name,job_key,job_type,enabled,schedule_type,interval_min,next_run_utc,grace_sec,config_json)VALUES(8,'GGB','jrbot_heartbeat','ping',?,'interval',1,?,60,?)",(enabled,due,json.dumps(dict(system_job=True,required=True,locked=True,created_by='test',description='fixture'))))
 def test_older_manual_before_unrelated_regular(self):
  self.manual();self.add_heartbeat();self.assertEqual(self.lease(t=61)['job_id'],'1')
 def test_foreign_lock_respected(self):
  with sqlite3.connect(self.path)as db:db.execute("UPDATE tbl_jobs SET locked_by='foreign',locked_until_utc='2026-10-18 01:00:00'")
  with self.assertRaisesRegex(v2.FoundationError,'JOB_BUSY'):self.manual()
 def test_no_same_invocation_repeat_exclusion(self):
  with sqlite3.connect(self.path)as db:db.execute("UPDATE tbl_jobs SET enabled=1,next_run_utc='2026-10-18 00:00:00'")
  l=self.lease();self.report(l);self.add_heartbeat(due='2026-10-18 00:00:00')
  self.assertEqual(self.lease(t=61,exclude=['1'])['job_id'],'8')
 def test_log_policy_and_duration_snapshot(self):
  self.manual();l=self.lease()
  with sqlite3.connect(self.path)as db:db.execute("UPDATE tbl_jobs SET log_mode='none',grace_sec=1")
  self.report(l)
  self.assertEqual(self.count('tbl_job_log'),1)
 def test_uuid_missing_rejected(self):
  with self.assertRaisesRegex(v2.FoundationError,'IDENTITY_INVALID'):
   self.op('request_manual',{'job_id':'1'},actor={'context':'ggb','user_id':1})
 def test_nullable_actor_only_local(self):
  with self.assertRaisesRegex(v2.FoundationError,'ACTOR_INVALID'):
   self.op('request_manual',dict(request_id=uid(),job_id='1'),actor=dict(context='ggb',user_id=None))
 def test_after_lease_before_start_deadline(self):
  self.manual(start_within_seconds=2);l=self.lease()
  with self.assertRaisesRegex(v2.FoundationError,'START_DEADLINE_EXCEEDED'):
   self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=uid()),t=2)
 def test_regular_advance_and_manual_leave_plan(self):
  with sqlite3.connect(self.path)as db:db.execute("UPDATE tbl_jobs SET enabled=1,next_run_utc='2026-10-18 00:00:00'")
  l=self.lease();self.report(l)
  with sqlite3.connect(self.path)as db:self.assertEqual(db.execute('SELECT next_run_utc FROM tbl_jobs').fetchone()[0],'2026-10-18 00:01:00')

 def test_concurrent_pending_requests_only_one(self):
  import concurrent.futures
  def create(_):
   p=v2.SQLiteFoundation(self.path,'ggb',uid(),uid())
   try:return p.operation('request_manual',dict(request_id=uid(),job_id='1'),now=at(),actor=dict(context='ggb',user_id=1))['state']
   except v2.FoundationError as e:return str(e)
  with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:r=list(pool.map(create,range(2)))
  self.assertEqual(sorted(r),['JOB_BUSY','pending'])
 def test_log_mode_constraint(self):
  with sqlite3.connect(self.path)as db:
   with self.assertRaises(sqlite3.IntegrityError):db.execute("UPDATE tbl_jobs SET log_mode='invalid'")
 def test_future_finished_rejected(self):
  self.manual();l=self.lease();run=uid();self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run))
  d={k:l[k]for k in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt')};d.update(run_id=run,started_at=at(),finished_at=at(2),outcome='succeeded',message='future',execution_started=True)
  with self.assertRaisesRegex(v2.FoundationError,'REPORT_INVALID'):self.op('report',d,1)
 def test_same_numeric_user_other_context_conflicts(self):
  rid=uid();self.manual(request_id=rid)
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):
   self.op('request_manual',dict(request_id=rid,job_id='1'),actor=dict(context='dmr',user_id=1))

 def test_old_v1_request_id_cannot_be_reused(self):
  self.manual();rid=uid();key=self.p.runner+'/'+self.p.session+'/'+rid
  with sqlite3.connect(self.path)as db:db.execute('INSERT INTO jrbot_provider_requests(instance,request_key,dispatch_id)VALUES(?,?,NULL)',('ggb',key))
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):self.lease(rid=rid)

 def test_bound_run_can_renew_after_start_window(self):
  self.manual(start_within_seconds=2);l=self.lease();run=uid()
  self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run),t=1)
  renewed=self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run),t=3)
  self.assertEqual(renewed['lease_expires_at'],at(63))
  d=self.op('inspect',t=3)['dispatches'][l['dispatch_id']]
  self.assertEqual(d['lease']['start_before'],at(2))
  self.assertEqual(d['run'],run)
 def test_bound_run_cannot_change_run_after_start_window(self):
  self.manual(start_within_seconds=2);l=self.lease();run=uid()
  self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run),t=1)
  with self.assertRaisesRegex(v2.FoundationError,'DISPATCH_BINDING_MISMATCH'):
   self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=uid()),t=3)
 def test_bound_run_expired_execution_lease_not_revived(self):
  self.manual(start_within_seconds=2);l=self.lease();run=uid()
  self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run),t=1)
  with self.assertRaisesRegex(v2.FoundationError,'DISPATCH_STALE'):
   self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run),t=61)

 # F04 Variant A: fixture schemas are mutated only by these explicit tests.
 def schema_snapshot(self):
  with sqlite3.connect(self.path) as db:
   objects=db.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').fetchall()
   rows=[]
   for typ,name,_,_ in objects:
    if typ=='table':rows.append((name,db.execute('SELECT * FROM "'+name.replace('"','""')+'" ORDER BY rowid').fetchall()))
   return objects,rows,db.execute('PRAGMA user_version').fetchone()
 def schema_refused(self):
  before=self.schema_snapshot()
  with self.assertRaisesRegex(v2.FoundationError,'^PROVIDER_SCHEMA_INVALID$'):self.op('inspect')
  self.assertEqual(self.schema_snapshot(),before)
 def schema_guard_only(self):
  before=self.schema_snapshot()
  with sqlite3.connect(self.path) as db:
   db.execute('BEGIN IMMEDIATE');v2.schema_guard_sqlite(db);db.rollback()
  self.assertEqual(self.schema_snapshot(),before)
 def schema_replace(self,table,old,new):
  with sqlite3.connect(self.path) as db:
   ddl=db.execute('SELECT sql FROM sqlite_master WHERE name=?',(table,)).fetchone()[0]
   self.assertIn(old,ddl);changed=ddl.replace(old,new,1)
   db.execute('ALTER TABLE "'+table+'" RENAME TO f04_held')
   db.execute(changed)
   db.execute('INSERT INTO "'+table+'" SELECT * FROM f04_held')
   db.execute('DROP TABLE f04_held')
 def test_schema_f04_existing_baseline_read_only(self):self.schema_guard_only()
 def test_schema_f04_missing_each_table(self):
  for name in ('tbl_jobs','tbl_job_log','jrbot_manual_requests','jrbot_provider_state','jrbot_provider_dispatches','jrbot_provider_requests'):
   with self.subTest(table=name):
    with sqlite3.connect(self.path) as db:db.execute('ALTER TABLE "'+name+'" RENAME TO f04_held')
    try:self.schema_refused()
    finally:
     with sqlite3.connect(self.path) as db:db.execute('ALTER TABLE f04_held RENAME TO "'+name+'"')
 def test_schema_f04_view_replacement(self):
  with sqlite3.connect(self.path) as db:
   db.execute('ALTER TABLE tbl_job_log RENAME TO f04_held')
   db.execute('CREATE VIEW tbl_job_log AS SELECT * FROM f04_held')
  self.schema_refused()
 def test_schema_f04_missing_column(self):
  with sqlite3.connect(self.path) as db:db.execute('ALTER TABLE tbl_jobs RENAME COLUMN last_message TO f04_unknown')
  self.schema_refused()
 def test_schema_f04_wrong_type(self):
  self.schema_replace('tbl_jobs','job_group TEXT','job_group BLOB');self.schema_refused()
 def test_schema_f04_wrong_default(self):
  self.schema_replace('tbl_jobs',"DEFAULT 'all'","DEFAULT 'none'");self.schema_refused()
 def test_schema_f04_wrong_nullability(self):
  self.schema_replace('jrbot_manual_requests','document TEXT NOT NULL','document TEXT');self.schema_refused()
 def test_schema_f04_wrong_identity_collation(self):
  self.schema_replace('jrbot_manual_requests','instance TEXT NOT NULL','instance TEXT COLLATE NOCASE NOT NULL');self.schema_refused()
 def test_schema_f04_unknown_trigger(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE TRIGGER f04_trigger BEFORE INSERT ON tbl_job_log BEGIN SELECT 1; END')
  self.schema_refused()
 def test_schema_f04_unknown_unique(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE UNIQUE INDEX f04_extra_unique ON tbl_jobs(job_key)')
  self.schema_refused()
 def test_schema_f04_partial_unique(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE UNIQUE INDEX f04_partial ON tbl_job_log(dispatch_id) WHERE dispatch_id IS NOT NULL')
  self.schema_refused()
 def test_schema_f04_expression_unique(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE UNIQUE INDEX f04_expression ON tbl_job_log(lower(dispatch_id))')
  self.schema_refused()
 def test_schema_f04_ordinary_extra_index(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE INDEX f04_performance ON tbl_jobs(job_group)')
  self.schema_guard_only()
 def test_schema_f04_wrong_version(self):
  with sqlite3.connect(self.path) as db:db.execute('PRAGMA user_version=1')
  self.schema_refused()
 def test_schema_f04_unknown_incoming_foreign_key(self):
  with sqlite3.connect(self.path) as db:db.execute('CREATE TABLE f04_foreign(job_id INTEGER REFERENCES tbl_jobs(id))')
  self.schema_refused()
 def test_schema_f04_literal_case_is_not_normalized(self):
  self.schema_replace('jrbot_manual_requests',"'pending'","'PENDING'");self.schema_refused()
 def test_schema_f04_boolean_grouping_is_not_erased(self):
  # Moving boolean grouping must never disappear during normalization.
  old="(instance IS NULL AND dispatch_id IS NULL AND outcome IS NULL) OR\n (instance IS NOT NULL AND dispatch_id IS NOT NULL AND outcome IS NOT NULL AND outcome IN('succeeded','failed','rejected'))"
  changed="(instance IS NULL AND dispatch_id IS NULL AND (outcome IS NULL OR instance IS NOT NULL) AND dispatch_id IS NOT NULL AND outcome IS NOT NULL AND outcome IN('succeeded','failed','rejected'))"
  self.schema_replace('tbl_job_log',old,changed)
  self.schema_refused()
 def test_schema_f04_metadata_denial(self):
  before=self.schema_snapshot()
  with sqlite3.connect(self.path) as db:
   db.execute('BEGIN IMMEDIATE')
   def deny(action,table,column,database,source):
    return sqlite3.SQLITE_DENY if action==sqlite3.SQLITE_READ and table in ('sqlite_master','sqlite_schema') else sqlite3.SQLITE_OK
   db.set_authorizer(deny)
   with self.assertRaisesRegex(v2.FoundationError,'^PROVIDER_SCHEMA_UNVERIFIABLE$'):v2.schema_guard_sqlite(db)
   db.set_authorizer(None);db.rollback()
  self.assertEqual(self.schema_snapshot(),before)
 def test_schema_f04_disabled_check_enforcement(self):
  with sqlite3.connect(self.path) as db:
   db.execute('PRAGMA ignore_check_constraints=ON');db.execute('BEGIN IMMEDIATE')
   with self.assertRaisesRegex(v2.FoundationError,'^PROVIDER_SCHEMA_INVALID$'):v2.schema_guard_sqlite(db)
   db.rollback()


# F05: prepared only. Native execution requires the separately approved gate.
class F05Foundation(Foundation):
 # Inherited Foundation cases also remain available; targeted gate selects F05.
 def completed(self):
  r=self.manual();rid=uid();l=self.lease(rid=rid);_,report=self.report(l)
  return r,rid,l,report
 def maintain(self,t=0,**kw):return self.p.maintain(now=at(t),**kw)
 def dispatch(self,did):
  with sqlite3.connect(self.path)as db:return json.loads(db.execute('SELECT document FROM jrbot_provider_dispatches WHERE instance=? AND dispatch_id=?',('ggb',did)).fetchone()[0])
 def snapshot(self):
  with sqlite3.connect(self.path)as db:
   return {n:db.execute('SELECT * FROM '+n+' ORDER BY 1,2').fetchall()for n in ('tbl_jobs','tbl_job_log','jrbot_provider_state','jrbot_provider_dispatches','jrbot_provider_requests','jrbot_manual_requests')}
 def seed_empty_receipts(self,n):
  keys=[self.p.runner+'/'+self.p.session+'/'+uid()for _ in range(n)]
  with sqlite3.connect(self.path)as db:db.executemany('INSERT INTO jrbot_provider_requests(instance,request_key,dispatch_id,document)VALUES(?,?,NULL,?)',[('ggb',k,v2.canonical(dict(binding=v2.canonical([]),dispatch_id=None)))for k in keys])
  return keys
 def test_f05_history_over_10000_and_empty_replay(self):
  keys=self.seed_empty_receipts(10001);r=self.manual();l=self.lease();_,report=self.report(l)
  self.assertEqual(self.op('report',report,1)['result_state'],'already_recorded')
  self.assertIsNone(self.lease(t=2,rid=keys[0].split('/')[-1]))
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):self.lease(t=2,rid=keys[0].split('/')[-1],exclude=['1'])
  self.assertEqual(self.count('jrbot_provider_requests'),10002)
 def test_f05_old_completed_manual_and_report_lookup(self):
  r,rid,l,report=self.completed();self.assertEqual(self.op('report',report,2)['result_state'],'already_recorded')
  self.assertEqual(self.manual(request_id=r['request_id'])['dispatch_id'],l['dispatch_id'])
  with self.assertRaisesRegex(v2.FoundationError,'DISPATCH_STALE'):self.lease(t=2,rid=rid)
  bad=dict(report,message='conflict')
  with self.assertRaisesRegex(v2.FoundationError,'REPORT_CONFLICT'):self.op('report',bad,2)
 def test_f05_30_boundary_marker_and_preservation(self):
  r,rid,l,report=self.completed();before=self.dispatch(l['dispatch_id']);cut=30*86400+1
  self.assertEqual(self.maintain(cut-1)['dispatch_compacted'],0)
  self.assertEqual(self.maintain(cut)['dispatch_compacted'],1)
  after=self.dispatch(l['dispatch_id']);expected=copy.deepcopy(before);del expected['lease']['payload'];expected['history_detail']=dict(format=1,state='compacted',compacted_at=at(cut))
  self.assertEqual(after,expected);self.assertEqual(self.op('inspect',t=cut)['dispatches'][l['dispatch_id']],expected)
  snap=self.snapshot();self.assertEqual(self.maintain(cut+1)['dispatch_compacted'],0);self.assertEqual(self.snapshot(),snap)
 def test_f05_compacted_replays_and_actor(self):
  r,rid,l,report=self.completed();self.maintain(30*86400+1)
  self.assertEqual(self.op('report',report,30*86400+2)['result_state'],'already_recorded')
  self.assertEqual(self.manual(request_id=r['request_id'])['actor'],r['actor'])
  with self.assertRaisesRegex(v2.FoundationError,'DISPATCH_STALE'):self.lease(t=30*86400+2,rid=rid)
  with self.assertRaisesRegex(v2.FoundationError,'REQUEST_CONFLICT'):self.op('request_manual',dict(request_id=r['request_id'],job_id='1'),actor=dict(context='ggb',user_id=2))
  with self.assertRaisesRegex(v2.FoundationError,'REPORT_CONFLICT'):self.op('report',dict(report,message='changed'),30*86400+2)
 def test_f05_90_log_boundary_no_reprojection(self):
  r,rid,l,report=self.completed();cut=90*86400+1
  self.assertEqual(self.maintain(cut-1)['logs_deleted'],0);self.assertEqual(self.maintain(cut)['logs_deleted'],1)
  with sqlite3.connect(self.path)as db:last=db.execute('SELECT last_run_utc,last_ok,last_message,last_duration_ms FROM tbl_jobs').fetchone()
  self.assertEqual(self.op('report',report,cut+1)['result_state'],'already_recorded');self.assertEqual(self.count('tbl_job_log'),0)
  with sqlite3.connect(self.path)as db:self.assertEqual(db.execute('SELECT last_run_utc,last_ok,last_message,last_duration_ms FROM tbl_jobs').fetchone(),last)
 def test_f05_other_instance_legacy_and_missing_dispatch_logs(self):
  with sqlite3.connect(self.path)as db:
   db.execute("INSERT INTO tbl_job_log(job_id,bot_name,ran_at,ok)VALUES(1,'GGB','2020-01-01 00:00:00',1)")
   for inst in ('other','ggb'):
    db.execute("INSERT INTO tbl_job_log(job_id,bot_name,ran_at,ok,instance,dispatch_id,outcome)VALUES(1,'GGB','2020-01-01 00:00:00',1,?,?, 'succeeded')",(inst,uid()))
  self.assertEqual(self.maintain(100*86400)['logs_deleted'],0);self.assertEqual(self.count('tbl_job_log'),3)
 def test_f05_unknown_and_pending_not_compacted_or_restarted(self):
  r=self.manual();l=self.lease();run=uid();self.op('renew',dict(dispatch_id=l['dispatch_id'],run_id=run));self.op('inspect',t=61)
  before=self.snapshot();self.assertEqual(self.maintain(100*86400)['dispatch_compacted'],0);self.assertEqual(before,self.snapshot())
  self.assertIsNone(self.lease(t=100*86400));self.assertEqual(self.dispatch(l['dispatch_id'])['status'],'unknown')
 def test_f05_cursor_100_visited_and_restart(self):
  _,_,l,_=self.completed();template=self.dispatch(l['dispatch_id']);ids=[l['dispatch_id']]
  with sqlite3.connect(self.path)as db:
   for _ in range(100):
    did=uid();d=copy.deepcopy(template);d['lease']['dispatch_id']=did;d['lease']['request_id']=None;d['actor']=None
    report=json.loads(d['report']);report['dispatch_id']=did;d['report']=v2.canonical(report)
    db.execute('INSERT INTO jrbot_provider_dispatches VALUES(?,?,?,?)',('ggb',did,'completed',v2.canonical(d)));ids.append(did)
  first=self.maintain(30*86400+1);self.assertEqual(first['dispatch_visited'],100);self.assertFalse(first['dispatch_done']);self.assertEqual(first['dispatch_after'],sorted(ids)[99])
  second=self.maintain(30*86400+1,dispatch_after=first['dispatch_after'],log_after=first['log_after']);self.assertEqual(second['dispatch_compacted'],1);self.assertTrue(second['dispatch_done'])
  self.assertEqual(self.maintain(30*86400+2)['dispatch_compacted'],0)
 def test_f05_invalid_marker_rolls_back(self):
  _,_,l,_=self.completed()
  with sqlite3.connect(self.path)as db:
   d=self.dispatch(l['dispatch_id']);d['history_detail']=dict(format=99,state='compacted',compacted_at=at());db.execute('UPDATE jrbot_provider_dispatches SET document=?',(v2.canonical(d),))
  before=self.snapshot()
  with self.assertRaisesRegex(v2.FoundationError,'RETENTION_RECORD_INVALID'):self.maintain(100*86400)
  self.assertEqual(before,self.snapshot())
 def test_f05_maintenance_rollback_after_compaction(self):
  _,_,l,_=self.completed();before=self.snapshot();real=sqlite3.connect
  class Broken:
   def __init__(self,db):object.__setattr__(self,'db',db)
   def __getattr__(self,n):return getattr(self.db,n)
   def __setattr__(self,n,v):setattr(self.db,n,v)
   def execute(self,q,*args):
    if q.startswith('DELETE FROM tbl_job_log'):raise sqlite3.OperationalError('F05_SYNTHETIC_DELETE_FAILURE')
    return self.db.execute(q,*args)
  with patch.object(v2.sqlite3,'connect',side_effect=lambda *a,**k:Broken(real(*a,**k))):
   with self.assertRaisesRegex(sqlite3.OperationalError,'F05_SYNTHETIC_DELETE_FAILURE'):self.maintain(100*86400)
  self.assertEqual(before,self.snapshot())
 def test_f05_selective_reads_and_no_history_rewrites(self):
  self.seed_empty_receipts(10001);_,_,l,report=self.completed();seen=[];real=sqlite3.connect
  def connect(*a,**k):
   db=real(*a,**k);db.set_trace_callback(seen.append);return db
  with patch.object(v2.sqlite3,'connect',side_effect=connect):self.op('report',report,2)
  requests=[q for q in seen if q.startswith('SELECT request_key')];self.assertEqual(requests,[])
  self.assertFalse(any(q.startswith(('INSERT INTO jrbot_provider_dispatches','INSERT INTO tbl_job_log','INSERT INTO jrbot_manual_requests','UPDATE jrbot_manual_requests SET active_job_id=NULL'))for q in seen))
  self.assertFalse(any(q.startswith(('DELETE ','UPDATE jrbot_provider_dispatches SET document='))for q in seen))
 def test_f05_invalid_cursors_and_no_automatic_maintenance(self):
  before=self.snapshot()
  for kw in (dict(dispatch_after='../x'),dict(log_after=-1),dict(log_after=True)):
   with self.assertRaises(v2.FoundationError):self.maintain(**kw)
  self.assertEqual(before,self.snapshot())
 def test_f05_query_plan_evidence(self):
  # Captured at the native gate: no assertion of O(1) scans without an index.
  with sqlite3.connect(self.path)as db:
   self.f05_query_plans={q:db.execute('EXPLAIN QUERY PLAN '+q,('ggb',)).fetchall()for q in ("SELECT dispatch_id FROM jrbot_provider_dispatches WHERE instance=? AND status IN ('active','unknown')","SELECT request_id FROM jrbot_manual_requests WHERE instance=? AND active_job_id IS NOT NULL")}
  self.assertTrue(all(self.f05_query_plans.values()))

 def test_f05_over_10000_completed_and_cancelled_rows(self):
  r,_,l,report=self.completed();template=self.dispatch(l['dispatch_id'])
  dispatch_rows=[];manual_rows=[]
  for _ in range(10001):
   did=uid();d=copy.deepcopy(template);d['lease'].update(dispatch_id=did,request_id=None,trigger='scheduled',start_before=None);d['actor']=None
   body=json.loads(d['report']);body['dispatch_id']=did;d['report']=v2.canonical(body)
   dispatch_rows.append(('ggb',did,'completed',v2.canonical(d)))
   rid=uid();m=copy.deepcopy(r);m.update(request_id=rid,state='cancelled',reason='start_deadline_exceeded',dispatch_id=None)
   manual_rows.append(('ggb',rid,'1','cancelled',None,v2.canonical(m)))
  with sqlite3.connect(self.path)as db:
   db.executemany('INSERT INTO jrbot_provider_dispatches VALUES(?,?,?,?)',dispatch_rows)
   db.executemany('INSERT INTO jrbot_manual_requests VALUES(?,?,?,?,?,?)',manual_rows)
  self.assertEqual(self.op('report',report,2)['result_state'],'already_recorded')
  self.assertIsNone(self.lease(t=2));self.manual()
 def test_f05_release_only_expired_request_guard(self):
  old=self.manual();rid=uid()
  self.op('request_manual',dict(request_id=rid,job_id='1'),120,dict(context='ggb',user_id=1))
  with sqlite3.connect(self.path)as db:
   values=dict(db.execute('SELECT request_id,active_job_id FROM jrbot_manual_requests'))
  self.assertIsNone(values[old['request_id']]);self.assertEqual(values[rid],'1')
 def test_f05_old_report_does_not_run_maintenance(self):
  _,_,l,report=self.completed();self.assertEqual(self.op('report',report,100*86400)['result_state'],'already_recorded')
  self.assertIn('payload',self.dispatch(l['dispatch_id'])['lease']);self.assertEqual(self.count('tbl_job_log'),1)

if __name__=='__main__':unittest.main(verbosity=2)

