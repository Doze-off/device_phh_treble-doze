TARGET_GAPPS_ARCH := arm64
include build/make/target/product/aosp_arm64.mk
$(call inherit-product, device/phh/treble/base.mk)
$(call inherit-product, device/phh/treble/infinity.mk)

PRODUCT_NAME := infinity_gsi
PRODUCT_DEVICE := tdgsi_arm64_ab
PRODUCT_BRAND := google
PRODUCT_SYSTEM_BRAND := google
PRODUCT_MANUFACTURER := google
PRODUCT_SYSTEM_MANUFACTURER := google

PRODUCT_MODEL := Infinity X GSI TrebleDroid
LINEAGE_BUILD := GSI-Dozeoff

# Overwrite the inherited "emulator" characteristics
PRODUCT_CHARACTERISTICS := device
WITH_GAPPS := true

