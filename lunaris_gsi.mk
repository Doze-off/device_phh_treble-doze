TARGET_GAPPS_ARCH := arm64
include build/make/target/product/aosp_arm64.mk
$(call inherit-product, device/phh/treble/base.mk)
$(call inherit-product, device/phh/treble/lunaris.mk)

PRODUCT_NAME := lunaris_gsi
PRODUCT_DEVICE := tdgsi_arm64_ab
PRODUCT_BRAND := google
PRODUCT_SYSTEM_BRAND := google
PRODUCT_MANUFACTURER := google
PRODUCT_SYSTEM_MANUFACTURER := google

PRODUCT_MODEL := Lunaris GSI TrebleDroid
LINEAGE_BUILD := GSI-Doze-off

# Overwrite the inherited "emulator" characteristics
PRODUCT_CHARACTERISTICS := device

TARGET_USES_CORE_GAPPS := true
WITH_GMS := true
