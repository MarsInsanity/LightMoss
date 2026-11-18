#!/bin/sh
# Checks a Mini V2 image before it is released, as the LightMoss Update app
# and lightmoss-update will use it on a device:
#   - lightmoss-update --check reads it (xz, GPT, the LMSYS partition);
#   - the system in LMSYS: os-release names this board (and VERSION, if
#     given), the update scripts are there, the system's own boot-entry gives
#     entries whose kernel, initrd and device tree are among its boot files;
#   - the GPU stack is there, 64- and 32-bit (glvnd, Mesa, the Vulkan loader,
#     Turnip's two ICD manifests naming libraries in the image);
#   - the system's filesystem has room left (it is a fixed size).
#
#   sudo board/rpminiv2/check-image.sh lightmoss-rpminiv2-<version>.img.xz [VERSION]
#
# Needs root (a read-only loop mount), xz, losetup and about 1.5 GB in $TMPDIR.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
img="${1:-}"
want="${2:-}"
[ -f "$img" ] || { echo "usage: check-image.sh IMAGE.img.xz [VERSION]" >&2; exit 2; }

fails=0
ok()  { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/lm-check-image.XXXXXX")"
loop=""
cleanup() {
	set +e
	mountpoint -q "$tmp/m" && umount "$tmp/m"
	[ -n "$loop" ] && losetup -d "$loop"
	rm -rf "$tmp"
}
trap cleanup EXIT

echo "Checking $(basename "$img")..."
if ! sh "$HERE/rootfs-overlay/usr/bin/lightmoss-update" --check "$img" > "$tmp/check" 2>&1; then
	cat "$tmp/check"
	bad "lightmoss-update cannot read this image"
	exit 1
fi
geo="$(sed -n 's/^LMSYS: \([0-9]*\) bytes at offset \([0-9]*\)$/\1 \2/p' "$tmp/check")"
bytes="${geo% *}"; off="${geo#* }"
[ -n "$geo" ] || { cat "$tmp/check"; bad "no LMSYS geometry from lightmoss-update --check"; exit 1; }
ok "lightmoss-update reads it: LMSYS is $((bytes / 1048576)) MiB at $off"

xz -dc "$img" > "$tmp/disk.img"
loop="$(losetup -r -f --show -o "$off" --sizelimit "$bytes" "$tmp/disk.img")"
mkdir -p "$tmp/m"
mount -o ro -t ext4 "$loop" "$tmp/m"
m="$tmp/m"

osr() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$m/usr/lib/os-release" | head -n 1; }
if [ -f "$m/usr/lib/os-release" ]; then
	[ "$(osr ID)" = lightmoss ] && ok "os-release: ID=lightmoss" || bad "os-release: ID is '$(osr ID)'"
	[ "$(osr LIGHTMOSS_BOARD)" = rpminiv2 ] && ok "os-release: LIGHTMOSS_BOARD=rpminiv2" ||
		bad "os-release: LIGHTMOSS_BOARD is '$(osr LIGHTMOSS_BOARD)'"
	v="$(osr LIGHTMOSS_VERSION)"
	if [ -n "$want" ]; then
		[ "$v" = "$want" ] && ok "os-release: LIGHTMOSS_VERSION=$v" || bad "os-release: LIGHTMOSS_VERSION is '$v', not $want"
	else
		[ -n "$v" ] && ok "os-release: LIGHTMOSS_VERSION=$v" || bad "os-release: no LIGHTMOSS_VERSION"
	fi
else
	bad "no usr/lib/os-release"
fi

for f in usr/bin/lightmoss-update usr/libexec/lightmoss/lib.sh usr/libexec/lightmoss/bless \
	usr/libexec/lightmoss/boot-entry usr/share/lightmoss/update-keep \
	usr/share/lightmoss/spruce-app/LightMossUpdate/launch.sh; do
	[ -s "$m/$f" ] && ok "$f" || bad "no $f"
done

# The entries the system's boot-entry writes (for an update, the install and
# the card) name files that are among its boot files.
for slot in 1 2 sd; do
	if ! sh "$m/usr/libexec/lightmoss/boot-entry" "$slot" 00000000-0000-0000-0000-000000000000 "${want:-test}" > "$tmp/entry" 2>&1; then
		bad "boot-entry $slot fails"; continue
	fi
	grep -q "^options.*root=PARTUUID=00000000-0000-0000-0000-000000000000 .*lightmoss\.slot=$slot\( \|\$\)" "$tmp/entry" ||
		bad "boot-entry $slot: no options line with root= and lightmoss.slot=$slot"
	for k in linux initrd devicetree; do
		p="$(sed -n "s/^${k}[[:space:]][[:space:]]*//p" "$tmp/entry" | head -n 1)"
		[ -n "$p" ] || { [ "$k" = linux ] && bad "boot-entry $slot: no linux line"; continue; }
		case "$p" in
			/lightmoss-"$slot"/*) ;;
			*) bad "boot-entry $slot: $k $p is not in /lightmoss-$slot"; continue ;;
		esac
		[ -s "$m/usr/share/lightmoss/boot/${p#/lightmoss-"$slot"/}" ] ||
			bad "boot-entry $slot: $k ${p##*/} is not in usr/share/lightmoss/boot"
	done
