"""Reconcile NAS changes from all network protocols with Android's MTP index.

Run inside Alpine; Android am is reached through the init process root.
Two stable snapshots avoid indexing a file while it is still being uploaded.
Only NAS is scanned; removable storage continues to be owned by Android vold.
"""
import json
import os
import subprocess
import time
from pathlib import Path
from urllib.parse import quote

BASE = Path('/mnt/nas')
STATE = Path('/run/nas-mtp-state.json')


def snapshot():
    result = {}
    def fail(error):
        raise error
    for directory, folders, files in os.walk(BASE, followlinks=False, onerror=fail):
        folders[:] = [n for n in folders if not n.startswith('.')
                      and not (Path(directory) / n).is_symlink()]
        for name in folders + files:
            if name.startswith('.') or name.endswith('.PARTIAL'):
                continue
            path = Path(directory) / name
            try:
                if path.is_symlink():
                    continue
                stat = path.stat()
                result[str(path.relative_to(BASE))] = [stat.st_ino, stat.st_size,
                                                       stat.st_mtime_ns, path.is_dir()]
            except FileNotFoundError:
                pass
    return result


def scan(name):
    # MediaProvider can restart while USB stays connected, losing its binding
    # to MtpService. Scans then update SQL but send no ObjectAdded/Removed event.
    # Re-establish the Android 7 MTP notification binding before scanning.
    state = subprocess.check_output(['/usr/sbin/chroot', '/proc/1/root',
        '/system/bin/getprop', 'sys.usb.state'], text=True).strip().split(',')
    if 'mtp' in state:
        subprocess.run(['/usr/sbin/chroot', '/proc/1/root', '/system/bin/sh',
            '/system/bin/content', 'insert', '--uri',
            'content://media/none/mtp_connected', '--bind', 'connected:i:1'],
            check=True, timeout=20, stdout=subprocess.DEVNULL)
        time.sleep(0.2)
    uri = 'file://' + quote('/storage/emulated/0/NAS/' + name, safe='/')
    subprocess.run(['/usr/sbin/chroot', '/proc/1/root', '/system/bin/am',
                    'broadcast', '--user', '0', '-a',
                    'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', uri],
                   check=True, timeout=20, stdout=subprocess.DEVNULL)
    print('MTP scanned: ' + name, flush=True)


def main():
    try:
        indexed = json.loads(STATE.read_text())
    except (OSError, ValueError):
        indexed = {}
    previous = {}
    while True:
        try:
            current = snapshot()
            before = dict(indexed)
            # Parents first, including nested directories moved into NAS.
            for name in sorted(current, key=lambda n: (n.count('/'), n)):
                value = current[name]
                if value == previous.get(name) and value != indexed.get(name):
                    scan(name)
                    indexed[name] = value
            # Missing paths also need scanning so stale MTP rows are removed.
            for name in sorted(set(indexed) - set(current), reverse=True):
                if name not in previous:
                    scan(name)
                    del indexed[name]
            if indexed != before or not STATE.exists():
                temp = STATE.with_suffix('.tmp')
                temp.write_text(json.dumps(indexed, ensure_ascii=False))
                os.replace(temp, STATE)
            previous = current
        except Exception as error:
            print('MTP sync retry: %r' % error, flush=True)
        time.sleep(5)


if __name__ == '__main__':
    main()
