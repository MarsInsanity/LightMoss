#!/bin/sh
# LightMoss Report: writes how this R36S runs to the folder LightMoss-Report
# on the spruce card, for reading on a PC (and for sending to whoever is
# looking into a problem). Two things, both done by /usr/bin/lightmoss-report:
#
#   A report now: the kernel, the chip's grade, the CPU / GPU / memory clocks
#   with a CPU speed test, temperatures, the GPU driver, the PSP / Dreamcast /
#   N64 settings on the card, and the logs of this start and the previous one.
#
#   The game recorder: for the next 10 minutes, every 5 seconds, the clocks,
#   temperatures, how busy each CPU core and the GPU are, and which threads
#   use the CPU. Started here, it keeps running while a game is played, and
#   shows what limits that game.
#
# LightMoss ships this app and puts it on the spruce card at every start
# (/usr/libexec/lightmoss/spruce-app), so edits made here are overwritten.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

REPORT=/usr/bin/lightmoss-report
UNIT=lightmoss-report-watch
SECONDS_TO_WATCH=600

start_pyui_message_writer

show() { log_and_display_message "$1"; }
bail() { show "$1"; sleep 6; exit 1; }

grep -q '^ID=lightmoss$' /etc/os-release 2>/dev/null ||
	bail "This app reports on LightMoss, and this device runs something else."
[ -x "$REPORT" ] ||
	bail "This LightMoss has no report tool. Update LightMoss first (LightMoss Update), then try again."

show "LightMoss Report writes how this device runs to the folder LightMoss-Report on the SD card.\n\nPress A to write a report now (about a minute: it also tests the CPU at each of its speeds), or B for the game recorder."
if confirm; then
	show "Writing the report. This takes about a minute..."
	if out="$("$REPORT" now 2>/dev/null)" && [ -n "$out" ]; then
		log_message "LightMoss Report: wrote $out"
		show "Done. The report is in LightMoss-Report/${out##*/} on the SD card."
	else
		show "The report could not be written (is the SD card full?)."
	fi
	sleep 6
	exit 0
fi

if systemctl is-active --quiet "$UNIT.service" 2>/dev/null; then
	show "The game recorder is already running. It stops by itself and leaves a watch file in LightMoss-Report on the SD card."
	sleep 6
	exit 0
fi

show "Game recorder: for the next 10 minutes it notes the clocks, temperatures and what uses the CPU, to show what limits a game.\n\nPress A to start it, then start the game right away and play for a few minutes. Press B to cancel."
confirm || exit 0
# Its own unit, so it outlives this app and runs next to the game.
systemd-run --quiet --collect --unit="$UNIT" "$REPORT" watch "$SECONDS_TO_WATCH" 2>/dev/null ||
	{ setsid "$REPORT" watch "$SECONDS_TO_WATCH" > /dev/null 2>&1 & }
log_message "LightMoss Report: recording for $SECONDS_TO_WATCH s"
show "Recording for 10 minutes. Start the game now.\n\nAfterwards the recording is a watch file in LightMoss-Report on the SD card."
sleep 5
exit 0
