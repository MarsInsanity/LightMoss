#!/bin/bash
# Build PPSSPPSDL_dArkMoss3326_vk: spruce's PPSSPPSDL_dArkMoss3326 (PPSSPP v1.20.3,
# RK3326 / Cortex-A35, SDL2 on KMSDRM, GLES2) with Vulkan presented through
# VK_KHR_display added the way spruce's PPSSPPSDL_Flip does it.
#
# Recipe = spruceUI/PPSSPP-spruce build-darkmoss3326.sh + Dockerfile.darkmoss3326
# (same toolchain, sysroot, patches, CPU target and CMake flags), with the Vulkan
# changes from build-flip.sh (commit e193c9a "Flip: build Vulkan on VK_KHR_display"):
#   - patches/common/skip-vulkan-probe.py is NOT applied (it disables Vulkan),
#   - patches/pvr/vulkan-display-fallback.py is applied,
#   - -DVULKAN=ON -DUSE_VULKAN_DISPLAY_KHR=ON.
# libvulkan is dlopen()ed by PPSSPP at run time (VulkanLoader.cpp), not linked; without
# a Vulkan driver PPSSPP stays on OpenGL ES.
#
# Runs on an x86_64 Linux host (tested: Ubuntu 24.04) with git, curl, python3, cmake
# (>= 3.16) and make or ninja. No root, no Docker needed.
#
# Usage: tools/ppsspp-vk/build.sh   (work dir $HOME/ppsspp-vk, ~6 GB; output in $WORK/out)
#   WORK=/path OUT=/path tools/ppsspp-vk/build.sh
# Keep WORK outside the LightMoss checkout. The build sent to the owner in November 2026
# (PPSSPPSDL_dArkMoss3326_vk, v1.20.3) had sha256
# 5c8b57d4eb07dab32cdb44c99380bef68548e0fa30bb72b9a8207ec2be72c029.
set -euo pipefail

WORK="${WORK:-$HOME/ppsspp-vk}"
OUT="${OUT:-$WORK/out}"
JOBS="${JOBS:-$(nproc)}"

PPSSPP_VERSION="v1.20.3"
PPSSPP_COMMIT="d357e6a32934800d3d80b49f910a603e1b069751"      # tag v1.20.3
SPRUCE_REPO="https://github.com/spruceUI/PPSSPP-spruce"
SPRUCE_REV="e193c9a1d4aca6bbce927012b4e175f422ad6378"          # main, 2026-11-14
TOOLCHAIN_URL="https://github.com/steward-fu/website/releases/download/miyoo-flip/flip-toolchain-v1.0.tar.gz"
TOOLCHAIN_SHA256="1e975625ffc5ef8ffb9c243fadb36b587cb9611a89e7b817879d1a5bb14cbaeb"
NAME="PPSSPPSDL_dArkMoss3326_vk"

TC="$WORK/toolchain"
SPRUCE="$WORK/PPSSPP-spruce"
SRC="$WORK/ppsspp"
BUILD="$WORK/build"
mkdir -p "$WORK" "$OUT"

# --- 1. Toolchain: Steward-Fu Miyoo Flip toolchain (Buildroot 2024.08.2, GCC 13.3.0,
#        glibc 2.38; sysroot with SDL2 2.30.5, Mesa EGL/GLES2, zlib) - the one spruce's
#        dArkMoss3326 and Flip builds use.
if [ ! -x "$TC/bin/aarch64-flip-linux-gnu-gcc" ]; then
    echo "=== Fetching toolchain"
    TARBALL="$WORK/flip-toolchain-v1.0.tar.gz"
    curl -sSfL -o "$TARBALL" "$TOOLCHAIN_URL"
    echo "$TOOLCHAIN_SHA256  $TARBALL" | sha256sum -c -
    mkdir -p "$TC"
    tar xzf "$TARBALL" -C "$TC" --strip-components=1
    rm -f "$TARBALL"
fi
CC="$TC/bin/aarch64-flip-linux-gnu-gcc"
CXX="$TC/bin/aarch64-flip-linux-gnu-g++"
STRIP="$TC/bin/aarch64-flip-linux-gnu-strip"
SYSROOT="$("$CC" -print-sysroot)"

# --- 2. spruce's patch set, pinned.
if [ ! -d "$SPRUCE/.git" ]; then
    git clone --filter=blob:none --no-checkout "$SPRUCE_REPO" "$SPRUCE"
fi
git -C "$SPRUCE" checkout -q --detach "$SPRUCE_REV"
PATCHES="$SPRUCE/patches"

# --- 3. PPSSPP v1.20.3 with submodules (as build-darkmoss3326.sh clones it).
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$PPSSPP_VERSION" --recurse-submodules --shallow-submodules \
        https://github.com/hrydgard/ppsspp.git "$SRC"
    # Disk saving only: prebuilt FFmpeg for other platforms and the test corpus are unused here.
    ( cd "$SRC" && rm -rf ffmpeg/Windows10 ffmpeg/Windows ffmpeg/android ffmpeg/ios ffmpeg/macosx \
        ffmpeg/wiiu ffmpeg/blackberry ffmpeg/symbian ffmpeg/tvos \
        ffmpeg/linux/{armv7,loongarch64,mips32,riscv64,webos,x86,x86_64} \
        .git/modules/ffmpeg .git/modules/pspautotests ios/MoltenVK &&
      find pspautotests -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + )
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$PPSSPP_COMMIT" ] || { echo "unexpected PPSSPP commit" >&2; exit 1; }
# Bundled libpng puts __DATE__/__TIME__ in its copyright string; pin them to the commit
# date (GCC honours SOURCE_DATE_EPOCH) so rebuilds are bit-identical.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$SRC" log -1 --format=%ct)}"

