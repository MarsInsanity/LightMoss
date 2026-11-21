# Handoff: R36S performance under LightMoss (PSP on Vulkan, N64, Dreamcast, the 5.10 kernel)

You are picking up work on **LightMoss** (`MarsInsanity/LightMoss`, branch `main`) for the **R36S clone, G80CA board**
(`board/r36s`). The owner wants PSP emulation on this handheld to get as close as possible to what the dArkOS RE /
dArkOSen developers report (God of War at a steady 30 FPS), and wants the heavy systems (PSP, N64, Dreamcast) faster and
the optional 5.10 kernel more solid. This file is everything the previous session learned; read it before changing
anything. Facts here were checked against the code and the device; where something is a guess, it says so.

---

## 1. Ground rules (the owner's, non-negotiable)

- **Branch:** work on `main` only, in `/home/user/LightMoss` (re-clone `MarsInsanity/LightMoss` if missing). Fast-forward
  pushes only: never force-push, rebase or amend pushed history. Another Claude session runs a **daily maintenance task**
  that also commits to `main` (03:45 Pacific / 11:45 UTC): `git fetch` and merge `origin/main` before you push, and
  check the latest release before bumping the version.
- **Commits:** as `Mars <53840971+MarsInsanity@users.noreply.github.com>`. **No attribution lines at all**: no
  `Co-Authored-By`, no `Claude-Session`, no "Generated with Claude Code". One logical change per commit, saying why.
- **No pull requests or issues anywhere.** Never push to upstream repositories (spruceUI, christianhaitian, lcdyk0517,
  jokubasver, ROCKNIX, OpenHandheldCollective, djparentx, hrydgard). Don't create, move or delete tags or releases by
  hand: the build workflow does that (§7).
