#!/system/bin/sh
set -o pipefail

display_usage() {
    echo -e "\nUsage:\n ./phh-prop-handler.sh [prop]\n"
}

if [ "$#" -ne 1 ]; then
    display_usage
    exit 1
fi

prop_value=$(getprop "$1")

xiaomi_toggle_dt2w_proc_node() {
    DT2W_PROC_NODES=("/proc/touchpanel/wakeup_gesture"
        "/proc/tp_wakeup_gesture"
        "/proc/tp_gesture")
    for node in "${DT2W_PROC_NODES[@]}"; do
        [ ! -f "${node}" ] && continue
        echo "Trying to set dt2w mode with /proc node: ${node}"
        echo "$1" >"${node}"
        [[ "$(cat "${node}")" -eq "$1" ]] # Check result
        return
    done
    return 1
}

xiaomi_toggle_dt2w_event_node() {
    for ev in $(
        cd /sys/class/input || return
        echo event*
    ); do
        isTouchscreen=false
        if getevent -p /dev/input/$ev |grep -e 0035 -e 0036|wc -l |grep -q 2;then
            isTouchscreen=true
        fi
        [ ! -f "/sys/class/input/${ev}/device/device/gesture_mask" ] &&
            [ ! -f "/sys/class/input/${ev}/device/wake_gesture" ] &&
            ! $isTouchscreen && continue
        echo "Trying to set dt2w mode with event node: /dev/input/${ev}"
        if [ "$1" -eq 1 ]; then
            # Enable
            sendevent /dev/input/"${ev}" 0 1 5
            return
        else
            # Disable
            sendevent /dev/input/"${ev}" 0 1 4
            return
        fi
    done
    return 1
}

xiaomi_toggle_dt2w_ioctl() {
    if [ -c "/dev/xiaomi-touch" ]; then
        echo "Trying to set dt2w mode with ioctl on /dev/xiaomi-touch"
        # 14 - Touch_Doubletap_Mode
        xiaomi-touch 14 "$1"
        return
    fi
    return 1
}

restartAudio() {
    setprop ctl.restart audioserver
    audioHal="$(getprop |sed -nE 's/.*init\.svc\.(.*audio-hal[^]]*).*/\1/p')"
    setprop ctl.restart "$audioHal"
    setprop ctl.restart vendor.audio-hal-2-0
    setprop ctl.restart audio-hal-2-0
}

if [ "$1" == "persist.sys.phh.asus.dt2w" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == 1 ]];then
        setprop persist.asus.dclick 1
    else
        setprop persist.asus.dclick 0
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.asus.usb.port" ]; then
        setprop persist.vendor.usb.controller.default "$prop_value"
    exit
fi

