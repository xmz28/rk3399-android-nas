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
    [ "$(cat /data/local/rk3399-control/enabled/samba 2>/dev/null)" != 0 ] || return 0
    port_open 445 || chroot "$ROOT" /usr/sbin/smbd -D -s /etc/samba/smb.conf
}

start_http() {
    CP_PID=$(cat "$ROOT/run/copyparty.pid" 2>/dev/null)
    if [ -n "$CP_PID" ] && kill -0 "$CP_PID" 2>/dev/null && \
        tr '\000' ' ' < "/proc/$CP_PID/cmdline" | grep -q 'copyparty-sfx.py'; then
        return
    fi
    HTTP_PORT=$(chroot "$ROOT" /usr/bin/awk -F: '$1 ~ "^[[:space:]]*p$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/copyparty-base.conf 2>/dev/null)
    case "$HTTP_PORT" in ''|*[!0-9]*) HTTP_PORT=3923 ;; esac
    if ! port_open "$HTTP_PORT"; then
        am force-stop org.primftpd >/dev/null 2>&1
        chroot "$ROOT" /usr/bin/python3 /opt/nas-copyparty-fix.py /opt/copyparty-sfx.py -c /etc/copyparty.conf \
            >"$ROOT/var/log/copyparty.log" 2>&1 &
        echo $! > "$ROOT/run/copyparty.pid"
    fi
}

start_mtp_sync() {
    MTP_PID=$(cat "$ROOT/run/nas-mtp-sync.pid" 2>/dev/null)
    if [ -n "$MTP_PID" ] && kill -0 "$MTP_PID" 2>/dev/null && \
        tr '\000' ' ' < "/proc/$MTP_PID/cmdline" | grep -q '/opt/nas-mtp-sync.py'; then
        return
    fi
    chroot "$ROOT" /usr/bin/python3 /opt/nas-mtp-sync.py \
        >>"$ROOT/var/log/nas-mtp-sync.log" 2>&1 &
    echo $! > "$ROOT/run/nas-mtp-sync.pid"
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
    [ "$(cat /data/local/rk3399-control/enabled/iperf 2>/dev/null)" != 0 ] || return 0
    IPERF_PORT=$(cat /data/local/rk3399-control/config/iperf_port 2>/dev/null)
    case "$IPERF_PORT" in ''|*[!0-9]*) IPERF_PORT=5201 ;; esac
    if ! port_open "$IPERF_PORT"; then
        chroot "$ROOT" /usr/bin/iperf3 -s -p "$IPERF_PORT" \
            >"$ROOT/var/log/iperf3.log" 2>&1 &
        echo $! > "$ROOT/run/iperf3.pid"
    fi
}

start_mdns() {
    [ "$(cat /data/local/rk3399-control/enabled/mdns 2>/dev/null)" != 0 ] || return 0
    AVAHI_PID=$(cat "$ROOT/run/avahi-daemon/pid" 2>/dev/null)
    if [ -z "$AVAHI_PID" ] || ! kill -0 "$AVAHI_PID" 2>/dev/null; then
        rm -f "$ROOT/run/avahi-daemon/pid"
        mkdir -p "$ROOT/run/avahi-daemon"
        chroot "$ROOT" /usr/sbin/avahi-daemon --daemonize --no-chroot \
            --no-drop-root --file=/etc/avahi/avahi-daemon.conf
    fi
}

start_wsdd() {
    [ "$(cat /data/local/rk3399-control/enabled/samba 2>/dev/null)" != 0 ] || return 0
    [ "$(cat /data/local/rk3399-control/enabled/mdns 2>/dev/null)" != 0 ] || return 0
    WSDD_PID=$(cat "$ROOT/run/wsdd.pid" 2>/dev/null)
    if [ -n "$WSDD_PID" ] && kill -0 "$WSDD_PID" 2>/dev/null && \
        tr '\000' ' ' < "/proc/$WSDD_PID/cmdline" | grep -q '/usr/bin/wsdd'; then
        return
    fi
    # Listen on available interfaces, including br-lan and hot-plugged USB NICs.
    chroot "$ROOT" /usr/bin/python3 /usr/bin/wsdd -4 \
        -n a.local -p -w WORKGROUP >"$ROOT/var/log/wsdd.log" 2>&1 &
    echo $! > "$ROOT/run/wsdd.pid"
}

start_ssh() {
    SSHD_PID=$(cat "$ROOT/run/nas-sshd.pid" 2>/dev/null)
    if [ -n "$SSHD_PID" ] && kill -0 "$SSHD_PID" 2>/dev/null && \
        tr '\000' ' ' < "/proc/$SSHD_PID/cmdline" | grep -q 'sshd'; then
        return
    fi
    # Android /data remains nosuid; enable suid only on the root-owned sudo file.
    [ "$(stat -c %u "$ROOT/usr/bin/sudo")" = 0 ] || return
    is_mounted "$ROOT/usr/bin/sudo" || \
        mount -o bind "$ROOT/usr/bin/sudo" "$ROOT/usr/bin/sudo" || return
    chroot "$ROOT" /bin/mount -o remount,bind,suid,nodev \
        /usr/bin/sudo /usr/bin/sudo || return
    mkdir -p "$ROOT/run/sshd"
    chroot "$ROOT" /usr/sbin/sshd -f /etc/ssh/nas-sshd.conf \
        -E /var/log/nas-sshd.log
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
prepare_mounts
sync_usb_shares 2>>"$ROOT/var/log/nas-usb.log"
start_samba
start_http
start_mtp_sync
start_portal
start_iperf3
start_mdns
start_wsdd
start_ssh

while true; do
    sleep 2
    prepare_mounts
    sync_usb_shares 2>>"$ROOT/var/log/nas-usb.log"
    start_samba
    start_http
    start_mtp_sync
    start_portal
    start_iperf3
    start_mdns
    start_wsdd
    start_ssh
done
