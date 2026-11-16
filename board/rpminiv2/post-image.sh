#!/bin/sh
# LightMoss post-image (Retroid Pocket Mini V2): assemble the card image and
# compress it.
set -eu

BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "${BINARIES_DIR}/lightmoss-version" 2>/dev/null || date +%Y%m%d)"
BOOTFILES="${TARGET_DIR}/usr/share/lightmoss/boot"

# The card's LMBOOT: OpenABL's loader.conf and the card's boot entry, the
# system's boot files (post-build.sh put them in the system), the OpenABL
# image for installing it, and the text file that says what is what.
LMB="${BINARIES_DIR}/lmboot"
case "$LMB" in */lmboot) ;; *) echo "post-image: unexpected LMBOOT staging path" >&2; exit 1 ;; esac
rm -rf "$LMB"
mkdir -p "$LMB/loader/entries" "$LMB/lightmoss-sd" "$LMB/openabl"
cp "$BOOTFILES"/* "$LMB/lightmoss-sd/"
printf 'default lightmoss-sd.conf\ntimeout 0\n' > "$LMB/loader/loader.conf"
"${TARGET_DIR}/usr/libexec/lightmoss/boot-entry" sd 4c4d5344-0000-4000-8000-000000000002 "$VERSION" \
	> "$LMB/loader/entries/lightmoss-sd.conf"
cp "${BINARIES_DIR}/openabl/abl_signed-SM8250.elf" "$LMB/openabl/"
cp "${BOARD_DIR}/boot/openabl/"* "$LMB/openabl/"
cp "${BOARD_DIR}/boot/README-LightMoss.txt" "$LMB/"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"

IMG="${BINARIES_DIR}/lightmoss-rpminiv2.img"
OUT="${BINARIES_DIR}/lightmoss-rpminiv2-${VERSION}.img.xz"
rm -f "${BINARIES_DIR}"/lightmoss-rpminiv2-*.img.xz
xz -T0 -6 -k -c "$IMG" > "$OUT"
( cd "${BINARIES_DIR}" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "LightMoss image: $OUT"
