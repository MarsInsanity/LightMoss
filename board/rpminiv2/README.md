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
| Input | ROCKNIX's Retroid gamepad driver (the MCU on a UART), power key; the volume rocker's two keys (gpio-keys and the PMIC's resin) merged into one input device, "LightMoss Volume Keys" (`package/lightmoss-volkeys`), since spruce watches one node. |
| Not yet | Bluetooth (the QCA6390's; spruce's platform does not offer it), Vulkan, SDL3 rotation, the RGB stick LEDs, the fan curve, USB gadget mode. |

## Partitions

On the internal storage, behind Android's `userdata` (OpenABL's convention
for a Linux install: its *Uninstall CFW* removes everything there and gives
the space back to userdata):

| GPT name | Size | |
|---|---|---|
| `userdata` | the rest | Android's data, 4 GiB smaller |
| `LMBOOT` | 256 MiB | FAT32: `loader/loader.conf`, `loader/entries/lightmoss-{1,2}.conf`, `lightmoss-{1,2}/` (kernel, device tree, firmware initramfs), the flags |
| `LMSYS1` | ~1.9 GiB | system copy 1 |
| `LMSYS2` | ~1.9 GiB | system copy 2 |

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
   boot it again: `lightmoss-install-internal` shrinks `userdata` by 4 GiB,
   adds the three partitions, copies the running system to `LMSYS1`, writes
   the boot entry and restarts into it. **Android's data is lost** (userdata
   changes size, so Android formats it on its next start). Over SSH:
   `lightmoss-install-internal`.
4. Put spruce on the card's `SPRUCEOS` partition, or format the card for spruce.

Run again from a card, `lightmoss-install-internal` repairs an install
(system copy 1 becomes the card's system). Another system's partitions behind
userdata (ROCKNIX's) are only replaced with `--replace`.

## Switching between LightMoss and Android

OpenABL starts its *Boot mode* (Linux: LightMoss). Holding **Volume Up** at
power-on starts the other mode (Android); **Volume Down** opens its menu.
*Boot source* Auto tries the internal storage first, so a LightMoss card
left in the slot boots only when the internal install cannot (a rescue
card).

## Updates: two system copies

The LightMoss Update app downloads the release image to the spruce card and
runs `lightmoss-update`, which writes the image's system to the copy that is
**not** running, copies the machine ID and SSH host keys into it, puts its
boot files on `LMBOOT` and makes it the default entry with three tries
(`lightmoss-N+3.conf`, Boot Loader Specification boot counting, which OpenABL
does like systemd-boot). The device restarts into it.

Once spruce has started, `lightmoss-bless` renames the entry
`lightmoss-N.conf` (kept). If the new copy never gets that far, OpenABL has
counted its tries down after three starts and boots the old copy, whose
`lightmoss-bless` makes it the default again and leaves
`/boot/lightmoss-update-failed` for the app to report. The running copy is
never written, so the charger is not needed and a power cut at any point
leaves the device starting as before.

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
- The installer on a real GPT (`sfdisk -N` on userdata, 4 KiB UFS sectors,
  `sgdisk --resize-table`), and Android formatting userdata afterwards.
- Boot counting: OpenABL renaming `lightmoss-N+3.conf` on each try.

## Building

```bash
make BOARD=rpminiv2
```

The image is `output-rpminiv2/images/lightmoss-rpminiv2-<version>.img.xz`;
the 32-bit runtime builds into `output-rpminiv2-lib32/` first. CI builds it
next to the R36S's on every push, and a release carries both images.