if [ "$1" == "persist.sys.phh.xiaomi.dt2w" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    xiaomi_toggle_dt2w_proc_node "$prop_value"
    # Fallback to event node method
    xiaomi_toggle_dt2w_event_node "$prop_value"
    # Fallback to ioctl method
    xiaomi_toggle_dt2w_ioctl "$prop_value"
    exit
fi

if [ "$1" == "persist.sys.phh.oppo.dt2w" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" >/proc/touchpanel/double_tap_enable
    exit
fi

if [ "$1" == "persist.sys.phh.oppo.dc_dimming" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" >/sys/kernel/oppo_display/dimlayer_bl_en
    exit
fi

if [ "$1" == "persist.sys.phh.oppo.gaming_mode" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    echo "$prop_value" >/proc/touchpanel/game_switch_enable
    exit
fi

if [ "$1" == "sys.phh.oplus.fppress" ]; then
    prop_value=$(getprop sys.phh.oplus.fppress)

    nodes=(
        "/sys/kernel/oplus_display/oplus_notify_fppress"
        "/sys/kernel/oppo_display/oppo_notify_fppress"
    )

    for node in "${nodes[@]}"; do
        if [ -e "$node" ]; then
            echo "$prop_value" > "$node"
        fi
    done

    # ASUS ROG Phone 5 / 5s (ANAKIN) FOD HBM & Coordinate Bridge
    if [ -e /proc/globalHbm ]; then
        echo "$prop_value" > /proc/globalHbm 2>/dev/null || true
    fi
    if [ -e /sys/class/drm/fod_touched ]; then
        echo "$prop_value" > /sys/class/drm/fod_touched 2>/dev/null || true
    fi
    if [ "$prop_value" = "1" ]; then
        # 540 << 16 = 35389440, 1874 << 16 = 122814464 (16.16 fixed-point format)
        if [ -e /proc/driver/fp_xy ]; then
            echo "35389440,122814464" > /proc/driver/fp_xy 2>/dev/null || true
        fi
        if [ -e /data/vendor/fp_xy ]; then
            echo "35389440,122814464" > /data/vendor/fp_xy 2>/dev/null || true
        fi
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.securize" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == 1 ]]; then
        rm -f /metadata/securize_disable
    else
        touch /metadata/securize_disable
    fi
fi

if [ "$1" == "persist.sys.phh.oppo.usbotg" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi
    if [ -e /sys/class/power_supply/usb/otg_switch ]; then
        echo "$prop_value" >/sys/class/power_supply/usb/otg_switch
    else
        echo "$prop_value" >/sys/class/oplus_chg/usb/otg_switch
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.transsion.usbotg" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi
    OTG_PATH=$(find /sys/ -path *tran_battery/OTG_CTL)
    if [ -n "$OTG_PATH" ]; then
        echo "$prop_value" >$OTG_PATH
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.transsion.dt2w" ]; then
    if [[ "$prop_value" != "1" && "$prop_value" != "2" ]]; then
        exit 1
    fi
    echo cc${prop_value} > /proc/gesture_function
    exit
fi

if [ "$1" == "persist.sys.phh.allow_binder_thread_on_incoming_calls" ]; then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        resetprop_phh ro.telephony.block_binder_thread_on_incoming_calls false
    else
        resetprop_phh --delete ro.telephony.block_binder_thread_on_incoming_calls
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.disable_audio_effects" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        resetprop_phh ro.audio.ignore_effects true
    else
        resetprop_phh --delete ro.audio.ignore_effects
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.caf.audio_policy" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    sku="$(getprop ro.boot.product.vendor.sku)"
    if [[ "$prop_value" == 1 ]];then
        umount /vendor/etc/audio
        umount /vendor/etc/audio

        if [ -f /vendor/etc/audio_policy_configuration_sec.xml ];then
            mount /vendor/etc/audio_policy_configuration_sec.xml /vendor/etc/audio_policy_configuration.xml
        elif [ -f /vendor/etc/audio/sku_${sku}_qssi/audio_policy_configuration.xml ] && [ -f /vendor/etc/audio/sku_$sku/audio_policy_configuration.xml ];then
            umount /vendor/etc/audio
            mount /vendor/etc/audio/sku_${sku}_qssi/audio_policy_configuration.xml /vendor/etc/audio/sku_$sku/audio_policy_configuration.xml
        elif [ -f /vendor/etc/audio/audio_policy_configuration.xml ];then
            mount /vendor/etc/audio/audio_policy_configuration.xml /vendor/etc/audio_policy_configuration.xml
        elif [ -f /vendor/etc/audio_policy_configuration_base.xml ];then
            mount /vendor/etc/audio_policy_configuration_base.xml /vendor/etc/audio_policy_configuration.xml
        fi
    else
        umount /vendor/etc/audio_policy_configuration.xml
        umount /vendor/etc/audio/sku_$sku/audio_policy_configuration.xml
        if [ $(find /vendor/etc/audio -type f |wc -l) -le 3 ];then
            mount /mnt/phh/empty_dir /vendor/etc/audio
        fi
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.vsmart.dt2w" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        echo 0 > /sys/class/vsm/tp/gesture_control
    else
        echo > /sys/class/vsm/tp/gesture_control
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.backlight.scale" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        if [ -f /sys/class/leds/lcd-backlight/max_brightness ];then
            setprop persist.sys.qcom-brightness "$(cat /sys/class/leds/lcd-backlight/max_brightness)"
        elif [ -f /sys/class/backlight/panel0-backlight/max_brightness ];then
            setprop persist.sys.qcom-brightness "$(cat /sys/class/backlight/panel0-backlight/max_brightness)"
        elif [ -f /sys/class/backlight/sprd_backlight/max_brightness ];then
            setprop persist.sys.qcom-brightness "$(cat /sys/class/backlight/sprd_backlight/max_brightness)"
        fi
    else
        setprop persist.sys.qcom-brightness -1
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.disable_soundvolume_effect" ];then
    if [[ "$prop_value" != "0" && "$prop_value" != "1" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == 1 ]];then
        mount /mnt/phh/empty /vendor/lib/soundfx/libvolumelistener.so
        mount /mnt/phh/empty /vendor/lib64/soundfx/libvolumelistener.so
    else
        umount /vendor/lib/soundfx/libvolumelistener.so
        umount /vendor/lib64/soundfx/libvolumelistener.so
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.bluetooth.system_audio_hal.enabled" ]; then
    # Migrate from 0/1 to false/true first
    if [[ "$prop_value" == "0" ]]; then
        setprop persist.bluetooth.system_audio_hal.enabled false
        exit 1
    elif [[ "$prop_value" == "1" ]]; then
        setprop persist.bluetooth.system_audio_hal.enabled true
        exit 1
    fi

    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == "true" ]]; then
        setprop persist.bluetooth.bluetooth_audio_hal.disabled false
        setprop persist.bluetooth.a2dp_offload.disabled true
        resetprop_phh ro.bluetooth.a2dp_offload.supported false
    else
        resetprop_phh --delete persist.bluetooth.bluetooth_audio_hal.disabled
        resetprop_phh --delete persist.bluetooth.a2dp_offload.disabled
        resetprop_phh --delete ro.bluetooth.a2dp_offload.supported
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.bluetooth_fix" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == "true" ]]; then
      resetprop_phh persist.bluetooth.bluetooth_audio_hal.disabled true
      resetprop_phh persist.vendor.btstack.enable.lpa false
      resetprop_phh ro.bluetooth.a2dp_offload.supported false
      resetprop_phh persist.sys.phh.disable_a2dp_offload true
      resetprop_phh vendor.bluetooth.a2dp.offload.enable false
    else
      resetprop_phh --delete persist.bluetooth.bluetooth_audio_hal.disabled
      resetprop_phh --delete persist.vendor.btstack.enable.lpa
      resetprop_phh --delete ro.bluetooth.a2dp_offload.supported
      resetprop_phh --delete persist.sys.phh.disable_a2dp_offload
      resetprop_phh --delete vendor.bluetooth.a2dp.offload.enable
    fi
    restartAudio
    exit
fi

if [ "$1" == "persist.sys.phh.lmk_tweaks" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == "true" ]]; then
        # aggressive lmkd + background-app limits: free foreground headroom on
        # low-RAM devices (e.g. kernel-4.9 GSIs where isolated renderers get
        # OOM-reaped, #92). overrides the GSI's system.prop lmkd defaults.
        resetprop_phh ro.lmk.use_minfree_levels true
        resetprop_phh ro.lmk.kill_timeout_ms 100
        resetprop_phh ro.lmk.low 1001
        resetprop_phh ro.lmk.medium 800
        resetprop_phh ro.lmk.critical 0
        resetprop_phh ro.lmk.kill_heaviest_task false
        resetprop_phh ro.lmk.critical_upgrade false
        resetprop_phh ro.lmk.upgrade_pressure 100
        resetprop_phh ro.lmk.downgrade_pressure 250
        resetprop_phh ro.lmk.psi_partial_stall_ms 200
        resetprop_phh ro.lmk.psi_complete_stall_ms 700
        resetprop_phh ro.sys.fw.bg_apps_limit 16
        resetprop_phh ro.config.max_starting_bg 8
    else
        # off: remove the overrides so the GSI's system.prop lmkd defaults
        # (trebledroid-staging 0014) apply again.
        resetprop_phh --delete ro.lmk.use_minfree_levels
        resetprop_phh --delete ro.lmk.kill_timeout_ms
        resetprop_phh --delete ro.lmk.low
        resetprop_phh --delete ro.lmk.medium
        resetprop_phh --delete ro.lmk.critical
        resetprop_phh --delete ro.lmk.kill_heaviest_task
        resetprop_phh --delete ro.lmk.critical_upgrade
        resetprop_phh --delete ro.lmk.upgrade_pressure
        resetprop_phh --delete ro.lmk.downgrade_pressure
        resetprop_phh --delete ro.lmk.psi_partial_stall_ms
        resetprop_phh --delete ro.lmk.psi_complete_stall_ms
        resetprop_phh --delete ro.sys.fw.bg_apps_limit
        resetprop_phh --delete ro.config.max_starting_bg
    fi
    setprop ctl.restart lmkd
    exit
fi

if [ "$1" == "persist.sys.phh.axion_props" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == "true" ]]; then
        #axion props
        # set threshold to filter unused apps
        resetprop_phh pm.dexopt.downgrade_after_inactive_days 10
        resetprop_phh pm.dexopt.boot-after-ota speed

        resetprop_phh dalvik.vm.enable_pr_dexopt true
        resetprop_phh dalvik.vm.finalizer-timeout-ms 40000
        resetprop_phh dalvik.vm.ps-min-first-save-ms 150000

        # disable RescueParty
        resetprop_phh persist.sys.disable_rescue true

        # sf
        resetprop_phh ro.surface_flinger.uclamp.min 165

        # sound
        resetprop_phh audio.safemedia.bypass 1



        # virtual ab
        resetprop_phh ro.virtual_ab.compression.enabled true
        resetprop_phh ro.virtual_ab.userspace.snapshots.enabled true
        resetprop_phh ro.virtual_ab.batch_writes true
        resetprop_phh ro.virtual_ab.io_uring.enabled false
        resetprop_phh ro.virtual_ab.compression.xor.enabled false
        resetprop_phh ro.virtual_ab.read_ahead_size 16
        resetprop_phh ro.virtual_ab.o_direct.enabled true
        resetprop_phh ro.virtual_ab.merge_thread_priority 19
        resetprop_phh ro.virtual_ab.worker_thread_priority 0
        resetprop_phh ro.virtual_ab.num_worker_threads 3
        resetprop_phh ro.virtual_ab.num_merge_threads 1
        resetprop_phh ro.virtual_ab.num_verify_threads 1
        resetprop_phh ro.virtual_ab.cow_op_merge_size 16
        resetprop_phh ro.virtual_ab.verify_threshold_size 1073741824
        resetprop_phh ro.virtual_ab.verify_block_size 1048576
        resetprop_phh ro.virtual_ab.compression.threads true

        # Disable touch video heatmap to reduce latency, motion jitter, and CPU usage
        # on supported devices with Deep Press input classifier HALs and models
        resetprop_phh ro.input.video_enabled false

        # EGL shader cache
        resetprop_phh ro.egl.blobcache.multifile_limit 67108864
    else
        #axion props
        # set threshold to filter unused apps
        resetprop_phh --delete pm.dexopt.downgrade_after_inactive_days
        resetprop_phh --delete pm.dexopt.boot-after-ota

        resetprop_phh --delete dalvik.vm.enable_pr_dexopt
        resetprop_phh --delete dalvik.vm.finalizer-timeout-ms
        resetprop_phh --delete dalvik.vm.ps-min-first-save-ms

        # disable RescueParty
        resetprop_phh --delete persist.sys.disable_rescue

        # sf
        resetprop_phh --delete ro.surface_flinger.uclamp.min

        # sound
        resetprop_phh --delete audio.safemedia.bypass

        # virtual ab
        resetprop_phh --delete ro.virtual_ab.compression.enabled
        resetprop_phh --delete ro.virtual_ab.userspace.snapshots.enabled
        resetprop_phh --delete ro.virtual_ab.batch_writes
        resetprop_phh --delete ro.virtual_ab.io_uring.enabled
        resetprop_phh --delete ro.virtual_ab.compression.xor.enabled
        resetprop_phh --delete ro.virtual_ab.read_ahead_size
        resetprop_phh --delete ro.virtual_ab.o_direct.enabled
        resetprop_phh --delete ro.virtual_ab.merge_thread_priority
        resetprop_phh --delete ro.virtual_ab.worker_thread_priority
        resetprop_phh --delete ro.virtual_ab.num_worker_threads
        resetprop_phh --delete ro.virtual_ab.num_merge_threads
        resetprop_phh --delete ro.virtual_ab.num_verify_threads
        resetprop_phh --delete ro.virtual_ab.cow_op_merge_size
        resetprop_phh --delete ro.virtual_ab.verify_threshold_size
        resetprop_phh --delete ro.virtual_ab.verify_block_size
        resetprop_phh --delete ro.virtual_ab.compression.threads

        # Disable touch video heatmap to reduce latency, motion jitter, and CPU usage
        # on supported devices with Deep Press input classifier HALs and models
        resetprop_phh --delete ro.input.video_enabled

        # EGL shader cache
        resetprop_phh --delete ro.egl.blobcache.multifile_limit

    fi
    exit
fi

if [ "$1" == "persist.sys.phh.scroll_boost" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == "true" ]]; then
        resetprop_phh persist.sys.perf.scroll_opt true
        resetprop_phh persist.sys.perf.scroll_opt.heavy_app 2
        resetprop_phh ro.surface_flinger.uclamp.min 135
    else
        resetprop_phh --delete persist.sys.perf.scroll_opt
        resetprop_phh --delete persist.sys.perf.scroll_opt.heavy_app
        resetprop_phh --delete ro.surface_flinger.uclamp.min
    fi
    exit
