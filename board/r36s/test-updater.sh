#!/bin/sh
# Tests the LightMoss updater (board/r36s/initramfs/init) on a build host,
# against disk images instead of a device: a LightMoss card ("tf1", with a
# SPRUCEOS partition behind the system, as first boot makes it) and an "emmc".
# It sources the init with LM_UPDATER_TEST=1 and replaces its device helpers:
# the disks are files, FAT "mounts" are played by mtools (the build host's
# kernel may have no FAT driver), ext4 mounts are real loop mounts. Runs as
# root, in a private mount namespace, so the updater's /mnt and /tmp are its
# own.
#
#   board/r36s/test-updater.sh [OUTPUT_DIR]     (after a build; default: output)
#
# Scenarios: a fresh eMMC install over another system; an eMMC update that
# keeps SPRUCEOS and the device's settings; an in-place update of the card the
# system runs from, its image on that card's own SPRUCEOS; an image on the
# partition about to be overwritten (refused); no charger (nothing written,
# still waiting); a damaged image (set aside).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
O="$(cd "${1:-output}" && pwd)"
if [ -z "${LM_TEST_NS:-}" ]; then
	exec env LM_TEST_NS=1 unshare -m sh "$HERE/$(basename "$0")" "$O"
fi
mount -t tmpfs tmpfs /mnt
mount -t tmpfs tmpfs /tmp
export PATH="$O/host/bin:$O/host/sbin:$PATH"

W="$O/test-updater"
RAW="$O/images/lightmoss-r36s.img"
XZ="$(ls "$O"/images/lightmoss-r36s-*.img.xz | head -n 1)"
rm -rf "${W:?}"
mkdir -p "$W"
FAILS=0

ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# MBR entry N (1-4) of a disk file: type, start, size (sectors).
mbr_type()  { od -An -tu1 -j $((446 + ($2 - 1) * 16 + 4)) -N 1 "$1" | tr -d ' '; }
mbr_start() { od -An -tu4 -j $((446 + ($2 - 1) * 16 + 8)) -N 4 "$1" | tr -d ' '; }
mbr_size()  { od -An -tu4 -j $((446 + ($2 - 1) * 16 + 12)) -N 4 "$1" | tr -d ' '; }
sig()       { od -An -tx4 -j 440 -N 4 "$W/$1.disk" | tr -d ' \n'; }
off()       { echo $(($(mbr_start "$W/$1.disk" "$2") * 512)); }
# A partition's bytes, for comparing (disk, partition).
psum() { dd if="$W/$1.disk" bs=512 skip="$(mbr_start "$W/$1.disk" "$2")" count="$(mbr_size "$W/$1.disk" "$2")" 2>/dev/null | md5sum | cut -c1-32; }
dsum() { md5sum < "$W/$1.disk" | cut -c1-32; }
# Files on a FAT partition, from outside (disk, partition, path).
fat_has() { mdir -b -i "$W/$1.disk@@$(off "$1" "$2")" "::/$3" >/dev/null 2>&1; }
fat_cat() { mtype -i "$W/$1.disk@@$(off "$1" "$2")" "::/$3" 2>/dev/null; }
fat_put() { mcopy -o -i "$W/$1.disk@@$(off "$1" "$2")" "$3" "::/$4"; }
fat_ren() { mren -i "$W/$1.disk@@$(off "$1" "$2")" "::/$3" "::/$4"; }
fat_del() { mdel -i "$W/$1.disk@@$(off "$1" "$2")" "::/$3" 2>/dev/null; }
# A file on an ext4 partition, read or written through a real loop mount.
ext_do() { # disk part cmd...
	_d="$1"; _p="$2"; shift 2
	mkdir -p "$W/x"
	command mount -t ext4 -o "loop,offset=$(off "$_d" "$_p"),sizelimit=$(($(mbr_size "$W/$_d.disk" "$_p") * 512))" "$W/$_d.disk" "$W/x" || return 1
	( cd "$W/x" && eval "$*" ); _r=$?
	command umount "$W/x"
	return $_r
}

