#!/system/bin/sh
# Run as root on Android, from the openabl folder copied to Android's internal
# storage (/sdcard/openabl), after backup_abl.sh: writes OpenABL to the
# bootloader partitions of both slots.
#
# A bootloader that does not start can only be fixed through Qualcomm's EDL
# mode, so nothing is written unless this copy of OpenABL is intact (its
# SHA-256 against abl_signed-SM8250.elf.sha256), and each slot is read back
# after it is written: if slot a does not read back right, it gets its saved
# copy back and slot b is not touched.
cd "$(dirname "$0")" || exit 1
ELF=abl_signed-SM8250.elf
[ -f abl_a.img ] && [ -f abl_b.img ] || { echo "Run backup_abl.sh first."; exit 1; }
[ -s abl_a.img ] && [ -s abl_b.img ] || { echo "abl_a.img or abl_b.img is empty: run backup_abl.sh again."; exit 1; }
if [ ! -f "$ELF.sha256" ] || ! sha256sum -c "$ELF.sha256"; then
	echo "$ELF does not match $ELF.sha256: this copy is damaged"
	echo "(or the two files are from different OpenABL versions). Copy the"
	echo "openabl folder from the card again. Nothing was written."
	exit 1
fi
want="$(cut -d' ' -f1 "$ELF.sha256")"
size=$(( $(wc -c < "$ELF") ))

# The first SIZE bytes of a partition, as the flash has them.
readback() {
	sync
	echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
	head -c "$size" "$1" | sha256sum | cut -d' ' -f1
}

# flash SLOT: write OpenABL to abl_SLOT and check it, twice at most; else put
# the saved copy back.
flash() {
	p="/dev/block/by-name/abl_$1"
	for try in 1 2; do
		if dd if="$ELF" of="$p" bs=1M && [ "$(readback "$p")" = "$want" ]; then
			echo "abl_$1: written and checked."
			return 0
		fi
		echo "abl_$1 does not read back as written (try $try)."
	done
	echo "Putting the saved abl_$1.img back..."
	dd if="abl_$1.img" of="$p" bs=1M
	sync
	return 1
}

if ! flash a; then
	echo "OpenABL could not be written; abl_b was not touched. Restart as usual"
	echo "(should it not start, run restore_abl.sh)."
	exit 1
fi
if ! flash b; then
	echo "abl_a has OpenABL; abl_b could not be written and has its saved copy"
	echo "back. restore_abl.sh puts the original back on both."
	exit 1
fi
sync
echo "OpenABL is installed. Restart holding Volume Down to open its menu."
