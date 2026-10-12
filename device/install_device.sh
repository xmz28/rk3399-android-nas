#!/system/bin/sh
set -eu
STAGE=${0%/*}
ROOT=/data/local/alpine-nas
BASE=/data/local/rk3399-nas
sh "$STAGE/preflight.sh"

PY_FILES='prepare-nas.py nas-volumes.py nas-mount-private.py nas-open-files.py nas-speedtest-relay.py nas-storage.py'
SH_FILES='nas_services.sh nas_usb.sh nas-usb-eject.sh'
for file in $PY_FILES $SH_FILES smb.conf nas-portal-nginx.conf nas-portal.html nas-storage.html usb-share-ready install_boot.sh service-control.sh rollback.sh; do
    [ -s "$STAGE/$file" ] || { echo "ERROR: missing staged source $file"; exit 20; }
done
for file in $SH_FILES; do sh -n "$STAGE/$file"; done
chroot "$ROOT" /usr/bin/python3 -c 'import ast, pathlib; [ast.parse(pathlib.Path(p).read_text()) for p in __import__("sys").argv[1:]]' \
    $(for file in $PY_FILES; do echo "/proc/1/root$STAGE/$file"; done)

BACKUP="$BASE/backups/upgrade-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP" "$BASE/scripts" "$ROOT/opt/nas-portal" "$ROOT/etc/nas-ssh" "$ROOT/var/log/nginx"
chmod 700 "$BACKUP" "$ROOT/etc/nas-ssh"
: > "$BACKUP/manifest"
count=0
backup_file() {
    count=$((count + 1))
    if [ -f "$1" ]; then
        cp -p "$1" "$BACKUP/$count"
        printf 'present|%s|%s\n' "$1" "$count" >> "$BACKUP/manifest"
    else
        printf 'absent|%s|%s\n' "$1" "$count" >> "$BACKUP/manifest"
    fi
}
for file in $PY_FILES; do backup_file "$ROOT/opt/$file"; done
for file in $SH_FILES ethernet_role.sh openspeedtest_guard.sh; do
    backup_file "$BASE/scripts/$file"
    backup_file "/system/bin/$file"
done
for file in nas-services.rc ethernet-role.rc openspeedtest-autostart.rc; do backup_file "/system/etc/init/$file"; done
for target in "$ROOT/etc/copyparty-base.conf" "$ROOT/etc/copyparty.conf" "$ROOT/etc/samba/smb.conf" \
    "$ROOT/etc/samba/usb-shares.conf" "$ROOT/etc/nginx/nas-portal.conf" "$ROOT/etc/avahi/avahi-daemon.conf" \
    "$ROOT/etc/nas-ssh/ssh_host_ed25519_key" "$ROOT/etc/nas-script-dir" "$ROOT/usr/local/bin/usb-share-ready" \
    "$ROOT/opt/nas-portal/index.html" "$ROOT/opt/nas-portal/storage.html" "$BASE/boot-mode" \
    /data/adb/service.d/rk3399-nas.sh /data/data/org.primftpd/shared_prefs/org.primftpd_preferences.xml; do
    backup_file "$target"
done
chmod 600 "$BACKUP"/*
. "$STAGE/service-control.sh"
# Restore only the files this installer touches if a later step fails.
trap 'code=$?; trap - EXIT; if [ "$code" -ne 0 ]; then echo "Upgrade failed; restoring $BACKUP"; sh "$STAGE/rollback.sh" "$BACKUP" || echo "ERROR: automatic rollback failed; backup is $BACKUP"; fi; exit "$code"' EXIT
stop_nas
am force-stop org.primftpd 2>/dev/null || true
for file in $PY_FILES; do cp "$STAGE/$file" "$ROOT/opt/$file"; done
mkdir -p "$ROOT/usr/local/bin" "$ROOT/etc/nginx"
cp "$STAGE/usb-share-ready" "$ROOT/usr/local/bin/usb-share-ready"
chmod 755 "$ROOT/usr/local/bin/usb-share-ready"
cp "$STAGE/nas-portal.html" "$ROOT/opt/nas-portal/index.html"
cp "$STAGE/nas-storage.html" "$ROOT/opt/nas-portal/storage.html"
cp "$STAGE/nas-portal-nginx.conf" "$ROOT/etc/nginx/nas-portal.conf"
chroot "$ROOT" /usr/bin/python3 /opt/prepare-nas.py "/proc/1/root$STAGE/smb.conf"
for file in $SH_FILES; do cp "$STAGE/$file" "$BASE/scripts/$file"; done
chmod 755 "$BASE/scripts/"*.sh
chroot "$ROOT" /usr/bin/python3 /opt/nas-volumes.py
chroot "$ROOT" /usr/bin/testparm -s >/dev/null
chroot "$ROOT" /usr/sbin/nginx -t -c /etc/nginx/nas-portal.conf
sh "$STAGE/install_boot.sh"
start_nas
healthy=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 2
    if sh "$STAGE/status.sh" --health > "$BACKUP/health.log" 2>&1; then healthy=1; break; fi
done
cat "$BACKUP/health.log"
[ "$healthy" = 1 ] || { echo 'ERROR: service startup timed out'; exit 32; }
echo "UPGRADE_BACKUP=$BACKUP"
echo 'Upgrade complete; no storage was formatted and no reboot was requested.'
