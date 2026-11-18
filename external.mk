include $(sort $(wildcard $(BR2_EXTERNAL_LIGHTMOSS_PATH)/package/*/*.mk))

# Turnip, Mesa's Vulkan driver for Adreno (the Mini V2's builds only).
# BR2_LIGHTMOSS_MESA3D_TURNIP selects mesa3d's hidden Vulkan driver symbol,
# so mesa3d.mk already depends on host-python-glslang and passes
# -Dvulkan-drivers=<MESA3D_VULKAN_DRIVERS-y>: MESA3D_CONF_OPTS is a
# recursively expanded variable, read when Mesa is configured, after this
# file. Mesa installs the ICD manifest as
# /usr/share/vulkan/icd.d/freedreno_icd.<cpu>.json (library_arch "64"); the
# 32-bit one comes from package/lightmoss-lib32.
ifeq ($(BR2_LIGHTMOSS_MESA3D_TURNIP),y)
MESA3D_VULKAN_DRIVERS-y += freedreno

# SDL2's Vulkan support, which buildroot's sdl2.mk turns off
# (--disable-video-vulkan; the later --enable wins). Its KMS/DRM driver then
# makes Vulkan surfaces on VK_KHR_display, drops DRM master for the Vulkan
# driver and loads libvulkan.so.1 at run time: PPSSPP's and Flycast's Vulkan
# backends go through it.
ifeq ($(BR2_PACKAGE_SDL2),y)
SDL2_CONF_OPTS += --enable-video-vulkan
endif
endif

# The lib32 build: its libraries live in /usr/lib/arm-linux-gnueabihf on the
# 64-bit image, next to the 64-bit ones in /usr/lib, so the armhf loader must
# search that directory. glibc reads configparms from its build directory;
# user-defined-trusted-dirs is appended to the loader's built-in search path
# (after /lib and /usr/lib, where it skips the 64-bit libraries).
ifeq ($(BR2_LIGHTMOSS_LIB32),y)
define LIGHTMOSS_GLIBC_TRUSTED_DIRS
	echo "user-defined-trusted-dirs=/usr/lib/arm-linux-gnueabihf" >> $(@D)/build/configparms
endef
GLIBC_POST_CONFIGURE_HOOKS += LIGHTMOSS_GLIBC_TRUSTED_DIRS

# Mesa's libgbm has no built-in backend: it dlopens dri_gbm.so from a
# directory compiled in as $libdir/gbm, /usr/lib/gbm, where the 64-bit image
# has its own (64-bit) plugin. The 32-bit libgbm looks in the lib32
# directory instead, where package/lightmoss-lib32 installs the 32-bit one.
# Only the Mini V2's lib32 build has Mesa (the R36S's has the Mali blob).
MESA3D_CONF_OPTS += -Dgbm-backends-path=/usr/lib/arm-linux-gnueabihf/gbm
endif
