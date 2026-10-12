import ctypes
import os
import sys

path = sys.argv[1]
if not path.startswith('/mnt/usb/') or '/' in path[len('/mnt/usb/'):]:
    raise SystemExit('Invalid USB mount path')
libc = ctypes.CDLL(None, use_errno=True)
libc.mount.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                       ctypes.c_ulong, ctypes.c_void_p]
libc.mount.restype = ctypes.c_int
if libc.mount(None, os.fsencode(path), None, (1 << 18) | (1 << 14), None) != 0:
    raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()), path)
if len(sys.argv) > 2:
    flags = (1 << 12) | (1 << 5) | 2 | 4 | 8  # bind-remount, nosuid,nodev,noexec
    if sys.argv[2] == 'ro':
        flags |= 1
    if libc.mount(None, os.fsencode(path), None, flags, None) != 0:
        raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()), path)
