# LightMoss for the Retroid Pocket Mini V2

LightMoss on the **Retroid Pocket Mini V2** (Snapdragon 865 / SM8250, Adreno
650, 1240x1080 AMOLED, 128 GB UFS): a buildroot base OS that boots and hands
off to spruce, installed on the internal storage next to Android. spruce runs
from the card, through the Mini V2 platform of the spruce fork
(MarsInsanity/spruceOS, branch `mofang`).

> **Status: builds, not yet run on a device.** Everything below the line
> "untested" in the table is a design that needs a Mini V2 to confirm.

## What is in it

| | |
|---|---|
| Kernel | Linux 7.2 with ROCKNIX's SM8250 patches and configuration, unchanged ([ROCKNIX/distribution](https://github.com/ROCKNIX/distribution): `projects/ROCKNIX/packages/linux/patches/{mainline,7.2}`, `projects/ROCKNIX/devices/SM8250/patches/linux`, `.../linux/linux.aarch64.conf`), plus LightMoss's two: ROCKNIX's Mini/Mini V2 device trees as a patch, and L2/R2 reported as buttons as well as axes. Built and checked to compile with all 58+2 patches. |
| Boot | [OpenABL](https://github.com/OpenHandheldCollective/OpenABL) v1.2 (the release ROCKNIX ships) in the `abl` partitions boots the kernel through its EFI stub from Boot Loader Specification entries on LightMoss's FAT32 boot partition (`LMBOOT`). No U-Boot, no GRUB. |
| GPU | Mesa freedreno: OpenGL ES, EGL, GBM (64- and 32-bit). No Vulkan yet: buildroot 2025.11's Mesa package has no Turnip option. |
| Firmware | The files ROCKNIX installs for SM8250, from linux-firmware 20260309 (`package/lightmoss-firmware-sm8250`). The DSPs' firmware also comes in a small initramfs with no `/init`, since they start before the root filesystem is mounted. |
| Display | The panel scans out portrait (1080x1240) and is mounted landscape (`rotation = <90>`). LightMoss's SDL2 (64- and 32-bit) turns the primary plane 270 degrees on the SDE rotator (ROCKNIX's DPU patches) and shows programs a 1240x1080 display (`board/rpminiv2/patches/sdl2`), as dArkMoss's SDL does with RGA on the E5 Plus. PyUI (spruce's own SDL) turns its canvas itself. SDL3 (64- and 32-bit) does the same as SDL2 (`board/rpminiv2/patches/sdl3`). `SDL_KMSDRM_PANEL_ROTATION=0` turns it off for a test. |
| Audio | ROCKNIX's Retroid UCM configuration (alsa-ucm-conf 1.2.14 + ROCKNIX's patches). `lightmoss-audio` (a oneshot spruce waits for) sets the card up and routes `hw:0,0` to the speakers or the headphones; `lightmoss-audio-jack` follows the jack's control events from then on, and writes `/run/lightmoss/headphones` for spruce. Kernel patches let a line-out load count as headphones and move an open stream along with its route. `/etc/asound.conf` links to `/run/lightmoss/asound.conf`, where spruce puts its ALSA configuration for programs whose `HOME` has none. |
| Input | ROCKNIX's Retroid gamepad driver (the MCU on a UART), power key; the volume rocker's two keys (gpio-keys and the PMIC's resin) merged into one input device, "LightMoss Volume Keys" (`package/lightmoss-volkeys`), since spruce watches one node. LightMoss's driver patches (`4-lightmoss/0002`, `0020`-`0022`) frame and bound the MCU's packets, put the analog triggers on `ABS_Z`/`ABS_RZ` (0 at rest) and also report them as `BTN_TL2`/`BTN_TR2` (press at 50%, release below 40%). `/sys/module/retroid/parameters/trigger_mode` is 0 for analog (axes and buttons) or 1 for digital (buttons only, the axes held at 0); spruce's *Trigger mode* setting writes it. `swap_xy` (off) swaps the north and west face buttons' codes. Untested. |
| Not yet | Vulkan, SDL3 rotation, the RGB stick LEDs, the fan curve, USB gadget mode. |
| Bluetooth | The QCA6390's (hci_uart). BlueZ 5.79 (`bluetoothctl`; gamepads over HID, HID over GATT and the DualShock 3 sixaxis pairing) and bluez-alsa 4.3.1 for A2DP headsets, both started and stopped by spruce's Bluetooth setting (shipped disabled). Pairings are in `/var/lib/bluetooth`. 32-bit programs cannot play to a headset: the bluealsa ALSA plugin is 64-bit only. Untested. |

## Partitions

On the internal storage, behind Android's `userdata` (OpenABL's convention
for a Linux install: its *Uninstall CFW* removes everything there and gives
the space back to userdata):

