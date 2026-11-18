#!/bin/sh
# LightMoss post-build (Retroid Pocket Mini V2): runs on the target tree after
# every package is in.
set -eu

TARGET_DIR="$1"
EXT="${BR2_EXTERNAL_LIGHTMOSS_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"

# --- version --------------------------------------------------------------------
# LIGHTMOSS_VERSION from the environment (CI), else the git tag/commit, else the date.
VERSION="${LIGHTMOSS_VERSION:-$(git -C "$EXT" describe --tags --always --dirty 2>/dev/null || date +%Y%m%d)}"
echo "$VERSION" > "${BINARIES_DIR}/lightmoss-version"
# Where its releases are published, for the LightMoss Update app: CI passes its
# own repository, so a fork's builds update from the fork.
REPO="${LIGHTMOSS_REPO:-MarsInsanity/LightMoss}"

# --- os-release: what spruce and PortMaster read ------------------------------
# spruce has no Retroid platform upstream; the spruce fork's "lightmoss" family
# (MarsInsanity/spruceOS, branch mofang) recognises this base by
# OS_NAME="LIGHTMOSS" and takes its platform from SPRUCE_PLATFORM, before its
# CPU-based detection (the SM8250's cores would otherwise read as another SoC).
# LIGHTMOSS_BOARD tells the LightMoss Update app which release image is this
# device's.
cat > "$TARGET_DIR/usr/lib/os-release" <<EOF
NAME="LightMoss"
ID=lightmoss
ID_LIKE=buildroot
VERSION_ID="$VERSION"
PRETTY_NAME="LightMoss $VERSION (Retroid Pocket Mini V2)"
HOME_URL="https://github.com/$REPO"
OS_NAME="LIGHTMOSS"
SPRUCE_PLATFORM="RPMiniV2"
HW_DEVICE="RPMINIV2"
OS_VERSION="$VERSION"
LIGHTMOSS_BOARD="rpminiv2"
LIGHTMOSS_VERSION="$VERSION"
LIGHTMOSS_REPO="$REPO"
EOF
ln -sf ../usr/lib/os-release "$TARGET_DIR/etc/os-release"

# --- the LightMoss Update app ------------------------------------------------------
# A spruce app, kept here and put on the spruce card before spruce starts
# (usr/libexec/lightmoss/spruce-app), so the card always has the one that
# knows how this LightMoss updates.
APP="$TARGET_DIR/usr/share/lightmoss/spruce-app/LightMossUpdate"
rm -rf "${APP:?}"
mkdir -p "$APP"
cp "$EXT"/board/rpminiv2/spruce-app/LightMossUpdate/* "$APP/"
PYTHON="${HOST_DIR:-}/bin/python3"
[ -x "$PYTHON" ] || PYTHON=python3
"$PYTHON" "$EXT/board/r36s/make-app-icon.py" "$APP/icon.png"

# --- Debian library path ----------------------------------------------------------
# spruce's dArkMoss code and PortMaster (PYSDL2_DLL_PATH, LD_LIBRARY_PATH) look for
# the system libraries in Debian's multiarch directory.
ln -sfn . "$TARGET_DIR/usr/lib/aarch64-linux-gnu"
# Debian splits ncurses into libncursesw/libncurses and libtinfo; buildroot
# builds one wide-character library holding all of it. Programs built on
# Debian (spruce's rnano, its flip libmp3lame) load it by Debian's names.
for l in libtinfo.so.6 libncurses.so.6; do
	if [ -e "$TARGET_DIR/usr/lib/libncursesw.so.6" ] && [ ! -e "$TARGET_DIR/usr/lib/$l" ]; then
		ln -sf libncursesw.so.6 "$TARGET_DIR/usr/lib/$l"
	fi
done

# --- boot files: what LMBOOT boots this system with -------------------------------
# In the system itself, so an installed copy, the install to the internal
# storage and every update carry the kernel they were built with. lightmoss-
# install-internal and lightmoss-update copy them to /lightmoss-<copy> on LMBOOT;
# post-image.sh puts them on the card's LMBOOT.
BOOTFILES="$TARGET_DIR/usr/share/lightmoss/boot"
mkdir -p "$BOOTFILES"
cp "${BINARIES_DIR}/Image" "${BINARIES_DIR}/sm8250-retroidpocket-rpminiv2.dtb" "$BOOTFILES/"
# The audio, compute and sensor DSPs start while the kernel probes them, before
# the root filesystem is mounted: their firmware (and cfg80211's regulatory
# database) comes in an initramfs. It has no /init, so the kernel goes on to
# mount root= itself; the same files are in /usr/lib/firmware for later.
FWD="${BUILD_DIR}/lightmoss-firmware-initramfs"
rm -rf "${FWD:?}"
mkdir -p "$FWD/lib/firmware"
( cd "$TARGET_DIR/usr/lib/firmware" &&
	for f in qcom/a650_gmu.bin qcom/a650_sqe.fw qcom/sm8250 qcom/vpu qca/htbtfw20.tlv qca/htnv20.bin \
		regulatory.db regulatory.db.p7s; do
		[ -e "$f" ] || continue
		mkdir -p "$FWD/lib/firmware/$(dirname "$f")"
		cp -a "$f" "$FWD/lib/firmware/$(dirname "$f")/"
	done )
[ -e "$FWD/lib/firmware/qcom/sm8250/adsp.mbn" ] ||
	{ echo "post-build: no SM8250 firmware for the initramfs" >&2; exit 1; }
( cd "$FWD" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet ) |
	gzip -9 > "$BOOTFILES/firmware.cpio.gz"

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

# --- systemd generators: only the ones LightMoss has a use for -------------------
# Each runs as its own program before systemd starts any unit, on every boot.
# Kept: fstab (mounts), debug (systemd.mask= and friends on the kernel command
# line, for debugging). Gone: getty (tty1 is spruce's; no consoles), gpt-auto
# (it would mount Android's partitions; LightMoss mounts its own), ssh (SSH is
# dropbear's "ssh" unit), system-update (no offline updates), tpm2 (no TPM),
# run (no systemd.run= on the command line).
for g in getty gpt-auto ssh system-update tpm2 run; do
	rm -f "$TARGET_DIR/usr/lib/systemd/system-generators/systemd-$g-generator"
done

# --- SSH: dropbear as the "ssh" unit spruce toggles ---------------------------------
# board/rpminiv2/rootfs-overlay ships ssh.service; buildroot's dropbear.service would
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
