#!/bin/sh
# Tests the Mini V2's over-the-air update on a build host: lightmoss-update,
# boot-entry and lightmoss-bless from rootfs-overlay, run by busybox sh with
# busybox applets (as on the device), against loop devices laid out like an
# internal install: a "UFS" with 4 KiB sectors holding userdata, LMBOOT,
# LMSYS1 and LMSYS2. Release images are made the way post-image.sh makes
# them: an xz-compressed GPT disk image (512-byte sectors) whose LMSYS
# partition holds the system, with usr/lib/os-release and
# usr/share/lightmoss/boot/*.
#
# "Starting" a system copy means: its LMSYS mounted as the root of a chroot,
# LMBOOT at /boot, the kernel command line OpenABL would pass in
# /proc/cmdline, /tmp and /run as tmpfs. OpenABL's part (counting tries down
# by renaming lightmoss-N+3.conf) is played by this script, and so is
# spruce-launch.service (a systemctl stand-in that answers bless's questions
# and records a restart). The host needs no FAT driver: without one, LMBOOT
# is ext4 here.
#
#   sudo board/rpminiv2/test-updater.sh [BUSYBOX]
#
# BUSYBOX is a host build of busybox with LightMoss's configuration, e.g.
#   tar xf dl/busybox/busybox-1.37.0.tar.bz2 && cd busybox-1.37.0 &&
#   cp ../output-rpminiv2/build/busybox-1.37.0/.config . &&
#   make oldconfig && make -j4
# (or buildroot's package/busybox/busybox.config with board/r36s/busybox.fragment
# on top). Without one, the host's busybox is used; its applets may differ from
# the device's (dd's status line, for one, which lightmoss-update relies on
# no longer).
#
# Needs root, losetup with -b, sgdisk, mkfs.ext4 (with -d), xz, blkid,
# mountpoint, e2fsck, resize2fs, unshare and chroot.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
OVL="$HERE/rootfs-overlay"
BB="${1:-${BUSYBOX:-$(command -v busybox)}}"
[ "$(id -u)" = 0 ] || { echo "test-updater: run as root" >&2; exit 2; }
[ -x "$BB" ] || { echo "test-updater: no busybox (give one: test-updater.sh BUSYBOX)" >&2; exit 2; }
BB="$(readlink -f "$BB")"
# A mount namespace of its own: nothing mounted here shows outside, and it
# all goes when the script ends.
if [ -z "${LM_TEST_NS:-}" ]; then
	exec env LM_TEST_NS=1 unshare -m --propagation private sh "$HERE/$(basename "$0")" "$BB"
fi

W="$(mktemp -d "${TMPDIR:-/tmp}/lm-test-updater.XXXXXX")"
R="$W/root"
LOOPS=""
FAILS=0
cleanup() {
	set +e
	umount -R "$R" 2>/dev/null
	umount -R "$W/look" 2>/dev/null
	for l in $LOOPS; do losetup -d "$l" 2>/dev/null; done
	rm -rf "$W"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- the system (what every LMSYS here runs) -------------------------------------
# busybox and its applets in /bin, except what LightMoss has as real programs
# (util-linux's blkid and mountpoint, e2fsprogs, xz), copied from the host
# with their libraries.
echo "Building a test system around $BB..."
S="$W/sysroot"
mkdir -p "$S/bin" "$S/sbin" "$S/usr/bin" "$S/usr/sbin" "$S/usr/lib" "$S/etc" "$S/proc" "$S/sys" \
	"$S/dev" "$S/tmp" "$S/run" "$S/boot" "$S/mnt/SDCARD" "$S/var/lib" "$S/root" "$S/test"
copy_bin() { # host program, destination
	cp -L "$1" "$S$2"
	ldd "$1" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p; s/^[[:space:]]*\(\/[^ ]*\) (.*/\1/p' |
		while read -r lib; do
			[ -e "$S$lib" ] && continue
			mkdir -p "$S$(dirname "$lib")"
			cp -L "$lib" "$S$lib"
		done
}
copy_bin "$BB" /bin/busybox
REAL="xz blkid mountpoint e2fsck resize2fs"
for a in $("$BB" --list); do
	case " $REAL " in *" $a "*) continue ;; esac
	ln -sf busybox "$S/bin/$a"
done
for p in $REAL; do copy_bin "$(command -v "$p")" "/usr/bin/$p"; done
# spruce-launch.service as bless sees it: /test/unit.<Property>; a restart is
# written to /test/reboot.
cat > "$S/usr/bin/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
	*reboot*) echo reboot >> /test/reboot; exit 0 ;;
	"show -P "*) cat "/test/unit.$3" 2>/dev/null; exit 0 ;;
