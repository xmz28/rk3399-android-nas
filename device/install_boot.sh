#!/system/bin/sh
set -eu
STAGE=${0%/*}
ROOT=/data/local/alpine-nas
BASE=/data/local/rk3399-nas
if [ ! -f /system/etc/init/nas-services.rc ] && { command -v magisk >/dev/null 2>&1 || [ -d /data/adb/modules ]; }; then
    mkdir -p /data/adb/service.d
    cp "$STAGE/rk3399-nas-magisk.sh" /data/adb/service.d/rk3399-nas.sh
    chmod 755 /data/adb/service.d/rk3399-nas.sh
    echo "$BASE/scripts" > "$ROOT/etc/nas-script-dir"
    echo magisk > "$BASE/boot-mode"
else
    [ -w /system/bin ] && [ -w /system/etc/init ] || exit 31
    for file in nas_services.sh nas_usb.sh nas-usb-eject.sh; do
        cp "$STAGE/$file" "/system/bin/$file"
        chmod 755 "/system/bin/$file"
        restorecon "/system/bin/$file" 2>/dev/null || true
    done
    cp "$STAGE/nas-services.rc" /system/etc/init/nas-services.rc
    chmod 644 /system/etc/init/nas-services.rc
    restorecon /system/etc/init/nas-services.rc 2>/dev/null || true
    echo /system/bin > "$ROOT/etc/nas-script-dir"
    echo system-init > "$BASE/boot-mode"
fi
# Existing Ethernet and OpenSpeedTest boot hooks are intentionally retained.
