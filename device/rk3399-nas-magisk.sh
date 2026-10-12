#!/system/bin/sh

BASE=/data/local/rk3399-nas/scripts
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
"$BASE/nas_services.sh" >/dev/null 2>&1 &
"$BASE/ethernet_role.sh" >/dev/null 2>&1 &
"$BASE/openspeedtest_guard.sh" >/dev/null 2>&1 &
