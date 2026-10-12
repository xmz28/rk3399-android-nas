import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('init_nas', Path(__file__).resolve().parents[1] / 'device/initialize-nas.py')
init = importlib.util.module_from_spec(spec)
spec.loader.exec_module(init)


class InitializationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'etc/avahi').mkdir(parents=True)

    def test_invalid_password_rejected_before_any_command_or_write(self):
        run = Mock()
        for password in ('short', 'valid-length-but\nconfig-injection', 'password:with:colons'):
            with self.assertRaises(ValueError):
                init.initialize({'password': password}, self.root, run)
        run.assert_not_called()
        self.assertFalse((self.root / 'etc/copyparty-base.conf').exists())

    def test_existing_identity_is_never_replaced(self):
        key = self.root / 'etc/nas-ssh/ssh_host_ed25519_key'
        key.parent.mkdir()
        key.write_text('keep-this-identity')
        run = Mock()
        with self.assertRaises(ValueError):
            init.initialize({'password': 'Example_Fixture_123456'}, self.root, run)
        run.assert_not_called()
        self.assertEqual(key.read_text(), 'keep-this-identity')

    def test_samba_receives_password_on_stdin_and_ssh_uses_new_key(self):
        run = Mock()
        password = 'Example_Fixture_123456'
        init.initialize({'password': password}, self.root, run)
        calls = run.call_args_list
        self.assertEqual(calls[0].args[0][0], '/usr/bin/ssh-keygen')
        self.assertEqual(calls[2].kwargs['input'], password + '\n' + password + '\n')
        self.assertNotIn(password, ' '.join(calls[2].args[0]))
        self.assertIn('admin: ' + password, (self.root / 'etc/copyparty-base.conf').read_text())
        self.assertIn('enable-dbus=no', (self.root / 'etc/avahi/avahi-daemon.conf').read_text())


if __name__ == '__main__':
    unittest.main()
