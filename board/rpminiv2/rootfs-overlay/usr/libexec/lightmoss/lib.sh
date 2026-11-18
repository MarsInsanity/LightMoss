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

# The GPT name of a partition (kernel name: sda34, mmcblk0p1). The kernel
# knows it when it read the table itself; a partition added by partx (BLKPG)
# has none there, so the table on the disk is asked then.
lm_part_name() {
	_n="$(sed -n 's/^PARTNAME=//p' "/sys/class/block/$1/uevent" 2>/dev/null)"
	[ -n "$_n" ] || _n="$(blkid -p -o value -s PART_ENTRY_NAME "/dev/$1" 2>/dev/null)"
	echo "$_n"
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

# The card slot's disk (mmcblk0), without an eMMC's boot and RPMB areas.
lm_card_disks() {
	for _d in /sys/block/mmcblk*; do
		[ -e "$_d" ] || continue
		case "${_d##*/}" in *boot*|*rpmb*) continue ;; esac
		echo "${_d##*/}"
	done
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

# A charger is connected, or the battery has at least $1 percent (30 when not
# given) left. A device that reports no battery level is let through.
lm_power_ok() {
	lm_charger_online && return 0
	for _c in /sys/class/power_supply/*/capacity; do
		[ -e "$_c" ] || continue
		[ "$(cat "${_c%/capacity}/type" 2>/dev/null)" = Battery ] || continue
		_l="$(cat "$_c" 2>/dev/null)"
		case "$_l" in ''|*[!0-9]*) continue ;; esac
		[ "$_l" -ge "${1:-30}" ]
		return
	done
	return 0
}

# The FAT on a partition as the firmware's FAT driver (edk2's EnhancedFatDxe,
# which OpenABL boots through) judges it, from the boot sector: prints
# "FAT32 130784" (the type and the number of data clusters) and succeeds when
# that driver mounts it. It refuses a FAT32 with fewer than 65525 clusters,
# which Linux mounts without a word (256 MiB on 4 KiB sectors has 65376), and
# a FAT12/16 with that many or more.
lm_fat_info() {
	# Bytes 11-39: the BIOS parameter block up to FAT32's sectors per FAT.
	# shellcheck disable=SC2046 # one argument per byte
	set -- $(od -A n -t u1 -j 11 -N 29 "$1" 2>/dev/null)
	[ $# -eq 29 ] || return 1
	_bps=$(( $1 + $2 * 256 )); _spc=$3; _rsvd=$(( $4 + $5 * 256 )); _nfats=$6
	_root=$(( $7 + $8 * 256 )); _secs=$(( $9 + ${10} * 256 ))
	_fatsz=$(( ${12} + ${13} * 256 ))
	[ "$_secs" != 0 ] || _secs=$(( ${22} + ${23} * 256 + ${24} * 65536 + ${25} * 16777216 ))
	_type=FAT16
	if [ "$_fatsz" = 0 ]; then
		_type=FAT32
		_fatsz=$(( ${26} + ${27} * 256 + ${28} * 65536 + ${29} * 16777216 ))
	fi
	case "$_bps" in 512|1024|2048|4096) ;; *) return 1 ;; esac
	case "$_spc" in 1|2|4|8|16|32|64|128) ;; *) return 1 ;; esac
	[ "$_rsvd" -gt 0 ] && [ "$_nfats" -gt 0 ] && [ "$_secs" -gt 0 ] && [ "$_fatsz" -gt 0 ] || return 1
	_data=$(( _rsvd + _nfats * _fatsz + (_root * 32 + _bps - 1) / _bps ))
	[ "$_secs" -gt "$_data" ] || return 1
	_clusters=$(( (_secs - _data) / _spc ))
	if [ "$_type" = FAT32 ]; then
		[ "$_clusters" -ge 65525 ] || { echo "FAT32 $_clusters"; return 1; }
		# The FAT has an entry for each cluster.
		[ $(( _fatsz * _bps / 4 )) -ge $(( _clusters + 2 )) ] || return 1
	else
		if [ "$_root" = 0 ] || [ "$_clusters" -ge 65525 ]; then
			echo "$_type $_clusters"
			return 1
		fi
		[ "$_clusters" -ge 4085 ] || _type=FAT12
	fi
	echo "$_type $_clusters"
}

# The filesystem on a partition was not cleanly unmounted (power cut, crash):
# the dirty flag Linux sets while a FAT or exFAT volume is mounted (FAT) or
# being written (exFAT, kept until a check clears it). lm_fs_dirty DEV TYPE
# shellcheck disable=SC2046 # od's bytes, one argument each
lm_fs_dirty() {
	case "$2" in
		vfat)
			# The state byte: offset 65 on FAT32 (no FAT16 sectors-per-FAT), 37 before.
			set -- "$1" $(od -A n -t u1 -j 22 -N 2 "$1" 2>/dev/null)
			[ $# -eq 3 ] || return 1
			if [ $(( $2 + $3 )) = 0 ]; then _at=65; else _at=37; fi
			set -- $(od -A n -t u1 -j "$_at" -N 1 "$1" 2>/dev/null)
			[ $# -eq 1 ] && [ $(( $1 & 1 )) = 1 ]
			;;
		exfat)
			# VolumeFlags, bit 1: VolumeDirty.
			set -- $(od -A n -t u1 -j 106 -N 1 "$1" 2>/dev/null)
			[ $# -eq 1 ] && [ $(( $1 & 2 )) = 2 ]
			;;
		*) return 1 ;;
	esac
}

# A message on the screen (tty1). Never fails: the screen is a nicety.
lm_say() {
	printf '\033[2J\033[H\n\n  %b\n' "$1" > /dev/tty1 2>/dev/null || :
}
