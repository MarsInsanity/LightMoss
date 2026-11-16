################################################################################
#
# alsa-ucm-conf
#
################################################################################

# The release that goes with buildroot's alsa-lib (1.2.14): newer
# configurations may use UCM syntax that alsa-lib does not know yet.
# ROCKNIX's Retroid Pocket patches (its 0002 and 0003 for SM8250) apply to it
# unchanged; its 0004 (DisplayPort audio) does not, and is not needed.
ALSA_UCM_CONF_VERSION = 1.2.14
ALSA_UCM_CONF_SOURCE = alsa-ucm-conf-$(ALSA_UCM_CONF_VERSION).tar.bz2
ALSA_UCM_CONF_SITE = https://www.alsa-project.org/files/pub/lib
ALSA_UCM_CONF_LICENSE = BSD-3-Clause
ALSA_UCM_CONF_LICENSE_FILES = LICENSE

# Data only: the ucm2 tree, with the Retroid Pocket files the patches add
# (some of them symbolic links between configurations).
define ALSA_UCM_CONF_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/alsa/ucm2
	cp -a $(@D)/ucm2/. $(TARGET_DIR)/usr/share/alsa/ucm2/
endef

$(eval $(generic-package))
