#############################################################
#
#	fbmenu_light
#
#############################################################

FBMENU_VERSION = 12665b5c9a
FBMENU_SITE = git://github.com/dTatham/fbmenu_light.git

define FBMENU_BUILD_CMDS
	$(MAKE) CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D) all
endef

define FBMENU_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 777 $(@D)/fbmenu $(TARGET_DIR)/usr/bin
	$(INSTALL) -D -m 755 $(@D)/consolefont.psf $(TARGET_DIR)/usr/lib
endef

$(eval $(generic-package))
