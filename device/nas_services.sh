#!/system/bin/sh

ROOT=/data/local/alpine-nas
NAS_DIR=/data/media/0/NAS

is_mounted() {
    mount | grep -q " $1 "
}

prepare_mounts() {
    mkdir -p "$NAS_DIR" "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/pts" "$ROOT/run" "$ROOT/mnt/nas"
    is_mounted "$ROOT/proc" || mount -t proc proc "$ROOT/proc"
    is_mounted "$ROOT/sys" || mount -t sysfs sysfs "$ROOT/sys"
    is_mounted "$ROOT/dev" || mount --bind /dev "$ROOT/dev"
    is_mounted "$ROOT/dev/pts" || mount --bind /dev/pts "$ROOT/dev/pts"
    is_mounted "$ROOT/mnt/nas" || mount --bind "$NAS_DIR" "$ROOT/mnt/nas"
}

port_open() {
    netstat -lnt 2>/dev/null | grep -q ":$1 "
}

start_samba() {
    port_open 445 || chroot "$ROOT" /usr/sbin/smbd -D -s /etc/samba/smb.conf
}

start_http() {
    if ! port_open 3923; then
        chroot "$ROOT" /usr/bin/python3 /opt/copyparty-sfx.py -c /etc/copyparty.conf \
            >"$ROOT/var/log/copyparty.log" 2>&1 &
    fi
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
prepare_mounts
start_samba
start_http

while true; do
    sleep 30
    prepare_mounts
    start_samba
    start_http
done
