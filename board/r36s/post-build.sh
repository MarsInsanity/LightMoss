#!/bin/sh
# LightMoss post-build: runs on the target tree after every package is in.
set -eu

TARGET_DIR="$1"
EXT="${BR2_EXTERNAL_LIGHTMOSS_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"

# --- version --------------------------------------------------------------------
# LIGHTMOSS_VERSION from the environment (CI), else the git tag/commit, else the date.
VERSION="${LIGHTMOSS_VERSION:-$(git -C "$EXT" describe --tags --always --dirty 2>/dev/null || date +%Y%m%d)}"
echo "$VERSION" > "${BINARIES_DIR}/lightmoss-version"

# --- os-release: what spruce and PortMaster read ------------------------------
# spruce's platform detection (helperFunctions.sh) recognises a dArkMoss base by
# OS_NAME="DARKMOSS" and takes its platform from SPRUCE_PLATFORM. spruce has no
# R36S platform; the G80CA is a G350 as far as it can tell (RK3326, 640x480, two
# sticks, the same odroidgo3-joypad and button codes, rk817 audio, 0-255
# backlight), so it runs spruce's G350 profile unchanged, as BobMoss does.
#
# OS_VERSION is 999.0.0 so spruce's Firmware Update never offers dArkMoss's G350
# payload, which would replace this system with one for another board.
# HW_DEVICE is PortMaster's: harbourmaster maps "R36S" to its 640x480 rk3326
# profile.
cat > "$TARGET_DIR/usr/lib/os-release" <<EOF
NAME="LightMoss"
ID=lightmoss
ID_LIKE=buildroot
VERSION_ID="$VERSION"
PRETTY_NAME="LightMoss $VERSION (R36S clone G80CA)"
HOME_URL="https://github.com/MarsInsanity/LightMoss"
OS_NAME="DARKMOSS"
SPRUCE_PLATFORM="G350"
HW_DEVICE="R36S"
DARKMOSS_UNIT="r36sclone"
OS_VERSION="999.0.0"
LIGHTMOSS_VERSION="$VERSION"
EOF
ln -sf ../usr/lib/os-release "$TARGET_DIR/etc/os-release"

# --- Debian library path ----------------------------------------------------------
# spruce's dArkMoss code and PortMaster (PYSDL2_DLL_PATH, LD_LIBRARY_PATH) look for
# the system libraries in Debian's multiarch directory.
ln -sfn . "$TARGET_DIR/usr/lib/aarch64-linux-gnu"

# --- MT7601U firmware -------------------------------------------------------------
# linux-firmware installs mediatek/mt7601u.bin; the 4.4 driver asks for mt7601u.bin.
if [ -e "$TARGET_DIR/usr/lib/firmware/mediatek/mt7601u.bin" ]; then
	ln -sf mediatek/mt7601u.bin "$TARGET_DIR/usr/lib/firmware/mt7601u.bin"
fi

# --- DNS: NetworkManager owns it --------------------------------------------------
ln -sf ../run/NetworkManager/resolv.conf "$TARGET_DIR/etc/resolv.conf"

# --- the spruce login ---------------------------------------------------------------
# Every spruce device offers the same SSH login, user "spruce" password
# "happygaming", root-equivalent, and spruce's Network Settings prints it. A uid 0
# account of its own name, with root's password hash.
if ! grep -q '^spruce:' "$TARGET_DIR/etc/passwd"; then
	echo 'spruce:x:0:0:spruce:/root:/bin/sh' >> "$TARGET_DIR/etc/passwd"
	ROOT_HASH="$(sed -n 's/^root:\([^:]*\):.*/\1/p' "$TARGET_DIR/etc/shadow")"
	echo "spruce:${ROOT_HASH}:::::::" >> "$TARGET_DIR/etc/shadow"
fi

# --- SSH: dropbear as the "ssh" unit spruce toggles ---------------------------------
# board/r36s/rootfs-overlay ships ssh.service; buildroot's dropbear.service would
# be a second, always-on server.
rm -f "$TARGET_DIR/usr/lib/systemd/system/dropbear.service" \
	"$TARGET_DIR/etc/systemd/system/multi-user.target.wants/dropbear.service"
# /etc/dropbear must be real for -R to keep the host keys across boots.
if [ -L "$TARGET_DIR/etc/dropbear" ]; then
	rm -f "$TARGET_DIR/etc/dropbear"
fi
mkdir -p "$TARGET_DIR/etc/dropbear"
# scp/sftp: dropbear runs /usr/libexec/sftp-server; spruce ships one on the card.
mkdir -p "$TARGET_DIR/usr/libexec"
ln -sf /mnt/SDCARD/spruce/bin64/sftp-server "$TARGET_DIR/usr/libexec/sftp-server"

# --- persistent journal (capped in journald.conf.d) ---------------------------------
mkdir -p "$TARGET_DIR/var/log/journal"

# --- where spruce lives ---------------------------------------------------------------
mkdir -p "$TARGET_DIR/mnt/SDCARD" "$TARGET_DIR/boot"