| GPT name | Size | |
|---|---|---|
| `userdata` | the rest | Android's data, 4 GiB smaller |
| `LMBOOT` | 512 MiB | FAT32: `loader/loader.conf`, `loader/entries/lightmoss-{1,2}.conf`, `lightmoss-{1,2}/` (kernel, device tree, firmware initramfs), the flags |
| `LMSYS1` | ~1.75 GiB | system copy 1 |
| `LMSYS2` | ~1.75 GiB | system copy 2 |

`LMBOOT` is 512 MiB because OpenABL reads it through the firmware's FAT
driver (edk2's EnhancedFatDxe), which refuses a FAT32 with fewer than 65525
clusters, and the UFS has 4 KiB logical sectors: 256 MiB makes only 65376
(Linux mounts it all the same; the card's `LMBOOT`, with 512-byte sectors,
has 516190). The installer checks the FAT it made from its boot sector
(`lm_fat_info` in `lib.sh`); an install made with the earlier 256 MiB
layout is laid out again in the same 4 GiB by the next run, Android
untouched.

The names avoid Android's `_a`/`_b` suffixes, which Qualcomm's bootloader
treats as slot partitions. The kernel finds its root by PARTUUID; LightMoss's
scripts find their partitions by GPT name on the disk they run from
(`lib.sh`).

The card image (`lightmoss-rpminiv2-<version>.img.xz`) has `LMBOOT` (Microsoft
basic data, so a PC mounts it) and `LMSYS`; its first boot adds `SPRUCEOS`
(exFAT) in the rest of the card.

## Installing

`board/rpminiv2/boot/README-LightMoss.txt` goes on the card and says it for
users. In short:

1. Install OpenABL (skip it if ROCKNIX already did): as root on Android with
   the card's `openabl/backup_abl.sh` then `flash_abl.sh`, or `fastboot flash
   abl_a/abl_b` with an unlocked bootloader.
2. Flash the card image, boot it (OpenABL: Boot mode Linux, Boot source Auto).
3. Create `lightmoss-install` on the card's `LMBOOT`, connect the charger and
   boot it again: `lightmoss-install-internal` clears the start of `userdata`
   and shrinks it by 4 GiB, adds the three partitions, copies the running
   system to `LMSYS1` and checks it, then writes the boot entry
   (`lightmoss-1+3.conf`, kept by `lightmoss-bless`) and `loader.conf`, and
   the device restarts into it. **Android's data is lost** (userdata changes
   size, so Android formats it on its next start, as after `fastboot erase
   userdata`). Over SSH: `lightmoss-install-internal` (charger or 30%
   battery; it logs to the card's `lightmoss-install.log`).
4. Put spruce on the card's `SPRUCEOS` partition, or format the card for spruce.

Nothing boots the internal storage until system copy 1 is complete, so an
install that stops halfway (power cut, error) leaves the card starting, and
the next run finishes it. Run again from a card (OpenABL: *Boot entries*,
the entry marked "(card)"), `lightmoss-install-internal` repairs an install:
system copy 1 becomes the card's system, keeping the installed one's machine
ID, SSH host and user keys, NetworkManager connections and Bluetooth
pairings; an `LMBOOT` or `LMSYS2` without a usable filesystem is formatted.
Another system's partitions behind userdata (ROCKNIX's) are only replaced
with `--replace` (the flag file `lightmoss-install-replace`), which also lays
LightMoss's own out again; when they leave 4 GiB at the end, `userdata`
keeps its size and Android its data.

`board/rpminiv2/test-install-internal.sh` (as root, on a build host) runs
the installer, the flag service, `firstboot` and `mount-spruce` under busybox
against loop devices: a 4 KiB-sector "UFS" with the Mini V2's Android
partition table, interrupted and repaired installs, the old layout,
ROCKNIX's partitions, and LightMoss cards.

## Switching between LightMoss and Android

OpenABL starts its *Boot mode* (Linux: LightMoss). Holding **Volume Up** at
power-on starts the other mode (Android); **Volume Down** opens its menu.
*Boot source* Auto tries the internal storage first, so a LightMoss card
left in the slot boots only when the internal install cannot (a rescue
card).

## Updates: two system copies

The LightMoss Update app looks through the repository's releases for the
newest one with an image for this board (`lightmoss-rpminiv2-<version>.img.xz`
and its `.sha256`), sets the clock first if it is off (spruce's time sync),
downloads the image to the spruce card, checks it and runs `lightmoss-update`.
That writes the image's system to the copy that is **not** running: it first
takes that copy out of OpenABL's entries (and keeps the running copy's), then
writes and reads back the system, checks that the image is for this board,
carries over what `/usr/share/lightmoss/update-keep` lists (machine ID, SSH
host and authorized keys, Wi-Fi networks, Bluetooth pairings, the synced
clock, your own `/etc/lightmoss/update-keep`; also a changed root/spruce
password), puts the boot files on `LMBOOT`, writes the entry with the
**image's own** `boot-entry` (so a release's kernel options come with it) as
`lightmoss-N+3.conf` (three tries, Boot Loader Specification boot counting,
which OpenABL does like systemd-boot) and only then makes it the default. The
device restarts into it.

On such a trial start, `lightmoss-bless` waits for spruce to be up (its boot
jobs started, `spruce-launch.service` active and not restarting) and then
renames the entry `lightmoss-N.conf` (kept). If spruce keeps failing, or is
not up within 10 minutes, it restarts the device instead; a kernel panic
(`panic=10`) or a root that never appears (`rootwait=30`, then a panic)
restarts it too. Each start costs a try, and after three OpenABL boots the old
copy, whose `lightmoss-bless` makes it the default again and leaves
`/boot/lightmoss-update-failed` for the app to report. The running copy is
never written, so the charger is not needed and a power cut at any point
leaves the device starting as before. A kernel that hangs without panicking
still needs the power key held (three times) before OpenABL falls back.

A LightMoss running from a card has one system copy, the running one, so the
app does not update it: install LightMoss on the internal storage, or make a
new card (writing a card image over a card erases its `SPRUCEOS`).

`board/rpminiv2/test-updater.sh` runs all of this on a build host against
loop devices (`sudo board/rpminiv2/test-updater.sh BUSYBOX`), and CI checks
each image with `board/rpminiv2/check-image.sh` before it can be released.

This does not depend on UEFI variables: OpenABL's QSEECOM kernel patch for
them is not in ROCKNIX's SM8250 kernel, so everything goes through files on
`LMBOOT`.

## What needs a device

- OpenABL's boot of `LMBOOT` on UFS, and of the card image's `LMBOOT`.
- The plane rotation: whether ROCKNIX's SDE rotator patches offer 90/270 on
  the primary plane to legacy `drmModeSetCrtc` users, and which way round
  (270 by the panel orientation; `SDL_KMSDRM_PANEL_ROTATION=90` flips it).
- The firmware initramfs (remoteprocs up, audio card present).
- The audio routing of `hw:0,0` to the speakers (`WSA_CODEC_DMA_RX_0 Audio
  Mixer MultiMedia1`) and the jack switching, also while a game plays
  (4-lightmoss/0071 moves the open stream; `journalctl -u lightmoss-audio-jack`).
- The installer on the real UFS (tested on 4 KiB-sector loop devices with
  the device's table), OpenABL reading the 512 MiB FAT32 `LMBOOT` on it, and
  Android formatting the cleared userdata by itself afterwards (Android's
  `fs_mgr` formats a wiped `formattable` userdata; Retroid's fstab is not
  checked).
- Boot counting: OpenABL renaming `lightmoss-N+3.conf` on each try.
- A panic restarting into OpenABL (`panic=10`, not Qualcomm's download mode),
  and `ro` + `systemd-fsck-root` + the remount read-write at every start.
- An update over the air end to end, and the fallback after three failed
  starts (`lightmoss-bless` restarting a copy whose spruce does not come up).

## Building

```bash
make BOARD=rpminiv2
```

The image is `output-rpminiv2/images/lightmoss-rpminiv2-<version>.img.xz`;
the 32-bit runtime builds into `output-rpminiv2-lib32/` first. CI builds it
next to the R36S's on every push, and a release carries both images.
