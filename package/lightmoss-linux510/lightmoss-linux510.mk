################################################################################
#
# lightmoss-linux510
#
################################################################################

# Rockchip's BSP 5.10 kernel as the R36S's second kernel, next to the 4.4
# one buildroot builds as BR2_LINUX_KERNEL (it builds only one). It runs the
# Mali g29p1 blob (package rk3326-mali-g29p1), whose Vulkan the 4.4 kernel's
# r12p0 kbase cannot carry. boot.ini starts it instead of 4.4 when the file
# "lightmoss-kernel-5.10" is on the BOOT partition.
#
# Source: jokubasver/rockchip-kernel, branch arkos4clone-5.10 (lcdyk0517's
# and jokubasver's RK3326 handheld kernel, arkos4clone's 5.10 option),
# pinned; LightMoss's patches and config fragment are in
# board/r36s/linux-5.10.
LIGHTMOSS_LINUX510_VERSION = f2d282f266a4641a8cd4664ae1ebc11cb8bff301
# GitHub's archive of the commit (~200 MB) rather than a clone of the whole
# repository, which CI's disk could not also hold next to the 4.4 kernel's.
LIGHTMOSS_LINUX510_SITE = $(call github,jokubasver,rockchip-kernel,$(LIGHTMOSS_LINUX510_VERSION))
LIGHTMOSS_LINUX510_LICENSE = GPL-2.0
LIGHTMOSS_LINUX510_LICENSE_FILES = COPYING
LIGHTMOSS_LINUX510_INSTALL_IMAGES = YES
LIGHTMOSS_LINUX510_DEPENDENCIES = host-bison host-flex host-kmod host-openssl host-bc

LIGHTMOSS_LINUX510_BOARD_DIR = $(BR2_EXTERNAL_LIGHTMOSS_PATH)/board/r36s/linux-5.10
LIGHTMOSS_LINUX510_DEFCONFIG = clone_defconfig
LIGHTMOSS_LINUX510_FRAGMENT = $(LIGHTMOSS_LINUX510_BOARD_DIR)/lightmoss-5.10.config
# kernel DTB name -> name on the BOOT partition (boot.ini adds -5.10)
LIGHTMOSS_LINUX510_DTBS = \
	rk3326-r36sclone-linux \
	rk3326-r36sclone-panel9-linux

# As buildroot's linux.mk does it: host make environment (host-pkgconf finds
# host libraries), the kernel's host programs built with the host compiler
# and buildroot's host libraries, WERROR=0 for kernels that have it.
LIGHTMOSS_LINUX510_DEPENDENCIES += $(BR2_MAKE_HOST_DEPENDENCY)
LIGHTMOSS_LINUX510_KCFLAGS = -Wno-attribute-alias
LIGHTMOSS_LINUX510_MAKE = \
	$(HOST_MAKE_ENV) $(BR2_MAKE) -C $(@D) \
	HOSTCC="$(HOSTCC) $(subst -I/,-isystem /,$(subst -I /,-isystem /,$(HOST_CFLAGS))) $(HOST_LDFLAGS)" \
	ARCH=arm64 \
	KCFLAGS="$(LIGHTMOSS_LINUX510_KCFLAGS)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	WERROR=0 \
	DEPMOD=$(HOST_DIR)/sbin/depmod

define LIGHTMOSS_LINUX510_APPLY_BOARD_PATCHES
	$(APPLY_PATCHES) $(@D) $(LIGHTMOSS_LINUX510_BOARD_DIR)/patches \*.patch
endef
LIGHTMOSS_LINUX510_POST_PATCH_HOOKS += LIGHTMOSS_LINUX510_APPLY_BOARD_PATCHES

# clone_defconfig, then LightMoss's fragment, the way buildroot merges
# BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES. Every fragment line must survive
# (board/r36s/linux-5.10/check-fragment.sh): a value exactly, an "is not set"
# as not set (a symbol whose dependencies are off is left out of .config
# altogether, which is just as off).
define LIGHTMOSS_LINUX510_CONFIGURE_CMDS
	$(LIGHTMOSS_LINUX510_MAKE) $(LIGHTMOSS_LINUX510_DEFCONFIG)
	cd $(@D) && $(HOST_MAKE_ENV) ARCH=arm64 \
		./scripts/kconfig/merge_config.sh -m .config $(LIGHTMOSS_LINUX510_FRAGMENT)
	$(LIGHTMOSS_LINUX510_MAKE) olddefconfig
	$(SHELL) $(LIGHTMOSS_LINUX510_BOARD_DIR)/check-fragment.sh \
		$(LIGHTMOSS_LINUX510_FRAGMENT) $(@D)/.config
endef

define LIGHTMOSS_LINUX510_BUILD_CMDS
	$(LIGHTMOSS_LINUX510_MAKE) -j$(PARALLEL_JOBS) Image modules \
		$(addprefix rockchip/,$(addsuffix .dtb,$(LIGHTMOSS_LINUX510_DTBS)))
endef

define LIGHTMOSS_LINUX510_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/arch/arm64/boot/Image $(BINARIES_DIR)/Image-5.10
	$(foreach d,$(LIGHTMOSS_LINUX510_DTBS),
		$(INSTALL) -D -m 0644 $(@D)/arch/arm64/boot/dts/rockchip/$(d).dtb \
			$(BINARIES_DIR)/$(d)-5.10.dtb
	)
endef

# Modules next to 4.4's in /lib/modules (each kernel finds its own by
# release), stripped as linux.mk does, depmod run for the target tree.
define LIGHTMOSS_LINUX510_INSTALL_TARGET_CMDS
	$(LIGHTMOSS_LINUX510_MAKE) INSTALL_MOD_PATH=$(TARGET_DIR) \
		INSTALL_MOD_STRIP=1 modules_install
	release="$$(cat $(@D)/include/config/kernel.release)"; \
	rm -f $(TARGET_DIR)/lib/modules/$$release/build \
		$(TARGET_DIR)/lib/modules/$$release/source
endef

$(eval $(generic-package))