done
[ "$fails" = 0 ] && ok "boot entries name the system's boot files: $(ls "$m/usr/share/lightmoss/boot" | tr '\n' ' ')"

# The GPU stack, 64- and 32-bit: glvnd's dispatch libraries with Mesa as the
# EGL vendor, desktop OpenGL, the Vulkan loader, and Turnip's ICD manifests
# naming a library that is in the image, one per word size.
for f in usr/lib/libEGL.so.1 usr/lib/libGLESv2.so.2 usr/lib/libOpenGL.so.0 \
	usr/lib/libEGL_mesa.so.0 usr/lib/libgbm.so.1 usr/lib/libvulkan.so.1 \
	usr/lib/libvulkan_freedreno.so usr/share/glvnd/egl_vendor.d/50_mesa.json \
	usr/lib/arm-linux-gnueabihf/libEGL.so.1 usr/lib/arm-linux-gnueabihf/libGLESv2.so.2 \
	usr/lib/arm-linux-gnueabihf/libGLdispatch.so.0 usr/lib/arm-linux-gnueabihf/libEGL_mesa.so.0 \
	usr/lib/arm-linux-gnueabihf/libvulkan.so.1 usr/lib/arm-linux-gnueabihf/libvulkan_freedreno.so; do
	[ -e "$m/$f" ] || bad "GPU: no $f"
done
icds=0
for j in "$m"/usr/share/vulkan/icd.d/freedreno_icd.*.json; do
	[ -f "$j" ] || continue
	lp="$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$j" | head -n 1)"
	la="$(sed -n 's/.*"library_arch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$j" | head -n 1)"
	case "$lp" in
		/usr/lib/arm-linux-gnueabihf/*) wa=32 ;;
		/usr/lib/*) wa=64 ;;
		*) bad "GPU: ${j##*/}: library_path '$lp' is not under /usr/lib"; continue ;;
	esac
	[ -e "$m$lp" ] || { bad "GPU: ${j##*/}: $lp is not in the image"; continue; }
	[ -z "$la" ] || [ "$la" = "$wa" ] || { bad "GPU: ${j##*/}: library_arch $la for a $wa-bit $lp"; continue; }
	icds=$((icds + 1))
done
[ "$icds" = 2 ] && ok "GPU: glvnd, Mesa, Vulkan loader and Turnip (64- and 32-bit)" ||
	bad "GPU: $icds usable Turnip ICD manifests, not 2 (64- and 32-bit)"

# Room: the system copy is a fixed-size filesystem (grown to its partition on
# the internal storage, not on a card).
df -k "$m" | awk 'NR == 2 { print $3, $4 }' > "$tmp/df"
read -r used avail < "$tmp/df"
pct=$(( used * 100 / (used + avail) ))
echo "  info  the system uses $((used / 1024)) MiB, $((avail / 1024)) MiB free ($pct% full)"
if [ "$avail" -lt 32768 ]; then
	bad "less than 32 MiB left on the system filesystem: raise BR2_TARGET_ROOTFS_EXT2_SIZE"
elif [ "$pct" -ge 90 ]; then
	echo "  WARN  the system filesystem is $pct% full"
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::rpminiv2 system filesystem is $pct% full ($((avail / 1024)) MiB free)"
fi

if [ "$fails" = 0 ]; then echo "check-image: all good"; else echo "check-image: $fails failed"; fi
[ "$fails" = 0 ]
