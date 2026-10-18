#!/usr/bin/env python3
"""Only new, marked fixture databases; no production files or network."""
import json,sqlite3,sys,tempfile,unittest,uuid
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_logging_manual_requests import jr,v2,uid
class Storage(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='jrbot-schema-new-');self.base=Path(self.tmp.name)/'ggb';self.base.mkdir()
  self.cfg=jr.RuntimeConfig('ggb','standalone','local_pi',self.base,'','none');jr.LocalDbProvider.prepare(self.cfg)
  self.path=self.base/'state/local_db/runtime.sqlite3'
 def tearDown(self):self.tmp.cleanup()
 def migrate(self):
  with sqlite3.connect(self.path)as db:db.execute('BEGIN IMMEDIATE');v2.migrate_sqlite(db,'ggb',60)
 def test_new_schema_and_no_automatic_prepare(self):
  with sqlite3.connect(self.path)as db:self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],0)
  self.migrate()
  with sqlite3.connect(self.path)as db:self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],2)
 def test_repeat_migration_rejected(self):
  self.migrate()
  with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_VERSION_UNSUPPORTED'):self.migrate()
 def test_partial_rolls_back(self):
  with sqlite3.connect(self.path)as db:db.execute("CREATE TABLE tbl_job_log(id INTEGER)")
  with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_PARTIAL'):self.migrate()
  with sqlite3.connect(self.path)as db:self.assertNotIn('log_mode',{r[1]for r in db.execute('PRAGMA table_info(tbl_jobs)')})
 def test_old_log_preserved(self):
  with sqlite3.connect(self.path)as db:
   db.execute('CREATE TABLE tbl_job_log(id INTEGER PRIMARY KEY,job_id INTEGER,bot_name TEXT,ran_at TEXT,duration_ms INTEGER,ok INTEGER,message TEXT,created_at TEXT)')
   db.execute("INSERT INTO tbl_job_log VALUES(1,1,'GGB','old',1,1,'historical','old')")
  self.migrate()
  with sqlite3.connect(self.path)as db:self.assertEqual(db.execute('SELECT message,dispatch_id FROM tbl_job_log').fetchone(),('historical',None))
 def test_active_cutover_refused(self):
  with sqlite3.connect(self.path)as db:db.execute("INSERT INTO jrbot_provider_dispatches VALUES('ggb',?,'active','{}')",(uid(),))
  with self.assertRaisesRegex(v2.FoundationError,'ACTIVE_DISPATCH_CUTOVER_REQUIRED'):self.migrate()
 def test_wal_backup_and_restore(self):
  self.migrate();backup=Path(self.tmp.name)/'new-backup.sqlite3'
  with sqlite3.connect(self.path)as source:
   source.execute('PRAGMA journal_mode=WAL');source.execute("INSERT INTO tbl_bot_status(bot_name,last_seen)VALUES('ggb','fixture')");source.commit()
   with sqlite3.connect(backup)as dest:source.backup(dest)
  with sqlite3.connect(backup)as db:self.assertEqual(db.execute('SELECT last_seen FROM tbl_bot_status').fetchone()[0],'fixture')
 def test_no_implicit_unknown_version(self):
  with sqlite3.connect(self.path)as db:db.execute('PRAGMA user_version=99')
  with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_VERSION_UNSUPPORTED'):self.migrate()
 def test_symlink_rejected(self):
  link=Path(self.tmp.name)/'alias';link.symlink_to(self.path)
  with self.assertRaisesRegex(v2.FoundationError,'DB_SYMLINK'):v2.SQLiteFoundation(link,'ggb',uid(),uid())
 def test_transaction_required(self):
  with sqlite3.connect(self.path)as db:
   with self.assertRaisesRegex(v2.FoundationError,'MIGRATION_TRANSACTION_REQUIRED'):v2.migrate_sqlite(db,'ggb',60)
 def test_log_identity_all_or_none(self):
  self.migrate()
  with sqlite3.connect(self.path)as db:
   with self.assertRaises(sqlite3.IntegrityError):
    db.execute("INSERT INTO tbl_job_log(job_id,bot_name,ran_at,instance,dispatch_id,outcome)VALUES(1,'GGB','fixture','ggb',?,NULL)",(uid(),))

 def legacy_log(self):
  with sqlite3.connect(self.path)as db:
   db.execute('CREATE TABLE tbl_job_log(id INTEGER PRIMARY KEY,job_id INTEGER,bot_name TEXT,ran_at TEXT,duration_ms INTEGER,ok INTEGER,message TEXT,created_at TEXT)')
   db.execute("INSERT INTO tbl_job_log VALUES(1,1,'GGB','old',1,1,'historical','old')")
 def schema_snapshot(self):
  with sqlite3.connect(self.path)as db:
   return (db.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').fetchall(),db.execute('SELECT * FROM tbl_job_log').fetchall(),db.execute('SELECT * FROM jrbot_provider_state').fetchall(),db.execute('PRAGMA user_version').fetchone())
 def test_recognized_log_indexes_preserved(self):
  self.legacy_log()
  with sqlite3.connect(self.path)as db:
   db.execute('CREATE INDEX idx_job_time ON tbl_job_log(job_id,ran_at)')
   db.execute('CREATE INDEX idx_bot_time ON tbl_job_log(bot_name,ran_at)')
  self.migrate()
  with sqlite3.connect(self.path)as db:
   for name,columns in [('idx_job_time',['job_id','ran_at']),('idx_bot_time',['bot_name','ran_at'])]:
    self.assertEqual([x[2]for x in db.execute('PRAGMA index_info('+name+')')],columns)
   self.assertEqual(db.execute('SELECT message FROM tbl_job_log').fetchone()[0],'historical')
 def test_log_trigger_refused_without_schema_or_row_change(self):
  self.legacy_log()
  with sqlite3.connect(self.path)as db:db.execute("CREATE TRIGGER legacy_log_guard BEFORE DELETE ON tbl_job_log BEGIN SELECT RAISE(ABORT,'guard'); END")
  before=self.schema_snapshot()
  with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_LOG_TRIGGER_REVIEW_REQUIRED'):self.migrate()
  self.assertEqual(before,self.schema_snapshot())
 def test_log_view_refused_without_schema_or_row_change(self):
  self.legacy_log()
  with sqlite3.connect(self.path)as db:db.execute('CREATE VIEW legacy_log_view AS SELECT * FROM tbl_job_log')
  before=self.schema_snapshot()
  with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_LOG_VIEW_REVIEW_REQUIRED'):self.migrate()
  self.assertEqual(before,self.schema_snapshot())
 def test_known_name_unknown_index_definition_refused(self):
  definitions=['CREATE INDEX idx_job_time ON tbl_job_log(message)',
   'CREATE INDEX idx_job_time ON tbl_job_log(job_id DESC,ran_at)',
   'CREATE UNIQUE INDEX idx_job_time ON tbl_job_log(job_id,ran_at)',
   'CREATE INDEX idx_job_time ON tbl_job_log(job_id,ran_at) WHERE ok=1',
   'CREATE INDEX idx_job_time ON tbl_job_log(job_id COLLATE NOCASE,ran_at)']
  self.legacy_log()
  for definition in definitions:
   with self.subTest(definition=definition):
    with sqlite3.connect(self.path)as db:db.execute(definition)
    before=self.schema_snapshot()
    with self.assertRaisesRegex(v2.FoundationError,'SCHEMA_UNRECOGNIZED_INDEX'):self.migrate()
    self.assertEqual(before,self.schema_snapshot())
    with sqlite3.connect(self.path)as db:db.execute('DROP INDEX idx_job_time')

if __name__=='__main__':unittest.main(verbosity=2)
