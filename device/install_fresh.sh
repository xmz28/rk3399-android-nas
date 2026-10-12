#!/system/bin/sh
set -eu
STAGE=${0%/*}
ROOT=/data/local/alpine-nas
BASE=/data/local/rk3399-nas
sh "$STAGE/preflight.sh" --fresh
IMAGE="$STAGE/alpine-nas-clean.tar.gz"
[ "${1:-}" != --online ] || IMAGE="$STAGE/alpine-minirootfs.tar.gz"
[ -s "$IMAGE" ] && [ -s "$STAGE/credentials.json" ] || exit 21
# Host validates the pinned archive. Verify transferred bytes before extraction too.
EXPECTED=$(cat "$STAGE/rootfs.sha256")
ACTUAL=$(busybox sha256sum "$IMAGE" | cut -d ' ' -f 1)
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'ERROR: transferred rootfs checksum mismatch'; exit 22; }
NEXT=/data/local/alpine-nas.new-$$
[ ! -e "$NEXT" ] || exit 23
mkdir -p "$NEXT"
chmod 700 "$NEXT"
cleanup() {
    code=$?
    trap - EXIT
    rm -f "$STAGE/credentials.json"
    if [ "$code" -ne 0 ] && [ -f "$ROOT/etc/nas-clean-image" ]; then
        # Keep failed state and passwords for inspection. Never delete mounted trees.
        . "$STAGE/service-control.sh"
        stop_nas
        for target in "$ROOT/mnt/nas" "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/sys" "$ROOT/proc"; do
            if mount | grep -q " $target "; then umount "$target" || true; fi
        done
        if mount | grep -q " $ROOT/"; then
            echo "ERROR: failed installation retained at $ROOT (mounts remain); do not delete it recursively"
        else
            FAILED=/data/local/alpine-nas.failed-$(date +%Y%m%d-%H%M%S)-$$
            mv "$ROOT" "$FAILED"
            echo "FAILED_INSTALL_SAVED=$FAILED"
        fi
    fi
    exit "$code"
}
trap cleanup EXIT
busybox tar -xzf "$IMAGE" -C "$NEXT"
if [ "${1:-}" = --online ]; then
    cp "$STAGE/copyparty-sfx.py" "$NEXT/tmp/copyparty-sfx.py"
    cp "$STAGE/build-rootfs.sh" "$NEXT/tmp/build-rootfs.sh"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$NEXT/etc/resolv.conf"
    chroot "$NEXT" /bin/sh /tmp/build-rootfs.sh
    rm -f "$NEXT/tmp/build-rootfs.sh"
fi
[ -x "$NEXT/usr/bin/python3" ] && [ -f "$NEXT/etc/nas-clean-image" ] || exit 24
SPEED_EXPECTED=$(cat "$STAGE/speedtest.sha256")
[ "$(busybox sha256sum "$STAGE/openspeedtest.tar.gz" | cut -d ' ' -f 1)" = "$SPEED_EXPECTED" ] || exit 22
mkdir -p "$NEXT/opt/openspeedtest" "$NEXT/etc/nginx/nas-extra"
busybox tar -xzf "$STAGE/openspeedtest.tar.gz" -C "$NEXT/opt/openspeedtest"
chroot "$NEXT" /usr/bin/python3 -c 'from pathlib import Path; Path("/opt/openspeedtest/downloading").write_bytes(bytes(range(256)) * (30 * 1024 * 1024 // 256))'
cp "$STAGE/nas-speedtest-nginx.conf" "$NEXT/etc/nginx/nas-extra/speedtest.conf"
# No mounts or active services exist under NEXT. Rename only to an absent destination.
[ ! -e "$ROOT" ] || exit 25
mv "$NEXT" "$ROOT"
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount --bind /dev "$ROOT/dev"
chmod 600 "$STAGE/credentials.json"
chroot "$ROOT" /usr/bin/python3 "/proc/1/root$STAGE/initialize-nas.py" "/proc/1/root$STAGE/credentials.json"
cp "$STAGE/smb.conf" "$ROOT/etc/samba/smb.conf"
# Use the same backed-up, validated service installation as upgrades.
sh "$STAGE/install_device.sh"
echo 'Fresh installation complete. File-service account: admin (password saved on PC).'
