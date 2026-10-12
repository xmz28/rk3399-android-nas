#!/system/bin/sh

echo "MODEL=$(getprop ro.product.model)"
echo "ANDROID=$(getprop ro.build.version.release) API=$(getprop ro.build.version.sdk) ABI=$(getprop ro.product.cpu.abi)"
BOOT_MODE=$(cat /data/local/rk3399-nas/boot-mode 2>/dev/null)
if [ -z "$BOOT_MODE" ] && [ -f /system/etc/init/nas-services.rc ]; then BOOT_MODE=system-init; fi
echo "BOOT_MODE=$BOOT_MODE"
echo "ETH_ROLE=$(cat /data/local/tmp/ethernet_role 2>/dev/null)"
echo "ETH_IP=$(ip -4 addr show dev eth0 2>/dev/null | grep ' inet ' | sed 's/^[[:space:]]*//')"
echo "PACKAGES:"
pm path org.primftpd 2>/dev/null || true
pm path com.openspeedtest.server 2>/dev/null || true
echo "PORTS:"
netstat -lnt 2>/dev/null | grep -E ':(445|3923|12345|1234|3000) ' || true
echo "PROCESSES:"
ps -A 2>/dev/null | grep -E 'smbd|copyparty|dnsmasq|primftpd|openspeedtest' || true
