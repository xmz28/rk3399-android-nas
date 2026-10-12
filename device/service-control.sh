#!/system/bin/sh
ROOT=/data/local/alpine-nas
BASE=/data/local/rk3399-nas

stop_nas() {
    stop nas_services 2>/dev/null || true
    # Stop only known NAS watcher commands, including the Magisk copy.
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        cmd=$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null)
        case "$cmd" in
            *'/system/bin/nas_services.sh'*|*'/data/local/rk3399-nas/scripts/nas_services.sh'*)
                kill "${proc#/proc/}" 2>/dev/null || true ;;
            *copyparty-sfx.py*)
                # Older packages did not record a Copyparty PID.
                [ "$(readlink "$proc/root" 2>/dev/null)" != "$ROOT" ] || kill "${proc#/proc/}" 2>/dev/null || true ;;
        esac
    done
    for name in copyparty nas-portal-nginx nas-speedtest-relay iperf3 avahi-daemon/pid; do
        file="$ROOT/run/$name.pid"
        [ "$name" != avahi-daemon/pid ] || file="$ROOT/run/avahi-daemon/pid"
        pid=$(cat "$file" 2>/dev/null || true)
        case "$pid" in ''|*[!0-9]*|0|1) continue ;; esac
        command=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
        case "$name:$command" in
            copyparty:*copyparty-sfx.py*|nas-portal-nginx:*nginx*|nas-speedtest-relay:*nas-speedtest-relay.py*|iperf3:*iperf3*|avahi-daemon/pid:*avahi-daemon*) ;;
            *) continue ;;
        esac
        kill "$pid" 2>/dev/null || true
        rm -f "$file"
    done
    for pid in $(pidof smbd 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
    sleep 2
}

start_nas() {
    if [ "$(cat "$BASE/boot-mode" 2>/dev/null)" = magisk ]; then
        nohup /system/bin/sh "$BASE/scripts/nas_services.sh" </dev/null >"$ROOT/var/log/nas-service.log" 2>&1 &
    else
        start nas_services
    fi
}
