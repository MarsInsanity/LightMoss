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

# Desktop OpenGL through libglvnd (the Mini V2's builds, as above): keep
# glvnd's GL/gl.h, GL/glext.h and GL/glcorearb.h in staging for programs
# built against libOpenGL.so.0 (pkg-config opengl). mesa3d.mk removes
# $(STAGING_DIR)/usr/include/GL/ after installing Mesa whenever it builds
# no GLX; with glvnd, installed first as Mesa's dependency, those are
# glvnd's, and Mesa installs no GL headers of its own. Hooks are expanded
# when they run, after this file.
ifeq ($(BR2_PACKAGE_LIBGLVND),y)
MESA3D_POST_INSTALL_STAGING_HOOKS := \
	$(filter-out MESA3D_REMOVE_OPENGL_HEADERS,$(MESA3D_POST_INSTALL_STAGING_HOOKS))
endif
endif

# SDL2's Vulkan support (BR2_LIGHTMOSS_SDL2_VULKAN: the Mini V2's Turnip, the
# R36S's g29p1 blob), which buildroot's sdl2.mk turns off
# (--disable-video-vulkan; the later --enable wins). Its KMS/DRM driver then
# makes Vulkan surfaces on VK_KHR_display, drops DRM master for the Vulkan
# driver and loads libvulkan.so.1 at run time: PPSSPP's and Flycast's Vulkan
# backends go through it.
ifeq ($(BR2_LIGHTMOSS_SDL2_VULKAN)$(BR2_PACKAGE_SDL2),yy)
SDL2_CONF_OPTS += --enable-video-vulkan
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
