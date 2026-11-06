# LightMoss shell helpers, sourced by the scripts next to this file.

# The whole disk the root filesystem is on (mmcblk0, mmcblk1, ...). Asked of the
# kernel rather than of /proc/mounts, which only says /dev/root.
lm_root_disk() {
	_majmin="$(mountpoint -d /)" || return 1
	_part="$(readlink -f "/sys/dev/block/$_majmin")" || return 1
	basename "$(dirname "$_part")"
}

# Partition N of a disk: lm_part mmcblk1 3 -> /dev/mmcblk1p3
lm_part() {
	case "$1" in
		*[0-9]) echo "/dev/${1}p$2" ;;
		*)      echo "/dev/$1$2" ;;
	esac
}

# "SD" for a card slot, "MMC" for the eMMC.
lm_disk_type() {
	cat "/sys/block/$1/device/type" 2>/dev/null
}

lm_say() {
	printf '\033[2J\033[H\n\n  %s\n' "$1" > /dev/tty1 2>/dev/null
}
