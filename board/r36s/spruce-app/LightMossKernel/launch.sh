#!/bin/sh
# LightMoss Kernel: chooses the kernel LightMoss starts on the R36S, 4.4 (its
# standard kernel) or the optional BSP 5.10 kernel with the Mali g29p1 blob
# (Vulkan), and restarts into it.
#
# LightMoss ships this app and puts it on the spruce card at every start
# (/usr/libexec/lightmoss/spruce-app), so edits made here are overwritten.
#
# The choice is the file lightmoss-kernel-5.10 on LightMoss's BOOT, which
# boot.ini reads (updates keep it). Every 5.10 start is a try: boot.ini
# writes lightmoss-kernel-5.10-trying first and starts 4.4 while it is there;
# LightMoss removes it once spruce is up on 5.10 (lightmoss-kernel-ok). So if
# 5.10 does not get spruce running for 3 minutes, the next start is 4.4, and this app says so
# and offers another try.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

FLAG=/boot/lightmoss-kernel-5.10
TRY=/boot/lightmoss-kernel-5.10-trying

start_pyui_message_writer

show() { log_and_display_message "$1"; }
bail() { show "$1"; sleep 6; exit 1; }

restart() {
	sync
	/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
	exit 0
}

grep -q '^ID=lightmoss$' /etc/os-release 2>/dev/null ||
	bail "This app chooses LightMoss's kernel, and this device runs something else."
mountpoint -q /boot || bail "LightMoss's BOOT partition is not mounted, so the kernel cannot be chosen."
[ -f /boot/Image-5.10 ] ||
	bail "This LightMoss has no 5.10 kernel. Update LightMoss first (LightMoss Update), then try again."

case "$(uname -r)" in
5.10.*) RUNNING=5.10 ;;
*) RUNNING=4.4 ;;
esac
log_message "LightMoss Kernel: running $(uname -r); 5.10 chosen: $([ -f "$FLAG" ] && echo yes || echo no); try marker: $([ -f "$TRY" ] && echo yes || echo no)"

if [ "$RUNNING" = 4.4 ] && [ -f "$FLAG" ] && [ -f "$TRY" ]; then
	show "The last 5.10 start did not keep spruce running for 3 minutes (it stopped, froze or was switched off), so LightMoss started its 4.4 kernel instead.\n\nPress A to try 5.10 again (turn the volume down first), or B to stay on 4.4."
	if confirm; then
		rm -f "$TRY"
		restart
	fi
	rm -f "$FLAG" "$TRY"
	sync
	show "LightMoss stays on its 4.4 kernel."
	sleep 3
	exit 0
fi

if [ "$RUNNING" = 4.4 ]; then
	show "Kernel: 4.4, LightMoss's standard kernel.\n\nSwitch to the 5.10 kernel? It is experimental and adds Vulkan (PPSSPP, RetroArch). Turn the volume down first: another R36S clone had a loud speaker pop on its first 5.10 start. If 5.10 does not get to spruce, the next start goes back to 4.4 by itself.\n\nPress A to switch and restart, or B to cancel."
	confirm || exit 0
	rm -f "$TRY"
	: > "$FLAG" || bail "Could not write to LightMoss's BOOT partition."
	restart
fi

show "Kernel: 5.10 (experimental, with Vulkan).\n\nSwitch back to LightMoss's standard 4.4 kernel?\n\nPress A to switch and restart, or B to cancel."
confirm || exit 0
rm -f "$FLAG" "$TRY"
restart
