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
