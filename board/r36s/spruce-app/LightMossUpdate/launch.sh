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
# lightmoss-update on LightMoss's BOOT (so the image goes on the disk the
# system runs from, not on the eMMC) and restarts. LightMoss's updater, the
# initramfs every start goes through, writes it in place, with the charger
# connected only, and restarts again into the new LightMoss.

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

# Images an earlier update installed (or could not use). A partial download
# (LightMoss-<version>.rkimg.part) is kept: it resumes below.
rm -f "$IMG.done" "$IMG.bad" "$IMG.part"

# An update already downloaded, waiting for the charger.
if [ -f "$FLAG" ] && [ -f "$IMG" ]; then
	offer_restart "A LightMoss update is downloaded and waiting. It installs when the device starts with the charger connected.\n\nConnect the charger and press A to restart and install it now, or B to cancel."
fi

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != 1 ]; then
	bail "WiFi is off, so no LightMoss update can be looked for. Turn WiFi on in spruce's settings and try again."
fi

show "Looking for a LightMoss update on github.com/$REPO..."
# A few tries: the WiFi may drop a request or two.
n=0
while :; do
	rm -f "$JSON"
	CODE="$(curl -sSL -m 20 -o "$JSON" -w '%{http_code}' "$API" 2>/dev/null)"
	case "$CODE" in 200|404) break ;; esac
	n=$((n + 1))
	[ "$n" -ge 4 ] && bail "Could not reach GitHub to look for a LightMoss update. Check the WiFi connection (and the date and time) and try again."
	sleep 3
done
[ "$CODE" = 404 ] && bail "github.com/$REPO has no LightMoss release yet."

TAG="$(jq -r '.tag_name // empty' "$JSON")"
NAME="$(jq -r '.assets[]? | select(.name | startswith("lightmoss-r36s-") and endswith(".img.xz")) | .name' "$JSON" | head -n 1)"
URL="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .browser_download_url' "$JSON" | head -n 1)"
SIZE="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .size' "$JSON" | head -n 1)"
SUM_URL="$(jq -r --arg n "$NAME.sha256" '.assets[]? | select(.name == $n) | .browser_download_url' "$JSON" | head -n 1)"
log_message "LightMoss Update: installed $INSTALLED, latest $TAG, asset $NAME ($SIZE bytes)"
[ -n "$TAG" ] && [ -n "$NAME" ] && [ -n "$URL" ] ||
	bail "The newest LightMoss release ($TAG) has no image for this device."
[ -n "$SUM_URL" ] ||
	bail "The newest LightMoss release ($TAG) has no checksum (.sha256), so its download could not be checked. It is not installed."

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

# The partial download of this version, if an earlier run left one; any
# other version's goes.
PART="$SD_ROOT/LightMoss-$TAG.rkimg.part"
for f in "$SD_ROOT"/LightMoss-*.rkimg.part; do
	[ -f "$f" ] && [ "$f" != "$PART" ] && rm -f "$f"
done
partsize() { ls -ln "$PART" 2>/dev/null | awk '{ print $5 }'; }
HAVE_BYTES="$(partsize)"; HAVE_BYTES="${HAVE_BYTES:-0}"

MB=$(( ${SIZE:-0} / 1048576 ))
FREE_MB="$(df -m "$SD_ROOT" | awk 'END { print $4 }')"
[ "${FREE_MB:-0}" -ge $(( (SIZE - HAVE_BYTES) / 1048576 + 20 )) ] ||
	bail "The spruce card needs $(( (SIZE - HAVE_BYTES) / 1048576 + 20 )) MB free for the update and has ${FREE_MB} MB."

if [ "$HAVE_BYTES" -gt 0 ]; then
	GOT_MB=$((HAVE_BYTES / 1048576))
	show "LightMoss $TAG is available (this device has $INSTALLED). $GOT_MB of its $MB MB are already downloaded.\n\nThe rest downloads now, and it installs on $WHERE the next time the device starts with the charger connected. spruce, your games and your settings stay as they are.\n\nPress A to continue the download, or B to cancel."
else
	show "LightMoss $TAG is available (this device has $INSTALLED).\n\nIt downloads now ($MB MB) and installs on $WHERE the next time the device starts with the charger connected. spruce, your games and your settings stay as they are.\n\nPress A to download it, or B to cancel."
fi
confirm || exit 0

# Resumable, for patchy WiFi: a dropped or stalled transfer (under 1 KB/s for
# 30 s) picks up where it stopped, up to 8 times now, and the partial file is
# kept for the next run. Certificates are checked against spruce's bundle;
# only a TLS failure (a wrong clock, say) falls back to no check, as spruce's
# own downloads do: the checksum below, fetched over a checked connection
# only, decides whether the file is good.
download_image() {
	tries=0; insecure=""
	while :; do
		have="$(partsize)"; have="${have:-0}"
		[ "$have" -ge "$SIZE" ] && return 0
		curl -sS -L -f $insecure -C - --connect-timeout 15 --speed-limit 1024 --speed-time 30 \
			-o "$PART" "$URL" 2>/tmp/lightmoss-curl.log &
		pid=$!
		while kill -0 "$pid" 2>/dev/null; do
			have="$(partsize)"; have="${have:-0}"
			pct=$((have * 100 / SIZE)); [ "$pct" -gt 100 ] && pct=100
			display_text_with_percentage_bar "Downloading LightMoss $TAG" "$pct" "$((have / 1048576)) MB / $MB MB"
			sleep 0.5
		done
		wait "$pid"; rc=$?
		[ "$rc" = 0 ] && return 0
		log_message "LightMoss Update: download stopped at $(partsize) bytes (curl $rc: $(tail -n 1 /tmp/lightmoss-curl.log))"
		case "$rc" in
			35|51|58|59|60|77) if [ -z "$insecure" ]; then insecure=-k; continue; fi ;;
			33) rm -f "$PART" ;;   # the server would not resume: start over
		esac
		tries=$((tries + 1))
		[ "$tries" -ge 8 ] && return 1
		show "The WiFi connection dropped. Resuming the download ($((tries + 1)) of 8)..."
		sleep 5
	done
}
download_image ||
	bail "LightMoss $TAG could not be downloaded completely, the WiFi kept dropping. What came through is kept: open LightMoss Update again to continue from there."

# The checksum comes over a verified connection only, so that it and the image
# are never both from an unchecked one.
show "Checking the download..."
WANT=""; n=0
while [ -z "$WANT" ] && [ "$n" -lt 5 ]; do
	WANT="$(curl -sSfL -m 20 "$SUM_URL" 2>/dev/null | awk 'NR == 1 { print $1 }')"
	[ -n "$WANT" ] || { n=$((n + 1)); sleep 3; }
done
[ -n "$WANT" ] ||
	bail "Could not fetch the release's checksum, so the download cannot be checked yet. It is kept: open LightMoss Update again to check it and go on."
if [ "$(sha256sum "$PART" | cut -d' ' -f1)" != "$WANT" ]; then
	rm -f "$PART"
	bail "The download was damaged on the way and has been deleted. Please try again."
fi
mv -f "$PART" "$IMG"
: > "$FLAG"
sync
log_message "LightMoss Update: $TAG ready to install on $WHERE"

if charger_online; then
	show "LightMoss $TAG is downloaded. The device now restarts to install it on $WHERE: keep the charger connected and do not power off. It takes a few minutes."
	sleep 5
	restart
fi
offer_restart "LightMoss $TAG is downloaded. It installs the next time the device starts with the charger connected.\n\nConnect the charger and press A to restart and install it now, or B to install it later."
