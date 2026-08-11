$(call inherit-product, vendor/lineage/config/common.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigSoong.mk)
$(call inherit-product, vendor/lineage/config/BoardConfigLineage.mk)
$(call inherit-product, device/lineage/sepolicy/common/sepolicy.mk)
-include vendor/lineage/build/core/config.mk

TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920

AXION_MAINTAINER := Doze-off
TARGET_DISABLE_EPPE := true

TARGET_INCLUDE_AXFX := true

TARGET_SUPPORTED_REFRESH_RATES := 30,60,75,90,120,144

BYPASS_CHARGE_SUPPORTED := true
# Path for charge toggle
BYPASS_CHARGE_TOGGLE_PATH := /sys/class/power_supply/battery/input_suspend
# Path for level path in case device does not support charge toggle
BYPASS_CHARGE_LEVEL_PATH := /sys/devices/platform/google,charger/charge_stop_level

PERF_GOV_SUPPORTED := true
PERF_DEFAULT_GOV := schedutil
HBM_SUPPORTED := true
HBM_NODE := /sys/class/backlight/panel0-backlight/hbm_mode
TORCH_STR_SUPPORTED := true
TARGET_ENABLES_IMS_OVERRIDE := true
TARGET_TOUCH_BOOST_SUPPORTED := false

# optional
TARGET_DISABLES_LIBPERF := true

# flags
TARGET_NEEDS_DOZE_FIX := true
TARGET_DOZE_TAP_PULSE_SUPPORTED := true
TARGET_DOZE_DOUBLE_TAP_PULSE_SUPPORTED := true
TARGET_DOZE_PICKUP_PULSE_SUPPORTED := true
TARGET_DOZE_SIDE_FPS_PULSE_SUPPORTED := true


