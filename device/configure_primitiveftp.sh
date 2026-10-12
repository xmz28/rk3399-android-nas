#!/system/bin/sh
set -e

STAGE=/data/local/tmp/rk3399-deploy
PKG=org.primftpd
DATA=/data/data/$PKG
PREFS=$DATA/shared_prefs

[ "$(id -u)" = 0 ] || exit 20
[ -d "$DATA" ] || { echo "ERROR: Primitive FTPd has not initialized"; exit 21; }
UID=$(stat -c %u "$DATA")
GID=$(stat -c %g "$DATA")
mkdir -p "$PREFS"
cp "$STAGE/primitiveftp_prefs.xml" "$PREFS/org.primftpd_preferences.xml"
chown "$UID:$GID" "$PREFS" "$PREFS/org.primftpd_preferences.xml"
chmod 0700 "$PREFS"
chmod 0600 "$PREFS/org.primftpd_preferences.xml"
echo "Primitive FTPd base preferences installed"
