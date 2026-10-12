#!/system/bin/sh

ROOT=/data/local/alpine-nas
ETH=eth0
ROLE_FILE=/data/local/tmp/ethernet_role
LAN_ADDR=192.168.1.1
LAN_CIDR=192.168.1.0/24

set_role() {
    echo "$1" > "$ROLE_FILE"
    setprop persist.rk3399.eth_role "$1"
}

stop_lan_dhcp() {
    PID_FILE="$ROOT/run/dnsmasq-eth0.pid"
    if [ -s "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
    fi
}

start_lan_dhcp() {
    stop_lan_dhcp
    mkdir -p "$ROOT/run" "$ROOT/var/lib/misc"
    chroot "$ROOT" /usr/sbin/dnsmasq --conf-file=/etc/dnsmasq-eth0.conf
}

clear_lan() {
    stop_lan_dhcp
    ip addr del "$LAN_ADDR/24" dev "$ETH" 2>/dev/null
    ip route del "$LAN_CIDR" dev "$ETH" table 97 2>/dev/null
    ip route del "$LAN_CIDR" dev "$ETH" table 1002 2>/dev/null
    ip route flush cache
}

configure_lan() {
    ip addr flush dev "$ETH" scope global
    ip addr add "$LAN_ADDR/24" dev "$ETH"
    ip link set "$ETH" up
    ip route replace "$LAN_CIDR" dev "$ETH" src "$LAN_ADDR" table 97
    ip route replace "$LAN_CIDR" dev "$ETH" src "$LAN_ADDR" table 1002
    ip route flush cache
    start_lan_dhcp
    set_role lan
}

has_upstream_address() {
    ip -4 addr show dev "$ETH" scope global 2>/dev/null | grep -v " $LAN_ADDR/" | grep -q ' inet '
}

ROLE=unknown
while true; do
    CARRIER=$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null)
    if [ "$CARRIER" != "1" ]; then
        [ "$ROLE" = down ] || { clear_lan; set_role down; ROLE=down; }
        sleep 2
        continue
    fi
    if has_upstream_address; then
        [ "$ROLE" = wan ] || { stop_lan_dhcp; set_role wan; ROLE=wan; }
        sleep 3
        continue
    fi
    if [ "$ROLE" = lan ] && ip -4 addr show dev "$ETH" | grep -q "$LAN_ADDR/24"; then
        [ -s "$ROOT/run/dnsmasq-eth0.pid" ] || start_lan_dhcp
        sleep 3
        continue
    fi
    set_role probing
    ROLE=probing
    WAIT=0
    while [ "$WAIT" -lt 15 ]; do
        [ "$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null)" = 1 ] || break
        has_upstream_address && break
        sleep 1
        WAIT=$((WAIT + 1))
    done
    if has_upstream_address; then
        set_role wan; ROLE=wan
    elif [ "$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null)" = 1 ]; then
        configure_lan; ROLE=lan
    else
        ROLE=unknown
    fi
done
