################################################################################
#
# rk3326-mali
#
################################################################################

# The blob, from christianhaitian/rk3326_core_builds (what dArkOS/dArkMoss
# install on the rg351 kernel; its kbase is r12p0). One package for both the
# 64-bit image and the 32-bit (lib32) runtime: the two blobs share a file
# name, so each architecture has its own version, download directory and
# hash file (<version>/rk3326-mali.hash).
RK3326_MALI_COMMIT = 2e1b272a8837b55ae4c17be48abe019dbb37ca7a
RK3326_MALI_ARCH = $(if $(BR2_arm),armhf,aarch64)
RK3326_MALI_VERSION = g31-rxp0-$(RK3326_MALI_ARCH)
RK3326_MALI_DL_SUBDIR = rk3326-mali-$(RK3326_MALI_ARCH)
RK3326_MALI_SITE = https://raw.githubusercontent.com/christianhaitian/rk3326_core_builds/$(RK3326_MALI_COMMIT)/mali/$(RK3326_MALI_ARCH)
RK3326_MALI_SOURCE = libmali-bifrost-g31-rxp0-gbm.so
RK3326_MALI_LICENSE = Proprietary
RK3326_MALI_LICENSE_FILES = END_USER_LICENCE_AGREEMENT.txt
RK3326_MALI_REDISTRIBUTE = NO
RK3326_MALI_INSTALL_STAGING = YES
RK3326_MALI_DEPENDENCIES = host-patchelf libdrm
RK3326_MALI_PROVIDES = libegl libgles libgbm

# The headers (and the EULA), one file at a time from rockchip's libmali
# (JeffyCN/mirrors, the commit buildroot's rockchip-mali uses): the whole
# repository is 350 MB of blobs for other GPUs.
RK3326_MALI_HDR_SITE = https://raw.githubusercontent.com/JeffyCN/mirrors/721653b5b3b525a4f80d15aa7e2f9df7b7e60427
RK3326_MALI_HEADERS = \
	EGL/egl.h EGL/eglext.h EGL/eglplatform.h \
	GLES/gl.h GLES/glext.h GLES/glplatform.h \
	GLES2/gl2.h GLES2/gl2ext.h GLES2/gl2platform.h \
	GLES3/gl3.h GLES3/gl31.h GLES3/gl32.h GLES3/gl3platform.h \
	KHR/khrplatform.h gbm.h
RK3326_MALI_EXTRA_DOWNLOADS = \
	$(addprefix $(RK3326_MALI_HDR_SITE)/include/,$(RK3326_MALI_HEADERS)) \
	$(RK3326_MALI_HDR_SITE)/END_USER_LICENCE_AGREEMENT.txt

# Every GL/EGL/GBM name a program may look for: they all are the blob.
# libwayland-egl is deliberately not among them (the blob does not export
# the wayland-egl API).
RK3326_MALI_LIB_SYMLINKS = \
	libmali.so.1 libmali.so libMali.so \
	libEGL.so libEGL.so.1 libEGL.so.1.1.0 \
	libGLESv1_CM.so libGLESv1_CM.so.1 libGLESv1_CM.so.1.1.0 \
	libGLES_CM.so libGLES_CM.so.1 \
	libGLESv2.so libGLESv2.so.2 libGLESv2.so.2.0.0 libGLESv2.so.2.1.0 \
	libGLESv3.so libGLESv3.so.3 \
	libgbm.so libgbm.so.1 libgbm.so.1.0.0

# The g29p1 blob for the R36S's second kernel (BSP 5.10, package
# lightmoss-linux510), whose g29p1 kbase it matches; it adds Vulkan (1.3,
# VK_KHR_display). From rockchip's libmali-next (JeffyCN/mirrors), the build
# arkos4clone and dArkOSen use. It is installed beside the rxp0 blob, in
# /usr/lib/mali-g29p1, and only lightmoss-mali-select puts it in rxp0's
# place, by bind mount, when a 5.10 kernel is running: 4.4 is untouched.
RK3326_MALI_G29P1_COMMIT = bf621d15f009509557d6b28f81427651695cac20
RK3326_MALI_G29P1_ARCH = $(if $(BR2_arm),arm-linux-gnueabihf,aarch64-linux-gnu)
RK3326_MALI_G29P1_FILE = libmali-bifrost-g31-g29p1.so
ifeq ($(BR2_PACKAGE_RK3326_MALI_G29P1),y)
RK3326_MALI_EXTRA_DOWNLOADS += \
	https://raw.githubusercontent.com/JeffyCN/mirrors/$(RK3326_MALI_G29P1_COMMIT)/lib/$(RK3326_MALI_G29P1_ARCH)/$(RK3326_MALI_G29P1_FILE)

# The armhf blob lists PT_GNU_STACK second among its program headers, before
# the LOAD segments it sits between; arkos4clone and dArkOSen move that entry
# (32 bytes at offset 84) after the other eight. The result is checked
# against the sha256 both of them check.
RK3326_MALI_G29P1_ARMHF_FIXED_SHA256 = 92455f88319628cb4623564c6dadcc3024123e8ae245eea7e8e13721efa87595
ifeq ($(BR2_arm),y)
define RK3326_MALI_G29P1_FIX_ARMHF
	cd $(@D) && cp g29p1/$(RK3326_MALI_G29P1_FILE) g29p1/orig.so && \
	{ dd if=g29p1/orig.so bs=1 skip=52 count=32 status=none; \
	  dd if=g29p1/orig.so bs=1 skip=116 count=224 status=none; \
	  dd if=g29p1/orig.so bs=1 skip=84 count=32 status=none; } > g29p1/phdr && \
	dd if=g29p1/phdr of=g29p1/$(RK3326_MALI_G29P1_FILE) bs=1 seek=52 \
		conv=notrunc status=none && \
	echo "$(RK3326_MALI_G29P1_ARMHF_FIXED_SHA256)  g29p1/$(RK3326_MALI_G29P1_FILE)" | \
		sha256sum -c - && rm -f g29p1/orig.so g29p1/phdr
