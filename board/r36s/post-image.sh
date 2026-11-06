#!/bin/sh
# LightMoss post-image: assemble the disk image and compress it.
set -eu

BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "${BINARIES_DIR}/lightmoss-version" 2>/dev/null || date +%Y%m%d)"

# BOOT's own files (boot.ini, logo, the text files) next to the kernel and dtbs.
rm -rf "${BINARIES_DIR:?}/boot"
mkdir -p "${BINARIES_DIR}/boot"
cp "${BOARD_DIR}"/boot/* "${BINARIES_DIR}/boot/"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

IMG="${BINARIES_DIR}/lightmoss-r36s.img"
OUT="${BINARIES_DIR}/lightmoss-r36s-${VERSION}.img.xz"
rm -f "${BINARIES_DIR}"/lightmoss-r36s-*.img.xz
xz -T0 -6 -k -c "$IMG" > "$OUT"
( cd "${BINARIES_DIR}" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "LightMoss image: $OUT"
