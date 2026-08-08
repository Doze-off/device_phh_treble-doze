# Disables compression for APEX modules in the product.
PRODUCT_COMPRESSED_APEX := false

# Enables insecure ADB (root ADB access without authentication, depending on build configuration).
WITH_ADB_INSECURE := true

# Adds product-specific properties for the /product partition.
TARGET_PRODUCT_PROP += device/phh/treble/product.prop
# Adds system-specific properties for the /system partition.
TARGET_SYSTEM_PROP += device/phh/treble/system.prop

# Defines whether the GSI image should be built using the EROFS filesystem.
USE_EROFS := false
# Defines whether MicroG should be included in the build.
BUILD_MICROG := false

SELINUX_IGNORE_NEVERALLOWS := true
TARGET_NO_KERNEL_OVERRIDE := true
TARGET_NO_KERNEL_IMAGE := true
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
override BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# If USE_EROFS is enabled, build the image using EROFS.
ifeq ($(USE_EROFS), true)
    # Selects EROFS as the filesystem for the GSI image.
    GSI_FILE_SYSTEM_TYPE := erofs
    # Uses LZ4HC compression at level 9 for the EROFS image.
    BOARD_EROFS_COMPRESSOR := lz4hc,9
    # Shares duplicate blocks to reduce the final EROFS image size.
    BOARD_EROFS_SHARE_DUP_BLOCKS := true
else
    # If EROFS is disabled, build the GSI image using EXT4.
    GSI_FILE_SYSTEM_TYPE := ext4
    # Shares duplicate blocks in EXT4 to reduce image size.
    BOARD_EXT4_SHARE_DUP_BLOCKS := true
endif

# If BUILD_MICROG is enabled, inherit the MicroG product configuration.
ifeq ($(BUILD_MICROG), true)
    $(call inherit-product, vendor/microg/microg.mk)
else
    # Alternative line to include MicroG even when BUILD_MICROG is disabled.
    #$(call inherit-product, vendor/microg/microg.mk)
endif
