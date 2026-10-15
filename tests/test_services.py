"""Host-only checks for new service preparation; no devices or sockets are used."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

DEVICE = Path(__file__).resolve().parents[1] / 'device'


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, DEVICE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ssh = load('ssh_prepare', 'nas-ssh-prepare.py')
fix = load('copyparty_fix', 'nas-copyparty-fix.py')
mtp = load('mtp_sync', 'nas-mtp-sync.py')


class SshPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in ('etc/ssh', 'run'):
            (self.root / path).mkdir(parents=True)
        self.config = self.root / 'etc/copyparty-base.conf'
        self.config.write_text('[global]\n\n[accounts]\n  reader: example-reader\n  admin: Fixture_Password_123\n')
        self.passwd = self.root / 'etc/passwd'
        self.passwd.write_text('root:x:0:0:root:/root:/bin/ash\nadmin:x:1000:1000::/old:/sbin/nologin\n')
        (self.root / 'etc/group').write_text('root:x:0:\ninet:x:3003:existing\n')
        self.key = self.root / 'etc/ssh/ssh_host_ed25519_key'
        self.key.write_text('existing-openssh-identity')
        self.run = Mock()
        self.chown = Mock()

    def test_keeps_uid_host_key_and_selects_admin_after_other_accounts(self):
        ssh.prepare(self.root, self.run, self.chown)
        self.assertIn('admin:x:1000:1000::/home/admin:/bin/ash', self.passwd.read_text())
        self.assertEqual(self.key.read_text(), 'existing-openssh-identity')
        commands = [call.args[0] for call in self.run.call_args_list]
        self.assertFalse(any('ssh-keygen' in command[0] for command in commands))
        password_call = self.run.call_args_list[0]
        self.assertEqual(password_call.kwargs['input'], 'admin:Fixture_Password_123\n')
        self.assertNotIn('Fixture_Password_123', ' '.join(password_call.args[0]))
        self.assertIn('inet:x:3003:existing,admin', (self.root / 'etc/group').read_text())

    def test_repeat_preserves_profile_and_does_not_duplicate_group(self):
        ssh.prepare(self.root, self.run, self.chown)
        profile = self.root / 'home/admin/.profile'
        profile.write_text('user profile\n')
        # Windows read-only files cannot be rewritten even by the test user;
        # the real installer runs as root on Linux and can rewrite mode 0440.
        (self.root / 'etc/sudoers.d/nas-admin').chmod(0o600)
        ssh.prepare(self.root, self.run, self.chown)
        self.assertEqual(profile.read_text(), 'user profile\n')
        self.assertEqual((self.root / 'etc/group').read_text().count('existing,admin'), 1)

    def test_missing_admin_password_does_not_change_unix_account(self):
        self.config.write_text('[accounts]\nreader: example-reader\n')
        before = self.passwd.read_bytes()
        with self.assertRaises(ValueError):
            ssh.prepare(self.root, self.run, self.chown)
        self.run.assert_not_called()
        self.assertEqual(before, self.passwd.read_bytes())

    def test_root_admin_is_rejected_before_commands(self):
        self.passwd.write_text('admin:x:0:0::/root:/bin/ash\n')
        with self.assertRaisesRegex(ValueError, 'root UID'):
            ssh.prepare(self.root, self.run, self.chown)
        self.run.assert_not_called()


class CopypartyTests(unittest.TestCase):
    SOURCE = ('def initialize(self):\n'
              '        Daemon(self._snapshot, "up2k-snapshot")\n'
              '        if self.indexing:\n'
              '            Daemon(self._sched_rescan, "up2k-rescan")\n'
              '            self.index()\n')

    def test_reload_scheduler_runs_without_indexing_and_patch_is_idempotent(self):
        source = fix.patch_source(self.SOURCE)
        events = []
        namespace = {'Daemon': lambda fn, name: events.append(name)}
        exec(compile(source, 'fixture', 'exec'), namespace)
        instance = Mock(indexing=False)
        namespace['initialize'](instance)
        self.assertEqual(events, ['up2k-snapshot', 'up2k-rescan'])
        self.assertEqual(fix.patch_source(source), source)

    def test_unknown_source_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Unsupported'):
            fix.patch_source('new incompatible upstream source')

    def test_wrapper_forwards_sfx_unpack_cache_argument(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'copyparty/up2k.py'
            source.parent.mkdir()
            source.write_text(self.SOURCE)
            namespace = {'unpack': Mock(return_value=temp)}
            original_unpack = namespace['unpack']
            exec('def main():\n    unpack("cache-directory")\n', namespace)
            with patch.object(fix.runpy, 'run_path', return_value={'main': namespace['main']}), \
                    patch.object(fix.sys, 'argv', ['wrapper.py', 'sfx.py', '--help']):
                fix.main()
            original_unpack.assert_called_once_with('cache-directory')
            self.assertEqual(source.read_text(), fix.patch_source(self.SOURCE))


class MtpTests(unittest.TestCase):
    def test_snapshot_tracks_nested_files_but_excludes_temporary_uploads(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'nested').mkdir()
            (root / 'nested/file.txt').write_text('finished')
            (root / '.hidden').mkdir()
            (root / '.hidden/secret').write_text('hidden')
            (root / 'upload.PARTIAL').write_text('unfinished')
            with patch.object(mtp, 'BASE', root):
                snapshot = mtp.snapshot()
            filename = str(Path('nested') / 'file.txt')
            self.assertEqual(set(snapshot), {'nested', filename})
            self.assertTrue(snapshot['nested'][3])
            self.assertFalse(snapshot[filename][3])


if __name__ == '__main__':
    unittest.main()
