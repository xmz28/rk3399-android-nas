#!/bin/sh
# Run inside a NEW Alpine aarch64 minirootfs, never inside an existing device NAS.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
[ ! -e /etc/copyparty-base.conf ] && [ ! -e /etc/nas-clean-image ] || exit 1
apk add --no-cache ca-certificates samba-server samba-common-tools nginx avahi iperf3 \
    py3-paramiko openssh-keygen dnsmasq curl
mkdir -p /opt /etc/samba /usr/share/rk3399-nas
[ -s /tmp/copyparty-sfx.py ] || { echo 'Place verified Copyparty SFX in /tmp first'; exit 1; }
echo 'fed92d38ae9efe99b453a9d48020ba860758cc7b3207a8909e9495ffb600cd1f  /tmp/copyparty-sfx.py' | sha256sum -c -
cp /tmp/copyparty-sfx.py /opt/copyparty-sfx.py
apk info -vv > /usr/share/rk3399-nas/packages.txt
cp /lib/apk/db/installed /usr/share/rk3399-nas/apk-installed.txt
printf 'Alpine 3.22 aarch64, Copyparty 1.20.25, no device credentials\n' > /etc/nas-clean-image
rm -f /tmp/copyparty-sfx.py
echo 'Build complete. Unmount proc/sys/dev before archiving. Never export a live NAS.'
