$(call inherit-product, vendor/circle/config/common.mk)
$(call inherit-product, vendor/circle/config/common_full_phone.mk)
$(call inherit-product, vendor/circle/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/circle/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/circle/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 720
TARGET_HAS_UDFPS:= false

PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.circle.maintainer=Doze-off

CIRCLE_MAINTAINER := Doze-off
TARGET_DISABLE_EPPE := true
PERF_ANIM_OVERRIDE := false
