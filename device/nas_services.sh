#!/system/bin/sh

ROOT=/data/local/alpine-nas
NAS_DIR=/data/media/0/NAS
SCRIPT_DIR=${0%/*}
. "$SCRIPT_DIR/nas_usb.sh"

is_mounted() {
    mount | grep -q " $1 "
}

prepare_mounts() {
    mkdir -p "$NAS_DIR" "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/pts" "$ROOT/run" "$ROOT/mnt/nas" "$ROOT/mnt/nas-gateway"
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
    CP_PID=$(cat "$ROOT/run/copyparty.pid" 2>/dev/null)
    if [ -n "$CP_PID" ] && kill -0 "$CP_PID" 2>/dev/null && \
        tr '\000' ' ' < "/proc/$CP_PID/cmdline" | grep -q 'copyparty-sfx.py'; then
        return
    fi
    if ! port_open 3923; then
        am force-stop org.primftpd >/dev/null 2>&1
        chroot "$ROOT" /usr/bin/python3 /opt/copyparty-sfx.py -c /etc/copyparty.conf \
            >"$ROOT/var/log/copyparty.log" 2>&1 &
        echo $! > "$ROOT/run/copyparty.pid"
    fi
}

start_portal() {
    RELAY_PID=$(cat "$ROOT/run/nas-speedtest-relay.pid" 2>/dev/null)
    if [ -z "$RELAY_PID" ] || ! kill -0 "$RELAY_PID" 2>/dev/null; then
        chroot "$ROOT" /usr/bin/python3 /opt/nas-speedtest-relay.py >"$ROOT/var/log/nas-speedtest-relay.log" 2>&1 &
        echo $! > "$ROOT/run/nas-speedtest-relay.pid"
    fi
    PORTAL_PID=$(cat "$ROOT/run/nas-portal-nginx.pid" 2>/dev/null)
    if [ -n "$PORTAL_PID" ] && kill -0 "$PORTAL_PID" 2>/dev/null; then
        return
    fi
    port_open 80 || chroot "$ROOT" /usr/sbin/nginx -c /etc/nginx/nas-portal.conf
}

start_iperf3() {
    if ! port_open 5201; then
        chroot "$ROOT" /usr/bin/iperf3 -s \
            >"$ROOT/var/log/iperf3.log" 2>&1 &
        echo $! > "$ROOT/run/iperf3.pid"
    fi
}

start_mdns() {
    AVAHI_PID=$(cat "$ROOT/run/avahi-daemon/pid" 2>/dev/null)
    if [ -z "$AVAHI_PID" ] || ! kill -0 "$AVAHI_PID" 2>/dev/null; then
        rm -f "$ROOT/run/avahi-daemon/pid"
        mkdir -p "$ROOT/run/avahi-daemon"
        chroot "$ROOT" /usr/sbin/avahi-daemon --daemonize --no-chroot \
            --no-drop-root --file=/etc/avahi/avahi-daemon.conf
    fi
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
prepare_mounts
sync_usb_shares 2>>"$ROOT/var/log/nas-usb.log"
start_samba
start_http
start_portal
start_iperf3
start_mdns

while true; do
    sleep 2
    prepare_mounts
    sync_usb_shares 2>>"$ROOT/var/log/nas-usb.log"
    start_samba
    start_http
    start_portal
    start_iperf3
    start_mdns
done
