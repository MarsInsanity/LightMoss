################################################################################
#
# lightmoss-firmware-sm8250
#
################################################################################

# The linux-firmware release ROCKNIX builds its SM8250 images with
# (projects/ROCKNIX/packages/linux-firmware/kernel-firmware/package.mk).
LIGHTMOSS_FIRMWARE_SM8250_VERSION = 20260309
LIGHTMOSS_FIRMWARE_SM8250_SOURCE = linux-firmware-$(LIGHTMOSS_FIRMWARE_SM8250_VERSION).tar.gz
LIGHTMOSS_FIRMWARE_SM8250_SITE = https://cdn.kernel.org/pub/linux/kernel/firmware
LIGHTMOSS_FIRMWARE_SM8250_LICENSE = Qualcomm proprietary, redistributable
LIGHTMOSS_FIRMWARE_SM8250_LICENSE_FILES = LICENSE.qcom LICENSE.QualcommAtheros_ath10k

# ROCKNIX's list. The RB5 (Thundercomm) sensor DSP image is the one ROCKNIX
# installs as qcom/sm8250/slpi.mbn.
LIGHTMOSS_FIRMWARE_SM8250_FILES = \
	qcom/a650_gmu.bin \
	qcom/a650_sqe.fw \
	qcom/sm8250/a650_zap.mbn \
	qcom/sm8250/adsp.mbn \
	qcom/sm8250/cdsp.mbn \
	qcom/vpu/vpu20_p4.mbn \
	ath11k/QCA6390/hw2.0 \
	qca/htbtfw20.tlv \
	qca/htnv20.bin

define LIGHTMOSS_FIRMWARE_SM8250_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib/firmware
	cd $(@D) && for f in $(LIGHTMOSS_FIRMWARE_SM8250_FILES); do \
		test -e "$$f" || { echo "linux-firmware has no $$f" >&2; exit 1; }; \
		mkdir -p "$(TARGET_DIR)/usr/lib/firmware/$$(dirname $$f)"; \
		cp -aL "$$f" "$(TARGET_DIR)/usr/lib/firmware/$$(dirname $$f)/"; \
	done
	cp -L $(@D)/qcom/sm8250/Thundercomm/RB5/slpi.mbn \
		$(TARGET_DIR)/usr/lib/firmware/qcom/sm8250/slpi.mbn
endef

$(eval $(generic-package))
