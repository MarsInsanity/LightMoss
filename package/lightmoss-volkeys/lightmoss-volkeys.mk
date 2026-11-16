################################################################################
#
# lightmoss-volkeys
#
################################################################################

LIGHTMOSS_VOLKEYS_VERSION = 1.0
LIGHTMOSS_VOLKEYS_SITE = $(LIGHTMOSS_VOLKEYS_PKGDIR)/src
LIGHTMOSS_VOLKEYS_SITE_METHOD = local
LIGHTMOSS_VOLKEYS_LICENSE = GPL-3.0+

define LIGHTMOSS_VOLKEYS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -Wall -Wextra \
		-o $(@D)/lightmoss-volkeys $(@D)/lightmoss-volkeys.c
endef

define LIGHTMOSS_VOLKEYS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/lightmoss-volkeys $(TARGET_DIR)/usr/sbin/lightmoss-volkeys
endef

define LIGHTMOSS_VOLKEYS_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(LIGHTMOSS_VOLKEYS_PKGDIR)/lightmoss-volkeys.service \
		$(TARGET_DIR)/usr/lib/systemd/system/lightmoss-volkeys.service
endef

$(eval $(generic-package))
