#!/bin/sh
# LightMoss Kernel: chooses the kernel LightMoss starts on the R36S, 4.4 (its
# standard kernel) or the optional BSP 5.10 kernel with the Mali g29p1 blob
# (Vulkan), and under 5.10 the opt-in CPU overclock, then restarts into it.
#
# LightMoss ships this app and puts it on the spruce card at every start
# (/usr/libexec/lightmoss/spruce-app), so edits made here are overwritten.
#
# The choice is the file lightmoss-kernel-5.10 on LightMoss's BOOT, which
# boot.ini reads (updates keep it), and lightmoss-cpu-overclock next to it
# for the overclock (5.10's -oc dtbs: 1416/1512 MHz at 1.4 V; without it the
# kernel holds the CPU at Rockchip's 1248/1296 MHz). Every 5.10 start is a
# try: boot.ini writes lightmoss-kernel-5.10-trying first and starts 4.4
# while it is there; LightMoss removes it once spruce has run on 5.10 for 3
# minutes (lightmoss-kernel-ok). So if 5.10 stops, freezes or is switched off
# before then, the next start is 4.4, and this app says so and offers another
# try (without the overclock, if that was on).

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

FLAG=/boot/lightmoss-kernel-5.10
TRY=/boot/lightmoss-kernel-5.10-trying
OC=/boot/lightmoss-cpu-overclock

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
# The running kernel has the overclock when boot.ini gave it max_cpufreq=.
RUNNING_OC=no
grep -q 'max_cpufreq=' /proc/cmdline 2>/dev/null && RUNNING_OC=yes
yn() { [ -f "$1" ] && echo yes || echo no; }
log_message "LightMoss Kernel: running $(uname -r), overclock $RUNNING_OC; 5.10 chosen: $(yn "$FLAG"); overclock chosen: $(yn "$OC"); try marker: $(yn "$TRY")"

if [ "$RUNNING" = 4.4 ] && [ -f "$FLAG" ] && [ -f "$TRY" ]; then
	if [ -f "$OC" ]; then
		show "The last 5.10 start, with the CPU overclock, did not keep spruce running for 3 minutes (it stopped, froze or was switched off), so LightMoss started its 4.4 kernel instead.\n\nPress A to try 5.10 again without the overclock, or B to stay on 4.4."
		if confirm; then
			rm -f "$OC" "$TRY"
			restart
		fi
	else
		show "The last 5.10 start did not keep spruce running for 3 minutes (it stopped, froze or was switched off), so LightMoss started its 4.4 kernel instead.\n\nPress A to try 5.10 again (turn the volume down first), or B to stay on 4.4."
		if confirm; then
			rm -f "$TRY"
			restart
		fi
	fi
	rm -f "$FLAG" "$TRY" "$OC"
	sync
	show "LightMoss stays on its 4.4 kernel."
	sleep 3
	exit 0
fi

if [ "$RUNNING" = 4.4 ]; then
	show "Kernel: 4.4, LightMoss's standard kernel.\n\nSwitch to the 5.10 kernel? It is experimental and adds Vulkan (PPSSPP, RetroArch). Turn the volume down first: another R36S clone had a loud speaker pop on its first 5.10 start. If 5.10 does not keep spruce running for 3 minutes, the next start goes back to 4.4 by itself.\n\nPress A to switch and restart, or B to cancel."
	confirm || exit 0
	rm -f "$TRY" "$OC"
	: > "$FLAG" || bail "Could not write to LightMoss's BOOT partition."
	restart
fi

# Under 5.10: the overclock first, then the way back to 4.4. A choice made
# here restarts into 5.10 straight away, so this start, which is evidently
# working, no longer needs its try marker.
if [ "$RUNNING_OC" = yes ]; then
	show "Kernel: 5.10 (experimental, with Vulkan), with the CPU overclock: the CPU runs at spruce's 1416 MHz (1512 MHz in Overclock) at 1.4 V.\n\nPress A to turn the overclock off and restart, or B for the other choice."
	if confirm; then
		rm -f "$OC" "$TRY"
		restart
	fi
else
	show "Kernel: 5.10 (experimental, with Vulkan). The CPU runs at Rockchip's 1248-1296 MHz, whatever spruce's CPU mode says.\n\nTurn on the CPU overclock? The CPU then runs at spruce's 1416 MHz (1512 MHz in Overclock), at 1.4 V instead of 1.35 V. Experimental: more heat, battery use and long-term wear, and some units freeze with it (a start that freezes goes back to 4.4 by itself).\n\nPress A to turn it on and restart, or B for the other choice."
	if confirm; then
		rm -f "$TRY"
		: > "$OC" || bail "Could not write to LightMoss's BOOT partition."
		restart
	fi
fi

show "Switch back to LightMoss's standard 4.4 kernel?\n\nPress A to switch and restart, or B to cancel."
confirm || exit 0
rm -f "$FLAG" "$TRY" "$OC"
restart
