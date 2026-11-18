#!/bin/bash
# shellcheck disable=SC2034 # variables the checks read through eval
# Tests LightMoss's internal install (lightmoss-install-internal and the flag
# service's install-internal-from-flag), the card's first boot (firstboot) and
# the spruce card mount (mount-spruce) on a build host, against loop devices
# instead of a Mini V2: a "UFS" with 4 KiB logical sectors and the Mini V2's
# own Android partition table (23 partitions, userdata last; sizes from a
# device), and LightMoss cards with 512-byte sectors.
#
#   sudo board/rpminiv2/test-install-internal.sh [DIR]
#
# It works in DIR/lightmoss-test-install (DIR: $TMPDIR or /tmp).
#
# The scripts run under busybox sh, with busybox's applets where LightMoss has
# them (dd, od, cmp, cp, sed, awk...) and the build host's util-linux,
# e2fsprogs, dosfstools, exfatprogs and gptfdisk for the rest, as on the
# device. The system they install is a small fake root (LM_ROOT) whose lib.sh
# points the disk helpers at the loop devices. The build host's kernel may
# have no FAT driver: FAT mounts are played by mtools (a tmpfs filled from the
# partition at mount and written back at umount), ext4 mounts are real.
# Faults are injected through stand-ins for mkfs, blockdev and cp.
#
# Scenarios: a fresh install over stock Android (userdata shrunk and cleared,
# LMBOOT a FAT32 the firmware reads); a repair that keeps the installed
# system's identity and settings; installs stopped at each step (a failing
# mkfs, a power cut during the copy) and finished by the next run; the old
# 256 MiB LMBOOT laid out again without touching Android; another system's
# partitions (ROCKNIX's) refused, then replaced keeping userdata, through the
# prompt; the table re-read refused (partx, no PARTNAME); the flag service
# (no charger, replace flag, a failure's reason); firstboot (new SPRUCEOS, one
# left unformatted, one that is fine, a card with a gap in its numbering);
# mount-spruce (UTF-8 FAT names, a dirty FAT or exFAT checked first, an empty
# SPRUCEOS, spruce-launch's start timeout long enough for a check). Every
# successful run must exit 0.
#
# It takes about ten minutes, most of it the scripts' own pauses (busybox
# sh's sleep is a builtin). Needs root, losetup with -b, sfdisk, sgdisk,
# partx, mtools, busybox, mkfs.vfat, fsck.fat, mkfs.ext4, e2fsck,
# mkfs.exfat, fsck.exfat. The UFS is a sparse 117 GiB file (a few hundred MB
# written).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
OV="$HERE/rootfs-overlay"
if [ -z "${LM_TEST_NS:-}" ]; then
	[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
	W="${1:-${TMPDIR:-/tmp}}/lightmoss-test-install"
	mkdir -p "$W" || exit 1
	W="$(cd "$W" && pwd)"
	exec env LM_TEST_NS=1 unshare -m --propagation private bash "$HERE/$(basename "$0")" "$W"
fi
# In the namespace: the work directory itself, made above.
W="$1"
case "$W" in */lightmoss-test-install) ;; *) echo "bad work directory $W" >&2; exit 1 ;; esac
export LM_TEST_W="$W"
export MTOOLS_SKIP_CHECK=1
FAILS=0
LOOPS=""

ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
section() { echo; echo "== $*"; }

cleanup() {
	for l in $LOOPS; do
		for m in $(awk -v d="$l" 'index($1, d) == 1 { print $2 }' /proc/mounts | sort -r); do
			/usr/bin/umount "$m" 2>/dev/null
		done
		losetup -d "$l" 2>/dev/null
	done
}
trap cleanup EXIT

for d in bin fat r m tmp; do
	[ ! -e "$W/$d" ] || mountpoint -q "$W/$d" || /usr/bin/find "$W/$d" -mindepth 1 -delete
	mkdir -p "$W/$d"
done
/usr/bin/find "$W" -maxdepth 1 -type f -delete

# --- tools: busybox where LightMoss has busybox, stand-ins for some -------
B="$W/bin"
BB="$(command -v busybox)"
for a in sh dd od cmp sed awk grep mktemp cp rm mkdir rmdir sort tail head cat \
	sync tr wc touch mv ln timeout basename dirname readlink find chmod ls cut \
	tee uniq printf echo true false env id; do
	ln -sf "$BB" "$B/$a"
done

rm -f "$B/cp"
# cp: with $W/kill-cp, the big system copy is a power cut (the installer is
# killed outright, nothing of it runs).
cat > "$B/cp" <<EOF
#!/bin/bash
if [ -e "$W/kill-cp" ] && [ "\$1" = -a ] && [ "\${2%/src/.}" != "\$2" ]; then
	rm -f "$W/kill-cp"
	"$BB" cp "\$@" &
	/usr/bin/sleep 0.3
	kill -9 \$PPID
	wait
	exit 1
fi
exec "$BB" cp "\$@"
EOF
cat > "$B/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$B/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >> "$W/systemctl.log"
EOF
# mkfs.vfat / mkfs.ext4: with $W/fail-<name>, fail once.
for t in mkfs.vfat mkfs.ext4; do
	cat > "$B/$t" <<EOF
