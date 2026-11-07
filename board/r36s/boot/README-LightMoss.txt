LightMoss
=========

A minimal base OS for spruce on the R36S clone (G80CA-MB). It boots, mounts
the spruce card at /mnt/SDCARD and starts spruce. spruce is found on:
  - the card in the other slot (TF2), partition 1, or
  - a FAT32/exFAT partition on this card or the eMMC, after the system ones
    (the first boot adds an empty exFAT partition, "SPRUCEOS", in the space
    left behind the system: copy spruce onto it to run from one card).
With no spruce anywhere, it says so on the screen and powers off.

Logs
----
Create an empty file named "lightmoss-debug" (no extension) in this folder,
put the card back and boot. The kernel and systemd then print on the screen,
and each boot writes a folder under "logs" here with the previous and the
current boot's journal, dmesg and a system summary (the five newest are kept).
Delete the file to go back to a quiet boot.

Blue LED test
-------------
The blue LED should be off, lit only while spruce "vibrates" (the Game
Switcher, for example). If it does something else, create an empty file named
"lightmoss-ledtest" in this folder and boot: before spruce starts, the screen
counts through 7 numbered steps, each trying the LED's pins another way. Note
the step numbers at which the LED is on. The file deletes itself (the test
runs once) and the details go to lightmoss-ledtest.txt here.

SSH
---
spruce's Network Settings turns SSH on and off. Log in as "spruce" (or
"root"), password "happygaming".

Installing to the internal eMMC
-------------------------------
Boot LightMoss from TF1, then over SSH run:
    lightmoss-install-emmc
It copies this system to the eMMC (everything on the eMMC is erased) and
gives it its own disk ID. Afterwards, with no LightMoss card in TF1, the
device boots from the eMMC; a LightMoss card in TF1 still takes precedence.

Updates over WiFi
-----------------
spruce's app list has "LightMoss Update" (LightMoss puts it on the spruce
card). It installs the newest LightMoss release from GitHub on whatever
LightMoss runs from (the eMMC, or this card), keeping spruce and its settings.
It needs WiFi, and the charger connected when the device restarts to install.

Installing or updating the eMMC without SSH
-------------------------------------------
Put a LightMoss release image (lightmoss-r36s-<version>.img.xz) on any card,
FAT32 or exFAT (the spruce card will do), renamed so that its name ends in
    .rkimg
for example LightMoss.rkimg. Connect the charger and switch on. That is all.

At every start with the charger connected, LightMoss looks for such a file
and writes it to the internal eMMC: a LightMoss already there keeps SPRUCEOS
and its settings; anything else (EmuELEC) is replaced. The file is then
renamed <name>.rkimg.done and the device restarts. Take this card out of TF1
to boot from the eMMC. Without the charger nothing happens; a file that is
not a usable image is renamed <name>.rkimg.bad.

If the eMMC shows a "no SD card" screen and powers off when TF1 is empty, it
holds an older LightMoss: start this card in TF1, with an .rkimg on a card
and the charger connected.

From SSH instead: boot a card with the newer LightMoss in TF1 and run
lightmoss-install-emmc again: it replaces the system and keeps SPRUCEOS.

If the eMMC does not start
--------------------------
1. Create an empty "lightmoss-debug" here and install as above. The eMMC
   then also starts with lightmoss-debug: its kernel prints on the screen (a
   photo of where it stops helps).
2. Take this card out, try starting from the eMMC, power off.
3. Put this card back in TF1 and start. Its logs (logs/<newest> here) then
   include emmc.txt: the eMMC's boot loader against this card's, its
   partitions, how far U-Boot got with it, and its own last boot's journal
   (emmc-last-boot.log). lightmoss-update.log here says what the update did.
