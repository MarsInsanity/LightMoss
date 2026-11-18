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
LIGHTMOSS_FIRMWARE_SM8250_LICENSE = Qualcomm proprietary, redistributable; Realtek, redistributable
LIGHTMOSS_FIRMWARE_SM8250_LICENSE_FILES = LICENSE.qcom LICENSE.QualcommAtheros_ath10k \
	LICENCE.rtlwifi_firmware.txt

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
	qca/htnv20.bin \
	$(LIGHTMOSS_FIRMWARE_SM8250_RTL8152)

# USB-C Ethernet adapters (r8152, CONFIG_USB_RTL8152=m). ROCKNIX installs
# rtl8153a-4.fw; the others are the rest of what r8152 asks for (in this
# linux-firmware: rtl8157/rtl8159 are newer), a few KiB each.
LIGHTMOSS_FIRMWARE_SM8250_RTL8152 = \
	rtl_nic/rtl8153a-2.fw \
	rtl_nic/rtl8153a-3.fw \
	rtl_nic/rtl8153a-4.fw \
	rtl_nic/rtl8153b-2.fw \
	rtl_nic/rtl8153c-1.fw \
	rtl_nic/rtl8156a-2.fw \
	rtl_nic/rtl8156b-2.fw

# Some names exist in the tarball only as "Link: name -> target" lines of
# WHENCE (linux-firmware's copy-firmware.sh makes them at install time): such
# a file is copied from its target, relative to its own directory.
define LIGHTMOSS_FIRMWARE_SM8250_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib/firmware/qcom/sm8250
	cd $(@D) && for f in $(LIGHTMOSS_FIRMWARE_SM8250_FILES) qcom/sm8250/Thundercomm/RB5/slpi.mbn; do \
		src="$$f"; \
		if [ ! -e "$$src" ]; then \
			t="$$(sed -n "s|^Link: $$f -> ||p" WHENCE | head -n 1)"; \
			[ -n "$$t" ] && src="$$(dirname $$f)/$$t"; \
		fi; \
		test -e "$$src" || { echo "linux-firmware has no $$f" >&2; exit 1; }; \
		case "$$f" in \
			*/Thundercomm/RB5/slpi.mbn) dst=qcom/sm8250/slpi.mbn ;; \
			*) dst="$$f" ;; \
		esac; \
		mkdir -p "$(TARGET_DIR)/usr/lib/firmware/$$(dirname $$dst)"; \
		if [ -d "$$src" ]; then \
			mkdir -p "$(TARGET_DIR)/usr/lib/firmware/$$dst"; \
			cp -aL "$$src/." "$(TARGET_DIR)/usr/lib/firmware/$$dst/"; \
		else \
			cp -L "$$src" "$(TARGET_DIR)/usr/lib/firmware/$$dst"; \
		fi; \
	done
endef

$(eval $(generic-package))
