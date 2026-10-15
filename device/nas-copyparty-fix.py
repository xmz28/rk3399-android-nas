"""Start pinned Copyparty with its reload scheduler independent of indexing."""
import runpy
import sys
from pathlib import Path

def patch_source(source):
    old = '            Daemon(self._sched_rescan, "up2k-rescan")\n'
    anchor = '        Daemon(self._snapshot, "up2k-snapshot")\n'
    fixed = anchor + '        Daemon(self._sched_rescan, "up2k-rescan")\n'
    if fixed in source:
        return source
    if source.count(old) != 1 or source.count(anchor) != 1:
        raise RuntimeError('Unsupported Copyparty source; reload fix needs review')
    return source.replace(old, '').replace(anchor, fixed)


def main():
    sys.argv = sys.argv[1:]
    sfx = runpy.run_path(sys.argv[0], run_name='nas_copyparty_sfx')
    original_main = sfx['main']
    original_unpack = original_main.__globals__['unpack']

    def unpack(*args, **kwargs):
        # SFX 1.20.25 passes its cache directory to unpack(top).
        folder = original_unpack(*args, **kwargs)
        path = Path(folder) / 'copyparty/up2k.py'
        source = path.read_text()
        fixed = patch_source(source)
        compile(fixed, str(path), 'exec')
        if fixed != source:
            path.write_text(fixed)
        print('[NAS] reload scheduler enabled independently of indexing', flush=True)
        return folder

    original_main.__globals__['unpack'] = unpack
    original_main()


if __name__ == '__main__':
    main()
