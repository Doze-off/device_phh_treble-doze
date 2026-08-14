$(call inherit-product, vendor/infinity/config/common.mk)
$(call inherit-product, vendor/infinity/config/common_full_phone.mk)
$(call inherit-product, vendor/infinity/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/infinity/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/infinity/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 720
TARGET_SUPPORTS_BLUR := true
TARGET_SHIPS_FULL_GAPPS := false
TARGET_HAS_UDFPS := false
BYPASS_CHARGE_SUPPORTED := true
TARGET_DISABLE_EPPE := true

INFINITY_MAINTAINER := Doze-off
INFINITY_BUILD_TYPE := OFFICIAL

