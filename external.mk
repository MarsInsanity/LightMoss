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
endif
