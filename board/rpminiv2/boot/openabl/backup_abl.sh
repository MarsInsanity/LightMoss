#!/system/bin/sh
# Run as root on Android, from the openabl folder copied to Android's internal
# storage (/sdcard/openabl): saves the current bootloader of both slots next
# to this script, abl_a.img and abl_b.img. Keep them off the device too.
cd "$(dirname "$0")" || exit 1
dd if=/dev/block/by-name/abl_a of=abl_a.img bs=1M || exit 1
dd if=/dev/block/by-name/abl_b of=abl_b.img bs=1M || exit 1
sync
echo "Saved abl_a.img and abl_b.img in $(pwd)"
