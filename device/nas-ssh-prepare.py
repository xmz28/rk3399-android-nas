"""Sync the Alpine admin shell to the NAS account without replacing host keys.

Called after prepare-nas.py by the installer. Samba's password database is retained;
the existing NAS config is authoritative for the Unix password. Never log secrets.
"""
import os
from pathlib import Path
import subprocess


def prepare(root=Path('/'), run=subprocess.run, chown=None):
    chown = chown or os.chown
    at = lambda path: root / path.lstrip('/')
    config = at('/etc/copyparty-base.conf').read_text()
    accounts = config.split('[accounts]', 1)[1].split('[', 1)[0]
    password = None
    for line in accounts.splitlines():
        if line.lstrip().startswith('#') or ':' not in line:
            continue
        name, value = line.strip().split(':', 1)
        if name.strip() == 'admin':
            password = value.strip()
            break
    if not password or any(char in password for char in '\r\n\x00:'):
        raise ValueError('NAS admin password cannot be used with chpasswd')
    passwd = at('/etc/passwd')
    lines = passwd.read_text().splitlines()
    entries = [(i, line.split(':')) for i, line in enumerate(lines)
               if line.split(':', 1)[0] == 'admin']
    if len(entries) != 1 or len(entries[0][1]) != 7:
        raise ValueError('Exactly one existing Unix admin account is required')
    index, fields = entries[0]
    uid, gid = int(fields[2]), int(fields[3])
    if uid <= 0 or gid <= 0:
        raise ValueError('NAS admin must not have a root UID or GID')
    fields[5:7] = ['/home/admin', '/bin/ash']
    lines[index] = ':'.join(fields)
    passwd.write_text('\n'.join(lines) + '\n')
    home = at('/home/admin')
    home.mkdir(mode=0o750, parents=True, exist_ok=True)
    chown(home, uid, gid)
    home.chmod(0o750)
    run(['/usr/sbin/chpasswd', '-c', 'SHA512'], input='admin:' + password + '\n',
        text=True, check=True, capture_output=True)

    groups = at('/etc/group')
    lines = groups.read_text().splitlines()
    for index, line in enumerate(lines):
        fields = line.split(':')
        if len(fields) == 4 and fields[2] == '3003':
            members = [name for name in fields[3].split(',') if name]
            if 'admin' not in members:
                members.append('admin')
            fields[3] = ','.join(members)
            lines[index] = ':'.join(fields)
            break
    else:
        if any(line.split(':', 1)[0] == 'inet' for line in lines):
            raise ValueError('inet group exists with an unexpected GID')
        lines.append('inet:x:3003:admin')
    groups.write_text('\n'.join(lines) + '\n')

    sudoers = at('/etc/sudoers.d/nas-admin')
    sudoers.parent.mkdir(mode=0o750, exist_ok=True)
    sudoers.write_text('admin ALL=(ALL:ALL) ALL\n')
    sudoers.chmod(0o440)
    run(['/usr/sbin/visudo', '-cf', '/etc/sudoers'], check=True)
    profile = home / '.profile'
    if not profile.exists():
        profile.write_text('export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n')
        chown(profile, uid, gid)
        profile.chmod(0o644)
    key = at('/etc/ssh/ssh_host_ed25519_key')
    key.parent.mkdir(mode=0o755, exist_ok=True)
    if not key.exists():
        run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '',
             '-f', str(key)], check=True)
    at('/run/sshd').mkdir(mode=0o755, parents=True, exist_ok=True)
    run(['/usr/sbin/sshd', '-t', '-f', '/etc/ssh/nas-sshd.conf'], check=True)
    print('Alpine admin shell, sudo and SSH configuration ready; host identity retained')


if __name__ == '__main__':
    prepare()