esac
exit 1
EOF
chmod 755 "$S/usr/bin/systemctl"
mkdir -p "$S/usr/libexec/lightmoss" "$S/usr/share/lightmoss"
cp "$OVL/usr/bin/lightmoss-update" "$S/usr/bin/"
cp "$OVL"/usr/libexec/lightmoss/lib.sh "$OVL"/usr/libexec/lightmoss/boot-entry "$OVL"/usr/libexec/lightmoss/bless \
	"$S/usr/libexec/lightmoss/"
cp "$OVL/usr/share/lightmoss/update-keep" "$S/usr/share/lightmoss/"
mkdir -p "$S/usr/lib"
ln -sf ../usr/lib/os-release "$S/etc/os-release"
ln -sf ../proc/self/mounts "$S/etc/mtab"
printf 'root:$6$image$default:19000:0:99999:7:::\nspruce:$6$image$default:::::::\nnobody:*:19000:0:99999:7:::\n' > "$S/etc/shadow"
chmod 600 "$S/etc/shadow"
: > "$S/etc/machine-id"
mkdir -p "$S/etc/NetworkManager/system-connections" "$S/etc/dropbear"

# A system tree of a given version and board (in $W/tree-<name>).
tree() { # name version board
	T="$W/tree-$1"
	rm -rf "$T"
	cp -a "$S" "$T"
	printf 'NAME=LightMoss\nID=lightmoss\nLIGHTMOSS_BOARD="%s"\nLIGHTMOSS_VERSION="%s"\n' "$3" "$2" > "$T/usr/lib/os-release"
	mkdir -p "$T/usr/share/lightmoss/boot"
	head -c 3000000 /dev/urandom > "$T/usr/share/lightmoss/boot/Image"
	head -c 400000 /dev/urandom > "$T/usr/share/lightmoss/boot/firmware.cpio.gz"
	head -c 90000 /dev/urandom > "$T/usr/share/lightmoss/boot/sm8250-retroidpocket-rpminiv2.dtb"
}

# A release image as post-image.sh makes it: GPT, LMBOOT at 1 MiB, LMSYS (the
# ext4 system, made like buildroot's rootfs.ext4) behind it, xz-compressed.
image() { # tree-name out.img.xz [LMSYS MiB]
	_mb="${3:-64}"
	rm -f "$W/rootfs.ext4" "$W/disk.img"
	mkfs.ext4 -q -F -L LIGHTMOSS -d "$W/tree-$1" "$W/rootfs.ext4" "${_mb}M" || return 1
	truncate -s $(( 1 + 16 + _mb + 1 ))M "$W/disk.img"
	sgdisk -n 1:2048:+16M -t 1:0700 -c 1:LMBOOT -u 1:4c4d5344-0000-4000-8000-000000000001 \
		-n 2:0:+"${_mb}"M -t 2:8300 -c 2:LMSYS -u 2:4c4d5344-0000-4000-8000-000000000002 \
		-U 4c4d5344-0000-4000-8000-000000000000 "$W/disk.img" > /dev/null || return 1
	_start="$(sgdisk -i 2 "$W/disk.img" | sed -n 's/^First sector: \([0-9]*\).*/\1/p')"
	dd if="$W/rootfs.ext4" of="$W/disk.img" bs=512 seek="$_start" conv=notrunc status=none
	xz -T0 -1 -c "$W/disk.img" > "$2"
	rm -f "$W/disk.img" "$W/rootfs.ext4"
}

