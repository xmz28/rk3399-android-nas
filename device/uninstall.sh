#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 40
. "${0%/*}/service-control.sh"
stop_nas
rm -f /data/adb/service.d/rk3399-nas.sh
if [ -w /system/bin ]; then
    rm -f /system/bin/nas_services.sh /system/bin/nas_usb.sh /system/bin/nas-usb-eject.sh
    rm -f /system/etc/init/nas-services.rc
fi
echo 'NAS startup hook removed. Data, rootfs, credentials, backups, network hooks and APKs retained.'
echo 'If RK3399 Control also starts services, disable its boot switches separately.'
