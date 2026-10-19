#!/usr/bin/env python3
"""Retention regressions: ownership, protected data, interrupted work and rotation."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[1]
if __name__ == '__main__' and not os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
    os.execv(sys.executable, [sys.executable, '-I', str(PROJECT / 'tools/artifacts.py'),
                            'run', '--label', 'test-artifacts', '--', sys.executable, __file__, *sys.argv[1:]])

spec = importlib.util.spec_from_file_location('artifacts', PROJECT / 'tools/artifacts.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


def app(path, version):
    (path / 'Contents/MacOS').mkdir(parents=True)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.exerunner.app'}))
    (path / 'Contents/MacOS/ExeRunner').write_text(version)
    return path


def engine(path, version):
    (path / 'bin').mkdir(parents=True)
    (path / 'engine.json').write_text('{}')
    (path / 'bin/wine').write_text(version)
    (path / 'bin/wineserver').write_text(version)
    return path


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.project = self.root / 'project'
        self.project.mkdir()
        self.installed = self.root / 'installed.app'
        self.store = artifacts.Artifacts(self.project, in_use=lambda p: False, verify=lambda k, p: None,
                                         installed=self.installed)
        self.game = self.project / 'bottles/live/drive_c/Games/owner.sav'
        self.game.parent.mkdir(parents=True)
        self.game.write_bytes(b'OWNER SAVE')
        self.source = self.project / 'engine/src/uncommitted.c'
        self.source.parent.mkdir(parents=True)
        self.source.write_text('owner source')

    def tearDown(self):
        self.tmp.cleanup()

    def test_unknown_directory_never_removed(self):
        unknown = self.store.root / 'jobs/looks-like-a-test'
        unknown.mkdir(); (unknown / 'important').write_text('keep')
        self.store.gc()
        self.assertTrue((unknown / 'important').exists())

    def test_dead_owned_job_removed_sources_preserved(self):
        job = self.store.new_owned('jobs', 'test')
        (job / 'original.c').write_text('int original;')
        (job / 'binary.exe').write_bytes(b'compiled')
        lease = self.store.owned(job, 'jobs'); lease['pid'] = 0
        artifacts.atomic_json(job / 'lease.json', lease)
        self.store.gc()
        self.assertFalse(job.exists())
        self.assertEqual(next((self.store.root / 'preserved').iterdir()).read_text(), 'int original;')
        self.assertEqual(self.game.read_bytes(), b'OWNER SAVE')
        self.assertEqual(self.source.read_text(), 'owner source')

    def test_live_job_not_removed(self):
        job = self.store.new_owned('jobs', 'live')
        self.store.gc()
        self.assertTrue(job.exists())

    def test_open_files_defer_cleanup(self):
        job = self.store.new_owned('jobs', 'busy')
        lease = self.store.owned(job, 'jobs'); lease['pid'] = 0
        artifacts.atomic_json(job / 'lease.json', lease)
        self.store.in_use = lambda p: True
        self.store.gc()
        self.assertTrue(job.exists())

    def test_symlink_job_never_followed(self):
        outside = self.root / 'owner'; outside.mkdir(); (outside / 'save').write_text('owner')
        (self.store.root / 'jobs/symlink').symlink_to(outside, target_is_directory=True)
        self.store.gc()
        self.assertEqual((outside / 'save').read_text(), 'owner')

    def test_symlink_lease_not_trusted(self):
        job = self.store.root / 'jobs/fake'; job.mkdir()
        outside = self.root / 'metadata.json'
        artifacts.atomic_json(outside, {'project': str(self.project), 'pid': 0, 'area': 'jobs'})
        (job / 'lease.json').symlink_to(outside)
        self.store.gc()
        self.assertTrue(job.exists())

    def test_symlink_build_root_refused(self):
        project = self.root / 'other'; project.mkdir()
        (project / 'build').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            artifacts.Artifacts(project)

    def test_wrong_checkout_owner_refused(self):
        marker = self.store.root / 'owner.json'
        artifacts.atomic_json(marker, {'schema': 1, 'project': '/wrong', 'uid': os.getuid()})
        with self.assertRaises(RuntimeError):
            artifacts.Artifacts(self.project)

    def test_protected_tree_cannot_be_registered(self):
        for p in [self.project, self.project / 'bottles/live', self.project / 'engine/src', self.installed]:
            with self.assertRaises(RuntimeError):
                self.store.safe_pin('engine', p)

    def test_backup_rotation_keeps_exactly_one(self):
        old = app(self.root / 'old.app', 'old')
        first = app(self.root / 'first.app', 'first')
        last = app(self.root / 'last.app', 'last')
        self.store.seed({'backup': str(old)})
        self.store.retain('backup', first, 'checked')
        one = Path(self.store.state()['backup']['path'])
        self.assertFalse(old.exists()); self.assertTrue(one.exists())
        self.store.retain('backup', last, 'checked')
        self.assertFalse(one.exists())
        self.assertEqual(len(list((self.store.root / 'retained').iterdir())), 1)
        self.assertEqual((Path(self.store.state()['backup']['path']) / 'Contents/MacOS/ExeRunner').read_text(), 'last')

    def test_failed_engine_verification_preserves_last_checked_engine(self):
        old = engine(self.root / 'old-engine', 'accepted')
        new = engine(self.root / 'bad-engine', 'broken')
        self.store.seed({'engine': str(old)})
        def reject(kind, path):
            if path == new:
                raise RuntimeError('native acceptance failed')
        self.store.verify = reject
        with self.assertRaises(RuntimeError):
            self.store.retain('engine', new, 'failed')
        self.assertEqual(self.store.state()['engine']['path'], str(old))
        self.assertTrue(old.exists())

    def test_modified_old_artifact_never_deleted(self):
        old = engine(self.root / 'old-engine', 'accepted')
        new = engine(self.root / 'new-engine', 'accepted2')
        self.store.seed({'engine': str(old)})
        (old / 'owner-source.c').write_text('important unrecorded edit')
        with self.assertRaises(RuntimeError):
            self.store.retain('engine', new, 'checked')
        self.assertTrue(old.exists())
        self.assertEqual(self.store.state()['engine']['path'], str(old))

    def test_busy_old_artifact_not_rotated(self):
        old = engine(self.root / 'old-engine', 'accepted')
        new = engine(self.root / 'new-engine', 'accepted2')
        self.store.seed({'engine': str(old)})
        self.store.in_use = lambda p: True
        with self.assertRaises(RuntimeError):
            self.store.retain('engine', new, 'checked')
        self.assertTrue(old.exists())

    def test_installer_same_version_refresh_and_version_rotation(self):
        old = self.project / 'build/ExeRunner-0.4.dmg'; old.write_bytes(b'old')
        new = self.project / 'build/ExeRunner-0.5.dmg'; new.write_bytes(b'new')
        self.store.seed({'installer': str(old)})
        old.write_bytes(b'rebuilt current version')
        self.store.retain('installer', old, 'new checked image')
        self.store.retain('installer', new, 'new version')
        self.assertFalse(old.exists()); self.assertTrue(new.exists())

    def test_failed_command_cleanup_and_report(self):
        status = self.store.run('failed-test', [sys.executable, '-c',
            "import os,pathlib,sys;p=pathlib.Path(os.environ['TMPDIR']);(p/'probe.cs').write_text('source');sys.exit(7)"])
        self.assertEqual(status, 7)
        self.assertEqual(list((self.store.root / 'jobs').iterdir()), [])
        report = json.loads((self.store.root / 'reports/run-failed-test.json').read_text())
        self.assertEqual(report['status'], 7)
        self.assertEqual(self.game.read_bytes(), b'OWNER SAVE')

    def test_successful_command_cleanup(self):
        self.assertEqual(self.store.run('success', [sys.executable, '-c', 'print("pass")']), 0)
        self.assertEqual(list((self.store.root / 'jobs').iterdir()), [])

    def test_reports_bounded(self):
        for n in range(25):
            artifacts.atomic_json(self.store.root / 'reports' / ('run-%02d.json' % n), {'status': 0})
        self.store.gc()
        self.assertEqual(len(list((self.store.root / 'reports').iterdir())), 20)

    def test_failed_install_restores_previous_installed_app(self):
        app(self.installed, 'old installed')
        new = app(self.root / 'new.app', 'new')
        job = self.store.new_owned('jobs', 'install')
        def verifier(kind, path):
            if path == self.installed and (path / 'Contents/MacOS/ExeRunner').read_text() == 'new':
                raise RuntimeError('post-install check failed')
        self.store.verify = verifier
        old = os.environ.get('EXERUNNER_ARTIFACT_SESSION')
        os.environ['EXERUNNER_ARTIFACT_SESSION'] = str(job)
        try:
            with self.assertRaises(RuntimeError):
                self.store.install(new)
        finally:
            if old is None: os.environ.pop('EXERUNNER_ARTIFACT_SESSION')
            else: os.environ['EXERUNNER_ARTIFACT_SESSION'] = old
        self.assertEqual((self.installed / 'Contents/MacOS/ExeRunner').read_text(), 'old installed')
        self.assertEqual(self.game.read_bytes(), b'OWNER SAVE')


    def test_rollback_failure_never_moves_installed_app(self):
        app(self.installed, 'old installed')
        new = app(self.root / 'new.app', 'new')
        job = self.store.new_owned('jobs', 'install')
        def fail(*args):
            raise RuntimeError('rollback could not be retained')
        self.store.retain = fail
        old = os.environ.get('EXERUNNER_ARTIFACT_SESSION')
        os.environ['EXERUNNER_ARTIFACT_SESSION'] = str(job)
        try:
            with self.assertRaisesRegex(RuntimeError, 'rollback could not'):
                self.store.install(new)
        finally:
            if old is None: os.environ.pop('EXERUNNER_ARTIFACT_SESSION')
            else: os.environ['EXERUNNER_ARTIFACT_SESSION'] = old
        self.assertEqual((self.installed / 'Contents/MacOS/ExeRunner').read_text(), 'old installed')
        self.assertFalse((job / 'previous.app').exists())

    def test_sigterm_cleans_owned_workspace(self):
        helper = self.root / 'interrupt.py'
        helper.write_text("import importlib.util,sys\n" +
            "sys.dont_write_bytecode=True\n" +
            "s=importlib.util.spec_from_file_location('a', " + repr(str(PROJECT / 'tools/artifacts.py')) + ");m=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n" +
            "a=m.Artifacts(" + repr(str(self.project)) + ",in_use=lambda p:False)\n" +
            "sys.exit(a.run('interrupted',[sys.executable,'-c',\"import time;print('READY',flush=True);time.sleep(60)\"]))\n")
        proc = subprocess.Popen([sys.executable, str(helper)], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(proc.stdout.readline().strip(), 'READY')
            proc.send_signal(signal.SIGTERM)
            self.assertEqual(proc.wait(timeout=15), 130)
        finally:
            if proc.poll() is None: proc.kill(); proc.wait()
            proc.stdout.close()
        self.assertEqual(list((self.store.root / 'jobs').iterdir()), [])
        self.assertEqual(self.game.read_bytes(), b'OWNER SAVE')

    def test_sigkill_workspace_collected_on_next_invocation(self):
        helper = self.root / 'killed.py'
        helper.write_text("import importlib.util,sys,time\n" +
            "sys.dont_write_bytecode=True\n" +
            "s=importlib.util.spec_from_file_location('a', " + repr(str(PROJECT / 'tools/artifacts.py')) + ");m=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n" +
            "a=m.Artifacts(" + repr(str(self.project)) + ",in_use=lambda p:False)\n" +
            "j=a.new_owned('jobs','killed');print(j,flush=True);time.sleep(60)\n")
        proc = subprocess.Popen([sys.executable, str(helper)], stdout=subprocess.PIPE, text=True)
        try:
            job = Path(proc.stdout.readline().strip())
            self.assertTrue(job.is_dir())
            proc.kill(); proc.wait(timeout=5)
        finally:
            if proc.poll() is None: proc.kill(); proc.wait()
            proc.stdout.close()
        self.store.gc()
        self.assertFalse(job.exists())
        self.assertEqual(self.source.read_text(), 'owner source')

    def test_modified_unpinned_container_preserved(self):
        src = engine(self.root / 'engine-source', 'accepted')
        self.store.retain('engine', src, 'checked')
        pin = self.store.state()['engine']
        p = Path(pin['path']); (p / 'new-owner-source.c').write_text('keep this edit')
        lease = self.store.owned(Path(pin['container']), 'retained'); lease['pid'] = 0
        artifacts.atomic_json(Path(pin['container']) / 'lease.json', lease)
        artifacts.atomic_json(self.store.statepath, {})
        self.store.gc()
        self.assertTrue((p / 'new-owner-source.c').exists())

    def test_checked_engine_lookup_refuses_modified_payload(self):
        old = engine(self.root / 'accepted', 'verified')
        self.store.seed({'engine': str(old)})
        self.assertEqual(self.store.engine_path(), old)
        (old / 'bin/wine').write_text('changed')
        with self.assertRaises(RuntimeError):
            self.store.engine_path()

    def test_fresh_checkout_engine_lookup_uses_development_portable(self):
        self.assertEqual(self.store.engine_path(), self.project / 'engine/portable')


if __name__ == '__main__':
    unittest.main()