fi

if [ "$1" == "persist.sys.phh.sf.background_blur" ]; then
    if [[ "$prop_value" != "disabled" && "$prop_value" != "gaussian" && "$prop_value" != "kawase" && "$prop_value" != "kawase2" && "$prop_value" != "kawase2_fix_aliasing" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == disabled ]]; then
        resetprop_phh ro.surface_flinger.supports_background_blur 0
        settings put global disable_window_blurs 1
        resetprop_phh --delete debug.renderengine.blur_algorithm
    fi

    if [[ "$prop_value" == gaussian ]]; then
        resetprop_phh ro.surface_flinger.supports_background_blur 1
        settings put global disable_window_blurs 0
        resetprop_phh ro.sf.blurs_are_expensive=0
        resetprop_phh ro.launcher.blur.appLaunch=1
        resetprop_phh debug.renderengine.blur_algorithm gaussian
    fi

    if [[ "$prop_value" == kawase ]]; then
        resetprop_phh ro.surface_flinger.supports_background_blur 1
        settings put global disable_window_blurs 0
        resetprop_phh ro.sf.blurs_are_expensive=0
        resetprop_phh ro.launcher.blur.appLaunch=0
        resetprop_phh debug.renderengine.blur_algorithm kawase
        aflags disable com.android.graphics.surfaceflinger.flags.window_blur_kawase2
        aflags disable com.android.graphics.surfaceflinger.flags.window_blur_kawase2_fix_aliasing
    fi

    if [[ "$prop_value" == kawase2 ]]; then
        resetprop_phh ro.surface_flinger.supports_background_blur 1
        settings put global disable_window_blurs 0
        resetprop_phh ro.sf.blurs_are_expensive=0
        resetprop_phh ro.launcher.blur.appLaunch=0
        resetprop_phh debug.renderengine.blur_algorithm kawase2
        aflags enable com.android.graphics.surfaceflinger.flags.window_blur_kawase2
        aflags disable com.android.graphics.surfaceflinger.flags.window_blur_kawase2_fix_aliasing
    fi

    if [[ "$prop_value" == kawase2_fix_aliasing ]]; then
        resetprop_phh ro.surface_flinger.supports_background_blur 1
        settings put global disable_window_blurs 0
        resetprop_phh ro.sf.blurs_are_expensive=0
        resetprop_phh ro.launcher.blur.appLaunch=0
        resetprop_phh debug.renderengine.blur_algorithm kawase2_fix_aliasing
        aflags enable com.android.graphics.surfaceflinger.flags.window_blur_kawase2
        aflags enable com.android.graphics.surfaceflinger.flags.window_blur_kawase2_fix_aliasing
    fi

    exit
