#!/bin/sh
# LightMoss post-image: assemble the disk image and compress it.
set -eu

BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "${BINARIES_DIR}/lightmoss-version" 2>/dev/null || date +%Y%m%d)"

# BOOT's own files (boot.ini, logo, the text files) next to the kernel and dtbs.
rm -rf "${BINARIES_DIR:?}/boot"
mkdir -p "${BINARIES_DIR}/boot"
cp "${BOARD_DIR}"/boot/* "${BINARIES_DIR}/boot/"
# The charging screen's images (U-Boot's charge mode, see the script).
PYTHON="${HOST_DIR}/bin/python3"
[ -x "$PYTHON" ] || PYTHON=python3
"$PYTHON" "${BOARD_DIR}/make-charge-images.py" "${BINARIES_DIR}/boot"

# The updater's initramfs (uInitrd), which boot.ini loads only when TF1 holds a
# LightMoss.rkimg: the image's own busybox and xz, with their libraries.
IRD="${BUILD_DIR}/lightmoss-initramfs"
rm -rf "${IRD:?}"
mkdir -p "$IRD/bin" "$IRD/lib"
cp "${TARGET_DIR}/usr/bin/busybox" "${TARGET_DIR}/usr/bin/xz" "$IRD/bin/"
ln -s busybox "$IRD/bin/sh"
for l in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libresolv.so.2 liblzma.so.5; do
	cp -L "${TARGET_DIR}/usr/lib/$l" "$IRD/lib/"
done
# The 64-bit loader searches /lib64 and /usr/lib64, as the rootfs's lib64 -> lib.
ln -s lib "$IRD/lib64"
install -m 0755 "${BOARD_DIR}/initramfs/init" "$IRD/init"
# Where the build host can run aarch64 binaries, prove the updater's busybox
# starts and reads its script: a broken initramfs is only found mid-update.
if QEMU="$(command -v qemu-aarch64-static || command -v qemu-aarch64)"; then
	"$QEMU" -L "$IRD" "$IRD/bin/busybox" sh -n "$IRD/init" ||
		{ echo "post-image: the updater initramfs does not run" >&2; exit 1; }
fi
( cd "$IRD" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet ) |
	gzip -9 > "${BINARIES_DIR}/initramfs.cpio.gz"
"${HOST_DIR}/bin/mkimage" -A arm64 -O linux -T ramdisk -C none -n "LightMoss updater" \
	-d "${BINARIES_DIR}/initramfs.cpio.gz" "${BINARIES_DIR}/boot/uInitrd" >/dev/null

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

IMG="${BINARIES_DIR}/lightmoss-r36s.img"
OUT="${BINARIES_DIR}/lightmoss-r36s-${VERSION}.img.xz"
rm -f "${BINARIES_DIR}"/lightmoss-r36s-*.img.xz
xz -T0 -6 -k -c "$IMG" > "$OUT"
( cd "${BINARIES_DIR}" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "LightMoss image: $OUT"
