$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 720
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

EVO_BUILD_TYPE := Unofficial
BUILD_BCR := false
TARGET_DISABLE_EPPE := true
TARGET_SUPPORT_BOOT_ANIMATIONS := true

TARGET_HAS_UDFPS := false

# Face Unlock
TARGET_FACE_UNLOCK_SUPPORTED := true
TARGET_PREBUILT_BCR := true
BYPASS_CHARGE_SUPPORTED := true