fi


if [ "$1" == "persist.sys.phh.sf.renderengine.backend" ]; then
    if [[ "$prop_value" != "" && "$prop_value" != "skiagl" && "$prop_value" != "skiaglthreaded" && "$prop_value" != "skiavk" && "$prop_value" != "skiavkthreaded" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == "" ]]; then
        resetprop_phh --delete debug.renderengine.backend
    fi

    if [[ "$prop_value" == skiagl ]]; then
        resetprop_phh debug.renderengine.backend skiagl
    fi

    if [[ "$prop_value" == skiaglthreaded ]]; then
        resetprop_phh debug.renderengine.backend skiaglthreaded
    fi

    if [[ "$prop_value" == skiavk ]]; then
        resetprop_phh debug.renderengine.backend skiavk
    fi

    if [[ "$prop_value" == skiavkthreaded ]]; then
        resetprop_phh debug.renderengine.backend skiavkthreaded
    fi

    exit
fi

if [ "$1" == "persist.sys.phh.sf.debug.renderengine.backend" ]; then
    if [[ "$prop_value" != "" && "$prop_value" != "skiagl" && "$prop_value" != "skiavk" ]]; then
        exit 1
    fi

    if [[ "$prop_value" == "" ]]; then
        resetprop_phh --delete ro.hwui.use_vulkan
    fi

    if [[ "$prop_value" == skiagl ]]; then
        resetprop_phh ro.hwui.use_vulkan 0
    fi

    if [[ "$prop_value" == skiavk ]]; then
        resetprop_phh ro.hwui.use_vulkan 1
    fi

    exit
