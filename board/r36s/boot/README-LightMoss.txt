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
Switcher, for example). If it stays on, create an empty file named
"lightmoss-ledtest" in this folder and boot: before spruce starts, the screen
counts through 7 numbered steps, each trying the LED's pins another way. Note
the step numbers at which the LED is off. The file deletes itself (the test
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

Installing or updating the eMMC without SSH
-------------------------------------------
Rename a LightMoss release image (lightmoss-r36s-<version>.img.xz) to
    LightMoss.rkimg

First install (EmuELEC still on the eMMC): copy LightMoss.rkimg to the spruce
card (TF2), create an empty file named
    lightmoss-install
in this BOOT folder, keep this card in TF1, connect the charger, switch on.

Updates (LightMoss already on the eMMC): copy LightMoss.rkimg to a FAT32 card
in TF1, connect the charger, switch on. (With it on the spruce card in TF2
instead, also put an empty lightmoss-install on the card in TF1.)

The image is checked and written to the internal eMMC (an existing LightMoss
keeps SPRUCEOS and its settings), LightMoss.rkimg is renamed
LightMoss.rkimg.done, lightmoss-install is removed, and the device restarts.

If the eMMC shows a "no SD card" screen and powers off when TF1 is empty, it
holds an older LightMoss: update it the same way as a first install (this
card in TF1, LightMoss.rkimg on the spruce card, lightmoss-install here).
Take the LightMoss card out of TF1 to boot from the eMMC. Without the charger
connected nothing is written.

From SSH instead: boot a card with the newer LightMoss in TF1 and run
lightmoss-install-emmc again: it replaces the system and keeps SPRUCEOS.
