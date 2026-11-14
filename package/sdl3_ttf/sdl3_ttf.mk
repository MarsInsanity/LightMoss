################################################################################
#
# sdl3_ttf
#
################################################################################

SDL3_TTF_VERSION = 3.2.2
SDL3_TTF_SOURCE = SDL3_ttf-$(SDL3_TTF_VERSION).tar.gz
SDL3_TTF_SITE = https://github.com/libsdl-org/SDL_ttf/releases/download/release-$(SDL3_TTF_VERSION)
SDL3_TTF_LICENSE = Zlib
SDL3_TTF_LICENSE_FILES = LICENSE.txt
SDL3_TTF_INSTALL_STAGING = YES
SDL3_TTF_DEPENDENCIES = sdl3 freetype

SDL3_TTF_CONF_OPTS = \
	-DSDLTTF_VENDORED=OFF \
	-DSDLTTF_STRICT=ON \
	-DSDLTTF_SAMPLES=OFF \
	-DSDLTTF_PLUTOSVG=OFF

ifeq ($(BR2_PACKAGE_HARFBUZZ),y)
SDL3_TTF_DEPENDENCIES += harfbuzz
SDL3_TTF_CONF_OPTS += -DSDLTTF_HARFBUZZ=ON
else
SDL3_TTF_CONF_OPTS += -DSDLTTF_HARFBUZZ=OFF
endif

$(eval $(cmake-package))
