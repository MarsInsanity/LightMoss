# LightMoss: buildroot wrapper.
#
#   make            build the image (output/images/lightmoss-r36s-<version>.img.xz)
#   make menuconfig / linux-menuconfig / savedefconfig / clean / ...
#                   any other target is passed to buildroot
#
# buildroot itself is fetched on first use, pinned to BR_VERSION: 2025.11.x is
# the last series with systemd 257, the last systemd that still boots on the
# R36S's 4.4 kernel (cgroup v1). See README.md.

BR_VERSION   ?= 2025.11.3
BR_REPO      ?= https://github.com/buildroot/buildroot.git
BR_DIR       ?= $(CURDIR)/buildroot
O            ?= $(CURDIR)/output
DEFCONFIG    ?= lightmoss_r36s_defconfig

BR_MAKE = $(MAKE) -C $(BR_DIR) O=$(O) BR2_EXTERNAL=$(CURDIR)

.PHONY: all buildroot config
all: $(O)/.config
	$(BR_MAKE)

$(BR_DIR)/Makefile:
	git clone --depth 1 --branch $(BR_VERSION) $(BR_REPO) $(BR_DIR)

buildroot: $(BR_DIR)/Makefile

$(O)/.config: $(BR_DIR)/Makefile configs/$(DEFCONFIG)
	$(BR_MAKE) $(DEFCONFIG)

config: $(BR_DIR)/Makefile
	$(BR_MAKE) $(DEFCONFIG)

# Real files of this tree are never built from anything: keep the catch-all
# rule below away from them.
Makefile configs/$(DEFCONFIG): ;

# Everything else goes to buildroot (menuconfig, linux-rebuild, clean, ...).
%: $(BR_DIR)/Makefile
	$(BR_MAKE) $@
