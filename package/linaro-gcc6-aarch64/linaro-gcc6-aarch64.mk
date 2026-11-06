################################################################################
#
# linaro-gcc6-aarch64
#
################################################################################

# Linaro GCC 6.3.1 (2017.05), the toolchain Rockchip's legacy U-Boot is built
# and tested with. Only rk3326-uboot uses it; everything else is built with
# buildroot's own toolchain. Fetched from christianhaitian's copy, the one
# dArkOS/dArkMoss build their U-Boot with.
LINARO_GCC6_AARCH64_VERSION = cb13553920ca235b3bf568900779dc349e0ebce4
LINARO_GCC6_AARCH64_SITE = https://github.com/christianhaitian/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git
LINARO_GCC6_AARCH64_SITE_METHOD = git
LINARO_GCC6_AARCH64_LICENSE = GPL-3.0+, LGPL-3.0+ (Linaro GCC 6.3.1 binaries)

HOST_LINARO_GCC6_AARCH64_INSTALL_DIR = $(HOST_DIR)/opt/gcc-linaro-6.3.1-aarch64

define HOST_LINARO_GCC6_AARCH64_INSTALL_CMDS
	rm -rf $(HOST_LINARO_GCC6_AARCH64_INSTALL_DIR)
	mkdir -p $(HOST_LINARO_GCC6_AARCH64_INSTALL_DIR)
	cp -a $(@D)/. $(HOST_LINARO_GCC6_AARCH64_INSTALL_DIR)/
endef

$(eval $(host-generic-package))
