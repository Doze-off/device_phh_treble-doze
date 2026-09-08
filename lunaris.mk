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
TARGET_USE_GPHOTOS := false
TARGET_USE_FILES := false
TARGET_USE_MAPS := false
TARGET_DEFAULT_PIXEL_LAUNCHER := false
WITH_GMS_COMMS_SUITE := false
SURFACE_FLINGER_BOOST := false
TARGET_ENABLE_BLUR := true
WITH_PIXEL_LAUNCHER := true
