"""Host-only upgrade checks. No ADB, disks, mounts or network are touched."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

DEVICE = Path(__file__).resolve().parents[1] / 'device'


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, DEVICE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load('prepare_nas', 'prepare-nas.py')
volumes = load('nas_volumes', 'nas-volumes.py')


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in ('etc/nas-ssh', 'etc/avahi', 'etc/nginx'):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        (self.root / 'etc/avahi/avahi-daemon.conf').write_text('[server]\n')
        (self.root / 'etc/nginx/nas-portal.conf').write_text('proxy_pass http://127.0.0.1:3923;\n')

    def config(self, text):
        (self.root / 'etc/copyparty.conf').write_text(text)

    def test_upgrade_retains_password_ports_and_host_identity(self):
        key = self.root / 'etc/nas-ssh/ssh_host_ed25519_key'
        key.write_text('existing-host-identity')
        self.config('[global]\n  p: 40923\n  ftp: 12340\n  sftp: 12341\n\n[accounts]\n  admin: example-local-password\n  reader: example-reader\n\n[/]\n  /mnt/nas\n')
        prepare.prepare(self.root)
        base = (self.root / 'etc/copyparty-base.conf').read_text()
        self.assertIn('admin: example-local-password', base)
        self.assertIn('reader: example-reader', base)
        self.assertIn('p: 40923', base)
        self.assertIn('ftp: 12340', base)
        self.assertIn('sftp: 12341', base)
        self.assertEqual(key.read_text(), 'existing-host-identity')
        self.assertIn('127.0.0.1:40923;', (self.root / 'etc/nginx/nas-portal.conf').read_text())
        prepare.prepare(self.root)
        self.assertEqual(base, (self.root / 'etc/copyparty-base.conf').read_text())

    def test_missing_admin_is_rejected_before_writing(self):
        self.config('[global]\n  p: 3923\n\n[accounts]\n  somebody: example\n')
        with self.assertRaisesRegex(ValueError, 'admin'):
            prepare.prepare(self.root)
        self.assertFalse((self.root / 'etc/copyparty-base.conf').exists())

    def test_first_migration_refuses_different_ftp_password(self):
        self.config('[global]\n  p: 3923\n\n[accounts]\n  admin: example\n')
        legacy = self.root / 'proc/1/root/data/data/org.primftpd/shared_prefs'
        legacy.mkdir(parents=True)
        prefs = '<map><string name="userNamePref">admin</string><string name="passwordPref">different</string></map>'
        (legacy / 'org.primftpd_preferences.xml').write_text(prefs)
        with patch.dict(sys.modules, {'paramiko': object()}):
            with self.assertRaisesRegex(ValueError, 'credentials differ'):
                prepare.prepare(self.root)
        self.assertFalse((self.root / 'etc/copyparty-base.conf').exists())
        self.assertFalse((self.root / 'etc/nas-ssh/ssh_host_ed25519_key').exists())
        self.assertEqual(prefs, (legacy / 'org.primftpd_preferences.xml').read_text())

    def test_disk_numbering_has_no_reserved_device_uuid(self):
        with patch.object(volumes, 'REGISTRY', self.root / 'registry'):
            self.assertEqual(volumes.name_for('FIRST-USB'), 'USB1')
            self.assertEqual(volumes.name_for('SECOND-USB'), 'USB2')
            self.assertEqual(volumes.name_for('FIRST-USB'), 'USB1')
            self.assertEqual(sorted(p.name for p in volumes.REGISTRY.iterdir()), ['FIRST-USB', 'SECOND-USB'])

    def test_existing_disk_number_and_readonly_flag_remain(self):
        registry = self.root / 'registry'
        registry.mkdir()
        (registry / 'EXISTING').write_text('USB7\n')
        flag = self.root / 'etc/usb-readonly-EXISTING'
        flag.write_text('')
        with patch.object(volumes, 'REGISTRY', registry):
            self.assertEqual(volumes.name_for('EXISTING'), 'USB7')
        self.assertTrue(flag.exists())

    def test_invalid_uuid_never_creates_registry_entry(self):
        with patch.object(volumes, 'REGISTRY', self.root / 'registry'):
            for invalid in ('../etc', 'USB;reboot', '', 'a/b'):
                with self.assertRaises(ValueError):
                    volumes.name_for(invalid)
            self.assertFalse(volumes.REGISTRY.exists())

    def test_upgrade_preserves_existing_smb_device_name(self):
        (self.root / 'etc/nas-ssh/ssh_host_ed25519_key').write_text('existing-host-identity')
        self.config('[global]\n  p: 3923\n\n[accounts]\n  admin: example\n')
        smb = self.root / 'etc/samba/smb.conf'
        smb.parent.mkdir()
        smb.write_text('[global]\n    server string = My NAS\n    netbios name = MY-NAS\n')
        template = self.root / 'smb-template.conf'
        template.write_text('[global]\n    server string = RK3399 NAS\n    netbios name = RK3399-NAS\n    include = /etc/samba/usb-shares.conf\n')
        prepare.prepare(self.root, template)
        self.assertIn('server string = My NAS', smb.read_text())
        self.assertIn('netbios name = MY-NAS', smb.read_text())
        self.assertIn('include = /etc/samba/usb-shares.conf', smb.read_text())


if __name__ == '__main__':
    unittest.main()
