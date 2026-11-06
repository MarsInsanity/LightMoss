# LightMoss

A minimal [buildroot](https://buildroot.org) base OS for running
[spruce](https://github.com/spruceUI/spruceOS) on the **R36S clone with the
G80CA-MB board** (RK3326). It boots, mounts the spruce card at `/mnt/SDCARD`
and starts spruce; spruce provides the UI, the emulators and PortMaster from
its own card.

It is the BobMoss (`g80ca` branch of MarsInsanity/BobMoss, itself spruceUI's
dArkMoss) hardware support on a buildroot userland instead of Debian: same
kernel, same board device trees, same U-Boot, same hand-off to spruce, and
nothing else.

## What is in it

| | |
|---|---|
| Kernel | christianhaitian's `rg351` 4.4 BSP kernel (as dArkOS/dArkMoss), with BobMoss's G80CA device trees (Panel 8 and Panel 9), lcdyk0517's odroidgo3 joypad driver, the rk817 fuel-gauge fix, the DRM async-flip fix, the VT CSI fix, and the internal eMMC enabled. ~20 modules instead of ~560. |
| Boot loader | christianhaitian's RG351MP U-Boot with BobMoss's G80CA board and panel-ID check, plus a fallback to the internal eMMC when TF1 has no system. |
| GPU | Mali-G31 blob (`libmali-bifrost-g31-rxp0-gbm`, the build that matches the kernel's r12p0 driver): EGL, GLES 1/2/3, GBM. |
| Wi-Fi | MT7601U USB dongles on the OTG port (driver + firmware; dongles that first appear as a driver CD are switched with usb_modeswitch). No other Wi-Fi drivers. |
| Hardware | Joypad and both sticks, volume keys, power key, rk817 audio with automatic headphone switching (`hpjackd`), rk817 battery/charger, backlight, both TF slots, eMMC, suspend, USB host on the OTG port (dongle, USB pad, USB DAC). |
| Userland | glibc 2.42, systemd 257, NetworkManager + wpa_supplicant, dropbear (as the `ssh` unit), busybox, bash, ALSA utils, util-linux, e2fsprogs/dosfstools/exfatprogs. |
| PortMaster runtime | SDL2 (KMSDRM + GLES), SDL2_image, SDL2_mixer, SDL2_ttf, SDL2_net, SDL2_gfx, OpenAL, libevdev, libgomp, libstdc++, zlib/png/jpeg/freetype/ogg/vorbis/theora/flac/modplug, squashfs + loop + overlayfs for PortMaster's runtimes, and Debian's `/usr/lib/aarch64-linux-gnu` path. |
| 32-bit runtime | The same libraries built for armhf (plus libudev and the armhf Mali blob) in `/usr/lib/arm-linux-gnueabihf`, with the loader at `/lib/ld-linux-armhf.so.3`, Debian's paths: for 32-bit-only PortMaster ports and spruce's `ra32` cores. 32-bit `time_t`, the armhf ABI those binaries are built for (and the one whose ALSA calls the 4.4 kernel understands). |

Left out on purpose: Python (spruce brings its own), Bluetooth (the R36S has no
radio), logind, networkd/resolved, polkit, the udev hwdb, locales, and every
filesystem and network protocol nothing here uses.

## How spruce sees it

spruce has no R36S platform. As in BobMoss, the image stamps `/etc/os-release`
so spruce treats the device as a dArkMoss G350 (same SoC, panel size, sticks,
joypad driver and button codes):

```
OS_NAME="DARKMOSS"
SPRUCE_PLATFORM="G350"
HW_DEVICE="R36S"          # PortMaster's device profile
OS_VERSION="999.0.0"      # spruce never offers dArkMoss's G350 firmware update
```

Everything spruce's dArkMoss platform code calls is there: `systemctl` (suspend,
poweroff, reboot, the `ssh` unit), `nmcli`, `amixer`, `nc`, `lsblk`, `ip`.

## Where spruce goes

`mount-spruce` looks, in order, for spruce (`spruce/scripts/runtime.sh`) on:

1. partition 1 of a card in a slot the system is not on: TF2, or TF1 when
   LightMoss runs from the eMMC;
2. a FAT32/exFAT partition behind the system on its own disk. The first boot
   adds an empty exFAT partition, `SPRUCEOS`, in the free space there.

With spruce nowhere, it says so on the screen and powers off.

## Building

On a Linux PC with buildroot's usual host packages (`build-essential`, `rsync`,
`cpio`, `bc`, `unzip`, `wget`, `file`, `python3`, `git`):

```bash
git clone https://github.com/MarsInsanity/LightMoss
cd LightMoss
make
```

The `Makefile` fetches buildroot 2025.11.3 into `buildroot/`, builds the 32-bit
runtime into `output-lib32/` and then the image into `output/`. The image is
`output/images/lightmoss-r36s-<version>.img.xz`. A first build takes a few
hours (it builds a GCC 14 toolchain for each); later ones reuse them. Any other
target goes to the image's buildroot (`make menuconfig`, `make linux-menuconfig`,
`make savedefconfig`, `make linux-rebuild`, ...), and `lib32-<target>` to the
32-bit one (`make lib32-menuconfig`, ...). After changing the 32-bit build,
`make lightmoss-lib32-reinstall all` puts it in the image.

