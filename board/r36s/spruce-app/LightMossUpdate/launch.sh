#!/bin/sh
# LightMoss Update: installs the newest LightMoss release from GitHub on the
# disk LightMoss runs from (the internal eMMC, or the card in TF1), keeping
# SPRUCEOS, spruce and the device's settings.
#
# LightMoss ships this app and puts it on the spruce card at every start
# (/usr/libexec/lightmoss/spruce-app), so edits made here are overwritten.
#
# It downloads the release's image to the root of the spruce card as
# LightMoss.rkimg, checks it against the release's .sha256, leaves an empty
# lightmoss-update on LightMoss's BOOT and restarts. boot.ini then starts
# LightMoss's updater (initramfs), which writes the image in place, with the
# charger connected only, and restarts again into the new LightMoss.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /usr/libexec/lightmoss/lib.sh

# One key of /etc/os-release (read, not sourced into spruce's environment).
osr() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" /etc/os-release; }

SD_ROOT=/mnt/SDCARD
IMG="$SD_ROOT/LightMoss.rkimg"
FLAG=/boot/lightmoss-update
REPO="$(osr LIGHTMOSS_REPO)"; REPO="${REPO:-MarsInsanity/LightMoss}"
API="https://api.github.com/repos/$REPO/releases/latest"
INSTALLED="$(osr LIGHTMOSS_VERSION)"; INSTALLED="${INSTALLED:-unknown}"
JSON=/tmp/lightmoss-release.json

# No sleep or idle power-off while this runs, as in spruce's firmware updater.
killall -q idlemon 2>/dev/null
killall -q idle_watchdog.sh 2>/dev/null
start_pyui_message_writer

show() { log_and_display_message "$1"; }
bail() { show "$1"; sleep 6; exit 1; }

charger_online() {
	for f in /sys/class/power_supply/*/online; do
		[ "$(cat "$f" 2>/dev/null)" = 1 ] && return 0
	done
	return 1
}

restart() {
	sync
	/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
	exit 0
}

# Ask to restart into the updater now; without the charger it would only say
# so and start as usual, so insist on it.
offer_restart() {
	show "$1"
	confirm || exit 0
	charger_online || bail "No charger detected. The update installs the next time the device starts with the charger connected."
	restart
}

# The 1.2.3 of v1.2.3 as one comparable number, or nothing for a build that
# is not a release (a commit, a branch build).
vnum() {
	printf '%s' "$1" | sed -n 's/^[vV]\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)$/\1 \2 \3/p' |
		awk '{ printf "%d%04d%04d", $1, $2, $3 }'
}

[ "$(osr ID)" = lightmoss ] || bail "This app updates LightMoss, and this device runs something else."
mountpoint -q /boot || bail "LightMoss's BOOT partition is not mounted, so no update can be set up."
if [ "$(lm_disk_type "$(lm_root_disk)")" = MMC ]; then
	WHERE="the internal eMMC"
else
	WHERE="the card in TF1"
fi

# Images an earlier update installed (or could not use).
rm -f "$IMG.done" "$IMG.bad" "$IMG.part"

# An update already downloaded, waiting for the charger.
if [ -f "$FLAG" ] && [ -f "$IMG" ]; then
	offer_restart "A LightMoss update is downloaded and waiting. It installs when the device starts with the charger connected.\n\nConnect the charger and press A to restart and install it now, or B to cancel."
fi

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != 1 ]; then
	bail "WiFi is off, so no LightMoss update can be looked for. Turn WiFi on in spruce's settings and try again."
fi

show "Looking for a LightMoss update on github.com/$REPO..."
rm -f "$JSON"
CODE="$(curl -sSL -m 20 -o "$JSON" -w '%{http_code}' "$API" 2>/dev/null)"
case "$CODE" in
	200) ;;
	404) bail "github.com/$REPO has no LightMoss release yet." ;;
	*)   bail "Could not reach GitHub to look for a LightMoss update. Check the WiFi connection (and the date and time) and try again." ;;
esac

TAG="$(jq -r '.tag_name // empty' "$JSON")"
NAME="$(jq -r '.assets[]? | select(.name | startswith("lightmoss-r36s-") and endswith(".img.xz")) | .name' "$JSON" | head -n 1)"
URL="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .browser_download_url' "$JSON" | head -n 1)"
SIZE="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .size' "$JSON" | head -n 1)"
SUM_URL="$(jq -r --arg n "$NAME.sha256" '.assets[]? | select(.name == $n) | .browser_download_url' "$JSON" | head -n 1)"
log_message "LightMoss Update: installed $INSTALLED, latest $TAG, asset $NAME ($SIZE bytes)"
[ -n "$TAG" ] && [ -n "$NAME" ] && [ -n "$URL" ] ||
	bail "The newest LightMoss release ($TAG) has no image for this device."

if [ "$TAG" = "$INSTALLED" ]; then
	show "This device has LightMoss $INSTALLED, the newest release. Press A to close."
	acknowledge
	exit 0
fi
HAVE="$(vnum "$INSTALLED")"; LATEST="$(vnum "$TAG")"
if [ -n "$HAVE" ] && [ -n "$LATEST" ] && [ "$HAVE" -gt "$LATEST" ]; then
	show "This device has LightMoss $INSTALLED, newer than the newest release ($TAG). Press A to close."
	acknowledge
	exit 0
fi

MB=$(( ${SIZE:-0} / 1048576 ))
FREE_MB="$(df -m "$SD_ROOT" | awk 'END { print $4 }')"
[ "${FREE_MB:-0}" -ge $((MB + 20)) ] ||
	bail "The spruce card needs $((MB + 20)) MB free for the update and has ${FREE_MB} MB."

show "LightMoss $TAG is available (this device has $INSTALLED).\n\nIt downloads now ($MB MB) and installs on $WHERE the next time the device starts with the charger connected. spruce, your games and your settings stay as they are.\n\nPress A to download it, or B to cancel."
confirm || exit 0

download_and_display_progress "$URL" "$IMG.part" "LightMoss $TAG" "$SIZE" ||
	bail "LightMoss $TAG could not be downloaded. Please try again later."

# The checksum comes over a verified connection only: the download itself
# may have fallen back to an unverified one (spruce's helper does, for a
# wrong clock), and the two must not be trusted from the same source.
show "Checking the download..."
if [ -n "$SUM_URL" ]; then
	WANT="$(curl -sSfL -m 20 "$SUM_URL" 2>/dev/null | awk 'NR == 1 { print $1 }')"
	if [ -z "$WANT" ]; then
		rm -f "$IMG.part"
		bail "Could not fetch the release's checksum, so the download cannot be checked. Please try again later."
	fi
	if [ "$(sha256sum "$IMG.part" | cut -d' ' -f1)" != "$WANT" ]; then
		rm -f "$IMG.part"
		bail "The download was damaged on the way and has been deleted. Please try again."
	fi
else
	log_message "LightMoss Update: $NAME has no .sha256; only the updater's own xz check applies"
fi
mv -f "$IMG.part" "$IMG"
: > "$FLAG"
sync
log_message "LightMoss Update: $TAG ready to install on $WHERE"

if charger_online; then
	show "LightMoss $TAG is downloaded. The device now restarts to install it on $WHERE: keep the charger connected and do not power off. It takes a few minutes."
	sleep 5
	restart
fi
offer_restart "LightMoss $TAG is downloaded. It installs the next time the device starts with the charger connected.\n\nConnect the charger and press A to restart and install it now, or B to install it later."