# --- disks ----------------------------------------------------------------------
echo "Setting up the disks from $(basename "$RAW")..."
# tf1: the image, with a FAT SPRUCEOS behind the system (exFAT on a device).
cp --sparse=always "$RAW" "$W/tf1.disk"
truncate -s +128M "$W/tf1.disk"
P2END=$(($(mbr_start "$W/tf1.disk" 2) + $(mbr_size "$W/tf1.disk" 2)))
S3=$(((P2END + 2047) / 2048 * 2048))
echo "$S3,,c" | sfdisk --append --no-reread --no-tell-kernel -q "$W/tf1.disk" >/dev/null
mkfs.vfat -F 16 -n SPRUCEOS --offset "$S3" "$W/tf1.disk" $(($(mbr_size "$W/tf1.disk" 3) / 2)) >/dev/null
ext_do tf1 2 'echo tf1-machine-id > etc/machine-id'
# emmc: another system (EmuELEC's layout, more or less).
truncate -s 1600M "$W/emmc.disk"
printf '2048,1048576,c\n1050624,,83\n' | sfdisk -q "$W/emmc.disk" >/dev/null
mkfs.vfat -F 32 -n EMUELEC --offset 2048 "$W/emmc.disk" 524288 >/dev/null
[ "$(sig tf1)" = 4c4d3336 ] || { echo "tf1 is not a LightMoss image"; exit 1; }

# --- the updater, its device helpers replaced ------------------------------------
LM_UPDATER_TEST=1
. "$HERE/initramfs/init"
TTY=/dev/null
dev()      { echo "$W/$1.disk"; }
disks()    { echo tf1; echo emmc; }
disktype() { case "$1" in emmc) echo MMC ;; *) echo SD ;; esac; }
part()     { echo "$W/$1.disk:p$2"; }
parts()    { for n in 1 2 3 4; do [ "$(mbr_type "$W/$1.disk" $n)" != 0 ] && echo "$W/$1.disk:p$n"; done; }
pstart()   { mbr_start "${2%:p*}" "${2##*:p}"; }
psize()    { mbr_size "${2%:p*}" "${2##*:p}"; }
label()    { blkid -p -O $(($(mbr_start "${1%:p*}" "${1##*:p}") * 512)) -s LABEL -o value "${1%:p*}" 2>/dev/null; }
charger_online() { [ "$CHARGER" = 1 ]; }
sleep()    { :; }
blockdev() { :; }
reboot()   { echo "    (reboot $*)"; }
fail()     { say "$*"; echo "    (fail: stays)"; exit 2; }

