# LightMoss: buildroot wrapper.
#
#   make            build the 32-bit runtime, then the image
#                   (output/images/lightmoss-r36s-<version>.img.xz)
#   make lib32      only the 32-bit (armhf) runtime, into output-lib32/
#   make menuconfig / linux-menuconfig / savedefconfig / clean / ...
#                   any other target is passed to the image's buildroot
#   make lib32-menuconfig / lib32-clean / lib32-<target>
#                   the same for the 32-bit build
#
# buildroot itself is fetched on first use, pinned to BR_VERSION: 2025.11.x is
# the last series with systemd 257, the last systemd that still boots on the
# R36S's 4.4 kernel (cgroup v1). See README.md.

BR_VERSION   ?= 2025.11.3
BR_REPO      ?= https://github.com/buildroot/buildroot.git
BR_DIR       ?= $(CURDIR)/buildroot
O            ?= $(CURDIR)/output
O32          ?= $(O)-lib32
DEFCONFIG    ?= lightmoss_r36s_defconfig
DEFCONFIG32  ?= lightmoss_r36s_lib32_defconfig

BR_MAKE   = $(MAKE) -C $(BR_DIR) O=$(O) BR2_EXTERNAL=$(CURDIR) LIGHTMOSS_LIB32_DIR=$(O32)
BR32_MAKE = $(MAKE) -C $(BR_DIR) O=$(O32) BR2_EXTERNAL=$(CURDIR)

.PHONY: all lib32 buildroot config
all: lib32 $(O)/.config
	$(BR_MAKE)

lib32: $(O32)/.config
	$(BR32_MAKE)

$(BR_DIR)/Makefile:
	git clone --depth 1 --branch $(BR_VERSION) $(BR_REPO) $(BR_DIR)

buildroot: $(BR_DIR)/Makefile

$(O)/.config: $(BR_DIR)/Makefile configs/$(DEFCONFIG)
	$(BR_MAKE) $(DEFCONFIG)

$(O32)/.config: $(BR_DIR)/Makefile configs/$(DEFCONFIG32)
	$(BR32_MAKE) $(DEFCONFIG32)

config: $(BR_DIR)/Makefile
	$(BR_MAKE) $(DEFCONFIG)
	$(BR32_MAKE) $(DEFCONFIG32)

# Real files of this tree are never built from anything: keep the catch-all
# rules below away from them.
Makefile configs/$(DEFCONFIG) configs/$(DEFCONFIG32): ;

# lib32-<target> goes to the 32-bit build's buildroot.
lib32-%: $(BR_DIR)/Makefile
	$(BR32_MAKE) $*

# Everything else goes to the image's buildroot (menuconfig, linux-rebuild, ...).
%: $(BR_DIR)/Makefile
	$(BR_MAKE) $@
