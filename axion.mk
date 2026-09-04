$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

AXION_MAINTAINER := Doze-off
TARGET_DISABLE_EPPE := true

TARGET_INCLUDE_AXFX := true

TARGET_SUPPORTED_REFRESH_RATES := 60,90,120,144



