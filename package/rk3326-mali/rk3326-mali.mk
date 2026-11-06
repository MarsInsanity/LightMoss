################################################################################
#
# rk3326-mali
#
################################################################################

# The blob, from christianhaitian/rk3326_core_builds (what dArkOS/dArkMoss
# install on the rg351 kernel; its kbase is r12p0).
RK3326_MALI_VERSION = 2e1b272a8837b55ae4c17be48abe019dbb37ca7a
RK3326_MALI_SITE = https://raw.githubusercontent.com/christianhaitian/rk3326_core_builds/$(RK3326_MALI_VERSION)/mali/aarch64
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
