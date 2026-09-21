$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 1080

TARGET_DISABLE_EPPE := true

TARGET_SUPPORTS_64_BIT_APPS := true

WITAQUA_BUILD_TYPE := OFFICIAL
WITAQUA_MAINTAINER := Doze-off