# --- release images --------------------------------------------------------------------
echo "Making release images..."
mkdir -p "$W/sd"
# v2.0.0: its boot-entry marks its entries, so the test sees which one wrote
# them; its update-keep list adds a folder of its own.
tree v2 v2.0.0 rpminiv2
sed -i 's/lightmoss.slot=\$slot$/lightmoss.slot=$slot lightmoss.test=image-$version/' "$W/tree-v2/usr/libexec/lightmoss/boot-entry"
grep -q 'lightmoss.test=image' "$W/tree-v2/usr/libexec/lightmoss/boot-entry" || { echo "test-updater: boot-entry marker not applied" >&2; exit 2; }
echo /var/lib/newstate >> "$W/tree-v2/usr/share/lightmoss/update-keep"
printf 'bluetooth:*:19000::::::\n' >> "$W/tree-v2/etc/shadow"
image v2 "$W/sd/v2.img.xz"
# v3.0.0: its boot-entry gives an entry that would not boot (no files).
tree v3 v3.0.0 rpminiv2
printf '#!/bin/sh\necho "title broken"\necho "linux /nowhere/Image"\necho "options root=PARTUUID=$2 lightmoss.slot=$1"\n' \
	> "$W/tree-v3/usr/libexec/lightmoss/boot-entry"
image v3 "$W/sd/v3.img.xz"
# v4.0.0: a /root that is a link out of the system copy.
tree v4 v4.0.0 rpminiv2
rm -rf "$W/tree-v4/root"
ln -s /tmp/outside "$W/tree-v4/root"
image v4 "$W/sd/v4.img.xz"
# Another board's image, one too big for LMSYS, a damaged one, no GPT.
tree other v2.0.0 r36s
image other "$W/sd/other.img.xz"
image v2 "$W/sd/big.img.xz" 200
head -c 2000000 "$W/sd/v2.img.xz" > "$W/sd/damaged.img.xz"
head -c 4000000 /dev/zero | xz -1 -c > "$W/sd/nogpt.img.xz"

# --- the "UFS": 4 KiB sectors, userdata + LightMoss's three partitions --------------------
echo "Laying out the internal storage..."
truncate -s 600M "$W/ufs.disk"
U="$(losetup -b 4096 -P -f --show "$W/ufs.disk")" || { echo "test-updater: losetup -b 4096 failed" >&2; exit 2; }
LOOPS="$U"
sgdisk -n 1:0:+16M -t 1:8300 -c 1:userdata -n 2:0:+64M -t 2:0700 -c 2:LMBOOT \
	-n 3:0:+160M -t 3:8300 -c 3:LMSYS1 -n 4:0:+160M -t 4:8300 -c 4:LMSYS2 "$U" > /dev/null
