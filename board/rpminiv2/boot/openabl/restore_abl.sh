#!/system/bin/sh
# Run as root on Android, from the folder holding the abl_a.img and abl_b.img
# that backup_abl.sh saved: puts the original bootloader back on both slots.
cd "$(dirname "$0")" || exit 1
[ -f abl_a.img ] && [ -f abl_b.img ] || { echo "No abl_a.img/abl_b.img here."; exit 1; }
dd if=abl_a.img of=/dev/block/by-name/abl_a bs=1M || exit 1
dd if=abl_b.img of=/dev/block/by-name/abl_b bs=1M || exit 1
sync
echo "The original bootloader is back."
