################################################################################
#
# openabl
#
################################################################################

# The release ROCKNIX's SM8250 images ship (projects/ROCKNIX/packages/tools/
# openabl in github.com/ROCKNIX/distribution).
OPENABL_VERSION = 1.2
OPENABL_SOURCE = openabl-v$(OPENABL_VERSION).tar.gz
OPENABL_SITE = https://github.com/OpenHandheldCollective/OpenABL/releases/download/v$(OPENABL_VERSION)
OPENABL_LICENSE = GPL-3.0+ (OpenABL), BSD-2-Clause-Patent (Qualcomm ABL, edk2)
OPENABL_INSTALL_TARGET = NO
OPENABL_INSTALL_IMAGES = YES

define OPENABL_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/openabl
	$(INSTALL) -m 0644 $(@D)/SM8250/abl_signed-SM8250.elf $(BINARIES_DIR)/openabl/
endef

$(eval $(generic-package))
