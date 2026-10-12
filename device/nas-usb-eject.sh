#!/system/bin/sh
# Usage: su 0 sh /system/bin/nas-usb-eject.sh USB1 (or a filesystem UUID)
ROOT=/data/local/alpine-nas
uuid=$1
case "$uuid" in
    USB[0-9]*)
        uuid=
        for entry in "$ROOT/etc/nas-usb-names"/*; do
            [ -f "$entry" ] || continue
            if [ "$(cat "$entry")" = "$1" ]; then
                uuid=${entry##*/}
                break
            fi
        done
        ;;
esac
case "$uuid" in ''|*[!A-Za-z0-9_-]*) echo 'Supply a known USB name or disk UUID'; exit 1 ;; esac
source=/mnt/media_rw/$uuid
boot=$(cat /proc/sys/kernel/random/boot_id)
id=$(chroot "$ROOT" /usr/bin/awk -v boot="$boot" -v p="$source" '$5 == p {print boot ":" $1; exit}' /proc/1/mountinfo)
volume=$(chroot "$ROOT" /usr/bin/awk -v p="$source" '$5 == p {for(i=6;i<=NF;i++) if($i=="-") {print $(i+2); exit}}' /proc/1/mountinfo)
case "$volume" in /dev/block/vold/public:*) volume=${volume##*/} ;; *) echo 'Not a mounted public disk'; exit 1 ;; esac
mkdir -p "$ROOT/run/nas-usb-ejected"
echo "$id" > "$ROOT/run/nas-usb-ejected/$uuid"
# The watcher closes SMB handles and detaches its bind before vold unmounts.
sleep 4
if chroot "$ROOT" /usr/bin/awk -v p="$ROOT/mnt/usb/$uuid" '$5 == p {found=1} END {exit !found}' /proc/1/mountinfo; then
    echo 'NAS still holds this disk; do not unplug'; exit 1
fi
attempt=0
while ! chroot "$ROOT" /usr/bin/python3 /opt/nas-open-files.py "$uuid"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 10 ]; then
        echo 'Disk files are still in use; stop transfers and retry. Do not unplug.'
        exit 1
    fi
    sleep 2
done
sync
sm unmount "$volume" || exit 1
if chroot "$ROOT" /usr/bin/awk -v p="$source" '$5 == p {found=1} END {exit !found}' /proc/1/mountinfo; then
    echo 'Disk remains mounted; do not unplug'; exit 1
fi
# Linux may reuse the same mount ID on the next insertion. Once unmounted,
# the source cannot be re-exported until vold mounts it again, so clear pause.
rm -f "$ROOT/run/nas-usb-ejected/$uuid"
echo "$uuid ejected; safe to unplug"
