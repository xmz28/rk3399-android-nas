"""Initialize a clean rootfs; credentials arrive through a private file, never argv."""
import json
import re
import subprocess
import sys
from pathlib import Path


def initialize(credentials, root=Path('/'), run=subprocess.run):
    password = credentials.get('password', '')
    # Deliberately restrict syntax accepted by both Samba stdin and Copyparty config.
    if not re.fullmatch(r'[A-Za-z0-9_-]{16,64}', password):
        raise ValueError('Password must contain 16-64 letters, digits, underscore or hyphen')
    at = lambda p: root / p.lstrip('/')
    if at('/etc/copyparty-base.conf').exists() or at('/etc/nas-ssh/ssh_host_ed25519_key').exists():
        raise ValueError('Refusing to initialize existing credentials')
    for folder in ('etc/nas-ssh', 'etc/samba', 'mnt/nas-gateway', 'mnt/nas',
                   'var/log/samba', 'var/log/nginx', 'run/nas-usb', 'run/nas-usb-ejected'):
        (root / folder).mkdir(parents=True, exist_ok=True)
    at('/etc/nas-ssh').chmod(0o700)
    run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'RK3399 NAS',
         '-f', str(at('/etc/nas-ssh/ssh_host_ed25519_key'))], check=True)
    run(['/usr/sbin/adduser', '-D', '-H', '-s', '/sbin/nologin', 'admin'], check=True)
    run(['/usr/bin/smbpasswd', '-s', '-a', 'admin'], input=password + '\n' + password + '\n',
        text=True, stdout=subprocess.DEVNULL, check=True)
    base = at('/etc/copyparty-base.conf')
    base.write_text('[global]\n  p: 3923\n  i: 0.0.0.0\n  ftp: 12345\n'
                    '  ftp-pr: 5678-5678\n  sftp: 1234\n  sftp-hostk: /etc/nas-ssh\n'
                    '  sftp-pw\n  name: RK3399 NAS\n\n[accounts]\n  admin: ' + password + '\n')
    base.chmod(0o600)
    at('/etc/samba/usb-shares.conf').write_text('')
    avahi = at('/etc/avahi/avahi-daemon.conf')
    avahi.write_text('[server]\nhost-name=a\nuse-ipv6=no\nenable-dbus=no\n'
                     '[wide-area]\nenable-wide-area=no\n[publish]\npublish-workstation=yes\n')
    print('Fresh credentials and independent SFTP identity initialized')


if __name__ == '__main__':
    credential_file = Path(sys.argv[1])
    try:
        initialize(json.loads(credential_file.read_text()))
    finally:
        credential_file.unlink(missing_ok=True)
