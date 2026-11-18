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
| GPU | Mesa 25.2 freedreno (64- and 32-bit): OpenGL ES, EGL, GBM, desktop OpenGL and Vulkan. Desktop OpenGL (freedreno's GL 4.x) through libglvnd: `libOpenGL.so.0`, with `libEGL.so.1`, `libGLESv1_CM.so.1` and `libGLESv2.so.2` now glvnd's and Mesa their vendor (`libEGL_mesa.so.0`, named by `/usr/share/glvnd/egl_vendor.d/50_mesa.json`, which the 32-bit glvnd reads too). glvnd's `libGLESv1_CM` and `libGLESv2` export the same symbols as Mesa's, its `libEGL` the same apart from Mesa's three `MesaGLInteropEGL*` functions (OpenCL interop), which nothing here uses. glvnd's desktop GL headers (`GL/gl.h`, `glext.h`, `glcorearb.h`) stay in staging for programs built here (`external.mk`; buildroot's Mesa package would delete them). No `libGL.so.1`: that is GLX, X11 only. SDL2 and SDL3 load `libOpenGL.so.0` (EGL, `EGL_OPENGL_API`) when a program asks for a desktop GL context, also in their GLES builds; a program that does not ask still gets OpenGL ES, and SDL2 stays built for GLES (buildroot only offers its desktop GL with X11). Before glvnd, SDL found no desktop GL library and quietly gave a program that asked for one (also any port whose own SDL is built with desktop GL, which asks by default) OpenGL ES 2.0; it now gets freedreno's desktop GL, which has not run on the device yet. spruce's RetroArch and PPSSPP link `libGLESv2.so.2` and its Flycast is a GLES build: they keep OpenGL ES. Vulkan: Turnip (`BR2_LIGHTMOSS_MESA3D_TURNIP`, `external.mk`: buildroot 2025.11's Mesa package has no option for it) and the Khronos loader `libvulkan.so.1`; ICD manifests `/usr/share/vulkan/icd.d/freedreno_icd.cortex-a76.cortex-a55.json` (64-bit, Mesa's) and `freedreno_icd.armhf.json` (32-bit, from `package/lightmoss-lib32`, library in `/usr/lib/arm-linux-gnueabihf`), each skipped by the other loader by its `library_arch`. SDL2 and SDL3 are built with Vulkan (KMS/DRM windows on `VK_KHR_display`). `vulkaninfo` is in the image. spruce keeps RetroArch on `gl` and PPSSPP and Flycast on OpenGL; RetroArch and Flycast can be switched to Vulkan in their own menus. |
| Firmware | The files ROCKNIX installs for SM8250, from linux-firmware 20260309 (`package/lightmoss-firmware-sm8250`). The DSPs' firmware also comes in a small initramfs with no `/init`, since they start before the root filesystem is mounted. |
| Display | The panel scans out portrait (1080x1240) and is mounted landscape (`rotation = <90>`). LightMoss's SDL2 (64- and 32-bit) turns the primary plane 270 degrees on the SDE rotator (ROCKNIX's DPU patches) and shows programs a 1240x1080 display (`board/rpminiv2/patches/sdl2`), as dArkMoss's SDL does with RGA on the E5 Plus. PyUI (spruce's own SDL) turns its canvas itself. SDL3 (64- and 32-bit) does the same as SDL2 (`board/rpminiv2/patches/sdl3`). Vulkan programs presenting on `VK_KHR_display` (RetroArch's `khr_display`, SDL's Vulkan windows) are turned the same way by Mesa (`board/rpminiv2/patches/mesa3d`): it shows them the display as 1240x1080 and turns the primary plane before each mode set. `SDL_KMSDRM_PANEL_ROTATION=0` and `MESA_KMS_PANEL_ROTATION=0` turn it off for a test (both, for an SDL Vulkan window). If the kernel refuses the turn, Mesa sets the plane upright and presents unturned from then on: the program's first swapchain is out of date (`VK_ERROR_OUT_OF_DATE_KHR`), and one it makes again for the surface's new size (1080x1240) comes out sideways; an SDL Vulkan window keeps SDL's 1240x1080 and fails until both variables are 0. |
| Audio | ROCKNIX's Retroid UCM configuration (alsa-ucm-conf 1.2.14 + ROCKNIX's patches). `lightmoss-audio` (a oneshot spruce waits for) sets the card up and routes `hw:0,0` to the speakers or the headphones; `lightmoss-audio-jack` follows the jack's control events from then on, and writes `/run/lightmoss/headphones` for spruce. Kernel patches let a line-out load count as headphones and move an open stream along with its route. `/etc/asound.conf` links to `/run/lightmoss/asound.conf`, where spruce puts its ALSA configuration for programs whose `HOME` has none. |
| Input | ROCKNIX's Retroid gamepad driver (the MCU on a UART), power key; the volume rocker's two keys (gpio-keys and the PMIC's resin) merged into one input device, "LightMoss Volume Keys" (`package/lightmoss-volkeys`), since spruce watches one node. LightMoss's driver patches (`4-lightmoss/0002`, `0020`-`0022`) frame and bound the MCU's packets, put the analog triggers on `ABS_Z`/`ABS_RZ` (0 at rest) and also report them as `BTN_TL2`/`BTN_TR2` (press at 50%, release below 40%). `/sys/module/retroid/parameters/trigger_mode` is 0 for analog (axes and buttons) or 1 for digital (buttons only, the axes held at 0); spruce's *Trigger mode* setting writes it. `swap_xy` (off) swaps the north and west face buttons' codes. Untested. |
| Not yet | The RGB stick LEDs, the fan curve, USB gadget mode. |
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
- The plane rotation: the device's RetroArch log shows SDL found a primary
  plane offering 270 and gave RetroArch 1240x1080, but no log or photo
  shows the picture: whether the SDE rotator turns it for legacy
  `drmModeSetCrtc` users, and which way round (270 by the panel
  orientation; `SDL_KMSDRM_PANEL_ROTATION=90` flips it).
- Vulkan: `vulkaninfo --summary` lists Turnip (FD650); RetroArch with
  `video_driver = "vulkan"` comes up upright at 1240x1080, and the spruce
  menu is upright again after it exits. Mesa says `display: panel mounted
  rotated, turned by plane ...` (or why it could not) on stderr, which
  spruce discards for games (`principal.sh` runs them with `2>/dev/null`;
  RetroArch's `--log-file` has only its own lines): to see it, stop spruce
  (`systemctl stop spruce-launch`, then `/usr/libexec/lightmoss/spruce-leftovers`
  for the menu it leaves running) and run the `Running CMD:` line from
  `spruce.log` over SSH, or add `MESA_LOG=syslog` to the program's
  environment and `journalctl | grep 'display:'`. A 32-bit Vulkan program
  finds `freedreno_icd.armhf.json`.
- Desktop OpenGL and glvnd: the spruce menu, RetroArch (`gl`) and the 32-bit
  RetroArch still start (EGL and GLES now go through glvnd); a program asking
  SDL for a desktop GL context gets one (`GL_VERSION` 4.x, freedreno). Such
  a program used to be given OpenGL ES 2.0 by SDL: check one port that asks
  for desktop GL still runs.
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
