include $(sort $(wildcard $(BR2_EXTERNAL_LIGHTMOSS_PATH)/package/*/*.mk))

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
