$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/custom/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_BOOT_ANIMATION_RES := 720

TARGET_DISABLE_EPPE := true
PERF_ANIM_OVERRIDE := false

TARGET_FACE_UNLOCK_SUPPORTED := true