endef
endif

define RK3326_MALI_G29P1_EXTRACT
	mkdir -p $(@D)/g29p1
	cp $(RK3326_MALI_DL_DIR)/$(RK3326_MALI_G29P1_FILE) $(@D)/g29p1/
	$(RK3326_MALI_G29P1_FIX_ARMHF)
endef
RK3326_MALI_POST_EXTRACT_HOOKS += RK3326_MALI_G29P1_EXTRACT

# In its own directory, never on the library path; buildroot's strip is kept
# off it (BR2_STRIP_EXCLUDE_DIRS) so the checked bytes stay as they are.
define RK3326_MALI_G29P1_INSTALL
	$(INSTALL) -D -m 0755 $(@D)/g29p1/$(RK3326_MALI_G29P1_FILE) \
		$(TARGET_DIR)/usr/lib/mali-g29p1/$(RK3326_MALI_G29P1_FILE)
endef
RK3326_MALI_POST_INSTALL_TARGET_HOOKS += RK3326_MALI_G29P1_INSTALL

# The 64-bit image also gets the switch and the Vulkan pieces.
ifeq ($(BR2_aarch64),y)
define RK3326_MALI_G29P1_INSTALL_SELECT
	$(INSTALL) -D -m 0755 $(RK3326_MALI_PKGDIR)/g29p1/lightmoss-mali-select \
		$(TARGET_DIR)/usr/libexec/lightmoss/mali-select
	$(INSTALL) -D -m 0644 $(RK3326_MALI_PKGDIR)/g29p1/lightmoss-mali-select.service \
		$(TARGET_DIR)/usr/lib/systemd/system/lightmoss-mali-select.service
	mkdir -p $(TARGET_DIR)/usr/lib/systemd/system/sysinit.target.wants
	ln -sf ../lightmoss-mali-select.service \
		$(TARGET_DIR)/usr/lib/systemd/system/sysinit.target.wants/lightmoss-mali-select.service
	$(INSTALL) -D -m 0644 $(RK3326_MALI_PKGDIR)/g29p1/70-mali-dma-heap.rules \
		$(TARGET_DIR)/usr/lib/udev/rules.d/70-mali-dma-heap.rules
	mkdir -p $(TARGET_DIR)/etc/vulkan/icd.d
	ln -sf /run/lightmoss/mali_icd.json $(TARGET_DIR)/etc/vulkan/icd.d/mali.json
endef
RK3326_MALI_POST_INSTALL_TARGET_HOOKS += RK3326_MALI_G29P1_INSTALL_SELECT
endif
endif

define RK3326_MALI_EXTRACT_CMDS
	cp $(RK3326_MALI_DL_DIR)/$(RK3326_MALI_SOURCE) $(@D)/
	cp $(RK3326_MALI_DL_DIR)/END_USER_LICENCE_AGREEMENT.txt $(@D)/
	$(foreach h,$(RK3326_MALI_HEADERS),
		$(INSTALL) -D -m 0644 $(RK3326_MALI_DL_DIR)/$(notdir $(h)) \
			$(@D)/include/$(h)
	)
	# GLES/egl.h is a compatibility header that only includes EGL/egl.h.
	printf '#include <EGL/egl.h>\n' > $(@D)/include/GLES/egl.h
	# Mesa's GBM_BO_USE_LINEAR (1 << 4), which SDL2's KMSDRM driver uses
	# unguarded: rockchip's gbm.h predates it. dArkMoss's SDL2 is built
	# against Mesa's header and runs on this same blob.
	sed -i 's/^\(\s*\)GBM_BO_USE_WRITE\(\s*\)= (1 << 3),/&\n\1GBM_BO_USE_LINEAR = (1 << 4),/' \
		$(@D)/include/gbm.h
	grep -q 'GBM_BO_USE_LINEAR = (1 << 4)' $(@D)/include/gbm.h
endef

# A proper soname, so what links against it records libmali.so.1.
define RK3326_MALI_BUILD_CMDS
	$(HOST_DIR)/bin/patchelf --set-soname libmali.so.1 $(@D)/$(RK3326_MALI_SOURCE)
endef

define RK3326_MALI_INSTALL_LIB
	$(INSTALL) -D -m 0755 $(@D)/$(RK3326_MALI_SOURCE) \
		$(1)/usr/lib/$(RK3326_MALI_SOURCE)
	$(foreach l,$(RK3326_MALI_LIB_SYMLINKS),
		ln -sf $(RK3326_MALI_SOURCE) $(1)/usr/lib/$(l)
	)
endef

define RK3326_MALI_INSTALL_STAGING_CMDS
	$(call RK3326_MALI_INSTALL_LIB,$(STAGING_DIR))
	mkdir -p $(STAGING_DIR)/usr/include
	cp -dpfr $(@D)/include/* $(STAGING_DIR)/usr/include/
	$(foreach pc,egl gbm glesv1_cm glesv2 mali,
		$(INSTALL) -D -m 0644 $(RK3326_MALI_PKGDIR)/pkgconfig/$(pc).pc \
			$(STAGING_DIR)/usr/lib/pkgconfig/$(pc).pc
	)
endef

define RK3326_MALI_INSTALL_TARGET_CMDS
	$(call RK3326_MALI_INSTALL_LIB,$(TARGET_DIR))
endef

$(eval $(generic-package))
