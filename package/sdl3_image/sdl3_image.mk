################################################################################
#
# sdl3_image
#
################################################################################

SDL3_IMAGE_VERSION = 3.4.8
SDL3_IMAGE_SOURCE = SDL3_image-$(SDL3_IMAGE_VERSION).tar.gz
SDL3_IMAGE_SITE = https://github.com/libsdl-org/SDL_image/releases/download/release-$(SDL3_IMAGE_VERSION)
SDL3_IMAGE_LICENSE = Zlib
SDL3_IMAGE_LICENSE_FILES = LICENSE.txt
SDL3_IMAGE_INSTALL_STAGING = YES
SDL3_IMAGE_DEPENDENCIES = sdl3

# Linked against the libraries it uses (not loaded at run time), only the
# enabled ones, and failing the build if one of those is not found.
SDL3_IMAGE_CONF_OPTS = \
	-DSDLIMAGE_VENDORED=OFF \
	-DSDLIMAGE_DEPS_SHARED=OFF \
	-DSDLIMAGE_STRICT=ON \
	-DSDLIMAGE_SAMPLES=OFF \
	-DSDLIMAGE_TESTS=OFF \
	-DSDLIMAGE_BACKEND_STB=ON \
	-DSDLIMAGE_AVIF=OFF \
	-DSDLIMAGE_JXL=OFF

ifeq ($(BR2_PACKAGE_LIBPNG),y)
SDL3_IMAGE_DEPENDENCIES += libpng
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_PNG_LIBPNG=ON
else
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_PNG_LIBPNG=OFF
endif

ifeq ($(BR2_PACKAGE_TIFF),y)
SDL3_IMAGE_DEPENDENCIES += tiff
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_TIF=ON
else
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_TIF=OFF
endif

# WebP needs both libwebpdemux and libwebpmux.
ifeq ($(BR2_PACKAGE_WEBP_DEMUX)$(BR2_PACKAGE_WEBP_MUX),yy)
SDL3_IMAGE_DEPENDENCIES += webp
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_WEBP=ON
else
SDL3_IMAGE_CONF_OPTS += -DSDLIMAGE_WEBP=OFF
endif

$(eval $(cmake-package))
