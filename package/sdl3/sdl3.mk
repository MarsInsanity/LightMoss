################################################################################
#
# sdl3
#
################################################################################

SDL3_VERSION = 3.4.20
SDL3_SOURCE = SDL3-$(SDL3_VERSION).tar.gz
SDL3_SITE = https://github.com/libsdl-org/SDL/releases/download/release-$(SDL3_VERSION)
SDL3_LICENSE = Zlib
SDL3_LICENSE_FILES = LICENSE.txt
SDL3_CPE_ID_VENDOR = libsdl
SDL3_CPE_ID_PRODUCT = simple_directmedia_layer
SDL3_INSTALL_STAGING = YES
SDL3_DEPENDENCIES = host-pkgconf libdrm libgbm libegl libgles

# What SDL2 is built with here (configs/lightmoss_r36s_defconfig), in SDL3's
# terms. SDL_UNIX_CONSOLE_BUILD: no X11 and no Wayland, on purpose.
# SDL_ROCKCHIP would pick up the blob's mali.pc and add a second video driver
# next to KMS/DRM; SDL2 has only KMS/DRM, and spruce's PyUI hands the
# display over the same way to both. Its libraries are loaded at run time
# (SDL_DEPS_SHARED, the default), as SDL2 does.
SDL3_CONF_OPTS = \
	-DSDL_SHARED=ON \
	-DSDL_STATIC=OFF \
	-DSDL_TEST_LIBRARY=OFF \
	-DSDL_TESTS=OFF \
	-DSDL_EXAMPLES=OFF \
	-DSDL_INSTALL_DOCS=OFF \
	-DSDL_RPATH=OFF \
	-DSDL_CCACHE=OFF \
	-DSDL_UNIX_CONSOLE_BUILD=ON \
	-DSDL_KMSDRM=ON \
	-DSDL_OPENGLES=ON \
	-DSDL_OPENGL=OFF \
	-DSDL_X11=OFF \
	-DSDL_WAYLAND=OFF \
	-DSDL_VULKAN=OFF \
	-DSDL_RPI=OFF \
	-DSDL_ROCKCHIP=OFF \
	-DSDL_PULSEAUDIO=OFF \
	-DSDL_PIPEWIRE=OFF \
	-DSDL_JACK=OFF \
	-DSDL_SNDIO=OFF \
	-DSDL_OSS=OFF \
	-DSDL_DBUS=OFF \
	-DSDL_IBUS=OFF \
	-DSDL_LIBURING=OFF \
	-DSDL_HIDAPI_LIBUSB=OFF

ifeq ($(BR2_PACKAGE_ALSA_LIB),y)
SDL3_DEPENDENCIES += alsa-lib
SDL3_CONF_OPTS += -DSDL_ALSA=ON
else
SDL3_CONF_OPTS += -DSDL_ALSA=OFF
endif

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
SDL3_DEPENDENCIES += udev
SDL3_CONF_OPTS += -DSDL_LIBUDEV=ON
else
SDL3_CONF_OPTS += -DSDL_LIBUDEV=OFF
endif

$(eval $(cmake-package))