partx -u "$U" 2>/dev/null
for i in 1 2 3 4; do
	n=0; while [ ! -b "${U}p$i" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
done
[ -b "${U}p4" ] || { echo "test-updater: no partitions on $U" >&2; exit 2; }
check "the UFS has 4096-byte sectors" '[ "$(blockdev --getss "$U")" = 4096 ]'
# The partitions' GPT names, as the device's kernel puts them in uevent
# (PARTNAME). A host kernel that does not read the table itself (partx adds
# the partitions without names) gets them from here, over its sysfs files.
NAMES=""
n=1
for name in userdata LMBOOT LMSYS1 LMSYS2; do
	ue="/sys/class/block/${U#/dev/}p$n/uevent"
	if ! grep -q '^PARTNAME=' "$ue"; then
		{ cat "$ue"; echo "PARTNAME=$name"; } > "$W/uevent-$n"
		NAMES="$NAMES $n"
	fi
	n=$((n + 1))
done
LMBOOT="${U}p2"; LMSYS1="${U}p3"; LMSYS2="${U}p4"
if modprobe vfat 2>/dev/null; grep -qw vfat /proc/filesystems; then
	mkfs.vfat -n LMBOOT "$LMBOOT" > /dev/null; BOOTFS=vfat
else
	mkfs.ext4 -q -L LMBOOT "$LMBOOT"; BOOTFS=ext4
	echo "  (no FAT driver on this host: LMBOOT is ext4 here)"
fi
# System copy 1, v1.0.0 as an install made it, with the device's settings.
tree v1 v1.0.0 rpminiv2
T="$W/tree-v1"
echo 0123456789abcdef0123456789abcdef > "$T/etc/machine-id"
echo hostkey > "$T/etc/dropbear/dropbear_ed25519_host_key"
mkdir -p "$T/root/.ssh" "$T/var/lib/NetworkManager" "$T/var/lib/bluetooth/AA:BB:CC:DD:EE:FF" \
	"$T/var/lib/systemd/timesync" "$T/var/lib/newstate" "$T/etc/lightmoss"
echo "ssh-ed25519 AAAA test" > "$T/root/.ssh/authorized_keys"
printf '[connection]\nid=Home\n' > "$T/etc/NetworkManager/system-connections/Home.nmconnection"
chmod 600 "$T/etc/NetworkManager/system-connections/Home.nmconnection"
echo "[main]" > "$T/var/lib/NetworkManager/NetworkManager.state"
echo "[General]" > "$T/var/lib/bluetooth/AA:BB:CC:DD:EE:FF/info"
: > "$T/var/lib/systemd/timesync/clock"
echo kept > "$T/var/lib/newstate/x"
echo /etc/custom.conf > "$T/etc/lightmoss/update-keep"
echo mine > "$T/etc/custom.conf"
sed -i 's/^root:[^:]*:/root:$6$device$changed:/' "$T/etc/shadow"
mkfs.ext4 -q -F -L LIGHTMOSS -d "$T" "$LMSYS1"
mkfs.ext4 -q -F -L LIGHTMOSS "$LMSYS2"
PU1="$(blkid -p -o value -s PART_ENTRY_UUID "$LMSYS1")"
PU2="$(blkid -p -o value -s PART_ENTRY_UUID "$LMSYS2")"
[ -n "$PU1" ] && [ -n "$PU2" ] || { echo "test-updater: no PARTUUIDs" >&2; exit 2; }
# LMBOOT as the install leaves it: copy 1, kept, the default.
mkdir -p "$W/look"
mount -t "$BOOTFS" "$LMBOOT" "$W/look"
mkdir -p "$W/look/loader/entries" "$W/look/lightmoss-1"
cp "$T"/usr/share/lightmoss/boot/* "$W/look/lightmoss-1/"
sh "$OVL/usr/libexec/lightmoss/boot-entry" 1 "$PU1" v1.0.0 > "$W/look/loader/entries/lightmoss-1.conf"
printf 'default lightmoss-1.conf\ntimeout 3\n' > "$W/look/loader/loader.conf"
umount "$W/look"

# --- starting a system copy -----------------------------------------------------------
# start SLOT [PARTITION]: the copy's LMSYS as / of the chroot $R.
start() {
	umount -R "$R" 2>/dev/null
	mkdir -p "$R"
	mount "${2:-$( [ "$1" = 2 ] && echo "$LMSYS2" || echo "$LMSYS1")}" "$R" || return 1
	mount -t "$BOOTFS" "$LMBOOT" "$R/boot"
	mount -t proc proc "$R/proc"
	echo "root=PARTUUID=x rootfstype=ext4 rootwait=30 ro panic=10 quiet lightmoss.slot=$1" > "$W/cmdline"
	mount --bind "$W/cmdline" "$R/proc/cmdline"
	mount --rbind /dev "$R/dev"
	mount --rbind /sys "$R/sys"
	for n in $NAMES; do
		mount --bind "$W/uevent-$n" "$R/sys/class/block/${U#/dev/}p$n/uevent"
	done
	mount -t tmpfs tmpfs "$R/tmp"
	mount -t tmpfs tmpfs "$R/run"
	mkdir -p "$R/run/systemd/timesync" "$R/test"
	touch "$R/run/systemd/timesync/synchronized"
	rm -f "$R"/test/*
	mount --bind "$W/sd" "$R/mnt/SDCARD"
}
# run CMD...: in the started copy, by busybox sh; output in $W/out, status in $RC.
run() {
	env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root chroot "$R" /bin/sh -c "$*" > "$W/out" 2>&1
	RC=$?
}
unit() { # ActiveState NRestarts MainPID
	echo "$1" > "$R/test/unit.ActiveState"
	echo "$2" > "$R/test/unit.NRestarts"
	echo "$3" > "$R/test/unit.MainPID"
}
B="$R/boot"
EN="$B/loader/entries"
dflt() { sed -n 's/^default[[:space:]]*//p' "$B/loader/loader.conf"; }
entries() { (cd "$EN" && ls | tr '\n' ' '); }
# OpenABL starting a counted entry: one try less.
abl_try() { # slot
	for f in "$EN"/lightmoss-"$1"+*.conf; do
		[ -e "$f" ] || continue
		c="${f##*+}"; c="${c%.conf}"; l="${c%%-*}"; d=0
		case "$c" in *-*) d="${c#*-}" ;; esac
		mv "$f" "$EN/lightmoss-$1+$((l - 1))-$((d + 1)).conf"
	done
}
# Files of a system copy, looked at from outside.
look() { umount "$W/look" 2>/dev/null; mount -o ro "$1" "$W/look"; }
same() { cmp -s "$1" "$2"; }

