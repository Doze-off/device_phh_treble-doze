TARGET_GAPPS_ARCH := arm64
include build/make/target/product/aosp_arm64.mk
$(call inherit-product, device/phh/treble/base.mk)
$(call inherit-product, device/phh/treble/circle.mk)

PRODUCT_NAME := ayaka_gsi
PRODUCT_DEVICE := tdgsi_arm64_ab
PRODUCT_BRAND := google
PRODUCT_SYSTEM_BRAND := google
PRODUCT_MANUFACTURER := google
PRODUCT_SYSTEM_MANUFACTURER := google

PRODUCT_MODEL := AyakaUI GSI TrebleDroid
LINEAGE_BUILD := AyakaUI

# Overwrite the inherited "emulator" characteristics
PRODUCT_CHARACTERISTICS := device