#!/bin/sh
if [ -e "$W/fail-$t" ]; then rm -f "$W/fail-$t"; echo "$t: injected failure" >&2; exit 1; fi
exec $(command -v "$t") "\$@"
EOF
done
# blockdev: with $W/fail-reread, the kernel will not re-read (a partition
# busy). The build host's kernel may have no partition table parsers (then a
# re-read drops every partition): partx adds them from the table after it,
# as the device's kernel would find them, but without their names (PARTNAME)
# in sysfs, so lm_part_name's fallback (blkid) is what finds them.
cat > "$B/blockdev" <<EOF
#!/bin/sh
if [ "\$1" = --rereadpt ]; then
	if [ -e "$W/fail-reread" ]; then echo "blockdev: BLKRRPART: Device or resource busy" >&2; exit 1; fi
	$(command -v blockdev) --rereadpt "\$2" || exit
	partx -a "\$2" 2>/dev/null
	exit 0
fi
exec $(command -v blockdev) "\$@"
EOF
# mount/umount: FAT and exFAT as a tmpfs named after the partition (so
# /proc/mounts shows it), filled by mtools from a FAT and written back to it
# at umount when mounted rw; exFAT stays empty. The rest is real.
cat > "$B/mount" <<'EOF'
#!/bin/bash
echo "mount $*" >> "$LM_TEST_W/mount.log"
orig=("$@"); type=""; opts=""; args=()
while [ $# -gt 0 ]; do
	case "$1" in
		-t) type="$2"; shift 2 ;;
		-o) opts="$2"; shift 2 ;;
		-*) exec /usr/bin/mount "${orig[@]}" ;;
		*) args+=("$1"); shift ;;
	esac
done
[ "${#args[@]}" = 2 ] || exec /usr/bin/mount "${orig[@]}"
dev="${args[0]}"; dir="${args[1]}"
fs="$(blkid -p -o value -s TYPE "$dev" 2>/dev/null)"
case "$fs" in
	vfat|exfat)
		[ -z "$type" ] || [ "$type" = "$fs" ] || { echo "mount: wrong fs type" >&2; exit 32; }
		/usr/bin/mount -t tmpfs -o size=1g "$dev" "$dir" || exit 32
		if [ "$fs" = vfat ]; then
			mcopy -s -n -m -i "$dev" "::/*" "$dir/" >/dev/null 2>&1
		fi
		echo "$dev $fs $opts" > "$LM_TEST_W/fat/$(echo "$dir" | md5sum | cut -c1-16)"
		exit 0 ;;
