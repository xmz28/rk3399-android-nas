#!/system/bin/sh
# Sourced by nas_services.sh. Android vold owns mounting and filesystem checks.
USB_BASE="$ROOT/mnt/usb"
USB_STATE="$ROOT/run/nas-usb"
USB_CONF="$ROOT/etc/samba/usb-shares.conf"
USB_EJECTED="$ROOT/run/nas-usb-ejected"

usb_share_name() {
    chroot "$ROOT" /usr/bin/python3 /opt/nas-volumes.py --name "$1"
}

usb_source_id() {
    boot=$(cat /proc/sys/kernel/random/boot_id)
    chroot "$ROOT" /usr/bin/awk -v boot="$boot" -v p="/mnt/media_rw/$1" '$5 == p { print boot ":" $1; exit }' /proc/1/mountinfo
}

usb_drop() {
    chroot "$ROOT" /usr/bin/smbcontrol smbd close-share "$(usb_share_name "$1")" >/dev/null 2>&1
    while is_mounted "$USB_BASE/$1"; do
        umount "$USB_BASE/$1" || umount -l "$USB_BASE/$1" || return 1
    done
    rmdir "$USB_BASE/$1" 2>/dev/null
    rm -f "$USB_STATE/$1"
}

sync_usb_shares() {
    mkdir -p "$USB_BASE" "$USB_STATE" "$USB_EJECTED"
    # Mount IDs detect replacement even if UUID and block-device number repeat.
    for state in "$USB_STATE"/*; do
        [ -f "$state" ] || continue
        uuid=${state##*/}
        current=$(usb_source_id "$uuid")
        if [ -n "$current" ] && [ "$(cat "$state")" = "$current" ] && \
            [ "$(cat "$USB_EJECTED/$uuid" 2>/dev/null)" != "$current" ] && \
            is_mounted "$USB_BASE/$uuid"; then
            mode=rw
            [ -f "$ROOT/etc/samba/usb-readonly-$uuid" ] && mode=ro
            chroot "$ROOT" /usr/bin/python3 /opt/nas-mount-private.py "/mnt/usb/$uuid" "$mode" || continue
            continue
        fi
        usb_drop "$uuid" || continue
    done
    for src in /mnt/media_rw/*; do
        [ -f "$ROOT/run/nas-storage-formatting" ] && continue
        [ -d "$src" ] || continue
        uuid=${src##*/}
        case "$uuid" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
        current=$(usb_source_id "$uuid")
        [ -n "$current" ] || continue
        [ "$(cat "$USB_EJECTED/$uuid" 2>/dev/null)" = "$current" ] && continue
        rm -f "$USB_EJECTED/$uuid"
        [ -f "$USB_STATE/$uuid" ] && continue
        mkdir -p "$USB_BASE/$uuid"
        # Detach an orphaned bind left by an interrupted service first.
        if is_mounted "$USB_BASE/$uuid"; then
            usb_drop "$uuid" || continue
            mkdir -p "$USB_BASE/$uuid"
        fi
        mount --bind "$src" "$USB_BASE/$uuid" || continue
        mode=rw
        [ -f "$ROOT/etc/samba/usb-readonly-$uuid" ] && mode=ro
        chroot "$ROOT" /usr/bin/python3 /opt/nas-mount-private.py "/mnt/usb/$uuid" "$mode" || { usb_drop "$uuid"; continue; }
        echo "$current" > "$USB_STATE/$uuid"
    done
    chroot "$ROOT" /usr/bin/python3 /opt/nas-volumes.py
}
