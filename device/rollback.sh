#!/system/bin/sh
set -eu
BACKUP=$1
case "$BACKUP" in /data/local/rk3399-nas/backups/upgrade-*) ;; *) echo 'ERROR: invalid backup path'; exit 1 ;; esac
[ "$(id -u)" = 0 ] && [ -s "$BACKUP/manifest" ] || exit 1
. "${0%/*}/service-control.sh"
stop_nas
while IFS='|' read -r state source copy; do
    case "$source" in
        /data/local/alpine-nas/*|/data/local/rk3399-nas/*|/system/bin/*|/system/etc/init/*|/data/adb/service.d/rk3399-nas.sh|/data/data/org.primftpd/shared_prefs/org.primftpd_preferences.xml) ;;
        *) echo 'ERROR: invalid manifest target'; exit 1 ;;
    esac
    if [ "$state" = present ]; then
        cp -p "$BACKUP/$copy" "$source"
        restorecon "$source" 2>/dev/null || true
    elif [ "$state" = absent ]; then
        rm -f "$source"
    else
        exit 1
    fi
done < "$BACKUP/manifest"
start_nas
echo "ROLLED_BACK=$BACKUP"
