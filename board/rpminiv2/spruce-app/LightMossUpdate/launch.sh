#!/bin/sh
# LightMoss Update (Retroid Pocket Mini V2): installs the newest LightMoss
# release from GitHub on the internal storage.
#
# The newest release is the one with the highest version among the
# repository's published releases that carry an image for this board
# (lightmoss-<board>-<version>.img.xz and its .sha256), not GitHub's
# "latest", which a release for another board alone could be.
#
# LightMoss ships this app and puts it on the spruce card at every start
# (/usr/libexec/lightmoss/spruce-app), so edits made here are overwritten.
#
# It downloads the release's image to the root of the spruce card, checks it
# against the release's .sha256 and hands it to lightmoss-update, which writes
# it to the system copy that is not running and makes that the next start's.
# The device then restarts into the new LightMoss; if it does not start,
# OpenABL goes back to the old copy by itself, and this app says so the next
# time it is opened. Nothing needs the charger: the running copy is never
# written.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /usr/libexec/lightmoss/lib.sh

# One key of /etc/os-release (read, not sourced into spruce's environment).
osr() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" /etc/os-release; }

SD_ROOT=/mnt/SDCARD
BOARD="$(osr LIGHTMOSS_BOARD)"; BOARD="${BOARD:-rpminiv2}"
IMG="$SD_ROOT/LightMoss-update.img.xz"
REPO="$(osr LIGHTMOSS_REPO)"; REPO="${REPO:-MarsInsanity/LightMoss}"
API="https://api.github.com/repos/$REPO/releases?per_page=30"
INSTALLED="$(osr LIGHTMOSS_VERSION)"; INSTALLED="${INSTALLED:-unknown}"
JSON=/tmp/lightmoss-releases.json
REL=/tmp/lightmoss-release.json

# No sleep or idle power-off while this runs, as in spruce's firmware updater.
killall -q idlemon 2>/dev/null
killall -q idle_watchdog.sh 2>/dev/null
start_pyui_message_writer

show() { log_and_display_message "$1"; }
bail() { show "$1"; sleep 6; exit 1; }

restart() {
	sync
	/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
	exit 0
}

# A version as one comparable number: v1.2.3 is 1.2.3.0; a development build
# made N commits after it (git describe: v1.2.3-N-g<commit>, maybe with a
# -<date> or -dirty after it) is 1.2.3.N, newer than the release. Nothing
# for anything else (a bare commit, a branch build).
vnum() {
	printf '%s' "$1" |
		sed -n 's/^[vV]\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(-\([0-9][0-9]*\)-g[0-9a-f][0-9a-f]*\)\{0,1\}\(-[0-9]\{8\}\)\{0,1\}\(-dirty\)\{0,1\}$/\1 \2 \3 \5/p' |
		awk '{ printf "%d%04d%04d%04d", $1, $2, $3, ($4 == "" ? 0 : $4) }'
}

# The clock comes up wrong on these devices (years off, until the network
# sets it), and GitHub's certificates do not check against a wrong clock.
# Plausible: not before this LightMoss was built, nor ten years after.
clock_ok() {
	_now="$(date +%s)"
	_built="$(stat -c %Y /usr/lib/os-release 2>/dev/null)"; _built="${_built:-0}"
	[ "$_now" -ge $(( _built - 86400 )) ] && [ "$_now" -le $(( _built + 315360000 )) ]
}

[ "$(osr ID)" = lightmoss ] || bail "This app updates LightMoss, and this device runs something else."
mountpoint -q /boot || bail "LightMoss's boot partition is not mounted, so no update can be set up."
case "$(lm_slot)" in
	1|2) ;;
	*)
		show "This LightMoss runs from the card, which has room for one copy of it, the one running. Updates over the air need LightMoss on the internal storage (two copies: one runs while the other is updated), so this app cannot update the card.\n\nTo get a newer LightMoss: install it on the internal storage (README-LightMoss.txt on the card's LMBOOT), or make a new card. Writing a new card image over this card erases its SPRUCEOS partition (games, saves): copy them off first.\n\nPress A to close."
		acknowledge
		exit 0 ;;
esac

# What the last update did, once.
if [ -f /boot/lightmoss-update-failed ]; then
	show "The last LightMoss update did not start, so the device went back to the LightMoss it had before.\n\n$(cat /boot/lightmoss-update-failed)\n\nPress A to go on."
	rm -f /boot/lightmoss-update-failed
	sync
	acknowledge
fi

# An image an earlier run left behind (a partial download resumes below).
rm -f "$IMG"

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != 1 ]; then
	bail "WiFi is off, so no LightMoss update can be looked for. Turn WiFi on in spruce's settings and try again."
fi

# The clock first: spruce's time sync (NTP, or a web server's Date header
# when NTP is blocked) unless systemd-timesyncd already set it.
if [ ! -e /run/systemd/timesync/synchronized ] && ! clock_ok; then
	show "Setting the clock..."
	if [ -f /mnt/SDCARD/spruce/scripts/network/timeFunctions.sh ]; then
		. /mnt/SDCARD/spruce/scripts/network/timeFunctions.sh
		sync_system_time --again 2>/dev/null
	fi
	n=0
	while ! clock_ok && [ ! -e /run/systemd/timesync/synchronized ] && [ "$n" -lt 15 ]; do
		sleep 2; n=$((n + 1))
	done
	clock_ok || log_message "LightMoss Update: the clock still reads $(date -u '+%Y-%m-%d %H:%M') UTC"
fi