mount() {
	_t=""; _o=rw
	while [ $# -gt 2 ]; do
		case "$1" in -t) _t="$2"; shift 2 ;; -o) _o="$2"; shift 2 ;; *) shift ;; esac
	done
	_f="${1%:p*}"; _n="${1##*:p}"; _dir="$2"
	[ "$(mbr_type "$_f" "$_n")" != 0 ] || return 1
	_off=$(($(mbr_start "$_f" "$_n") * 512))
	_real="$(blkid -p -O "$_off" -s TYPE -o value "$_f" 2>/dev/null)"
	[ -z "$_t" ] || [ "$_t" = "$_real" ] || return 1
	case "$_real" in
	vfat)
		mkdir -p "$_dir"
		find "$_dir" -mindepth 1 -delete
		mcopy -s -p -n -Q -i "$_f@@$_off" '::*' "$_dir/" >/dev/null 2>&1
		echo "$_dir|$_f|$_off|$_o" >> "$W/mounts" ;;
	ext4)
		command mount -t ext4 -o "loop,offset=$_off,sizelimit=$(($(mbr_size "$_f" "$_n") * 512)),$_o" "$_f" "$_dir" ;;
	*) return 1 ;;
	esac
}
umount() {
	_e="$(grep "^$1|" "$W/mounts" 2>/dev/null | tail -n 1)"
	[ -n "$_e" ] || { command umount "$1"; return; }
	_f="$(echo "$_e" | cut -d'|' -f2)"; _off="$(echo "$_e" | cut -d'|' -f3)"
	if [ "$(echo "$_e" | cut -d'|' -f4)" = rw ]; then
		# The directory, written back over the FAT's root.
		mdeltree -i "$_f@@$_off" '::*' >/dev/null 2>&1
		mdel -i "$_f@@$_off" '::*' >/dev/null 2>&1
		for x in "$1"/* "$1"/.[!.]*; do
			[ -e "$x" ] && mcopy -s -p -Q -i "$_f@@$_off" "$x" :: >/dev/null
		done
	fi
	grep -v "^$1|" "$W/mounts" > "$W/mounts.new"; mv "$W/mounts.new" "$W/mounts"
	find "$1" -mindepth 1 -delete
}

run() { # the system's disk, charger 0/1
	ROOTDISK="$1"; ROOTSPEC="PARTUUID=$(sig "$1")-02"; CHARGER="$2"
	: > "$LOG"; : > "$W/mounts"
	# As the init's main: update, then the source unmounted and the log saved.
	( update; umount /mnt/src 2>/dev/null; savelog ); RC=$?
	sed 's/^/    | /' "$LOG"
}

# --- 1: fresh eMMC install over another system -----------------------------------
echo "1. eMMC install over another system (image on tf1's SPRUCEOS, lightmoss-install on tf1's BOOT)"
fat_put tf1 3 "$XZ" LightMoss.rkimg
: > "$W/empty"; fat_put tf1 1 "$W/empty" lightmoss-install
TF1_P2="$(psum tf1 2)"
run tf1 1
ES="$(sig emmc)"
check "eMMC has a signature of its own ($ES)" '[ "$ES" != 4c4d3336 ] && [ "$ES" != 00000000 ]'
check "eMMC partitions are the image's" '[ "$(mbr_start "$W/emmc.disk" 2) $(mbr_size "$W/emmc.disk" 2)" = "$(mbr_start "$RAW" 2) $(mbr_size "$RAW" 2)" ]'
check "eMMC system partition is the image's" '[ "$(psum emmc 2)" = "$(dd if="$RAW" bs=512 skip="$(mbr_start "$RAW" 2)" count="$(mbr_size "$RAW" 2)" 2>/dev/null | md5sum | cut -c1-32)" ]'
check "eMMC boot loader is the image's" '[ "$(dd if="$W/emmc.disk" bs=512 skip=64 count=32704 2>/dev/null | md5sum)" = "$(dd if="$RAW" bs=512 skip=64 count=32704 2>/dev/null | md5sum)" ]'
check "eMMC boot.ini boots its own root" 'fat_cat emmc 1 boot.ini | grep -q "root=PARTUUID=$ES-02"'
check "image renamed .done, trigger cleared" 'fat_has tf1 3 LightMoss.rkimg.done && ! fat_has tf1 3 LightMoss.rkimg && ! fat_has tf1 1 lightmoss-install'
check "tf1's system untouched" '[ "$(psum tf1 2)" = "$TF1_P2" ]'
check "update log on tf1's BOOT" 'fat_cat tf1 1 lightmoss-update.log | grep -q "mode: install"'

# --- 2: eMMC update keeps SPRUCEOS and the device's settings ---------------------
echo "2. eMMC update (it now holds LightMoss, SPRUCEOS behind it)"
E3=$(((($(mbr_start "$W/emmc.disk" 2) + $(mbr_size "$W/emmc.disk" 2)) + 2047) / 2048 * 2048))
echo "$E3,,c" | sfdisk --append --no-reread --no-tell-kernel -q "$W/emmc.disk" >/dev/null
mkfs.vfat -F 16 -n SPRUCEOS --offset "$E3" "$W/emmc.disk" $(($(mbr_size "$W/emmc.disk" 3) / 2)) >/dev/null
echo keep > "$W/keep.txt"; fat_put emmc 3 "$W/keep.txt" keep.txt
fat_put emmc 1 "$W/empty" headphones-invert
fat_put emmc 1 "$W/empty" lightmoss-debug
ext_do emmc 2 'echo emmc-machine-id > etc/machine-id; mkdir -p etc/dropbear; echo key > etc/dropbear/dropbear_ed25519_host_key'
fat_ren tf1 3 LightMoss.rkimg.done LightMoss.rkimg
fat_put tf1 1 "$W/empty" lightmoss-install
run tf1 1
check "eMMC signature kept" '[ "$(sig emmc)" = "$ES" ]'
check "eMMC SPRUCEOS kept, with its files" '[ "$(mbr_start "$W/emmc.disk" 3)" = "$E3" ] && [ "$(fat_cat emmc 3 keep.txt)" = keep ]'
check "machine ID and SSH host key kept" 'ext_do emmc 2 "grep -qx emmc-machine-id etc/machine-id && grep -qx key etc/dropbear/dropbear_ed25519_host_key"'
check "headphones-invert and lightmoss-debug kept" 'fat_has emmc 1 headphones-invert && fat_has emmc 1 lightmoss-debug'
check "eMMC boot.ini boots its own root" 'fat_cat emmc 1 boot.ini | grep -q "root=PARTUUID=$ES-02"'
check "mode was update" 'fat_cat tf1 1 lightmoss-update.log | grep -q "mode: update"'

# --- 3: in-place update of the card the system runs from -------------------------
echo "3. in place: tf1 updates itself (lightmoss-update on its BOOT, image on its SPRUCEOS)"
# (Its BOOT is mounted rw to clear triggers, which the mtools stand-in
# rewrites: compare what an update would change instead.)
EMMC_MBR="$(dd if="$W/emmc.disk" bs=512 count=1 2>/dev/null | md5sum)"; EMMC_P2="$(psum emmc 2)"
fat_ren tf1 3 LightMoss.rkimg.done LightMoss.rkimg
fat_put tf1 1 "$W/empty" lightmoss-update
fat_put tf1 1 "$W/empty" lightmoss-debug
run tf1 1
check "tf1 signature kept (4c4d3336)" '[ "$(sig tf1)" = 4c4d3336 ]'
check "tf1 SPRUCEOS kept, image renamed .done" '[ "$(mbr_start "$W/tf1.disk" 3)" = "$S3" ] && fat_has tf1 3 LightMoss.rkimg.done'
check "tf1 machine ID kept" 'ext_do tf1 2 "grep -qx tf1-machine-id etc/machine-id"'
check "trigger cleared, lightmoss-debug kept" '! fat_has tf1 1 lightmoss-update && fat_has tf1 1 lightmoss-debug'
check "tf1 boot.ini boots its own root" 'fat_cat tf1 1 boot.ini | grep -q "root=PARTUUID=4c4d3336-02"'
check "the eMMC untouched (partition table, signature, system)" '[ "$(dd if="$W/emmc.disk" bs=512 count=1 2>/dev/null | md5sum)" = "$EMMC_MBR" ] && [ "$(psum emmc 2)" = "$EMMC_P2" ]'
check "target was tf1, mode update" 'fat_cat tf1 1 lightmoss-update.log | grep -q "target: tf1" && fat_cat tf1 1 lightmoss-update.log | grep -q "mode: update"'

# --- 4: an image on the partition about to be overwritten ------------------------
echo "4. in place, the only image on tf1's own BOOT: refused"
fat_del tf1 3 LightMoss.rkimg.done
head -c 510 /dev/zero > "$W/fake"; printf '\125\252' >> "$W/fake"
fat_put tf1 1 "$W/fake" LightMoss.rkimg
fat_put tf1 1 "$W/empty" lightmoss-update
P2_SUM="$(psum tf1 2)"
run tf1 1
check "not found there, nothing written" 'grep -q "No LightMoss.rkimg found" "$LOG" && [ "$(psum tf1 2)" = "$P2_SUM" ] && ! grep -q "written:" "$LOG"'
check "trigger cleared" '! fat_has tf1 1 lightmoss-update'
fat_del tf1 1 LightMoss.rkimg; fat_del tf1 1 LightMoss.rkimg.bad

# --- 5: no charger -----------------------------------------------------------------
echo "5. in place without the charger: nothing written, still waiting"
fat_put tf1 3 "$XZ" LightMoss.rkimg
fat_put tf1 1 "$W/empty" lightmoss-update
P2_SUM="$(psum tf1 2)"
run tf1 0
check "nothing written" '[ "$(psum tf1 2)" = "$P2_SUM" ] && ! grep -q "written:" "$LOG"'
check "image and trigger still there" 'fat_has tf1 3 LightMoss.rkimg && fat_has tf1 1 lightmoss-update'

# --- 6: a damaged image ------------------------------------------------------------
echo "6. in place, a damaged image: set aside"
head -c 20000000 "$XZ" > "$W/damaged.xz"
fat_del tf1 3 LightMoss.rkimg
fat_put tf1 3 "$W/damaged.xz" LightMoss.rkimg
run tf1 1
check "nothing written" '[ "$(psum tf1 2)" = "$P2_SUM" ] && ! grep -q "written:" "$LOG"'
check "set aside as .bad, trigger cleared" 'fat_has tf1 3 LightMoss.rkimg.bad && ! fat_has tf1 3 LightMoss.rkimg && ! fat_has tf1 1 lightmoss-update'

echo
if [ "$FAILS" -eq 0 ]; then echo "All checks passed."; else echo "$FAILS check(s) FAILED."; fi
rm -rf "${W:?}"
[ "$FAILS" -eq 0 ]
