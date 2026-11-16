#!/system/bin/sh
# Run as root on Android, from the openabl folder copied to Android's internal
# storage (/sdcard/openabl), after backup_abl.sh: writes OpenABL to the
# bootloader partitions of both slots.
cd "$(dirname "$0")" || exit 1
[ -f abl_a.img ] && [ -f abl_b.img ] || { echo "Run backup_abl.sh first."; exit 1; }
dd if=abl_signed-SM8250.elf of=/dev/block/by-name/abl_a bs=1M || exit 1
dd if=abl_signed-SM8250.elf of=/dev/block/by-name/abl_b bs=1M || exit 1
sync
echo "OpenABL is installed. Restart holding Volume Down to open its menu."
