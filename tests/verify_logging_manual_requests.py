#!/usr/bin/env python3
"""Isolated v2 contract tests: no HTTP, no installed audit commands."""
import copy
import json
import sqlite3
import sys
import tempfile
import unittest
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
  with sqlite3.connect(self.path)as db:db.execute("CREATE TRIGGER deny_log BEFORE INSERT ON tbl_job_log BEGIN SELECT RAISE(ABORT,'synthetic rollback'); END")
  d={k:l[k]for k in ('dispatch_id','job_id','job_key','job_revision','scheduled_for','attempt')};d.update(run_id=run,started_at=at(),finished_at=at(1),outcome='succeeded',message='ok',execution_started=True)
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

if __name__=='__main__':unittest.main(verbosity=2)
