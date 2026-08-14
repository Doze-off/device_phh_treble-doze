$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 1080

TARGET_DISABLE_EPPE := true
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.lunaris.maintainer=Doze-off

TARGET_SUPPORTED_REFRESH_RATES := 60,90,120,144
WITH_BCR := true

LUNARIS_BUILD_TYPE := OFFICIAL

TARGET_CUSTOM_UDFPS := false
TARGET_INCLUDE_PHOTOS := false
TARGET_INCLUDE_WEATHER := false
TARGET_SUPPORTS_GOOGLE_FILES := false
TARGET_SUPPORTS_GOOGLE_RECORDER := false
TARGET_DEFAULT_PIXEL_LAUNCHER := false
TARGET_ENABLE_BLUR := true
BYPASS_CHARGE_SUPPORTED := true
HBM_SUPPORTED := true
HBM_NODE := /sys/class/backlight/panel0-backlight/hbm_mode
USE_REALITY_ENGINE := true
USE_ADVANCED_DISPLAY_COLOR := true
WITH_PIXEL_LAUNCHER := true
