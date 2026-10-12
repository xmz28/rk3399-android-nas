"""Preserve NAS credentials and SFTP identity while preparing multi-disk services."""
from pathlib import Path
import base64
import hashlib
import io
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path('/')


def prepare(root=ROOT, smb_template=None):
    def at(path):
        return root / path.lstrip('/')

    base = at('/etc/copyparty-base.conf')
    source = base if base.exists() else at('/etc/copyparty.conf')
    original = source.read_text()
    match = re.search(r'(?ms)^\[accounts\]\s*\n(.*?)(?=^\[|\Z)', original)
    if not match:
        raise ValueError('Existing Copyparty accounts section is missing')
    accounts = match.group(1).strip()
    account = next((line.strip() for line in accounts.splitlines()
                    if line.strip().startswith('admin:')), None)
    if not account:
        raise ValueError('Multi-disk templates require existing admin account')
    password = account.split(':', 1)[1].strip()
    if not password:
        raise ValueError('Empty admin password is not supported')

    keydir = at('/etc/nas-ssh')
    private = keydir / 'ssh_host_ed25519_key'
    legacy = at('/proc/1/root/data/data/org.primftpd')
    # A previously migrated installation owns its existing host identity.
    # On the first migration, validate both passwords before any writes.
    key_text = None
    if not private.exists():
        import paramiko
        prefs = ET.parse(legacy / 'shared_prefs/org.primftpd_preferences.xml')
        values = {e.attrib.get('name'): e.text for e in prefs.getroot() if e.tag == 'string'}
        digest = base64.b64encode(hashlib.sha512((password + 'H§R&q}9').encode()).digest()).decode()
        if values.get('userNamePref') != 'admin' or values.get('passwordPref') != digest:
            raise ValueError('FTP and HTTP credentials differ; refusing automatic migration')
        raw = (legacy / 'files/id_ed25519').read_text().strip()
        key_text = ('-----BEGIN OPENSSH PRIVATE KEY-----\n'
                    + '\n'.join(raw[i:i + 70] for i in range(0, len(raw), 70))
                    + '\n-----END OPENSSH PRIVATE KEY-----\n')
        loaded = paramiko.Ed25519Key.from_private_key(io.StringIO(key_text))
        public = (legacy / 'files/id_ed25519.pub').read_text().strip().split()
        if len(public) < 2 or loaded.get_base64() != public[1]:
            raise ValueError('Legacy SFTP key does not match its public identity')

    global_section = original.split('[accounts]', 1)[0]
    # Retain existing custom ports; add required options only when absent.
    if not global_section.lstrip().startswith('[global]'):
        raise ValueError('Existing Copyparty global section is missing')
    defaults = {'p': '3923', 'i': '0.0.0.0', 'name': 'RK3399 NAS',
                'ftp': '12345', 'ftp-pr': '5678-5678', 'sftp': '1234',
                'sftp-hostk': '/etc/nas-ssh'}
    for option, value in defaults.items():
        if not re.search(r'(?m)^\s*' + re.escape(option) + r':', global_section):
            global_section += f'  {option}: {value}\n'
    if not re.search(r'(?m)^\s*sftp-pw\s*$', global_section):
        global_section += '  sftp-pw\n'
    for option, value in [('rp-loc', '/files'), ('rproxy', '1'), ('xff-hdr', 'x-forwarded-for')]:
        global_section = re.sub(r'(?m)^\s*' + re.escape(option) + r':[^\n]*\n?', '', global_section)
        global_section = global_section.rstrip() + '\n'
        global_section += f'  {option}: {value}\n'

    if key_text is not None:
        keydir.mkdir(mode=0o700, exist_ok=True)
        private.write_text(key_text)
        private.chmod(0o600)
    base.write_text(global_section.rstrip() + '\n\n[accounts]\n' + accounts + '\n')
    base.chmod(0o600)
    at('/mnt/nas-gateway').mkdir(parents=True, exist_ok=True)
    # Prevent the replaced Android FTP service from restarting on boot.
    pref = legacy / 'shared_prefs/org.primftpd_preferences.xml'
    if pref.exists():
        doc = ET.parse(pref)
        for entry in doc.getroot():
            if entry.attrib.get('name') in ('startOnBootPref', 'startOnOpenPref'):
                entry.attrib['value'] = 'false'
        # Preserve Android file ownership and SELinux label by writing in place.
        with pref.open('wb') as output:
            doc.write(output, encoding='utf-8', xml_declaration=True)
    avahi = at('/etc/avahi/avahi-daemon.conf')
    text = avahi.read_text()
    if re.search(r'(?m)^host-name=', text):
        text = re.sub(r'(?m)^host-name=.*$', 'host-name=a', text)
    else:
        text = text.replace('[server]', '[server]\nhost-name=a', 1)
    avahi.write_text(text)
    nginx = at('/etc/nginx/nas-portal.conf')
    if nginx.exists():
        port = re.search(r'(?m)^\s*p:\s*(\d+)\s*$', global_section)
        if port:
            nginx.write_text(re.sub(r'http://127\.0\.0\.1:3923(?=;)',
                                   'http://127.0.0.1:' + port.group(1), nginx.read_text()))
    if smb_template is not None:
        smb = at('/etc/samba/smb.conf')
        current = smb.read_text()
        template = Path(smb_template).read_text()
        for option in ('server string', 'netbios name'):
            value = re.search(r'(?mi)^\s*' + option + r'\s*=\s*(.+)$', current)
            if value:
                template = re.sub(r'(?mi)^\s*' + option + r'\s*=.*$',
                                  lambda m: '    ' + option + ' = ' + value.group(1).strip(), template)
        smb.write_text(template)
    print('File-service credentials, disk registry and SFTP identity preserved')


if __name__ == '__main__':
    prepare(smb_template=sys.argv[1] if len(sys.argv) > 1 else None)