# --- the tests ------------------------------------------------------------------------------
echo "busybox dd, as on the device:"
if "$BB" dd if=/dev/zero of=/dev/null bs=1k count=1 2>&1 | grep -q bytes; then
	echo "  (this busybox prints dd's byte count; LightMoss's does not)"
else
	ok "dd prints no byte count (what the old lightmoss-update relied on)"
fi

echo "Image checks (--check):"
start 1
run "lightmoss-update --check /mnt/SDCARD/v2.img.xz"
check "a release image reads as one (rc=$RC)" '[ "$RC" = 0 ] && grep -q "^LMSYS: 67108864 bytes at offset 17825792" "$W/out"'
run "lightmoss-update --check /mnt/SDCARD/nogpt.img.xz"
check "an image without a GPT is refused" '[ "$RC" = 1 ] && grep -q "no GPT" "$W/out"'

echo "Update from copy 1 to copy 2 (v1.0.0 -> v2.0.0):"
start 1
run "lightmoss-update -y /mnt/SDCARD/v2.img.xz"
cp "$W/out" "$W/update1.log"
check "lightmoss-update exits 0 when it worked (rc=$RC)" '[ "$RC" = 0 ]'
check "it says so last" 'tail -n 1 "$W/out" | grep -q "^Done: LightMoss v2.0.0 is on system copy 2"'
check "loader.conf: default lightmoss-2.conf, the timeout kept" '[ "$(dflt)" = lightmoss-2.conf ] && grep -qx "timeout 3" "$B/loader/loader.conf"'
check "entries: copy 1 kept, copy 2 with three tries ($(entries))" '[ "$(entries)" = "lightmoss-1.conf lightmoss-2+3.conf " ]'
E2="$EN/lightmoss-2+3.conf"
check "the entry comes from the image's boot-entry" 'grep -q "lightmoss.test=image-v2.0.0" "$E2"'
check "the entry boots LMSYS2 (PARTUUID $PU2) as copy 2" 'grep -q "^options.*root=PARTUUID=$PU2 .*lightmoss.slot=2" "$E2"'
check "the entry: ro fsck.repair=yes panic=10 rootwait=30 net.ifnames=0" \
	'grep -q "^options.* rootwait=30 ro fsck.repair=yes panic=10 net.ifnames=0 " "$E2"'
check "the boot files are the image's" 'same "$B/lightmoss-2/Image" "$W/tree-v2/usr/share/lightmoss/boot/Image" && same "$B/lightmoss-2/sm8250-retroidpocket-rpminiv2.dtb" "$W/tree-v2/usr/share/lightmoss/boot/sm8250-retroidpocket-rpminiv2.dtb"'
check "copy 1's boot files are untouched" 'same "$B/lightmoss-1/Image" "$W/tree-v1/usr/share/lightmoss/boot/Image"'
check "lightmoss-update-pending says v2.0.0" '[ "$(cat "$B/lightmoss-update-pending")" = v2.0.0 ]'
umount -R "$R"
look "$LMSYS2"
V="$W/look"
check "copy 2 is v2.0.0" 'grep -q "LIGHTMOSS_VERSION=\"v2.0.0\"" "$V/usr/lib/os-release"'
check "machine ID carried" 'same "$V/etc/machine-id" "$T/etc/machine-id"'
check "SSH host keys carried" 'same "$V/etc/dropbear/dropbear_ed25519_host_key" "$T/etc/dropbear/dropbear_ed25519_host_key"'
check "authorized_keys carried" 'same "$V/root/.ssh/authorized_keys" "$T/root/.ssh/authorized_keys"'
check "Wi-Fi network carried, still mode 600" 'same "$V/etc/NetworkManager/system-connections/Home.nmconnection" "$T/etc/NetworkManager/system-connections/Home.nmconnection" && [ "$(stat -c %a "$V/etc/NetworkManager/system-connections/Home.nmconnection")" = 600 ]'
check "NetworkManager state carried" '[ -f "$V/var/lib/NetworkManager/NetworkManager.state" ]'
check "Bluetooth pairing carried" '[ -f "$V/var/lib/bluetooth/AA:BB:CC:DD:EE:FF/info" ]'
check "timesyncd's clock carried (the clock was synced)" '[ -e "$V/var/lib/systemd/timesync/clock" ]'
check "/etc/lightmoss/update-keep and what it lists carried" '[ -f "$V/etc/lightmoss/update-keep" ] && [ "$(cat "$V/etc/custom.conf")" = mine ]'
check "what the image's own list adds carried" '[ "$(cat "$V/var/lib/newstate/x")" = kept ]'
check "root's changed password carried, the image's other users kept" \
	'grep -q "^root:\$6\$device\$changed:" "$V/etc/shadow" && grep -q "^bluetooth:" "$V/etc/shadow" && grep -q "^spruce:\$6\$image\$default:" "$V/etc/shadow"'
