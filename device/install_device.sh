#!/system/bin/sh
set -e

STAGE=/data/local/tmp/rk3399-deploy
ROOT=/data/local/alpine-nas
BACKUP=/data/local/alpine-nas.previous
BASE=/data/local/rk3399-nas

[ "$(id -u)" = 0 ] || { echo "ERROR: root required"; exit 10; }
[ -f "$STAGE/alpine-nas-ready.tar" ] || { echo "ERROR: payload missing"; exit 11; }
case "$(getprop ro.product.cpu.abi)" in arm64-v8a|aarch64) ;; *) echo "ERROR: ARM64 required"; exit 12;; esac

mkdir -p /data/media/0/NAS "$BASE/scripts"

stop nas_services 2>/dev/null || true
stop ethernet_role 2>/dev/null || true
stop openspeedtest_guard 2>/dev/null || true
for PID in $(pidof smbd dnsmasq 2>/dev/null); do kill "$PID" 2>/dev/null || true; done
for PROC in /proc/[0-9]*; do
    [ -r "$PROC/cmdline" ] || continue
    CMD=$(tr '\000' ' ' < "$PROC/cmdline" 2>/dev/null)
    case "$CMD" in
        *copyparty-sfx.py*|*rk3399-nas/scripts/nas_services.sh*|*rk3399-nas/scripts/ethernet_role.sh*|*rk3399-nas/scripts/openspeedtest_guard.sh*)
            kill "${PROC#/proc/}" 2>/dev/null || true ;;
    esac
done
sleep 1

for M in "$ROOT/mnt/nas" "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/sys" "$ROOT/proc"; do
    umount "$M" 2>/dev/null || true
done

if [ -e "$BACKUP" ]; then
    [ "$BACKUP" = /data/local/alpine-nas.previous ] || exit 13
    rm -rf "$BACKUP"
fi
if [ -d "$ROOT" ]; then mv "$ROOT" "$BACKUP"; fi
mkdir -p "$ROOT"
if ! tar -xf "$STAGE/alpine-nas-ready.tar" -C "$ROOT"; then
    rm -rf "$ROOT"
    [ -d "$BACKUP" ] && mv "$BACKUP" "$ROOT"
    echo "ERROR: rootfs extraction failed"
    exit 14
fi

cp "$STAGE/smb.conf" "$ROOT/etc/samba/smb.conf"
cp "$STAGE/copyparty.conf" "$ROOT/etc/copyparty.conf"
cp "$STAGE/dnsmasq-eth0.conf" "$ROOT/etc/dnsmasq-eth0.conf"
rm -f "$ROOT/var/cache/samba/"*.tdb "$ROOT/var/cache/samba/msg.lock/"* "$ROOT/var/lib/samba/msg.sock/"* 2>/dev/null || true
cp "$STAGE/nas_services.sh" "$STAGE/ethernet_role.sh" "$STAGE/openspeedtest_guard.sh" "$BASE/scripts/"
chmod 0755 "$BASE/scripts/"*.sh
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/pts" "$ROOT/run" "$ROOT/mnt/nas" "$ROOT/var/log"
echo "Device payload installed"
