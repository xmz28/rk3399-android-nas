"""Generate Samba and Copyparty views from the same mounted-disk inventory."""
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

REGISTRY = Path('/etc/nas-usb-names')
HOST = Path('/proc/1/root')
ROOT = '/data/local/alpine-nas'

def atomic(path, data, mode=0o600):
    path = Path(path)
    if path.exists() and path.read_text() == data:
        return False
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(data)
    temp.chmod(mode)
    os.replace(temp, path)
    return True

def name_for(uuid):
    if not re.fullmatch(r'[A-Za-z0-9_-]+', uuid):
        raise ValueError('Invalid disk UUID')
    REGISTRY.mkdir(parents=True, exist_ok=True)
    entry = REGISTRY / uuid
    if not entry.exists():
        used = {p.read_text().strip() for p in REGISTRY.iterdir() if p.is_file()}
        slot = 1
        while 'USB%d' % slot in used:
            slot += 1
        atomic(entry, 'USB%d\n' % slot)
    name = entry.read_text().strip()
    if not re.fullmatch(r'USB[1-9][0-9]*', name):
        raise ValueError('Invalid persistent disk name')
    return name

def mounted():
    mounts = {}
    for line in (HOST / 'proc/1/mountinfo').read_text().splitlines():
        fields = line.split()
        mounts[fields[4]] = fields
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    result = []
    for state in sorted(Path('/run/nas-usb').glob('*')):
        uuid = state.name
        source = mounts.get('/mnt/media_rw/' + uuid)
        target = mounts.get(ROOT + '/mnt/usb/' + uuid)
        if not source or not target or source[2] != target[2]:
            continue
        if state.read_text().strip() != boot + ':' + source[0]:
            continue
        ejected = Path('/run/nas-usb-ejected') / uuid
        if ejected.exists() and ejected.read_text().strip() == state.read_text().strip():
            continue
        readonly = Path('/etc/samba/usb-readonly-' + uuid).exists() or 'ro' in source[5].split(',')
        result.append({'uuid': uuid, 'name': name_for(uuid), 'readonly': readonly})
    return sorted(result, key=lambda d: int(d['name'][3:]))

def sync(stage=False):
    disks = mounted()
    smb = ''
    for disk in disks:
        smb += '''
[{name}]
    path = /mnt/usb/{uuid}
    comment = Removable disk {name}
    browseable = yes
    read only = {readonly}
    guest ok = no
    valid users = admin
    force user = root
    create mask = 0664
    directory mask = 0775
    root preexec = /usr/local/bin/usb-share-ready {uuid}
    root preexec close = yes
'''.format(**dict(disk, readonly='yes' if disk['readonly'] else 'no'))
    if not stage and atomic('/etc/samba/usb-shares.conf', smb):
        subprocess.run(['/usr/bin/smbcontrol', 'smbd', 'reload-config'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = Path('/etc/copyparty-base.conf').read_text()
    cp = base + '\n[/]\n  /mnt/nas-gateway\n  accs:\n    r: admin\n'
    cp += '\n[/NAS]\n  /mnt/nas\n  accs:\n    rwmda: admin\n'
    for disk in disks:
        cp += '\n[/{name}]\n  /mnt/usb/{uuid}\n  accs:\n    {permissions}: admin\n'.format(
            **dict(disk, permissions='r' if disk['readonly'] else 'rwmda'))
        # Copyparty caches filesystem classification while a hotplug path is
        # absent (the parent is Android tmpfs). Only mounted(), which checks
        # the live source and bind device identities, may emit this volume.
        cp += '  flags:\n    wram\n'
    if stage:
        cp = re.sub(r'(?m)^(  p:) .*$', r'\1 13923', cp)
        cp = re.sub(r'(?m)^(  ftp:) .*$', r'\1 12346', cp)
        cp = re.sub(r'(?m)^(  sftp:) .*$', r'\1 1235', cp)
        cp = re.sub(r'(?m)^(  ftp-pr:) .*$', r'\1 5679-5682', cp)
        atomic('/run/copyparty-stage.conf', cp)
        return
    changed = atomic('/etc/copyparty.conf', cp)
    atomic('/run/nas-disks.json', json.dumps({'NAS': '/mnt/nas', 'usb': disks}, indent=2) + '\n')
    if changed:
        try:
            pid = int(Path('/run/copyparty.pid').read_text())
            cmd = Path('/proc/%d/cmdline' % pid).read_bytes()
            if b'copyparty-sfx.py' in cmd:
                os.kill(pid, signal.SIGUSR1)
        except (OSError, ValueError):
            pass

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--name':
        print(name_for(sys.argv[2]))
    else:
        sync('--stage' in sys.argv)
