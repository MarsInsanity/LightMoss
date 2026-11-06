################################################################################
#
# rk3326-uboot
#
################################################################################

RK3326_UBOOT_VERSION = d793d20d61219cdb476b4df3bda84932843588b6
RK3326_UBOOT_SITE = https://github.com/christianhaitian/RG351MP-u-boot.git
RK3326_UBOOT_SITE_METHOD = git
RK3326_UBOOT_LICENSE = GPL-2.0+
RK3326_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt
RK3326_UBOOT_INSTALL_TARGET = NO
RK3326_UBOOT_INSTALL_IMAGES = YES
RK3326_UBOOT_DEPENDENCIES = host-linaro-gcc6-aarch64 host-bison host-flex host-python3

RK3326_UBOOT_BOARD_DIR = $(BR2_EXTERNAL_LIGHTMOSS_PATH)/board/r36s/uboot

# The G80CA board (r36sclone-uboot.dts), its two panels, and the same board
# starting on Panel 9; 0001 adds them to arch/arm/dts/Makefile.
define RK3326_UBOOT_COPY_BOARD_DTS
	cp $(RK3326_UBOOT_BOARD_DIR)/*.dts $(RK3326_UBOOT_BOARD_DIR)/*.dtsi \
		$(@D)/arch/arm/dts/
endef
RK3326_UBOOT_POST_PATCH_HOOKS += RK3326_UBOOT_COPY_BOARD_DTS

# make.sh runs its own make -j; keep buildroot's jobserver and flags out of it.
define RK3326_UBOOT_BUILD_CMDS
	cd $(@D) && env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL \
		PATH=$(BR_PATH) \
		TOOLCHAIN_ARM64=$(HOST_DIR)/opt/gcc-linaro-6.3.1-aarch64/bin \
		./make.sh odroidgoa
endef

define RK3326_UBOOT_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/idbloader.img $(BINARIES_DIR)/idbloader.img
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/uboot.img $(BINARIES_DIR)/uboot.img
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/trust.img $(BINARIES_DIR)/trust.img
	$(INSTALL) -D -m 0644 $(@D)/arch/arm/dts/r36sclone-uboot.dtb $(BINARIES_DIR)/uboot.dtb
	$(INSTALL) -D -m 0644 $(@D)/arch/arm/dts/r36sclone-panel9-uboot.dtb \
		$(BINARIES_DIR)/uboot-panel9.dtb
endef

$(eval $(generic-package))