check "/etc/shadow keeps its mode" '[ "$(stat -c %a "$V/etc/shadow")" = 600 ]'
check "first boot marked done" '[ -e "$V/var/lib/lightmoss/firstboot.done" ]'
umount "$W/look"
check "the written system is a clean ext4" 'e2fsck -fn "$LMSYS2" > /dev/null 2>&1'

echo "First start of copy 2: spruce comes up, the entry is kept:"
start 2
abl_try 2
run "LM_BLESS_STEP=1 LM_BLESS_WAIT=3 /usr/libexec/lightmoss/bless"
check "no spruce yet: bless waits (rc=$RC), then restarts" '[ "$RC" = 1 ] && [ -e "$R/test/reboot" ] && [ -e "$EN/lightmoss-2+2-1.conf" ]'
start 2
abl_try 2
unit active 0 100
mkdir "$R/tmp/spruce_boot_jobs_started"
run "LM_BLESS_STEP=1 LM_BLESS_WAIT=20 /usr/libexec/lightmoss/bless"
check "bless exits 0 (rc=$RC), no restart" '[ "$RC" = 0 ] && [ ! -e "$R/test/reboot" ]'
check "entries: lightmoss-1.conf lightmoss-2.conf ($(entries))" '[ "$(entries)" = "lightmoss-1.conf lightmoss-2.conf " ]'
check "default stays lightmoss-2.conf, nothing pending" '[ "$(dflt)" = lightmoss-2.conf ] && [ ! -e "$B/lightmoss-update-pending" ]'
start 2
run "/usr/libexec/lightmoss/bless"
check "a later start of a kept copy: bless does nothing, at once (rc=$RC)" '[ "$RC" = 0 ] && [ "$(entries)" = "lightmoss-1.conf lightmoss-2.conf " ] && [ ! -s "$W/out" ]'

echo "Update from copy 2 back to copy 1 (v2.0.0 -> v3.0.0, whose boot-entry is broken):"
start 2
run "lightmoss-update -y /mnt/SDCARD/v3.img.xz"
check "it installs (rc=$RC)" '[ "$RC" = 0 ]'
check "with this system's boot-entry instead of the image's" 'grep -q "using this system" "$W/out" && grep -q "^options.*root=PARTUUID=$PU1 .*lightmoss.slot=1" "$EN/lightmoss-1+3.conf" && grep -q "^linux */lightmoss-1/Image" "$EN/lightmoss-1+3.conf"'
check "entries: lightmoss-1+3.conf lightmoss-2.conf, default copy 1" '[ "$(entries)" = "lightmoss-1+3.conf lightmoss-2.conf " ] && [ "$(dflt)" = lightmoss-1.conf ]'
look "$LMSYS1"
check "settings carried on from copy 2" 'same "$W/look/etc/machine-id" "$T/etc/machine-id" && grep -q "^root:\$6\$device\$changed:" "$W/look/etc/shadow"'
umount "$W/look"