fi

# Performance Tweaks Handler
if [ "$1" == "persist.sys.phh.performance_tweaks" ]; then
    # Check if LMK Tweaks is enabled - CONFLICT DETECTION
    lmk_status=$(getprop persist.sys.phh.lmk_tweaks)
    if [[ "$lmk_status" == "true" && "$prop_value" == "true" ]]; then
        echo "WARNING: Performance Tweaks conflicts with LMK Tweaks!"
        echo "Disabling LMK Tweaks automatically..."
        setprop persist.sys.phh.lmk_tweaks false
        # Reset LMK props
        resetprop_phh --delete ro.lmk.use_minfree_levels
        resetprop_phh --delete ro.lmk.kill_timeout_ms
        resetprop_phh --delete ro.lmk.low
        resetprop_phh --delete ro.lmk.medium
        resetprop_phh --delete ro.lmk.critical
        resetprop_phh --delete ro.lmk.kill_heaviest_task
        resetprop_phh --delete ro.lmk.critical_upgrade
        resetprop_phh --delete ro.lmk.upgrade_pressure
        resetprop_phh --delete ro.lmk.downgrade_pressure
        resetprop_phh --delete ro.lmk.psi_partial_stall_ms
        resetprop_phh --delete ro.lmk.psi_complete_stall_ms
        resetprop_phh --delete ro.sys.fw.bg_apps_limit
        resetprop_phh --delete ro.config.max_starting_bg
        setprop ctl.restart lmkd
        echo "[Performance] LMK Tweaks disabled due to conflict"
    fi

    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == "true" ]]; then
        # ===== DALVIK/ART HEAP & GC OPTIMIZATIONS =====
        # Heap configuration for better memory management
        resetprop_phh dalvik.vm.heapgrowthlimit 256m
        resetprop_phh dalvik.vm.heapgrowthstart 16m
        resetprop_phh dalvik.vm.heapmaxfree 64m
        resetprop_phh dalvik.vm.heapminfree 8m
        resetprop_phh dalvik.vm.heapsize 512m
        resetprop_phh dalvik.vm.heaptargetutilization 0.75

        # GC and threading optimizations
        resetprop_phh dalvik.vm.finalizer-timeout-ms 30000
        resetprop_phh dalvik.vm.threadpool-size 4
        resetprop_phh dalvik.vm.gc-start-threads 4

        # ===== SURFACEFLINGER OPTIMIZATIONS =====
        resetprop_phh ro.surface_flinger.uclamp.min 100
        resetprop_phh ro.surface_flinger.uclamp.max 1024
        resetprop_phh ro.surface_flinger.set_idle_timer_ms 100
        resetprop_phh ro.surface_flinger.set_touch_timer_ms 200
        resetprop_phh ro.surface_flinger.max_frame_buffer_acquired_buffers 4
        resetprop_phh ro.surface_flinger.max_num_layers 384
        resetprop_phh debug.sf.vsync_reactor_ignore_present_fences false
        resetprop_phh debug.sf.latch_unsignaled 1
        resetprop_phh debug.sf.enable_gl_backpressure 1
        resetprop_phh debug.sf.enable_hwc_backpressure 1

        # ===== I/O AND STORAGE OPTIMIZATIONS =====
        resetprop_phh sys.io.scheduler cfq
        resetprop_phh sys.block.mmcblk.queue.read_ahead_kb 128
        resetprop_phh sys.block.sda.queue.read_ahead_kb 256
        resetprop_phh vm.dirty_ratio 20
        resetprop_phh vm.dirty_background_ratio 10
        resetprop_phh vm.vfs_cache_pressure 100
        resetprop_phh vm.swappiness 10
        resetprop_phh vm.min_free_kbytes 76800

        # ===== NETWORK OPTIMIZATIONS =====
        resetprop_phh net.tcp.2g.rmem_min 16384
        resetprop_phh net.tcp.3g.rmem_min 262144
        resetprop_phh net.tcp.4g.rmem_min 524288
        resetprop_phh net.tcp.wifi.rmem_min 1048576
        resetprop_phh net.core.rmem_max 16777216
        resetprop_phh net.core.wmem_max 16777216
        resetprop_phh net.core.netdev_max_backlog 5000
        resetprop_phh net.core.somaxconn 4096

        # ===== CPU/GPU OPTIMIZATIONS =====
        resetprop_phh ro.sys.fw.dex2oat_thread_count 8
        resetprop_phh ro.sys.fw.bcache_enable true
        resetprop_phh ro.opengles.version 196610
        resetprop_phh debug.egl.hw 1
        resetprop_phh debug.sf.hw 1

        echo "[Performance] All performance tweaks applied successfully"
    else
        # ===== RESET ALL PERFORMANCE PROPS =====
        # Dalvik/ART
        resetprop_phh --delete dalvik.vm.heapgrowthlimit
        resetprop_phh --delete dalvik.vm.heapgrowthstart
        resetprop_phh --delete dalvik.vm.heapmaxfree
        resetprop_phh --delete dalvik.vm.heapminfree
        resetprop_phh --delete dalvik.vm.heapsize
        resetprop_phh --delete dalvik.vm.heaptargetutilization
        resetprop_phh --delete dalvik.vm.finalizer-timeout-ms
        resetprop_phh --delete dalvik.vm.threadpool-size
        resetprop_phh --delete dalvik.vm.gc-start-threads

        # SurfaceFlinger
        resetprop_phh --delete ro.surface_flinger.uclamp.min
        resetprop_phh --delete ro.surface_flinger.uclamp.max
        resetprop_phh --delete ro.surface_flinger.set_idle_timer_ms
        resetprop_phh --delete ro.surface_flinger.set_touch_timer_ms
        resetprop_phh --delete ro.surface_flinger.max_frame_buffer_acquired_buffers
        resetprop_phh --delete ro.surface_flinger.max_num_layers
        resetprop_phh --delete debug.sf.vsync_reactor_ignore_present_fences
        resetprop_phh --delete debug.sf.latch_unsignaled
        resetprop_phh --delete debug.sf.enable_gl_backpressure
        resetprop_phh --delete debug.sf.enable_hwc_backpressure

        # I/O
        resetprop_phh --delete sys.io.scheduler
        resetprop_phh --delete sys.block.mmcblk.queue.read_ahead_kb
        resetprop_phh --delete sys.block.sda.queue.read_ahead_kb
        resetprop_phh --delete vm.dirty_ratio
        resetprop_phh --delete vm.dirty_background_ratio
        resetprop_phh --delete vm.vfs_cache_pressure
        resetprop_phh --delete vm.swappiness
        resetprop_phh --delete vm.min_free_kbytes

        # Network
        resetprop_phh --delete net.tcp.2g.rmem_min
        resetprop_phh --delete net.tcp.3g.rmem_min
        resetprop_phh --delete net.tcp.4g.rmem_min
        resetprop_phh --delete net.tcp.wifi.rmem_min
        resetprop_phh --delete net.core.rmem_max
        resetprop_phh --delete net.core.wmem_max
        resetprop_phh --delete net.core.netdev_max_backlog
        resetprop_phh --delete net.core.somaxconn

        # CPU/GPU
        resetprop_phh --delete ro.sys.fw.dex2oat_thread_count
        resetprop_phh --delete ro.sys.fw.bcache_enable
        resetprop_phh --delete ro.opengles.version
        resetprop_phh --delete debug.egl.hw
        resetprop_phh --delete debug.sf.hw

        echo "[Performance] All performance tweaks reset to default"
    fi
    exit