- **The default must stay clean.** The owner plans to upstream Vulkan support to dArkMoss (spruce's official base), so
  the default R36S setup must not overvolt or overclock. Anything beyond Rockchip's own tables is **opt-in**, protected
  by the 5.10 fallback (§3.4), and released only once the owner has tested it.
- **Stay in your board.** Don't change the Retroid Pocket Mini V2 (`board/rpminiv2`, `configs/lightmoss_rpminiv2*`) or
  its behaviour. Shared files (`.github/workflows/build.yml`, `external.mk`, `Config.in`, `package/**`) need care for both.
- **Keep LightMoss light**: only what spruce or the device needs, done the buildroot way.
- **spruce is upstream's.** The R36S runs *upstream* spruceOS, which LightMoss can't change. When a fix belongs in spruce
  (emulator launch scripts, settings files, emulator binaries), write it up for the owner; they deal with spruceUI.
  (`MarsInsanity/spruceOS` branch `mofang` is the *Mini V2's* spruce. It's not relevant here; leave it alone.)

## 2. Where things stand (short version)

| | State |
|---|---|
| Release | **v0.3.8** (2026-11-21). |
| Kernels | 4.4 (default) and the optional BSP **5.10** with Vulkan, chosen in the **LightMoss Kernel** spruce app. |
| 5.10 on the owner's unit | Starts and runs stably at Rockchip's CPU speeds; Vulkan works in PPSSPP. |
| PSP on Vulkan (owner-installed build, §4.2) | Ridge Racer: clearly faster than OpenGL, which ran ~42/60 with stutter. **God of War: Chains of Olympus shows "10/30 (100%)" on both OpenGL and Vulkan: full speed, but only 10 of the game's 30 frames drawn.** That's most likely frame skipping; the real rendering speed is still unmeasured (§4.3). |
| CPU overclock | Tried three ways (§3.3); froze the owner's unit every time. Removed in v0.3.8. **Don't bring it back by default.** |
| Controls | Fixed for PPSSPP on the R36S (v0.3.3 SDL patch plus a corrected button file, §4.4). |

## 3. The system

### 3.1 Hardware
- **SoC:** Rockchip RK3326 (PX30 family): 4× Cortex-A35 (ARMv8.0: no LSE, no dotprod) and a **Mali-G31 MP2**
  (Bifrost). About 1 GB of DRAM.
- **Display:** 640×480 MIPI-DSI. Two panel variants ("Panel 8" ST7703 and "Panel 9"), both driven at ~60 Hz.
- **Owner's unit:** G80CA-MB, with LightMoss installed on the **internal eMMC** and spruce on the SD card. The owner
  tests on the device and prefers spruce apps to SSH (dropbear SSH exists).

### 3.2 LightMoss on the R36S
LightMoss is a buildroot 2025.11.3 system that **impersonates a dArkMoss base**, so upstream spruce runs on it with its
**G350** profile:
- `board/r36s/post-build.sh` writes os-release with `OS_NAME="DARKMOSS"`, `SPRUCE_PLATFORM="G350"`,
  `DARKMOSS_UNIT="r36sclone"`, `HW_DEVICE="R36S"`, `OS_VERSION="999.0.0"`, `LIGHTMOSS_VERSION`.
- Layout: `configs/lightmoss_r36s_defconfig` (64-bit) and `configs/lightmoss_r36s_lib32_defconfig` (the armhf runtime,
  copied in by `package/lightmoss-lib32`); `board/r36s/` (boot, initramfs updater, rootfs-overlay, spruce apps, kernel
  patches); `package/rk3326-mali` (GPU blobs); `package/lightmoss-linux510` (the second kernel); `package/rk3326-uboot`.
- `README.md` describes each part; `board/r36s/boot/README-LightMoss.txt` is the user-facing manual on BOOT.

### 3.3 Kernels and CPU clocks
- **4.4** (default): christianhaitian's `rg351` 4.4.189 BSP with `board/r36s/linux/patches`.
- **5.10** (optional): `jokubasver/rockchip-kernel` branch `arkos4clone-5.10` at
  `f2d282f266a4641a8cd4664ae1ebc11cb8bff301` (5.10.252, the arkos4clone kernel; dArkOSen's 5.10 beta is the same
  version). Config: `clone_defconfig` plus `board/r36s/linux-5.10/lightmoss-5.10.config`, checked by `check-fragment.sh`.
  Patches in `board/r36s/linux-5.10/patches` (0001–0005: build fix, joypad LED-as-rumble, rk817 gauge resync, the G80CA
  dts `rk3326-r36sclone-linux.dts` and `-panel9-linux.dts`). Images on BOOT: `Image-5.10`, `*-5.10.dtb`.
- **CPU-clock finding (important):** with Rockchip's tables, **the CPU never runs above ~1248–1296 MHz, whatever
  cpufreq reports.** spruce's G350 modes ask for 1416 MHz (Smart/Performance) and 1512 MHz (Overclock); cpufreq shows
  those, but `rockchip_adjust_power_scale()` caps the APLL. `rockchip_get_pll_settings()` in
  `drivers/clk/rockchip/clk-pll.c` programs the capped rate and reports the requested one. Two things set the cap:
  `rockchip,max-volt` = 1.35 V makes `rockchip_adjust_opp_by_irdrop()` take the first 1.35 V OPP as the "safe rate"
  (1248 MHz on PVTM level L0), and `rockchip,bin-scaling-sel = <0 13 1 13>` gives PLL scale 13 (1296 MHz). The same
  tables are on 4.4. **Never trust `scaling_cur_freq` here: measure real speed** (§5.A).
- **Overclock history (don't repeat it):**
  - v0.3.4: real 1416/1512 MHz at 1.35 V (`max_cpufreq=1512`, `max-volt` 1.4 V). The unit froze at boot.
  - v0.3.5: the same plus `boot_cpufreq=1296`. It froze once spruce raised the clock.
  - v0.3.7: opt-in, 1416/1512 MHz at 1.4 V with `vdd_arm` capped at 1.4 V. It still froze.
  - v0.3.8: removed. The overclock commits stay in history (`git log --grep overclock`).
  - Working assumption: this chip is low-grade. Even **1296 MHz at 1.35 V may be marginal** if it is PVTM L0; the
    previous session couldn't confirm the level. Read it from `dmesg` on 5.10 (`cpu cpu0: ... pvtm ... / bin-scale= /
    leakage`).
  - The arkos4clone kernel's opt-in mechanism, if ever needed again: `rockchip,boot-max-freq` in the CPU OPP table, plus
    `max_cpufreq=` and `boot_cpufreq=` on the command line (`drivers/soc/rockchip/rockchip_opp_select.c`,
    `drivers/cpufreq/rockchip-cpufreq.c`; see `arch/arm64/boot/dts/rockchip/rk3326-oc.dtsi`).
- **Other 5.10 clocks:**

  | Clock | Steps | Normal use | Notes |
  |---|---|---|---|
  | GPU | 200 / 300 / 400 / 480 / **520** MHz | spruce sets max 520 MHz, governor `performance` in Performance/Overclock | devfreq `/sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu` |
  | Memory (DMC) | 194 / 328 / 450 / 666 MHz; **786 MHz disabled** | **666 MHz** via `system-status-freq` (4.4: 528 MHz) | spruce's G350 profile doesn't manage DMC (`DRAM_DEVFREQ_DIR` unset) |
  | Thermal | trips at 70 °C and 85 °C (passive), 115 °C (critical) | | |

### 3.4 Choosing 5.10, and its fallback (keep this working)
- `board/r36s/boot/boot.ini` starts 5.10 when `lightmoss-kernel-5.10` is on BOOT. Each 5.10 start is a **try**: it
  `fatwrite`s `lightmoss-kernel-5.10-trying` first and starts 4.4 while that marker exists.
- `rootfs-overlay/usr/libexec/lightmoss/kernel-ok` (`lightmoss-kernel-ok.service`) removes the marker only after
  spruce has run for **3 minutes** without a break. If spruce never comes up within 10 minutes, it restarts the device;
  once spruce has been up, it never restarts it.
- The **LightMoss Kernel** app (`board/r36s/spruce-app/LightMossKernel`) and `/usr/bin/lightmoss-kernel` set the
  choice. The initramfs updater (`board/r36s/initramfs/init`) keeps the choice across updates;
  `board/r36s/test-updater.sh` checks that.

### 3.5 GPU stack
- **4.4:** `libmali-bifrost-g31-rxp0-gbm` (matches the kernel's r12p0 driver): GLES 1/2/3, EGL, GBM. No Vulkan.
- **5.10:** rockchip's **g29p1** libmali (from `JeffyCN/mirrors` at `bf621d15`; aarch64 sha256 `9a931238…`, armhf
  `82e89b34…` original and `92455f88…` after a program-header fix done in `package/rk3326-mali/rk3326-mali.mk`).
  - `lightmoss-mali-select` (sysinit, 5.10 only) bind-mounts it over the r12p0 library names and writes the Vulkan ICD:
    `/etc/vulkan/icd.d/mali.json` → `/run/lightmoss/mali_icd.json`, which exists **only under 5.10**. Use that as the
    "Vulkan available" test; the Khronos loader is installed under 4.4 too.
  - Vulkan 1.3 presents through **VK_KHR_display**.
  - LightMoss's SDL2 (2.32.10) is built with Vulkan on the R36S (`BR2_LIGHTMOSS_SDL2_VULKAN`, `external.mk`) and
    carries `board/r36s/patches/sdl2/0001-…` (automatic pad mappings without the name CRC, so a program's
    `gamecontrollerdb.txt` applies, as on dArkMoss).
  - post-build verifies both blobs' sha256 after the strip step.
- **dArkOSen's 5.10 beta installs the very same g29p1 blob with the very same fix.** The driver isn't their secret.

## 4. PSP today

### 4.1 How spruce runs it on the R36S
- `spruce/scripts/emu/lib/ppsspp_functions.sh` (upstream spruce) runs `PSP_BIN` from `G350.cfg`, which is
  **`PPSSPPSDL_dArkMoss3326`**: spruce's own build of PPSSPP 1.20.3, OpenGL ES only, from `spruceUI/PPSSPP-spruce`
  (`build-darkmoss3326.sh`).
- There's no R36S-specific branch in the launch script. spruce's per-game "Governor" option sets the CPU mode
  (PSP default: Performance), and the requested clocks aren't the real ones (§3.3).
- spruce's defaults (`Emu/PSP/default_configs/SYSTEM/ppsspp-G350.ini`): 1× rendering, JIT (`CPUCore = 1`), fast memory,
  `AutoFrameSkip = True`, `FrameSkip = 0`, `SoftwareSkinning = True`, `HardwareTransform = True`,
  `TextureBackoffCache = False`, `SkipBufferEffects = False`, `AnisotropyLevel = 1`, `SplineBezierQuality = 1`.

### 4.2 The Vulkan build the owner uses
- `tools/ppsspp-vk/build.sh` rebuilds it exactly: PPSSPP v1.20.3 with spruce's dArkMoss3326 recipe, `-mcpu=cortex-a35`
  (LSE-free), plus `-DVULKAN=ON -DUSE_VULKAN_DISPLAY_KHR=ON`, spruce's `pvr/vulkan-display-fallback.py`, and without
  `common/skip-vulkan-probe.py`.
- It uses the Steward-Fu Flip toolchain (GCC 13.3, glibc 2.38). Output: `PPSSPPSDL_dArkMoss3326_vk`, sha256
  `5c8b57d4…`. libvulkan is dlopen()ed, so the same binary runs OpenGL under 4.4.
- The owner copied it over `/mnt/SDCARD/Emu/PSP/PPSSPPSDL_dArkMoss3326` by hand and picks the backend in PPSSPP's
  Settings > Graphics.

### 4.3 What the owner measured
- **Ridge Racer:** OpenGL ~42/60 with frame skips and lag spikes; Vulkan noticeably smoother (no number yet).
- **God of War: Chains of Olympus:** PPSSPP's counter shows **"10/30 (100%)"** on both backends.
- **How to read that counter** (`UI/DebugOverlay.cpp` `DrawFPS`, `Core/HW/Display.cpp`, `Core/HLE/sceDisplay.cpp`):
  - The format is `actual_fps/fps (speed%)`.
  - `fps` (30) counts the game's own flips per second.
  - `actual_fps` (10) counts only flips that show a newly drawn framebuffer (`DisplayFireActualFlip()` runs when
    `FramebufferReallyDirty()`); frames skipped by frameskip don't count.
  - Speed is emulated vblanks against 59.94 Hz.
- So the game runs at **full speed** and PPSSPP **draws only one frame in three**. With spruce's default `FrameSkip = 0`,
  auto frameskip can't skip anything (`doFrameSkip` is false in `DoFrameTiming()`). The owner's card therefore most
  likely has frame skipping set; a *fixed* frameskip of 2 shows exactly 10/30 however fast the device is.
- **The same 10/30 on OpenGL and Vulkan therefore proves nothing**, and the previous session's "CPU-bound" conclusion
  was premature. First job: measure with frame skipping **off** and auto frameskip **off** on both backends (§5.A.4).
  The counter then shows drawn frames and the speed the device really reaches, for example "18/18 (60%)".
- **Not yet tried by the owner:** lazy texture caching, skip buffer effects, or software skinning off.

### 4.4 Controls (done; don't redo)
- **Start/Select:** missing in PPSSPP because SDL 2.32's automatic, CRC-tagged mapping beat PPSSPP's database row for
  the "GO-Super Gamepad" (GUID `1900bb3e4b4800000011000000010000`). Fixed by the LightMoss SDL2 patch (v0.3.3).
- **Face buttons and L/R:** spruce's `controls-G350.ini` doesn't match the database layout (an upstream spruce bug).
  The owner uses a corrected file: `Circle = 10-189`, `Cross = 10-190`, `Square = 10-188`, `Triangle = 10-191`,
  `L = 10-193`, `R = 10-192`, `Start = 10-197`, `Select = 10-196`, with Select-combo hotkeys (as spruce's
  `controls-Miniloong.ini`).

### 4.5 The target, verify it before chasing it
- The Reddit post the owner shared (djparentx, dArkOSen) claimed **God of War: Ghost of Sparta** at a smooth 30 FPS on an
  **R36H ProMax** (`rk3326-r45h`, an RK3326 handheld that may have a better-binned chip), "available on the 15th".
- The owner understands dArkOS RE reached 30 FPS on **Chains of Olympus** with help from an AI agent. Find the primary
  source: `github.com/djparentx/dArkOSen-R36S` (README; `BETA/BSP_5.10_kernel.zip`; `usr/local/bin/perfmax`;
  `opt/ppsspp/`), their Reddit and Discord posts, and the dArkOS RE repositories.
- Establish exactly: game, scene, device, clocks, PPSSPP version/build and settings (frameskip? speed hacks?).
- What's known of dArkOSen's setup:
  - 5.10.252-darkosen kernel, booted with `max_cpufreq=1512 boot_cpufreq=1296`.
  - CPU 1416–1512 MHz at 1.4 V and GPU 600 MHz.
  - `perfmax` sets the GPU, CPU **and DMC** governors to `performance` for games.
  - PPSSPP **1.20.4**.
- The owner's unit can't run their CPU clocks (§3.3). Match everything else.

## 5. Work items, in the order the previous session would take them

### A. Measure first (the owner can only run apps)
1. **Build a diagnostics spruce app** ("LightMoss Report"), shipped like LightMoss Kernel: `board/r36s/spruce-app/*`,
   installed by `rootfs-overlay/usr/libexec/lightmoss/spruce-app` and given an icon in `post-build.sh`. It should write
   to the SD card:
   - `uname -a`, `/proc/cmdline`;
   - the `dmesg` lines for pvtm / bin-scale / leakage / opp / mali / dmc;
   - cpufreq, GPU devfreq and DMC states and their `trans_stat`;
   - thermal zones and the journal of the previous boot.
   This gives you the chip grade and real behaviour without SSH. `lightmoss-debug` on BOOT already exports logs, but on
   an eMMC install it needs SSH to create.
2. **Measure the real CPU speed.** Time a fixed-cycle busy loop (or `openssl speed` / a small C kernel) at each
   `scaling_max_freq`; real MHz is the ratio. Confirm the 1248/1296 cap on the owner's unit.
3. **Profile PPSSPP while GoW runs:**
   - per-thread CPU with `top -H`: is the emu (JIT) thread pegged at 100% of one core?
   - PPSSPP's own frame-time / debug overlays;
   - if needed, `perf` (check `CONFIG_PERF_EVENTS` in the 5.10 config, add a perf binary to a test build).
   - Watch temperatures and clocks for thermal throttling (70 °C trip).
4. **Make a repeatable benchmark:** a GoW savestate at a heavy scene, 60 s, the same for Ridge Racer. Ask the owner to
   make the savestates.
   - Run with **frame skipping Off and Auto FrameSkip off**, and the counter set to show both FPS and speed. A skipped
     frame isn't rendered, so frameskip hides the real cost.
   - Read the result as drawn frames and speed (§4.3); "30/30 (100%)" is the goal.
   - Record every result with its settings and backend.

### B. PSP / PPSSPP (the main goal)
1. **Settings sweep on GoW** (Vulkan and OpenGL), one change at a time:
   - software skinning **off** (moves skinning from the weak CPU to the GPU; likely big for GoW);
   - lazy texture caching on;
   - skip buffer effects (watch for missing effects);
   - frameskip 1/2 with auto frameskip;
   - spline/Bezier quality low;
   - anisotropic filtering off;
   - "Lower resolution for effects";
   - skip GPU readbacks;
   - I/O timing, fast memory;
   - Vulkan inflight frames.

   Settle on a per-game config (PPSSPP game settings) that the owner can use, and a recommended `ppsspp.ini` for the
   R36S under 5.10.
2. **Newer PPSSPP:** rebuild with `tools/ppsspp-vk/build.sh` at 1.20.4 (what dArkOSen ships) and at current `master`;
   ARM64 JIT and vertex-decoder work lands often. Bump `PPSSPP_VERSION`/`PPSSPP_COMMIT` and check that spruce's patches
   still apply.
3. **Compiler wins, if profiling shows PPSSPP's own threads are the limit on the A35:**
   - **PGO**: build with `-fprofile-generate`, have the owner play the GoW benchmark, collect the `.gcda` files, rebuild
     with `-fprofile-use`. Often worth 5–15% on CPU-bound code. Needs a writable profile path on the SD card.
   - `-O2` vs `-Ofast`, LTO (already on), `-mcpu=cortex-a35 -mtune=cortex-a35`.
   - Keep the LSE check at the end of the script.
4. **Memory clock:** test the DMC governor at `performance` while PPSSPP runs. It stays at 666 MHz while 786 MHz is
   disabled. Enabling 786 MHz (or arkos4clone's 924/1032 MHz) is a memory overclock: **opt-in only**, with the owner's
   agreement, and their unit has already failed CPU overclocks.
   - If rendering turns out to be the limit, the **GPU clock** matters too. dArkOSen runs the Mali at 600 MHz; this
     kernel's `rk3326-oc.dtsi` has a 600 MHz OPP at 1.175 V.
   - The GPU is on `vdd_logic`, not `vdd_arm`, so the failed CPU overclock says little about it.
   - It's still an **opt-in** experiment, and spruce's G350 profile caps the GPU at 520 MHz in every mode
     (`GPU_*_MAX_FREQ`), so it also needs that raised (a spruce change).
5. **Deliverable for spruce:** spruce's G350 profile should use a Vulkan-capable 3326 PPSSPP build when Vulkan exists
   (test `/run/lightmoss/mali_icd.json` or a working `libvulkan` + ICD) and the OpenGL one otherwise, as spruce already
   does for its Mini V2 port. Write the change up for the owner with your measurements; don't push it anywhere.

### C. GPU drivers
1. **g29p1** is the newest rockchip Bifrost blob the previous session found. Look for newer libmali releases for
   RK3326/PX30 (rockchip-linux `libmali`, JeffyCN mirrors) and check whether a newer one matches the 5.10 kernel's
   kbase driver.
2. **Panfrost / PanVK** (open-source Mesa) support the Mali-G31, but need the mainline `panfrost` kernel driver.
   Practically that means a **mainline kernel** (ROCKNIX runs the R36S and other RK3326 handhelds on mainline + Panfrost).
   - This is a big project: a third kernel option with its own device tree, joypad, panel and audio.
   - First research and report back: what ROCKNIX gets for GoW/Ridge Racer/Flycast on RK3326, whether PanVK supports
     Bifrost v7 well enough, and the cost. Don't start building it without the owner.
3. **Vulkan presentation:** FIFO through VK_KHR_display. Check for pacing problems (frames dropped or waiting) on the
   60 Hz panel, and for the "Panel 9" path.

### D. Dreamcast (Flycast)
- spruce on the R36S defaults to **Flycast standalone 2.7** (`Emu/DC/flycast`, option `Emulator_DARKMOSS`).
- That binary is **already built with Vulkan**: it links the system `libSDL2-2.0.so.0` and contains
  `SDL_Vulkan_CreateSurface` and `vkCreateDisplayPlaneSurfaceKHR`. LightMoss's SDL2 has Vulkan under 5.10.
- spruce's `emu.cfg` (`Emu/DC/config/flycast/emu.cfg`) sets `pvr.rend = 0` (OpenGL).
- **Test** Flycast with the Vulkan renderer under 5.10 (`pvr.rend = 4`, or Flycast's own video settings):
  - Does it start, and is it faster in GPU-heavy games?
  - What happens under 4.4 (no Vulkan): does it fall back or crash?
- If it's a win, spruce needs to choose the renderer by Vulkan availability (an upstream change: write it up).
  RetroArch's flycast core with RetroArch's `vulkan` video driver is the other path to test.

### E. N64 (mupen64plus)
- spruce on the R36S defaults to **mupen64plus standalone**, with **Rice**, **Glide64mk2** and **GLideN64** video
  plugins. All are OpenGL ES.
- Vulkan for N64 means **paraLLEl-RDP**, a Vulkan *compute* renderer far too heavy for a Mali-G31 MP2. **Don't chase
  Vulkan here.**
- N64 on the RK3326 is limited by the CPU dynarec and GL draw cost. Look at plugin choice (Rice is the fastest),
  GLideN64 settings, the RetroArch `mupen64plus_next` core, and the same compiler wins (PGO) if spruce's binaries allow
  a rebuild.
- Measure first (§5.A) with a couple of known-heavy games.

### F. 5.10 stability
- **Known:**
  - Stable on the owner's unit at Rockchip's clocks. Spruce, Vulkan PPSSPP and controls work.
  - Freezes were only ever the CPU unlock.
  - Another clone had a loud speaker pop on its first 5.10 start (arkos4clone report).
- **Verify on the device** (via the §5.A report app where possible):
  - both panels;
  - buttons, sticks, volume keys (adc-keys);
  - headphone detect (active high; `headphones-invert` on BOOT flips it);
  - blue-LED "rumble";
  - sleep/wake (the system-sleep hook);
  - battery percentage (rk817 gauge, patch 0004);
  - Wi-Fi (MT7601U dongle);
  - internal eMMC;
  - RetroArch with GL and with Vulkan;
  - temperatures under load.
- Any change to boot, `kernel-ok`, the app or the updater must keep the fallback (§3.4) working. Run
  `board/r36s/test-updater.sh` (§7).

### G. System-level
- zram (dArkOSen uses 768 MB; LightMoss has none);
- CPU governor/idle settings during games (cpuidle states, schedutil vs performance; spruce sets the governor itself);
- IRQ and thread placement;
- services that wake up during play;
- `CONFIG_HZ` and preemption in the 5.10 config.

Only keep what measurably helps.

## 6. Answers already given to the owner (don't contradict without new evidence)
- **Vulkan only exists under 5.10.** The 4.4 r12p0 driver has no Vulkan.
- **The CPU overclock isn't for this unit**, and stays out of the default.
- **Dreamcast:** Flycast is Vulkan-ready; it's a setting plus spruce-side selection.
- **N64:** no useful Vulkan path on this GPU.
- **GoW's "10/30 (100%)"** means full speed with two of every three frames skipped, not a 10 FPS device limit. The real
  limit is unmeasured until frameskip is off. "30 FPS" as dArkOS RE reports it presumably means 30/30 at 100%: every
  frame drawn at full speed. Find out how they measured it.
- **The CPU unlock** (~20% more CPU) failed on this unit anyway. Realistic levers are PPSSPP's rendering settings, a
  newer or PGO-built PPSSPP, GPU and memory throughput if rendering turns out to be the limit, and whatever dArkOS RE
  actually did.

## 7. Building, testing, shipping
- **CI is the build.** `.github/workflows/build.yml` builds both boards on every push except Markdown-only changes;
  add `[skip ci]` to a commit message to skip a build.
  - A full build is about an hour with warm caches; the first builds on `main` are cold (several hours).
  - To release, make the last commit of a push bump `.github/lightmoss-version` (v0.3.8 → v0.3.9) and add
    `.github/release-notes/vX.Y.Z.md`. The workflow creates the GitHub release with
    `lightmoss-r36s-vX.Y.Z.img.xz` and `.sha256`, which the LightMoss Update app installs.
  - Watch runs with `gh api repos/MarsInsanity/LightMoss/actions/runs…` (REST only).
- **Local checks before pushing:**
  - `busybox sh -n` and `shellcheck -s sh -S error` on changed scripts (target shell: busybox ash; post-build: bash).
  - **Kernel patches:** apply the whole `board/r36s/linux-5.10/patches` series to `f2d282f` with `git apply`. Build the
    dtbs with `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3326-r36sclone-linux.dtb`.
  - **Defconfig options** must exist in buildroot 2025.11.3. For a package patch, `make BR2_EXTERNAL=… O=…
    lightmoss_r36s_defconfig` then `make <pkg>-patch` (needs cpio, rsync).
  - **Updater:** `board/r36s/test-updater.sh <dir>` needs root and `<dir>/images/lightmoss-r36s.img` plus a
    `lightmoss-r36s-*.img.xz`, for instance a downloaded release.
  - The previous session also checked device-tree logic with a small simulator of `rockchip_adjust_power_scale()` (not
    in the repo). Reason from the kernel source; don't guess.
- **On-device testing is the owner's.** Give short, numbered steps that use spruce apps, say what to report (FPS, photos
  of where something stops), and say how to get back to safety:
  - a frozen 5.10 start → hold power, and the next start is 4.4;
  - LightMoss Kernel → back to 4.4.
- **Finish** each piece of work with a short report for the owner: what changed, measured before/after, what's left,
  with a recommendation.

## 8. Reference
- **R36S pad:** "GO-Super Gamepad", 17 buttons, BTN_TRIGGER_HAPPY1–5 for Select/Start/L3/R3/F; event device
  `/dev/input/by-path/platform-odroidgo3-joypad-event-joystick`.
- **spruce G350 profile:** `spruce/scripts/platform/darkmoss/G350.cfg` in `spruceUI/spruceOS` (CPU 408–1416 MHz, 1512 in
  Overclock; GPU max 520 MHz; `PSP_BIN`; `SDL_GAMECONTROLLER_MAP`). CPU modes: `spruce/scripts/platform/utils/cpu_control_functions.sh`.
- **Emulator launch scripts:** `spruce/scripts/emu/lib/{ppsspp,flycast,mupen,ra}_functions.sh`.
- **Upstreams LightMoss tracks:** `.github/upstream-sync.json`.
- **arkos4clone / Arch-R / dArkOSen:** the same 5.10 kernel family. Their overclock dtsi is
  `arch/arm64/boot/dts/rockchip/rk3326-oc.dtsi` in the kernel tree.
