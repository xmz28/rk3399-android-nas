#!/system/bin/sh
set -e

STAGE=/data/local/tmp/rk3399-deploy
BASE=/data/local/rk3399-nas

[ "$(id -u)" = 0 ] || exit 30
if command -v magisk >/dev/null 2>&1 || [ -d /data/adb/modules ]; then
    mkdir -p /data/adb/service.d
    cp "$STAGE/rk3399-nas-magisk.sh" /data/adb/service.d/rk3399-nas.sh
    chmod 0755 /data/adb/service.d/rk3399-nas.sh
    echo magisk > "$BASE/boot-mode"
    echo "Boot method: Magisk service.d"
    exit 0
fi

[ -w /system/bin ] || { echo "ERROR: /system is not writable and Magisk was not found"; exit 31; }
cp "$STAGE/nas_services.sh" "$STAGE/ethernet_role.sh" "$STAGE/openspeedtest_guard.sh" /system/bin/
cp "$STAGE/nas-services.rc" "$STAGE/ethernet-role.rc" "$STAGE/openspeedtest-autostart.rc" /system/etc/init/
chmod 0755 /system/bin/nas_services.sh /system/bin/ethernet_role.sh /system/bin/openspeedtest_guard.sh
chmod 0644 /system/etc/init/nas-services.rc /system/etc/init/ethernet-role.rc /system/etc/init/openspeedtest-autostart.rc
restorecon /system/bin/nas_services.sh /system/bin/ethernet_role.sh /system/bin/openspeedtest_guard.sh 2>/dev/null || true
restorecon /system/etc/init/nas-services.rc /system/etc/init/ethernet-role.rc /system/etc/init/openspeedtest-autostart.rc 2>/dev/null || true
echo system-init > "$BASE/boot-mode"
echo "Boot method: Android init"
