TARGET_GAPPS_ARCH := arm64
include build/make/target/product/aosp_arm64.mk
$(call inherit-product, device/phh/treble/base.mk)
$(call inherit-product, device/phh/treble/evox.mk)

PRODUCT_NAME := evox_gsi
PRODUCT_DEVICE := tdgsi_arm64_ab
PRODUCT_BRAND := google
PRODUCT_SYSTEM_BRAND := google
PRODUCT_MANUFACTURER := google
PRODUCT_SYSTEM_MANUFACTURER := google

PRODUCT_MODEL := Evolution-X Treble
LINEAGE_BUILD := evolution

# Overwrite the inherited "emulator" characteristics
PRODUCT_CHARACTERISTICS := device

WITH_GMS := true
TARGET_USES_PICO_GAPPS := true