# --- 4. Patches (reset the patched files first so reruns are idempotent).
cd "$SRC"
git checkout -q -- SDL Core Common UI
echo "=== Applying patches"
for patch in "$PATCHES"/common/*.py; do
    case "$(basename "$patch")" in
        skip-vulkan-probe.py) echo "Skipping: skip-vulkan-probe.py (Vulkan build)" ;;
        *) python3 "$patch" && echo "Applied: $(basename "$patch")" ;;
    esac
done
for patch in "$PATCHES"/darkmoss/*.py; do
    python3 "$patch" && echo "Applied: $(basename "$patch")"
done
python3 "$PATCHES/pvr/vulkan-display-fallback.py" && echo "Applied: vulkan-display-fallback.py"

# --- 5. CMake toolchain file, identical to the one Dockerfile.darkmoss3326 writes.
TCFILE="$WORK/flip-toolchain.cmake"
printf '%s\n' \
    "set(CMAKE_SYSTEM_NAME Linux)" \
    "set(CMAKE_SYSTEM_PROCESSOR aarch64)" \
    "set(CMAKE_C_COMPILER $CC)" \
    "set(CMAKE_CXX_COMPILER $CXX)" \
    "set(CMAKE_SYSROOT $SYSROOT)" \
    "set(CMAKE_FIND_ROOT_PATH $SYSROOT)" \
    "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)" \
    "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)" \
    "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)" \
    "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)" \
    "set(PKG_CONFIG_EXECUTABLE /usr/bin/pkg-config)" \
    "set(ENV{PKG_CONFIG_SYSROOT_DIR} \"$SYSROOT\")" \
    "set(ENV{PKG_CONFIG_LIBDIR} \"$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig\")" \
    "set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)" > "$TCFILE"

# --- 6. Configure: build-darkmoss3326.sh's options, plus VULKAN/USE_VULKAN_DISPLAY_KHR.
#        -mcpu=cortex-a35 = ARMv8.0-A+crc: no LSE, no RCpc, no dotprod. GCC 13's default
#        -moutline-atomics keeps the only LSE code in libgcc's runtime-dispatched helpers.
GEN="Unix Makefiles"; command -v ninja >/dev/null && GEN="Ninja"
CFLAGS="-Ofast -mcpu=cortex-a35 -ffunction-sections -fdata-sections -fomit-frame-pointer -flto=auto -Wno-error"
# Not in spruce's script: __FILE__ (assert/log strings) would embed this machine's work
# dir. Map it to /build/ppsspp, the path spruce's Docker builds carry, so the binary does
# not depend on where it was built.
CFLAGS="$CFLAGS -ffile-prefix-map=$SRC=/build/ppsspp -ffile-prefix-map=$BUILD=/build/ppsspp/build"
rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
cmake "$SRC" -G "$GEN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$TCFILE" \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_CXX_FLAGS="$CFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--gc-sections -flto=auto" \
    -DUSING_GLES2=ON \
    -DUSING_EGL=OFF \
    -DUSING_FBDEV=OFF \
    -DVULKAN=ON \
    -DUSE_VULKAN_DISPLAY_KHR=ON \
    -DUSING_X11_VULKAN=OFF \
    -DUSE_WAYLAND_WSI=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DUSE_SYSTEM_LIBPNG=OFF \
    -DUSE_SYSTEM_FFMPEG=OFF \
    -DUSE_DISCORD=OFF \
    -DUSE_MINIUPNPC=OFF \
    -DHEADLESS=OFF \
    -DUNITTEST=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_SDL2_ttf=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_Fontconfig=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_X11=ON

# Same fix as spruce's script: -isystem paths get sysroot-prepended by GCC.
find . \( -name 'flags.make' -o -name 'build.ninja' \) -exec sed -i 's|-isystem |-I|g' {} +

# --- 7. Build, strip, publish.
cmake --build . --target PPSSPPSDL -j "$JOBS"
cp PPSSPPSDL "$OUT/$NAME"
"$STRIP" -s "$OUT/$NAME"
( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" && cat "$NAME.sha256" )

# --- 8. Checks.
B="$OUT/$NAME"
RE="$TC/bin/aarch64-flip-linux-gnu-readelf"
OD="$TC/bin/aarch64-flip-linux-gnu-objdump"
echo "=== NEEDED";  "$RE" -d "$B" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' '; echo
echo "=== max GLIBC / GLIBCXX / CXXABI"
"$RE" -V "$B" | grep -o 'GLIBC_[0-9.]*'   | sort -uV | tail -1
"$RE" -V "$B" | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -1
"$RE" -V "$B" | grep -o 'CXXABI_[0-9.]*'  | sort -uV | tail -1
echo "=== ARMv8.1+ instructions (LSE / RCpc / dotprod)"
"$OD" -d --no-show-raw-insn "$B" | awk '{print $2}' |
    grep -E '^(ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|swp|cas|ldapr|stlur|ldapur|sdot|udot)' |
    sort | uniq -c || echo "none"
echo "=== Vulkan display strings"
strings "$B" | grep -cE '^(VK_KHR_display|vkCreateDisplayPlaneSurfaceKHR)$' || true
echo "=== Done: $B"
