################################################################################
#
# hpjackd
#
################################################################################

HPJACKD_VERSION = 1.0
HPJACKD_SITE = $(HPJACKD_PKGDIR)/src
HPJACKD_SITE_METHOD = local
HPJACKD_LICENSE = GPL-3.0+
HPJACKD_DEPENDENCIES = alsa-lib

define HPJACKD_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -Wall -Wextra \
		-o $(@D)/hpjackd $(@D)/hpjackd.c -lasound
endef

define HPJACKD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hpjackd $(TARGET_DIR)/usr/sbin/hpjackd
endef

define HPJACKD_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(HPJACKD_PKGDIR)/hpjackd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/hpjackd.service
endef

$(eval $(generic-package))
