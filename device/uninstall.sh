#!/system/bin/sh
set -e

[ "$(id -u)" = 0 ] || exit 40
rm -f /data/adb/service.d/rk3399-nas.sh
if [ -w /system/bin ]; then
    rm -f /system/bin/nas_services.sh /system/bin/ethernet_role.sh /system/bin/openspeedtest_guard.sh
    rm -f /system/etc/init/nas-services.rc /system/etc/init/ethernet-role.rc /system/etc/init/openspeedtest-autostart.rc
fi
pkill -f /data/local/alpine-nas 2>/dev/null || true
for M in /data/local/alpine-nas/mnt/nas /data/local/alpine-nas/dev/pts /data/local/alpine-nas/dev /data/local/alpine-nas/sys /data/local/alpine-nas/proc; do
    umount "$M" 2>/dev/null || true
done
pm uninstall org.primftpd 2>/dev/null || true
pm uninstall com.openspeedtest.server 2>/dev/null || true
echo "Services and boot hooks removed. NAS files under /data/media/0/NAS were preserved."