show "Looking for a LightMoss update on github.com/$REPO..."
# A few tries: the WiFi may drop a request or two.
n=0
while :; do
	rm -f "$JSON"
	CODE="$(curl -sSL -m 20 -o "$JSON" -w '%{http_code}' "$API" 2>/tmp/lightmoss-curl.log)"
	RC=$?
	case "$CODE" in 200|404) break ;; esac
	log_message "LightMoss Update: GitHub API: HTTP ${CODE:-none}, curl $RC: $(tail -n 1 /tmp/lightmoss-curl.log 2>/dev/null)"
	n=$((n + 1))
	if [ "$n" -ge 4 ]; then
		case "$RC" in
			35|51|58|59|60|77) bail "Could not check GitHub's certificate. The device's date and time are probably wrong ($(date '+%Y-%m-%d %H:%M')): set them in spruce's settings (or let it sync over WiFi) and try again." ;;
		esac
		[ "$CODE" = 403 ] && bail "GitHub turned the request down (too many requests from this network for now). Try again in an hour."
		bail "Could not reach GitHub to look for a LightMoss update. Check the WiFi connection (and the date and time) and try again."
	fi
	sleep 3
done
[ "$CODE" = 404 ] && bail "github.com/$REPO has no LightMoss releases."

# The published releases (not drafts or pre-releases) that have an image for
# this board, newest first as GitHub lists them; of those, the highest
# version (or, when none has a version number, the newest).
PFX="lightmoss-$BOARD-"
TAGS="$(jq -r --arg p "$PFX" '.[]? | select((.draft | not) and (.prerelease | not)) |
	select(any(.assets[]?; (.name | startswith($p)) and (.name | endswith(".img.xz")))) | .tag_name' "$JSON" 2>/dev/null)"
TAG=""; BEST=""
for t in $TAGS; do
	[ -n "$TAG" ] || TAG="$t"
	v="$(vnum "$t")"
	[ -n "$v" ] || continue
	if [ -z "$BEST" ] || [ "$v" -gt "$BEST" ]; then BEST="$v"; TAG="$t"; fi
done
[ -n "$TAG" ] || bail "github.com/$REPO has no LightMoss release for this device ($BOARD) yet."
jq --arg t "$TAG" 'first(.[] | select(.tag_name == $t))' "$JSON" > "$REL"

NAME="$(jq -r --arg p "$PFX" '.assets[]? | select(.name | startswith($p) and endswith(".img.xz")) | .name' "$REL" | head -n 1)"
URL="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .browser_download_url' "$REL" | head -n 1)"
SIZE="$(jq -r --arg n "$NAME" '.assets[]? | select(.name == $n) | .size' "$REL" | head -n 1)"
SUM_URL="$(jq -r --arg n "$NAME.sha256" '.assets[]? | select(.name == $n) | .browser_download_url' "$REL" | head -n 1)"
log_message "LightMoss Update: installed $INSTALLED, newest for $BOARD $TAG, asset $NAME ($SIZE bytes)"
[ -n "$NAME" ] && [ -n "$URL" ] && [ "${SIZE:-0}" -gt 0 ] 2>/dev/null ||
	bail "The newest LightMoss release ($TAG) has no image for this device."
[ -n "$SUM_URL" ] ||
	bail "The newest LightMoss release ($TAG) has no checksum (.sha256), so its download could not be checked. It is not installed."

if [ "$TAG" = "$INSTALLED" ]; then
	show "This device has LightMoss $INSTALLED, the newest release. Press A to close."
	acknowledge
	exit 0
fi
HAVE="$(vnum "$INSTALLED")"; LATEST="$(vnum "$TAG")"
NOTE=""
if [ -n "$HAVE" ] && [ -n "$LATEST" ] && [ "$HAVE" -ge "$LATEST" ]; then
	show "This device has LightMoss $INSTALLED, a build of $TAG or newer, the newest release. Press A to close."
	acknowledge
	exit 0
elif [ -z "$HAVE" ]; then
	NOTE="\n\n(This device has a development build, which may be newer than $TAG.)"
fi

# The partial download of this version, if an earlier run left one; any
# other version's goes.
PART="$SD_ROOT/LightMoss-$TAG.img.xz.part"
for f in "$SD_ROOT"/LightMoss-*.img.xz.part; do
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
	show "LightMoss $TAG is available (this device has $INSTALLED). $GOT_MB of its $MB MB are already downloaded.\n\nThe rest downloads now, then it is installed and the device restarts into it. spruce, your games and your settings stay as they are.$NOTE\n\nPress A to continue, or B to cancel."
else
	show "LightMoss $TAG is available (this device has $INSTALLED).\n\nIt downloads now ($MB MB), then it is installed and the device restarts into it. spruce, your games and your settings stay as they are.$NOTE\n\nPress A to download it, or B to cancel."
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

show "Installing LightMoss $TAG. This takes a few minutes: do not power off.\n\n(The LightMoss you have now stays as it is until the new one has started.)"
if /usr/bin/lightmoss-update -y "$IMG" > /tmp/lightmoss-update.log 2>&1; then
	rm -f "$IMG"
	cp -f /tmp/lightmoss-update.log /boot/lightmoss-update.log 2>/dev/null
	sync
	log_message "LightMoss Update: $TAG installed, restarting"
	show "LightMoss $TAG is installed. The device now restarts into it."
	sleep 4
	restart
fi
rm -f "$IMG"
cp -f /tmp/lightmoss-update.log /boot/lightmoss-update.log 2>/dev/null
sync
WHY="$(sed -n 's/^lightmoss-update: //p' /tmp/lightmoss-update.log | tail -n 1)"
WHY="${WHY:-$(tail -n 1 /tmp/lightmoss-update.log)}"
log_message "LightMoss Update: lightmoss-update failed: $WHY"
bail "LightMoss $TAG could not be installed:\n\n$WHY\n\nThe LightMoss you have is unchanged and starts as before (the log is lightmoss-update.log on LMBOOT)."