echo "Copy 1 never brings spruce up: three tries, then copy 2 again:"
for t in 1 2 3; do
	start 1
	abl_try 1
	unit activating 5 0
	run "LM_BLESS_STEP=1 LM_BLESS_WAIT=60 /usr/libexec/lightmoss/bless"
	check "try $t: spruce keeps failing, restart (rc=$RC, $(entries))" '[ "$RC" = 1 ] && [ -e "$R/test/reboot" ]'
done
check "copy 1 has no tries left" '[ -e "$EN/lightmoss-1+0-3.conf" ]'
start 2
run "/usr/libexec/lightmoss/bless"
check "copy 2's bless takes the default back (rc=$RC)" '[ "$RC" = 0 ] && [ "$(dflt)" = lightmoss-2.conf ]'
check "the failed entry is gone, the failure noted for the app" \
	'[ "$(entries)" = "lightmoss-2.conf " ] && grep -q "LightMoss v3.0.0 did not start; system copy 2 (v2.0.0) kept" "$B/lightmoss-update-failed" && [ ! -e "$B/lightmoss-update-pending" ]'

echo "A trial whose spruce crashed once, then runs:"
start 2
run "lightmoss-update -y /mnt/SDCARD/v2.img.xz"
check "update to copy 1 again (rc=$RC)" '[ "$RC" = 0 ] && [ "$(entries)" = "lightmoss-1+3.conf lightmoss-2.conf " ]'
start 1
abl_try 1
unit active 1 200
mkdir "$R/tmp/spruce_boot_jobs_started"
run "LM_BLESS_STEP=1 LM_BLESS_WAIT=60 LM_BLESS_STABLE=3 /usr/libexec/lightmoss/bless"
check "kept once its runtime.sh ran for a while (rc=$RC)" '[ "$RC" = 0 ] && [ "$(entries)" = "lightmoss-1.conf lightmoss-2.conf " ] && [ ! -e "$R/test/reboot" ]'

echo "Refused updates leave the device starting as before:"
start 1
before="$(entries) $(dflt)"
run "lightmoss-update -y /mnt/SDCARD/damaged.img.xz"
check "a damaged download is refused, nothing changed" '[ "$RC" = 1 ] && grep -q "damaged" "$W/out" && [ "$(entries) $(dflt)" = "$before" ]'
run "lightmoss-update -y /mnt/SDCARD/big.img.xz"
check "a system too big for LMSYS2 is refused, nothing changed" '[ "$RC" = 1 ] && grep -q "does not fit" "$W/out" && [ "$(entries) $(dflt)" = "$before" ]'
# The other copy is the default (picked from OpenABL's menu, this one by hand).
printf 'default lightmoss-2.conf\ntimeout 0\n' > "$B/loader/loader.conf"
run "lightmoss-update -y /mnt/SDCARD/other.img.xz"
check "another board's image is refused" '[ "$RC" = 1 ] && grep -q "for r36s" "$W/out" && tail -n 1 "$W/out" | grep -q "for r36s"'
check "... and the copy it overwrote is no longer an entry nor the default" '[ "$(entries)" = "lightmoss-1.conf " ] && [ "$(dflt)" = lightmoss-1.conf ]'
start sd
run "lightmoss-update -y /mnt/SDCARD/v2.img.xz"
check "a card system is told that updates are for the internal storage" '[ "$RC" = 1 ] && grep -q "runs from the card" "$W/out"'
start 1
run "LM_BLESS_STEP=1 /usr/libexec/lightmoss/bless"
check "bless leaves a card's or a kept copy's entries alone" '[ "$RC" = 0 ] && [ "$(entries)" = "lightmoss-1.conf " ]'

echo "An image with a link out of the system copy:"
start 1
mkdir -p "$R/tmp/outside"
run "lightmoss-update -y /mnt/SDCARD/v4.img.xz; echo rc=\$?; ls -A /tmp/outside"
check "it installs (rc=0) without following the link" 'grep -q "^rc=0" "$W/out" && grep -q "not kept (a link on its way" "$W/out" && [ "$(tail -n 1 "$W/out")" = rc=0 ]'

echo
if [ "$FAILS" = 0 ]; then
	echo "test-updater: all passed"
else
	echo "test-updater: $FAILS failed (the first update's log: see above)"
	sed 's/^/    | /' "$W/update1.log"
fi
[ "$FAILS" = 0 ]
