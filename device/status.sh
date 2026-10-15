#!/system/bin/sh
ROOT=/data/local/alpine-nas
echo "MODEL=$(getprop ro.product.model)"
echo "ANDROID=$(getprop ro.build.version.release) ABI=$(getprop ro.product.cpu.abi)"
echo "BOOT_MODE=$(cat /data/local/rk3399-nas/boot-mode 2>/dev/null)"
echo "ETH_ROLE=$(cat /data/local/tmp/ethernet_role 2>/dev/null)"
echo "ETH_IP=$(ip -4 addr show dev eth0 2>/dev/null | grep ' inet ')"
echo 'PORTS:'
netstat -lnt 2>/dev/null | grep -E ':(22|80|445|3923|12345|1234|3000|5201|8765) ' || true
echo 'USB_VIEWS:'
cat "$ROOT/run/nas-disks.json" 2>/dev/null || true
echo 'CONTROL_APP:'
pm path com.example.rk3399_control 2>/dev/null || true
if [ "${1:-}" = --health ]; then
    failed=0
    config_port() {
        value=$(chroot "$ROOT" /usr/bin/awk -F: -v option="$1" '$1 ~ "^[[:space:]]*" option "$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/copyparty-base.conf 2>/dev/null)
        case "$value" in ''|*[!0-9]*) echo "$2" ;; *) echo "$value" ;; esac
    }
    iperf_port=$(cat /data/local/rk3399-control/config/iperf_port 2>/dev/null)
    case "$iperf_port" in ''|*[!0-9]*) iperf_port=5201 ;; esac
    for port in 22 80 445 "$(config_port p 3923)" "$(config_port ftp 12345)" "$(config_port sftp 1234)" "$iperf_port"; do
        if ! netstat -lnt 2>/dev/null | grep -q ":$port "; then
            echo "ERROR: expected port $port is not listening"
            failed=1
        fi
    done
    [ "$failed" = 0 ] || exit 1
    echo 'HEALTH=PASS (listening ports only; OpenSpeedTest and controller checked separately)'
fi
