#!/system/bin/sh

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 10

tap_start() {
    SIZE=$(wm size 2>/dev/null | tail -n 1 | sed 's/.*: //')
    W=${SIZE%x*}
    H=${SIZE#*x}
    case "$W:$H" in
        *[!0-9:]*|:*) W=1920; H=1080 ;;
    esac
    input tap $((W / 2)) $((H * 66 / 100))
}

while true; do
    if ! netstat -lnt 2>/dev/null | grep -q ':3000 '; then
        am start --user 0 -n com.openspeedtest.server/.MainActivity >/dev/null 2>&1
        sleep 5
        tap_start
        sleep 10
    fi
    sleep 60
done
