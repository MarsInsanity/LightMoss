# LightMoss shell helpers (Retroid Pocket Mini V2), sourced by the scripts
# next to this file and by lightmoss-install-internal and lightmoss-update.
#
# Disks: the internal UFS shows up as SCSI disks (sda, sdb, ... one per LUN;
# Android's userdata is on one of them), the card slot as mmcblk0.
# LightMoss's own partitions are found by their GPT names: LMBOOT (FAT32: the
# boot entries, kernels and flags), LMSYS1 and LMSYS2 (the two system copies)
# on the internal UFS, after Android's userdata; LMBOOT and LMSYS on a card.

# The whole disk the root filesystem is on (sda, mmcblk0). Asked of the kernel
# rather than of /proc/mounts, which only says /dev/root.
lm_root_disk() {
	_majmin="$(mountpoint -d /)" || return 1
	_part="$(readlink -f "/sys/dev/block/$_majmin")" || return 1
	basename "$(dirname "$_part")"
}

# Partition N of a disk: lm_part mmcblk0 3 -> /dev/mmcblk0p3, lm_part sda 34 -> /dev/sda34
lm_part() {
	case "$1" in
		*[0-9]) echo "/dev/${1}p$2" ;;
		*)      echo "/dev/$1$2" ;;
	esac
}

# The GPT name of a partition (kernel name: sda34, mmcblk0p1).
lm_part_name() {
	sed -n 's/^PARTNAME=//p' "/sys/class/block/$1/uevent" 2>/dev/null
}

# The partition of a disk with a given GPT name: lm_part_named sda LMBOOT -> /dev/sda35
lm_part_named() {
	for _p in /sys/block/"$1"/"$1"*; do
		[ -e "$_p/partition" ] || continue
		if [ "$(lm_part_name "${_p##*/}")" = "$2" ]; then
			echo "/dev/${_p##*/}"
			return 0
		fi
	done
	return 1
}

# "SD" for the card slot, "UFS" for the internal storage.
lm_disk_type() {
	case "$1" in
		mmcblk*) echo SD ;;
		sd*)     echo UFS ;;
	esac
}

# The internal disk: the UFS LUN that holds Android's userdata.
lm_internal_disk() {
	for _d in /sys/block/sd*; do
		[ -e "$_d" ] || continue
		lm_part_named "${_d##*/}" userdata >/dev/null && { echo "${_d##*/}"; return 0; }
	done
	return 1
}

# Which system copy this is: 1 or 2 on the internal storage, "sd" on a card.
lm_slot() {
	sed -n 's/.*lightmoss\.slot=\([^ ]*\).*/\1/p' /proc/cmdline
}

# A charger or a powered USB port is connected.
lm_charger_online() {
	for _f in /sys/class/power_supply/*/online; do
		[ -e "$_f" ] || continue
		case "$(cat "${_f%/online}/type" 2>/dev/null)" in
			Battery) continue ;;
		esac
		[ "$(cat "$_f" 2>/dev/null)" = 1 ] && return 0
	done
	return 1
}

lm_say() {
	printf '\033[2J\033[H\n\n  %b\n' "$1" > /dev/tty1 2>/dev/null
}
