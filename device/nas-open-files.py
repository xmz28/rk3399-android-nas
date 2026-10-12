"""Fail safe eject while any regular file on the source disk is still open."""
import os
from pathlib import Path
import re
import stat
import sys

uuid = sys.argv[1]
if not re.fullmatch(r'[A-Za-z0-9_-]+', uuid):
    raise SystemExit('Invalid disk UUID')
source = Path('/proc/1/root/mnt/media_rw') / uuid
try:
    device = source.stat().st_dev
except FileNotFoundError:
    raise SystemExit(0)
busy = 0
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit() or int(proc.name) == os.getpid():
        continue
    try:
        descriptors = list((proc / 'fd').iterdir())
    except (FileNotFoundError, PermissionError):
        continue
    for fd in descriptors:
        try:
            info = fd.stat()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if info.st_dev == device and stat.S_ISREG(info.st_mode):
            busy += 1
if busy:
    print('%d disk file handle(s) still open' % busy)
raise SystemExit(1 if busy else 0)
