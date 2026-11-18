#!/system/bin/sh
# Run as root on Android, from the openabl folder copied to Android's internal
# storage (/sdcard/openabl): saves the current bootloader of both slots next
# to this script, abl_a.img and abl_b.img, for restore_abl.sh.
#
# Android's internal storage is erased when LightMoss is installed on the
# internal storage, this folder with it: copy the two files off the device.
cd "$(dirname "$0")" || exit 1
dd if=/dev/block/by-name/abl_a of=abl_a.img bs=1M || exit 1
dd if=/dev/block/by-name/abl_b of=abl_b.img bs=1M || exit 1
sync
[ -s abl_a.img ] && [ -s abl_b.img ] || { echo "The saved copies are empty: not usable."; exit 1; }
echo "Saved abl_a.img and abl_b.img in $(pwd)."
echo
echo "COPY THEM TO A PC (or the card) NOW: installing LightMoss on the internal"
echo "storage erases Android's internal storage, this folder included, and"
echo "restore_abl.sh needs them to put the original bootloader back."