esac
exec /usr/bin/mount "${orig[@]}"
EOF
cat > "$B/umount" <<'EOF'
#!/bin/bash
echo "umount $*" >> "$LM_TEST_W/mount.log"
rc=0
for a in "$@"; do
	st="$LM_TEST_W/fat/$(echo "$a" | md5sum | cut -c1-16)"
	if [ -f "$st" ]; then
		read -r dev fs opts < "$st"
		if [ "$fs" = vfat ] && [[ ",$opts," != *,ro,* ]]; then
			for e in $(mdir -b -i "$dev" ::/ 2>/dev/null); do
				case "$e" in */) mdeltree -i "$dev" "${e%/}" ;; *) mdel -i "$dev" "$e" ;; esac
			done 2>/dev/null
			for f in "$a"/* "$a"/.[!.]*; do
				[ -e "$f" ] || continue
				mcopy -s -o -m -i "$dev" "$f" ::/ 2>/dev/null || rc=1
			done
		fi
		/usr/bin/umount "$a" || rc=$?
		rm -f "$st"
	else
		/usr/bin/umount "$a" || rc=$?
	fi
done
exit $rc
EOF
chmod +x "$B"/*
export PATH="$B:/usr/sbin:/usr/bin:/sbin:/bin"
# The scripts' temporary directories (busybox mktemp), to see what they leave.
export TMPDIR="$W/tmp"

# --- the system being installed --------------------------------------------
R="$W/r"
mkdir -p "$R"/usr/bin "$R"/usr/libexec/lightmoss "$R"/usr/share/lightmoss/boot \
	"$R"/usr/lib/systemd "$R"/sbin "$R"/etc/dropbear "$R"/etc/NetworkManager/system-connections \
	"$R"/var/log/journal/0123 "$R"/boot "$R"/proc "$R"/mnt/SDCARD "$R"/tmp
for f in usr/bin/lightmoss-install-internal usr/libexec/lightmoss/lib.sh \
	usr/libexec/lightmoss/boot-entry usr/libexec/lightmoss/install-internal-from-flag \
	usr/libexec/lightmoss/firstboot usr/libexec/lightmoss/mount-spruce; do
	sed "1s|^#!/bin/sh|#!$B/sh|" "$OV/$f" > "$R/$f"
	chmod +x "$R/$f"
done
cat >> "$R/usr/libexec/lightmoss/lib.sh" <<'EOF'

# --- test-install-internal.sh: the test's loop devices, not the Mini V2's
lm_root_disk() { echo "${LM_TEST_ROOT_DISK:-mmcblk9}"; }
lm_disk_type() { case "$1" in mmcblk*|"${LM_TEST_ROOT_DISK:-mmcblk9}") echo SD ;; *) echo UFS ;; esac; }
lm_internal_disk() { echo "$LM_TEST_UFS"; }
lm_card_disks() { echo "${LM_TEST_CARDS:-}"; }
lm_charger_online() { [ "${LM_TEST_CHARGER:-1}" = 1 ]; }
lm_say() { printf '[screen] %b\n' "$1" >> "$LM_TEST_W/screen.log"; }
EOF
head -c 4194304 /dev/urandom > "$R/usr/share/lightmoss/boot/Image"
head -c 1048576 /dev/urandom > "$R/usr/share/lightmoss/boot/firmware.cpio.gz"
head -c 102400 /dev/urandom > "$R/usr/share/lightmoss/boot/sm8250-retroidpocket-rpminiv2.dtb"
printf 'NAME=LightMoss\nLIGHTMOSS_VERSION="v9.9.9-test"\n' > "$R/etc/os-release"
echo systemd > "$R/usr/lib/systemd/systemd"
ln -s ../usr/lib/systemd/systemd "$R/sbin/init"
echo cardid > "$R/etc/machine-id"
echo cardkey > "$R/etc/dropbear/dropbear_ed25519_host_key"
echo card > "$R/etc/NetworkManager/system-connections/CardWifi.nmconnection"
echo journal > "$R/var/log/journal/0123/system.journal"
# /boot and /proc are mounts on the device: empty underneath, as the copy sees them.
mount -t tmpfs tmpfs "$R/boot"
mount -t tmpfs tmpfs "$R/proc"
mkdir -p "$R/proc/device-tree"
printf 'retroidpocket,rpminiv2\0qcom,sm8250\0' > "$R/proc/device-tree/compatible"
echo "LightMoss README" > "$R/boot/README-LightMoss.txt"

export LM_ROOT="$R"

# --- disks -----------------------------------------------------------------
# The Mini V2's UFS LUN 0: 30693376 sectors of 4 KiB, 23 partitions, userdata
# last up to the last usable sector (from a device's fdisk -l).
UFS_IMG="$W/ufs.img"
ufs_layout() {
	cat <<'EOF'
label: gpt
unit: sectors
first-lba: 6
sector-size: 4096
start=6, size=2, name=ssd
start=8, size=256, name=persist_bkp
start=264, size=256, name=misc_bkp
start=520, size=128, name=keystore
start=648, size=128, name=frp
start=776, size=8192, name=persist
start=8968, size=256, name=misc
start=9224, size=256, name=logfs
start=9480, size=1024, name=oops
start=10504, size=1024, name=devinfo
start=11528, size=16384, name=metadata
start=27912, size=2560, name=splash
start=30472, size=128, name=limits
start=30600, size=128, name=limits-cdsp
start=30728, size=256, name=logdump
start=30984, size=32768, name=vbmeta_system_a
start=63752, size=32768, name=vbmeta_system_b
start=96520, size=16384, name=rawdump
start=112904, size=16, name=apdp
start=112920, size=16, name=msadp
start=112936, size=3145728, name=super
start=3258664, size=32768, name=cache
start=3291432, size=27401939, name=userdata
EOF
}
new_ufs() {
	[ -z "${UFS:-}" ] || { losetup -d "/dev/$UFS"; LOOPS="${LOOPS//\/dev\/$UFS/}"; }
	rm -f "$UFS_IMG"
	truncate -s $((30693376 * 4096)) "$UFS_IMG"
	l="$(losetup -b 4096 -P -f --show "$UFS_IMG")"
	LOOPS="$LOOPS $l"
	UFS="${l#/dev/}"
	export LM_TEST_UFS="$UFS"
	ufs_layout | sfdisk -q "$l" >/dev/null
	reread "$l"
	settle
	# Android's data: a marker at the start of userdata and one 1 GiB in.
	android_mark start ANDROID-START
	android_mark 1g ANDROID-DEEP
}
# The kernel learns the table: re-read, and partx for a kernel without parsers.
reread() { "$B/blockdev" --rereadpt "$1"; }
settle() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "/dev/${UFS}p23" ] && return; /usr/bin/sleep 0.2; done; echo "no userdata partition" >&2; exit 1; }
part() { echo "/dev/${UFS}p$1"; }
pnum() { # GPT name -> partition number on the UFS
	sfdisk -d "/dev/$UFS" | sed -n 's|^/dev/[a-z0-9]*p\([0-9]*\) .*name="'"$1"'".*|\1|p'
}
pfield() { # name field: start or size, from the table on the disk
	sfdisk -d "/dev/$UFS" | sed -n '/name="'"$1"'"/s/.*'"$2"'= *\([0-9]*\).*/\1/p'
}
android_mark() { # where text: write a marker into userdata
	local off=0; [ "$1" = 1g ] && off=262144
	[ -b "$(part 23)" ] || { echo "no $(part 23)" >&2; exit 1; }
	{ printf '%s' "$2"; head -c $(( 4096 - ${#2} )) /dev/zero; } |
		dd of="$(part 23)" bs=4096 count=1 seek="$off" conv=notrunc,fsync 2>/dev/null
}
android_read() {
	local off=0; [ "$1" = 1g ] && off=262144
	dd if="$(part 23)" bs=4096 skip="$off" count=1 2>/dev/null | tr -d '\0' | head -c 32
}
zero_mib() { # partition MiB: the first MiB are all zero
	[ "$(dd if="$1" bs=1M count="$2" 2>/dev/null | tr -d '\0' | wc -c)" = 0 ]
}
export MTOOLSRC=/dev/null
fat_cat() { mtype -i "$1" "::/$2" 2>/dev/null; }
fat_has() { mdir -b -i "$1" "::/$2" >/dev/null 2>&1; }
fat_ls() { mdir -b -i "$1" "::/$2" 2>/dev/null | sed 's|.*/\([^/]\)|\1|'; }
fat_clusters() { fsck.fat -nv "$1" 2>&1 | sed -n 's/^ *\([0-9]*\) data clusters.*/\1/p'; }
fat_clean() { ! fsck.fat -n "$1" 2>&1 | grep -q "less than the required minimum"; }
# ext4: run a command with the partition mounted read-only at $W/m.
ext_do() {
	local p="$1"; shift
	/usr/bin/mount -o ro "$p" "$W/m" || return 1
	( cd "$W/m" && eval "$*" ); local rc=$?
	/usr/bin/umount "$W/m"
	return $rc
}
no_leftovers() {
	! grep -q "^/dev/$UFS" /proc/mounts && [ -z "$(ls -A "$TMPDIR")" ]
}

run_install() { # args...: run the installer, output to $W/out, status in $RC
	: > "$W/screen.log"
	# LM_TEST_X=1: trace it.
	${LM_TEST_X:+"$B/sh" -x} "$R/usr/bin/lightmoss-install-internal" "$@" > "$W/out" 2>&1 < "${STDIN:-/dev/null}"
	RC=$?
	sed 's/^/        | /' "$W/out"
}

# The installed layout: LightMoss in the last 4 GiB, at the expected places.
LAST=30693370
LM_START=$(( (LAST + 1 - 4096 * 256) / 256 * 256 ))
BOOT_SIZE=$(( 512 * 256 ))
SYS_SIZE=$(( (LAST + 1 - LM_START - BOOT_SIZE) / 2 / 256 * 256 ))
check_installed() { # label
	local lb l1 l2 uuid
	lb="$(part "$(pnum LMBOOT)")"; l1="$(part "$(pnum LMSYS1)")"; l2="$(part "$(pnum LMSYS2)")"
	check "$1: exit status 0" '[ "$RC" = 0 ]'
	check "$1: LMBOOT at $LM_START, $BOOT_SIZE sectors" '[ "$(pfield LMBOOT start)" = $LM_START ] && [ "$(pfield LMBOOT size)" = $BOOT_SIZE ]'
	check "$1: LMSYS1/LMSYS2 $SYS_SIZE sectors each, back to back" '[ "$(pfield LMSYS1 start)" = $((LM_START + BOOT_SIZE)) ] && [ "$(pfield LMSYS2 start)" = $((LM_START + BOOT_SIZE + SYS_SIZE)) ] && [ "$(pfield LMSYS2 size)" = $SYS_SIZE ]'
	check "$1: LMBOOT is a FAT32 the firmware reads ($(fat_clusters "$lb") clusters)" '[ "$(blkid -p -o value -s TYPE "$lb")" = vfat ] && [ "$(fat_clusters "$lb")" -ge 65525 ] && fat_clean "$lb"'
	uuid="$(blkid -p -o value -s PART_ENTRY_UUID "$l1")"
	check "$1: loader.conf defaults to lightmoss-1.conf" '[ "$(fat_cat "$lb" loader/loader.conf | head -n 1)" = "default lightmoss-1.conf" ]'
	check "$1: the only entry is lightmoss-1+3.conf, root=PARTUUID of LMSYS1" '[ "$(fat_ls "$lb" loader/entries | tr "\n" " ")" = "lightmoss-1+3.conf " ] && fat_cat "$lb" "loader/entries/lightmoss-1+3.conf" | grep -q "root=PARTUUID=$uuid "'
	check "$1: boot files on LMBOOT intact" 'for f in Image firmware.cpio.gz sm8250-retroidpocket-rpminiv2.dtb; do fat_cat "$lb" "lightmoss-1/$f" | cmp -s - "$R/usr/share/lightmoss/boot/$f" || exit 1; done'
	check "$1: README on LMBOOT" 'fat_has "$lb" README-LightMoss.txt'
	check "$1: LMSYS1 is this system (ext4 LIGHTMOSS, init, os-release, firstboot.done)" '[ "$(blkid -p -o value -s LABEL "$l1")" = LIGHTMOSS ] && ext_do "$l1" "[ -L sbin/init ] && cmp -s etc/os-release $R/etc/os-release && [ -e var/lib/lightmoss/firstboot.done ] && [ -x usr/bin/lightmoss-install-internal ]"'
	check "$1: LMSYS1 without the card's journal, /boot and /proc contents" 'ext_do "$l1" "[ -z \"\$(ls -A var/log/journal)\" ] && [ -z \"\$(ls -A boot)\" ] && [ -z \"\$(ls -A proc)\" ]"'
	check "$1: LMSYS1's filesystem checks out" 'e2fsck -fn "$l1" >/dev/null 2>&1'
	check "$1: LMSYS2 is ext4" '[ "$(blkid -p -o value -s TYPE "$l2")" = ext4 ]'
	check "$1: nothing left mounted or in /tmp" 'no_leftovers'
}

# ===========================================================================
section "S1 fresh install over stock Android"
new_ufs
run_install -y
check_installed S1
check "S1: userdata shrunk to end where LightMoss starts" '[ "$(pfield userdata size)" = $((LM_START - 3291432)) ]'
check "S1: userdata's first 8 MiB cleared" 'zero_mib "$(part 23)" 8'
check "S1: says Android's data was cleared" 'grep -q "^Android.s data was cleared" "$W/out"'
check "S1: a new identity (empty machine-id, no host keys), the card's Wi-Fi" 'ext_do "$(part "$(pnum LMSYS1)")" "[ ! -s etc/machine-id ] && [ -z \"\$(ls -A etc/dropbear)\" ] && [ -e etc/NetworkManager/system-connections/CardWifi.nmconnection ]"'
P1_UUIDS="$(sfdisk -d "/dev/$UFS")"

# ===========================================================================
section "S2 repair keeps the installed system's identity and settings"
l1="$(part "$(pnum LMSYS1)")"; lb="$(part "$(pnum LMBOOT)")"
/usr/bin/mount "$l1" "$W/m"
echo installedid > "$W/m/etc/machine-id"
echo installedkey > "$W/m/etc/dropbear/dropbear_ed25519_host_key"
echo home > "$W/m/etc/NetworkManager/system-connections/HomeWifi.nmconnection"
mkdir -p "$W/m/root/.ssh" && echo "ssh-ed25519 AAAA user" > "$W/m/root/.ssh/authorized_keys"
/usr/bin/umount "$W/m"
# lightmoss-bless kept the entry; the user made a flag; Android set itself up again.
mren -i "$lb" "::/loader/entries/lightmoss-1+3.conf" "::/loader/entries/lightmoss-1.conf"
echo > "$W/flag" && mcopy -i "$lb" "$W/flag" ::/lightmoss-debug
android_mark start ANDROID-AGAIN
run_install -y
check_installed S2
check "S2: mode repair, partition table untouched" 'grep -q "^mode: repair" "$W/out" && [ "$(sfdisk -d "/dev/$UFS")" = "$P1_UUIDS" ]'
check "S2: Android's userdata untouched" '[ "$(android_read start)" = ANDROID-AGAIN ] && ! grep -q "^Android.s data was cleared" "$W/out"'
check "S2: machine ID, host key, SSH keys kept; Wi-Fi networks merged" 'ext_do "$l1" "grep -q installedid etc/machine-id && grep -q installedkey etc/dropbear/dropbear_ed25519_host_key && [ -e root/.ssh/authorized_keys ] && [ -e etc/NetworkManager/system-connections/HomeWifi.nmconnection ] && [ -e etc/NetworkManager/system-connections/CardWifi.nmconnection ]"'
check "S2: LMBOOT kept (the lightmoss-debug flag is still there)" 'fat_has "$lb" lightmoss-debug'

# ===========================================================================
section "S3a install stopped at system copy 1 (mkfs.ext4 fails), then finished"
new_ufs
touch "$W/fail-mkfs.ext4"
run_install -y
lb="$(part "$(pnum LMBOOT)")"
check "S3a: exit status 1, with the reason" '[ "$RC" = 1 ] && grep -q "^lightmoss-install-internal: cannot format LMSYS1" "$W/out"'
check "S3a: nothing can boot the internal storage (no entry, no loader.conf)" '! fat_has "$lb" loader/loader.conf && [ -z "$(fat_ls "$lb" loader/entries)" ]'
check "S3a: userdata already cleared and resized" 'zero_mib "$(part 23)" 8 && [ "$(pfield userdata size)" = $((LM_START - 3291432)) ]'
check "S3a: nothing left mounted or in /tmp" 'no_leftovers'
android_mark start ANDROID-AGAIN
run_install -y
check_installed S3a-rerun
check "S3a-rerun: a repair; Android's (new) data untouched" 'grep -q "^mode: repair" "$W/out" && [ "$(android_read start)" = ANDROID-AGAIN ]'

section "S3b install stopped before LMBOOT was formatted, then finished"
new_ufs
touch "$W/fail-mkfs.vfat"
run_install -y
check "S3b: exit status 1; LMBOOT has no filesystem" '[ "$RC" = 1 ] && [ -z "$(blkid -p -o value -s TYPE "$(part "$(pnum LMBOOT)")")" ]'
run_install -y
check_installed S3b-rerun
check "S3b-rerun: a repair that formatted LMBOOT" 'grep -q "^mode: repair" "$W/out"'

section "S3c power cut during the system copy, then finished"
new_ufs
touch "$W/kill-cp"
run_install -y
check "S3c: the installer died (killed)" '[ "$RC" = 137 ] || [ "$RC" = 143 ]'
lb="$(part "$(pnum LMBOOT)")"
check "S3c: no boot entry after the cut" '[ -z "$(fat_ls "$lb" loader/entries 2>/dev/null)" ]'
run_install -y
check "S3c-rerun: its leftover mounts are unmounted, then a repair" 'grep -q "^mode: repair" "$W/out"'
# The killed run's bind mount of the system and its directories stay (no
# EXIT trap runs on a power cut; on the device they were in RAM).
for m in $(awk -v t="$TMPDIR/" 'index($2, t) == 1 { print $2 }' /proc/mounts | sort -r); do /usr/bin/umount "$m"; done
/usr/bin/find "$TMPDIR" -mindepth 1 -depth -type d -empty -delete
check_installed S3c-rerun

# ===========================================================================
section "S4 an install from before LMBOOT was 512 MiB is laid out again"
new_ufs
OLD_START=$LM_START
OLD_BOOT=$(( 256 * 256 ))
OLD_SYS=$(( (LAST + 1 - OLD_START - OLD_BOOT) / 2 / 256 * 256 ))
echo ",$((OLD_START - 3291432))" | sfdisk -q --no-reread -N 23 "/dev/$UFS" >/dev/null
sfdisk -q --append --no-reread "/dev/$UFS" >/dev/null <<EOF
start=$OLD_START, size=$OLD_BOOT, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=LMBOOT
start=$((OLD_START + OLD_BOOT)), size=$OLD_SYS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=LMSYS1
start=$((OLD_START + OLD_BOOT + OLD_SYS)), size=$OLD_SYS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=LMSYS2
EOF
reread "/dev/$UFS"
lb="$(part "$(pnum LMBOOT)")"; l1="$(part "$(pnum LMSYS1)")"
/usr/sbin/mkfs.vfat -F 32 -n LMBOOT "$lb" >/dev/null 2>&1
check "S4: (the old LMBOOT has $(fat_clusters "$lb") clusters, which the firmware refuses)" '[ "$(fat_clusters "$lb")" -lt 65525 ]'
mmd -i "$lb" ::/loader ::/loader/entries
echo "default lightmoss-1.conf" > "$W/flag" && mcopy -i "$lb" "$W/flag" ::/loader/loader.conf
echo "title old" > "$W/flag" && mcopy -i "$lb" "$W/flag" ::/loader/entries/lightmoss-1.conf
echo > "$W/flag" && mcopy -i "$lb" "$W/flag" ::/headphones-invert
/usr/sbin/mkfs.ext4 -q -F -L LIGHTMOSS "$l1"
/usr/sbin/mkfs.ext4 -q -F -L LIGHTMOSS2 "$(part "$(pnum LMSYS2)")"
/usr/bin/mount "$l1" "$W/m"
mkdir -p "$W/m/etc/dropbear" "$W/m/etc/NetworkManager/system-connections"
echo oldid > "$W/m/etc/machine-id"; echo oldkey > "$W/m/etc/dropbear/dropbear_ed25519_host_key"
echo old > "$W/m/etc/NetworkManager/system-connections/OldWifi.nmconnection"
/usr/bin/umount "$W/m"
android_mark start ANDROID-KEPT
UD_SIZE="$(pfield userdata size)"
run_install -y
check_installed S4
check "S4: laid out again" 'grep -q "LMBOOT is smaller than 512 MiB" "$W/out"'
check "S4: userdata the same size ($UD_SIZE)" '[ "$(pfield userdata size)" = "$UD_SIZE" ]'
check "S4: userdata not cleared ($(android_read start))" '[ "$(android_read start)" = ANDROID-KEPT ] && ! grep -q "^Android.s data was cleared" "$W/out"'
check "S4: the installed identity and Wi-Fi kept, the headphones flag too" 'ext_do "$(part "$(pnum LMSYS1)")" "grep -q oldid etc/machine-id && grep -q oldkey etc/dropbear/dropbear_ed25519_host_key && [ -e etc/NetworkManager/system-connections/OldWifi.nmconnection ]" && fat_has "$(part "$(pnum LMBOOT)")" headphones-invert'

# ===========================================================================
section "S5 another system's partitions (ROCKNIX's) behind userdata"
new_ufs
RK_START=$(( LAST + 1 - 10 * 1024 * 256 ))
echo ",$((RK_START - 3291432))" | sfdisk -q --no-reread -N 23 "/dev/$UFS" >/dev/null
sfdisk -q --append --no-reread "/dev/$UFS" >/dev/null <<EOF
start=$RK_START, size=$((2048 * 256)), type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=ROCKNIX
start=$((RK_START + 2048 * 256)), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=STORAGE
EOF
reread "/dev/$UFS"
android_mark start ANDROID-KEPT
UD_SIZE="$(pfield userdata size)"
TABLE="$(sfdisk -d "/dev/$UFS")"
run_install -y
check "S5: refused without --replace, nothing changed" '[ "$RC" = 1 ] && grep -q -- "--replace" "$W/out" && [ "$(sfdisk -d "/dev/$UFS")" = "$TABLE" ]'
STDIN="$W/no"; echo no > "$STDIN"
run_install --replace
check "S5: answering no cancels, nothing changed" '[ "$RC" = 1 ] && grep -q cancelled "$W/out" && [ "$(sfdisk -d "/dev/$UFS")" = "$TABLE" ]'
STDIN="$W/yes"; echo yes > "$STDIN"
export LM_TEST_CHARGER=0
run_install --replace
unset STDIN LM_TEST_CHARGER
check_installed S5
check "S5: the prompt said Android is kept and named the unused gap" 'grep -q "Android and its data are not touched" "$W/out" && grep -q "MiB between userdata and LightMoss stay unused" "$W/out" && grep -q "REMOVED" "$W/out"'
check "S5: ROCKNIX and STORAGE gone" '[ -z "$(pnum ROCKNIX)$(pnum STORAGE)" ]'
check "S5: userdata the same size ($UD_SIZE)" '[ "$(pfield userdata size)" = "$UD_SIZE" ]'
check "S5: userdata not cleared ($(android_read start))" '[ "$(android_read start)" = ANDROID-KEPT ]'
check "S5: asked over a terminal, it logged to the card" 'grep -q "^Done" "$R/boot/lightmoss-install.log"'
rm -f "$R/boot/lightmoss-install.log"

# ===========================================================================
section "S6 the kernel will not re-read the table: partx, no PARTNAME"
new_ufs
touch "$W/fail-reread"
run_install -y
rm -f "$W/fail-reread"
check "S6: went through partx" 'grep -q "partition by partition" "$W/out"'
check "S6: the new partitions have no PARTNAME in sysfs (found through blkid)" '! grep -q PARTNAME "/sys/class/block/$(basename "$(part "$(pnum LMBOOT)")")/uevent"'
check_installed S6

# ===========================================================================
section "S7 the flag service"
FLAG="$R/usr/libexec/lightmoss/install-internal-from-flag"
new_ufs
: > "$W/systemctl.log"; : > "$W/screen.log"
touch "$R/boot/lightmoss-install"
LM_TEST_CHARGER=0 "$FLAG"; RC=$?
check "S7a: no charger: exit 0, flag kept, nothing written, says so" '[ "$RC" = 0 ] && [ -e "$R/boot/lightmoss-install" ] && [ -z "$(pnum LMBOOT)" ] && grep -q "connect the charger" "$W/screen.log"'
rm -f "$R/boot/lightmoss-install"
# Over ROCKNIX: the plain flag fails with the reason on screen...
RK_START=$(( LAST + 1 - 10 * 1024 * 256 ))
echo ",$((RK_START - 3291432))" | sfdisk -q --no-reread -N 23 "/dev/$UFS" >/dev/null
echo "start=$RK_START, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=STORAGE" | sfdisk -q --append --no-reread "/dev/$UFS" >/dev/null
reread "/dev/$UFS"
touch "$R/boot/lightmoss-install.txt"
: > "$W/screen.log"
"$FLAG"; RC=$?
check "S7b: plain flag over another system: .failed, reason on screen, no restart" '[ "$RC" = 0 ] && [ -e "$R/boot/lightmoss-install.failed" ] && [ ! -e "$R/boot/lightmoss-install.txt" ] && grep -q "replace" "$W/screen.log" && [ ! -s "$W/systemctl.log" ]'
rm -f "$R/boot/lightmoss-install.failed"
# ...the replace flag installs and restarts.
touch "$R/boot/lightmoss-install-replace"
: > "$W/screen.log"
"$FLAG"; RC=$?
check "S7c: replace flag: installed, renamed .done, restarts" '[ "$RC" = 0 ] && [ -e "$R/boot/lightmoss-install-replace.done" ] && grep -q "systemctl reboot" "$W/systemctl.log" && grep -q "^Done" "$R/boot/lightmoss-install.log"'
check "S7c: the screen did not mention Android's data (it was kept)" '! grep -q "data was cleared" "$W/screen.log"'
RC=0; check_installed S7c
rm -f "$R"/boot/lightmoss-install*

# ===========================================================================
section "F firstboot on a card"
# A LightMoss card as the image makes it: LMBOOT, LMSYS, the backup GPT where
# the image ends; then the card is bigger.
new_card() { # name [gap|spruce]: a 2 GiB card, 512-byte sectors -> $CARD_NEW
	local img="$W/$1.img" l
	rm -f "$img"; truncate -s $(( (2048 + 131072 + 524288 + 2048 + 8192) * 512 )) "$img"
	l="$(losetup -P -f --show "$img")"
	case "${2:-}" in
		gap) sfdisk -q "$l" >/dev/null <<EOF
label: gpt
${l}p1 : start=2048, size=131072, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=LMBOOT
${l}p4 : start=133120, size=8192, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=DATA
${l}p2 : start=141312, size=524288, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=LMSYS
EOF
			;;
		spruce) sfdisk -q "$l" >/dev/null <<EOF
label: gpt
start=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=SPRUCE
EOF
			;;
		*) sfdisk -q "$l" >/dev/null <<EOF
label: gpt
start=2048, size=131072, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=LMBOOT
start=133120, size=524288, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=LMSYS
EOF
			;;
	esac
	losetup -d "$l"
	truncate -s 2G "$img"
	# (losetup -P before the table: nothing of it known yet.)
	l="$(losetup -P -f --show "$img")"; LOOPS="$LOOPS $l"
	partx -a "$l" 2>/dev/null
	# The system runs from LMSYS: mounted, so the card is busy and the kernel
	# will not re-read its whole table, as on the device.
	if [ "${2:-}" != spruce ]; then
		/usr/sbin/mkfs.ext4 -q -F "${l}p2"
		mkdir -p "$W/root-$1"
		/usr/bin/mount "${l}p2" "$W/root-$1"
	fi
	CARD_NEW="${l#/dev/}"
}
firstboot() { rm -rf "$R/var/lib/lightmoss"; LM_TEST_ROOT_DISK="$CARD" "$R/usr/libexec/lightmoss/firstboot" > "$W/out" 2>&1; RC=$?; sed 's/^/        | /' "$W/out"; }
new_card card1; CARD="$CARD_NEW"
firstboot
check "F1: exit 0, firstboot.done" '[ "$RC" = 0 ] && [ -e "$R/var/lib/lightmoss/firstboot.done" ]'
check "F1: SPRUCEOS (exFAT) made as partition 3 right after LMSYS" '[ "$(blkid -p -o value -s TYPE "/dev/${CARD}p3")" = exfat ] && [ "$(blkid -p -o value -s LABEL "/dev/${CARD}p3")" = SPRUCEOS ] && [ "$(cat /sys/class/block/${CARD}p3/start)" = 657408 ]'
check "F1: the backup GPT moved to the end of the card" '[ "$(sfdisk -d "/dev/$CARD" | sed -n "s/^last-lba: *//p")" = $(( 2 * 1024 * 2048 - 34 )) ]'
dd if=/dev/zero of="/dev/${CARD}p3" bs=1M count=1 conv=fsync 2>/dev/null
firstboot
check "F2: a SPRUCEOS left without a filesystem is formatted" '[ "$RC" = 0 ] && [ "$(blkid -p -o value -s TYPE "/dev/${CARD}p3")" = exfat ] && grep -q "has no filesystem" "$W/out"'
U="$(blkid -p -o value -s UUID "/dev/${CARD}p3")"
firstboot
check "F3: a SPRUCEOS with a filesystem is left alone" '[ "$RC" = 0 ] && [ "$(blkid -p -o value -s UUID "/dev/${CARD}p3")" = "$U" ]'
new_card card2 gap; CARD="$CARD_NEW"
/usr/sbin/mkfs.vfat -n DATA "/dev/${CARD}p4" >/dev/null 2>&1
U="$(blkid -p -o value -s UUID "/dev/${CARD}p4")"
firstboot
check "F4: numbering gap (1, 2, 4): SPRUCEOS is 3, partition 4 untouched" '[ "$RC" = 0 ] && [ "$(blkid -p -o value -s LABEL "/dev/${CARD}p3")" = SPRUCEOS ] && [ "$(blkid -p -o value -s UUID "/dev/${CARD}p4")" = "$U" ]'

# ===========================================================================
section "M mount-spruce"
mspruce() { : > "$W/mount.log"; : > "$W/screen.log"; : > "$W/systemctl.log"; LM_TEST_ROOT_DISK="$CARD" LM_TEST_CARDS="$CARDS" "$R/usr/libexec/lightmoss/mount-spruce" > "$W/out" 2>&1; RC=$?; sed 's/^/        | /' "$W/out"; }
unmount_sd() { mountpoint -q "$R/mnt/SDCARD" && umount "$R/mnt/SDCARD"; }
new_card card3; CARD="$CARD_NEW"; CARDS="$CARD"
firstboot
mspruce
check "M1: SPRUCEOS without spruce: not found, says to copy spruce, powers off" '[ "$RC" = 1 ] && grep -q "spruce is not on the card yet" "$W/screen.log" && grep -q "systemctl poweroff" "$W/systemctl.log"'
# spruce on a FAT32 SPRUCEOS of the card the system runs from
S="/dev/${CARD}p3"
/usr/sbin/mkfs.vfat -F 32 -n SPRUCEOS "$S" >/dev/null 2>&1
mmd -i "$S" ::/spruce ::/spruce/scripts && echo "#!/bin/sh" > "$W/flag" && mcopy -i "$S" "$W/flag" ::/spruce/scripts/runtime.sh
mspruce
check "M2: found on SPRUCEOS, exit 0, FAT mounted with utf8 names" '[ "$RC" = 0 ] && [ -f "$R/mnt/SDCARD/spruce/scripts/runtime.sh" ] && grep -q -- "-t vfat -o rw,noatime,umask=0000,utf8 $S" "$W/mount.log"'
unmount_sd
check "M2: not checked when clean" '! grep -q "checking it" "$W/out"'
# Dirty: the state byte of a FAT32 (offset 65), as Linux leaves it after a power cut.
printf '\001' | dd of="$S" bs=1 seek=65 conv=notrunc,fsync 2>/dev/null
mspruce
check "M3: a dirty FAT is checked (and left clean) before the mount" '[ "$RC" = 0 ] && grep -q "checking it" "$W/out" && [ "$(od -A n -t u1 -j 65 -N 1 "$S" | tr -d " ")" = 0 ]'
unmount_sd
# exFAT, dirty (VolumeFlags bit 1).
/usr/sbin/mkfs.exfat -L SPRUCEOS "$S" >/dev/null 2>&1
printf '\002' | dd of="$S" bs=1 seek=106 conv=notrunc,fsync 2>/dev/null
mspruce
check "M4: a dirty exFAT is checked with fsck.exfat (dirty flag cleared)" 'grep -q "checking it" "$W/out" && [ $(( $(od -A n -t u1 -j 106 -N 1 "$S") & 2 )) = 0 ]'
unmount_sd
# A second card formatted for spruce (FAT32, MBR or GPT, partition 1) wins
# over the root card's SPRUCEOS; the root card's LMBOOT is never a candidate.
new_card card4 spruce; C2="$CARD_NEW"
/usr/sbin/mkfs.vfat -F 32 -n SPRUCE "/dev/${C2}p1" >/dev/null 2>&1
mmd -i "/dev/${C2}p1" ::/spruce ::/spruce/scripts && mcopy -i "/dev/${C2}p1" "$W/flag" ::/spruce/scripts/runtime.sh
CARDS="$C2 $CARD"
mspruce
check "M5: spruce on another card's FAT partition" '[ "$RC" = 0 ] && grep -q "spruce found on /dev/${C2}p1" "$W/out"'
unmount_sd
# mount-spruce runs as an ExecStartPre of spruce-launch.service: its start
# timeout must leave a check (and the retry's) the time mount-spruce gives it,
# or systemd ends the check, restarts and checks again, for ever.
tss="$(sed -n 's/^TimeoutStartSec=\([0-9]*\)min$/\1/p' "$OV/usr/lib/systemd/system/spruce-launch.service")"
fto="$(sed -n 's/.*timeout \([0-9]*\) fsck\.fat .*/\1/p' "$OV/usr/libexec/lightmoss/mount-spruce")"
check "M6: spruce-launch's start timeout (${tss:-default 1.5} min) outlasts two checks of ${fto:-?} s" \
	'[ -n "$tss" ] && [ -n "$fto" ] && [ $((tss * 60)) -gt $((2 * fto + 120)) ]'

# ===========================================================================
echo
if [ "$FAILS" = 0 ]; then echo "all passed"; else echo "$FAILS FAILED"; fi
[ "$FAILS" = 0 ]