### Why buildroot 2025.11 and not 2026.02

The only kernel with complete support for this board is the 4.4 BSP kernel,
which has no cgroup v2. systemd 258 (buildroot 2026.02 and later) dropped
cgroup v1, so it cannot boot on it; 2025.11 is the last buildroot with systemd
257, which still runs v1 when `boot.ini` asks for it. glibc is built against
5.10 headers (NetworkManager needs them) with `BR2_PACKAGE_GLIBC_KERNEL_COMPAT`
so it still runs on 4.4.

## Flashing

### TF1 card

Write the image to a card like any other:

```bash
xzcat lightmoss-r36s-<version>.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

(or use balenaEtcher / Raspberry Pi Imager with the `.img.xz`). Put it in TF1
and the spruce card in TF2.

### Internal eMMC

Boot LightMoss from TF1 first, then, over SSH (`spruce` / `happygaming`, after
turning SSH on in spruce's Network Settings):

```bash
lightmoss-install-emmc
```

It erases the eMMC (EmuELEC on most units), copies the running system onto it
with its own disk signature, and leaves the rest of the eMMC for the first
boot's `SPRUCEOS` partition. A LightMoss card in TF1 still boots first, so you
can always boot from a card to repair the eMMC.

The eMMC path (U-Boot's eMMC fallback and the installer) has not been tested
on hardware yet; test from TF1 first.

## The BOOT partition

| File | |
|---|---|
| `boot.ini` | U-Boot boot script |
| `Image`, `rk3326-r36sclone-*.dtb` | kernel, and the device tree for each panel |
| `uboot.dtb`, `uboot-panel9.dtb` | U-Boot's board device tree (see `R36S-PANEL.txt` if the screen stays dark) |
| `lightmoss-debug` (create it) | kernel and systemd text on screen, logs exported to `logs/` |
| `headphones-invert` (create it) | for boards that report the headphone jack the other way round |

## Layout of this repository

```
configs/lightmoss_r36s_defconfig     the buildroot configuration of the image
configs/lightmoss_r36s_lib32_defconfig  ... and of the 32-bit runtime in it
board/r36s/linux/                    kernel patches and config fragment
board/r36s/uboot/                    U-Boot board device trees (G80CA, two panels)
board/r36s/boot/                     files for the BOOT partition
board/r36s/rootfs-overlay/           systemd units and scripts (spruce hand-off,
                                     /boot mount, first boot, eMMC installer)
board/r36s/genimage.cfg              disk layout
board/r36s/post-build.sh             os-release, spruce login, compat links
package/rk3326-uboot/                legacy Rockchip U-Boot (+ patches)
package/linaro-gcc6-aarch64/         the GCC 6.3 toolchain that U-Boot needs
package/rk3326-mali/                 Mali-G31 user-space blob (64- and 32-bit)
package/lightmoss-lib32/             puts the 32-bit runtime in the image
package/hpjackd/                     headphone jack -> rk817 Playback Path
```

## Credits

christianhaitian (kernel, U-Boot, Mali builds), lcdyk0517 and kk (G80CA device
trees and joypad driver), southoz (dArkOSRE-R36's G80CA U-Boot tree), the
spruceUI team (spruce, dArkMoss), BobMoss's G80CA work.
