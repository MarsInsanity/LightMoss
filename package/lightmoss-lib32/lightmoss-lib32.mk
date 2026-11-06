################################################################################
#
# lightmoss-lib32
#
################################################################################

# The lib32 build's output directory: output -> output-lib32 by default, as
# the top-level Makefile builds it.
LIGHTMOSS_LIB32_DIR ?= $(BASE_DIR)-lib32

LIGHTMOSS_LIB32_VERSION = 1.0
LIGHTMOSS_LIB32_SITE = $(LIGHTMOSS_LIB32_DIR)/target
LIGHTMOSS_LIB32_SITE_METHOD = local
LIGHTMOSS_LIB32_LICENSE = various (see the lib32 build's legal-info)

LIGHTMOSS_LIB32_LIBDIR = /usr/lib/arm-linux-gnueabihf
# 32-bit ARM binaries in a 64-bit image, on purpose.
LIGHTMOSS_LIB32_BIN_ARCH_EXCLUDE = $(LIGHTMOSS_LIB32_LIBDIR) /usr/lib/ld-linux-armhf.so.3

# Every shared library of the armhf build (glibc's from /lib, the rest from
# /usr/lib), with their soname links; nothing else (no programs, no config).
define LIGHTMOSS_LIB32_INSTALL_TARGET_CMDS
	@test -e $(@D)/lib/ld-linux-armhf.so.3 || { \
		echo "lightmoss-lib32: no armhf runtime in $(LIGHTMOSS_LIB32_DIR)"; \
		echo "  build it first: make lib32 (or set LIGHTMOSS_LIB32_DIR)"; exit 1; }
	rm -rf $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)
	mkdir -p $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)
	for d in lib usr/lib; do \
		find $(@D)/$$d -maxdepth 1 -name '*.so*' \( -type f -o -type l \) \
			-exec cp -a {} $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)/ \; ; \
	done
	# One directory now: links into the other one (../../lib/libfoo.so.1)
	# point at the file's own name, and links to nothing are dropped.
	cd $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR) && for f in *; do \
		[ -L "$$f" ] || continue; \
		t="$$(readlink "$$f")"; \
		case "$$t" in */*) ln -sfn "$${t##*/}" "$$f" ;; esac; \
		[ -e "$$f" ] || unlink "$$f"; \
	done
	ln -sf arm-linux-gnueabihf/ld-linux-armhf.so.3 \
		$(TARGET_DIR)/usr/lib/ld-linux-armhf.so.3
endef

$(eval $(generic-package))
