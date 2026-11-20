################################################################################
#
# lightmoss-lib32
#
################################################################################

# The lib32 build's output directory: output -> output-lib32 by default, as
# the top-level Makefile builds it.
LM_LIB32_OUTPUT ?= $(BASE_DIR)-lib32

LIGHTMOSS_LIB32_VERSION = 1.0
LIGHTMOSS_LIB32_SITE = $(LM_LIB32_OUTPUT)/target
LIGHTMOSS_LIB32_SITE_METHOD = local
LIGHTMOSS_LIB32_LICENSE = various (see the lib32 build's legal-info)

LIGHTMOSS_LIB32_LIBDIR = /usr/lib/arm-linux-gnueabihf
# 32-bit ARM binaries in a 64-bit image, on purpose.
LIGHTMOSS_LIB32_BIN_ARCH_EXCLUDE = $(LIGHTMOSS_LIB32_LIBDIR) /usr/lib/ld-linux-armhf.so.3

# Every shared library of the armhf build (glibc's from /lib, the rest from
# /usr/lib), with their soname links; nothing else (no programs, no config).
define LIGHTMOSS_LIB32_INSTALL_TARGET_CMDS
	@test -e $(@D)/lib/ld-linux-armhf.so.3 || { \
		echo "lightmoss-lib32: no armhf runtime in $(LM_LIB32_OUTPUT)"; \
		echo "  build it first: make lib32 (or set LM_LIB32_OUTPUT)"; exit 1; }
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
	# Mesa's GBM backend (dri_gbm.so): a plugin in its own directory, which
	# the 32-bit libgbm searches (external.mk). Not in the Mali blob's build.
	if [ -d $(@D)/usr/lib/gbm ]; then \
		mkdir -p $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)/gbm && \
		cp -a $(@D)/usr/lib/gbm/. $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)/gbm/; \
	fi
	# The R36S's Mali g29p1 blob (rk3326-mali, BR2_PACKAGE_RK3326_MALI_G29P1):
	# also in a directory of its own, for lightmoss-mali-select.
	if [ -d $(@D)/usr/lib/mali-g29p1 ]; then \
		mkdir -p $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)/mali-g29p1 && \
		cp -a $(@D)/usr/lib/mali-g29p1/. $(TARGET_DIR)$(LIGHTMOSS_LIB32_LIBDIR)/mali-g29p1/; \
	fi
	ln -sf arm-linux-gnueabihf/ld-linux-armhf.so.3 \
		$(TARGET_DIR)/usr/lib/ld-linux-armhf.so.3
endef

# Turnip's ICD manifest (the Mini V2): Mesa names it freedreno_icd.<cpu>.json
# with the library in /usr/lib, and both builds' <cpu> is the same
# (cortex-a76.cortex-a55), so the 32-bit one goes in under its own name and
# points at the lib32 copy. Each loader skips the other's manifest by its
# library_arch ("32" here, "64" in Mesa's 64-bit one).
ifeq ($(BR2_LIGHTMOSS_MESA3D_TURNIP),y)
LIGHTMOSS_LIB32_VULKAN_ICD = $(TARGET_DIR)/usr/share/vulkan/icd.d/freedreno_icd.armhf.json
define LIGHTMOSS_LIB32_INSTALL_VULKAN_ICD
	icd="$$(ls $(@D)/usr/share/vulkan/icd.d/freedreno_icd.*.json 2>/dev/null | head -n 1)"; \
	if [ -z "$$icd" ]; then \
		echo "lightmoss-lib32: no 32-bit Turnip ICD manifest in $(LM_LIB32_OUTPUT)"; \
		exit 1; \
	fi; \
	mkdir -p $(dir $(LIGHTMOSS_LIB32_VULKAN_ICD)) && \
	sed 's|"library_path": *"[^"]*/libvulkan_freedreno.so"|"library_path": "$(LIGHTMOSS_LIB32_LIBDIR)/libvulkan_freedreno.so"|' \
		"$$icd" > $(LIGHTMOSS_LIB32_VULKAN_ICD) && \
	grep -q '"library_path": "$(LIGHTMOSS_LIB32_LIBDIR)/libvulkan_freedreno.so"' \
		$(LIGHTMOSS_LIB32_VULKAN_ICD) || { \
		echo "lightmoss-lib32: $$icd: no library_path to point at $(LIGHTMOSS_LIB32_LIBDIR)"; \
		exit 1; }
endef
LIGHTMOSS_LIB32_POST_INSTALL_TARGET_HOOKS += LIGHTMOSS_LIB32_INSTALL_VULKAN_ICD
endif

$(eval $(generic-package))