fi

# Aggressive DEXOPT Handler - ONLY DEXOPT PROPS
if [ "$1" == "persist.sys.phh.dexopt_aggressive" ]; then
    if [[ "$prop_value" != "false" && "$prop_value" != "true" ]]; then
        exit 1
    fi
    if [[ "$prop_value" == "true" ]]; then
        # ===== AGGRESSIVE DEXOPT MODE - ALL pm.dexopt.* PROPS =====

        # Boot scenarios
        resetprop_phh pm.dexopt.boot speed
        resetprop_phh pm.dexopt.post-boot speed
        resetprop_phh pm.dexopt.first-boot speed
        resetprop_phh pm.dexopt.boot-after-ota speed
        resetprop_phh pm.dexopt.boot-after-mainline-update speed

        # Install scenarios
        resetprop_phh pm.dexopt.install speed
        resetprop_phh pm.dexopt.install-fast speed
        resetprop_phh pm.dexopt.install-bulk speed
        resetprop_phh pm.dexopt.install-bulk-secondary speed
        resetprop_phh pm.dexopt.install-bulk-downgraded speed
        resetprop_phh pm.dexopt.install-bulk-secondary-downgraded speed

        # Background and other scenarios
        resetprop_phh pm.dexopt.bg-dexopt speed
        resetprop_phh pm.dexopt.core-app speed
        resetprop_phh pm.dexopt.shared-apk speed
        resetprop_phh pm.dexopt.shared speed
        resetprop_phh pm.dexopt.nsys-library speed
        resetprop_phh pm.dexopt.forced-dexopt speed
        resetprop_phh pm.dexopt.ab-ota speed
        resetprop_phh pm.dexopt.inactive speed
        resetprop_phh pm.dexopt.cmdline speed
        resetprop_phh pm.dexopt.first-use speed
        resetprop_phh pm.dexopt.secondary speed

        # System server and UI filters
        resetprop_phh dalvik.vm.systemservercompilerfilter speed
        resetprop_phh dalvik.vm.systemuicompilerfilter speed

        # DEXOPT control flags
        resetprop_phh pm.dexopt.post-boot-timeout 0
        resetprop_phh dalvik.vm.dex2oat-flags --force-large-compilation-threshold=0
        resetprop_phh dalvik.vm.background-dexopt true
        resetprop_phh pm.dexopt.enabled true
        resetprop_phh pm.dexopt.core-platform-only false
        resetprop_phh pm.dexopt.downgrade_after_inactive_days 3

        # Trigger manual DEXOPT compilation
        echo "[DEXOPT] Setting aggressive DEXOPT properties..."

        # Wait for system to stabilize
        sleep 5

        # Force recompilation of ALL apps
        echo "[DEXOPT] Starting manual DEXOPT compilation for all apps..."
        echo "[DEXOPT] This may take 10-30 minutes depending on number of apps"

        # Run in background and log output
        cmd package compile -m speed -f -a > /data/misc/dexopt.log 2>&1 &
        DEXOPT_PID=$!

        echo "[DEXOPT] Background compilation started (PID: $DEXOPT_PID)"
        echo "[DEXOPT] Check /data/misc/dexopt.log for progress"
        echo "[DEXOPT] Monitor with: tail -f /data/misc/dexopt.log"
    else
        # ===== RESET DEXOPT PROPS =====
        resetprop_phh --delete pm.dexopt.boot
        resetprop_phh --delete pm.dexopt.post-boot
        resetprop_phh --delete pm.dexopt.first-boot
        resetprop_phh --delete pm.dexopt.boot-after-ota
        resetprop_phh --delete pm.dexopt.boot-after-mainline-update
        resetprop_phh --delete pm.dexopt.install
        resetprop_phh --delete pm.dexopt.install-fast
        resetprop_phh --delete pm.dexopt.install-bulk
        resetprop_phh --delete pm.dexopt.install-bulk-secondary
        resetprop_phh --delete pm.dexopt.install-bulk-downgraded
        resetprop_phh --delete pm.dexopt.install-bulk-secondary-downgraded
        resetprop_phh --delete pm.dexopt.bg-dexopt
        resetprop_phh --delete pm.dexopt.core-app
        resetprop_phh --delete pm.dexopt.shared-apk
        resetprop_phh --delete pm.dexopt.shared
        resetprop_phh --delete pm.dexopt.nsys-library
        resetprop_phh --delete pm.dexopt.forced-dexopt
        resetprop_phh --delete pm.dexopt.ab-ota
        resetprop_phh --delete pm.dexopt.inactive
        resetprop_phh --delete pm.dexopt.cmdline
        resetprop_phh --delete pm.dexopt.first-use
        resetprop_phh --delete pm.dexopt.secondary
        resetprop_phh --delete dalvik.vm.systemservercompilerfilter
        resetprop_phh --delete dalvik.vm.systemuicompilerfilter
        resetprop_phh --delete pm.dexopt.post-boot-timeout
        resetprop_phh --delete dalvik.vm.dex2oat-flags
        resetprop_phh --delete dalvik.vm.background-dexopt
        resetprop_phh --delete pm.dexopt.enabled
        resetprop_phh --delete pm.dexopt.core-platform-only
        resetprop_phh --delete pm.dexopt.downgrade_after_inactive_days

        echo "[DEXOPT] DEXOPT properties reset to default"
    fi
    exit
fi
