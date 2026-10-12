#!/system/bin/sh
set -eu
ROOT=/data/local/alpine-nas
[ "$(id -u)" = 0 ] || { echo 'ERROR: root required'; exit 10; }
case "$(getprop ro.board.platform)" in *rk3399*) ;; *) echo 'ERROR: RK3399 required'; exit 11 ;; esac
case "$(getprop ro.product.cpu.abi)" in arm64-v8a|aarch64) ;; *) echo 'ERROR: ARM64 required'; exit 12 ;; esac
if [ "${1:-}" = --fresh ]; then
    [ ! -e "$ROOT" ] || { echo 'ERROR: existing Alpine directory; use upgrade, never overwrite'; exit 13; }
    command -v busybox >/dev/null 2>&1 || { echo 'ERROR: BusyBox required for verified gzip extraction'; exit 15; }
    for port in 80 445 3923 12345 1234 5201; do
        if netstat -lnt 2>/dev/null | grep -q ":$port "; then
            echo "ERROR: fresh installation port $port already in use"; exit 16
        fi
    done
    busybox tar --help >/dev/null 2>&1 && busybox sha256sum --help >/dev/null 2>&1 || exit 15
    if [ -w /system/bin ] && [ -w /system/etc/init ]; then
        echo 'PREFLIGHT=PASS (fresh installation; writable system)'; exit 0
    fi
    if [ -d /data/adb ] && { command -v magisk >/dev/null 2>&1 || [ -d /data/adb/modules ]; }; then
        if [ -n "$(pm path com.example.rk3399_control 2>/dev/null)" ] && [ ! -f /data/local/rk3399-control/config/nas-v3-compatible ]; then
            echo 'ERROR: update existing Control App before fresh Magisk installation'; exit 20
        fi
        echo 'PREFLIGHT=PASS (fresh installation; Magisk)'; exit 0
    fi
    echo 'ERROR: writable system or Magisk required for startup'; exit 19
fi
[ -d "$ROOT" ] || { echo 'ERROR: install and initialize Alpine NAS first; this package upgrades existing NAS'; exit 13; }
[ -d "$ROOT/proc/1/root" ] || { echo 'ERROR: existing NAS proc mount is not ready; start its service first'; exit 14; }
for executable in /usr/bin/python3 /usr/sbin/smbd /usr/bin/testparm /usr/bin/smbcontrol /usr/sbin/nginx /usr/sbin/avahi-daemon /usr/bin/iperf3 /usr/bin/awk; do
    [ -x "$ROOT$executable" ] || { echo "ERROR: missing Alpine dependency $executable"; exit 15; }
done
chroot "$ROOT" /usr/bin/python3 -c 'import paramiko, ctypes, fcntl'
[ -f "$ROOT/opt/copyparty-sfx.py" ] || { echo 'ERROR: Copyparty required'; exit 16; }
[ -f "$ROOT/etc/avahi/avahi-daemon.conf" ] || { echo 'ERROR: configure Avahi first'; exit 17; }
[ -s "$ROOT/etc/copyparty-base.conf" ] || [ -s "$ROOT/etc/copyparty.conf" ] || { echo 'ERROR: existing file-service accounts required'; exit 18; }
# Prefer Magisk on devices where system is read-only.
if [ -f /system/etc/init/nas-services.rc ]; then
    [ -w /system/bin ] && [ -w /system/etc/init ] || { echo 'ERROR: existing init hook requires writable system; remount before upgrade'; exit 19; }
elif command -v magisk >/dev/null 2>&1 || [ -d /data/adb/modules ]; then
    [ -d /data/adb ] || exit 19
    if [ -n "$(pm path com.example.rk3399_control 2>/dev/null)" ] && [ ! -f /data/local/rk3399-control/config/nas-v3-compatible ]; then
        echo 'ERROR: current Control APK stops the Magisk NAS watcher; update the App before using this combination'
        exit 20
    fi
elif [ -w /system/bin ] && [ -w /system/etc/init ]; then
    : # Fresh rootfs was initialized; the installer will add the init hook.
else
    echo 'ERROR: existing init NAS hook or Magisk required; cold installation is not supported'
    exit 19
fi
echo 'PREFLIGHT=PASS (existing NAS upgrade; no service changes)'
