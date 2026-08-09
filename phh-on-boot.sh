#!/system/bin/sh

# Disable restricted networking mode on devices without working BPF.
# Android 14+ uses BPF firewall chains to enforce restricted_networking_mode.
# On older kernels where BPF maps failed to load, the restricted chain cannot
# maintain its allowlist, causing all apps to lose network connectivity.
# The uid_owner_map is the BPF map backing firewall chain rules -- if it does
# not exist, the restricted chain cannot function and must be disabled.
if [ ! -e /sys/fs/bpf/netd_shared/map_netd_uid_owner_map ]; then
    settings put global restricted_networking_mode 0
    log -t phh-on-boot "Disabled restricted_networking_mode (BPF uid_owner_map absent)"
fi

# Disable FUSE BPF on devices whose kernels lack fuse-bpf support.
# Android 16 enables FUSE BPF by default, which requires kernel support for
# the fuse-bpf program type. On older kernels (< 5.4 without backport),
# fuseMedia.bpf fails to load and the FuseDaemon falls back to legacy mode
# but the legacy FUSE path may not work correctly on QPR2+. Setting
# persist.sys.fuse.bpf.override=false tells the FuseDaemon and vold to
# use the legacy FUSE path from the start, avoiding the failed BPF load
# and ensuring bind-mounts for Android/data and Android/obb are set up
# correctly by vold.
if [ ! -f /sys/fs/fuse/features/fuse_bpf ]; then
    setprop persist.sys.fuse.bpf.override false
    log -t phh-on-boot "Disabled FUSE BPF (kernel fuse_bpf feature absent)"
fi

# spoof post-boot props
# should be applied after boot complete to prevent breaking device features
if [ ! -f /metadata/securize_disable ]; then
  resetprop_phh ro.build.user nobody
  resetprop_phh ro.build.host android-build
  resetprop_phh ro.build.tags release-keys
  resetprop_phh ro.product.build.tags release-keys
  resetprop_phh ro.system.build.tags release-keys
  resetprop_phh ro.system_ext.build.tags release-keys
  resetprop_phh ro.vendor.build.tags release-keys
  resetprop_phh ro.boot.vbmeta.device_state locked
  resetprop_phh vendor.boot.vbmeta.device_state locked
  resetprop_phh ro.boot.verifiedbootstate green
  resetprop_phh vendor.boot.verifiedbootstate green
  resetprop_phh ro.boot.flash.locked 1
  resetprop_phh ro.boot.veritymode enforcing
  resetprop_phh ro.boot.warranty_bit 0
  resetprop_phh ro.vendor.warranty_bit 0
  resetprop_phh ro.warranty_bit 0
  resetprop_phh --delete ro.build.selinux
  resetprop_phh -n sys.oem_unlock_allowed 0
  resetprop_phh -n init.svc.flash_recovery stopped
fi

vndk="$(getprop persist.sys.vndk)"
[ -z "$vndk" ] && vndk="$(getprop ro.vndk.version |grep -oE '^[0-9]+')"

[ "$(getprop vold.decrypt)" = "trigger_restart_min_framework" ] && exit 0

# recover USB gadget if the UDC failed to bind during boot.
# on some exynos devices (e.g. samsung galaxy M33), the dwc3 OTG state
# machine starts the gadget before init has configured USB functions via
# configfs, leaving the UDC in a failed state with ENODEV.  cycling
# sys.usb.config forces the vendor USB init to tear down and rebuild
# the gadget cleanly.
udc_state="$(cat /config/usb_gadget/g1/UDC 2>/dev/null)"
if [ -z "$udc_state" ] || [ "$udc_state" = "none" ]; then
    usb_cfg="$(getprop persist.sys.usb.config)"
    if [ -n "$usb_cfg" ]; then
        log -t phh-on-boot "USB gadget not bound, retrying config: $usb_cfg"
        setprop sys.usb.config none
        sleep 1
        setprop sys.usb.config "$usb_cfg"
    fi
fi

# Restart fingerprint HAL after USB gadget recovery. The USB gadget reset
# can disconnect the biometrics HAL's connection to the TEE (trusted
# execution environment), causing fingerprint enrollment/auth to fail
# with a generic error. Restarting the HAL re-establishes the TEE session.
if [ -z "$udc_state" ] || [ "$udc_state" = "none" ]; then
    setprop ctl.restart vendor.fps_hal
    setprop ctl.restart vendor.biometrics-hal-1
fi

setprop ctl.start media.swcodec

for i in wpa p2p;do
	if [ ! -f /data/misc/wifi/${i}_supplicant.conf ];then
		cp /vendor/etc/wifi/wpa_supplicant.conf /data/misc/wifi/${i}_supplicant.conf
	fi
	chmod 0660 /data/misc/wifi/${i}_supplicant.conf
	chown wifi:system /data/misc/wifi/${i}_supplicant.conf
done

if [ -f /vendor/bin/mtkmal ];then
    if [ "$(getprop persist.mtk_ims_support)" = 1 ] || [ "$(getprop persist.mtk_epdg_support)" = 1 ];then
        setprop persist.mtk_ims_support 0
        setprop persist.mtk_epdg_support 0
        reboot
    fi
fi

if grep -qF android.hardware.boot /vendor/manifest.xml || grep -qF android.hardware.boot /vendor/etc/vintf/manifest.xml ;then
	bootctl mark-boot-successful
fi

setprop ctl.restart sec-light-hal-2-0
if find /sys/firmware -name support_fod |grep -qE .;then
	setprop ctl.restart vendor.fps_hal
fi

setprop ctl.stop storageproxyd

# zram swap fallback. the GSI itself does not set up zram -- AOSP's init.rc only
# chowns /sys/block/zram0/{idle,writeback}, expecting the vendor to mkswap +
# swapon. on devices whose vendor doesn't configure swap, low-RAM foreground
# workloads (PDF/WebView renderers in isolated processes, which carry
# oom_score_adj ~1000) get OOM-reaped at the slightest memory pressure,
# producing blurry or failed renders (#92 and similar). running this at
# boot_completed (not during early init) means a vendor that already set up
# zram is left untouched -- the guard skips when any swap is already active.
# no-op when the kernel has no zram support (/sys/block/zram0 absent) or no
# RAM read is available. zram is compressed swap in RAM; disksize is half of
# MemTotal, lz4 when the kernel exposes it (else the zram default, usually
# lzo). once zram is active, raise swappiness so the kernel actually swaps
# cold anon pages to it (zram is fast/in-RAM, so high swappiness is a net
# win) and lower the dirty ratios so less RAM is held by dirty pages -- both
# only when the fallback activates, so devices with vendor zram (or no zram)
# keep their default vm sysctls. this runs in the phhsu_daemon domain, which
# already holds rw_file_perms on dev_type:blk_file (ram_device) and
# rwx_file_perms on sysfs_type:file (sysfs_zram) + proc_type writes +
# capability sys_admin, so no sepolicy companion is needed.
if [ -e /sys/block/zram0 ] && ! grep -qE '^/' /proc/swaps 2>/dev/null; then
    echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    if grep -qw lz4 /sys/block/zram0/comp_algorithm 2>/dev/null; then
        echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    fi
    memtotal_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    if [ -n "$memtotal_kb" ]; then
        echo $((memtotal_kb * 1024 / 2)) > /sys/block/zram0/disksize 2>/dev/null || true
        mkswap /dev/block/zram0 >/dev/null 2>&1 || true
        swapon /dev/block/zram0 2>/dev/null || true
        echo 100 > /proc/sys/vm/swappiness 2>/dev/null || true
        echo 10 > /proc/sys/vm/dirty_ratio 2>/dev/null || true
        echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
        log -t phh-on-boot "zram swap fallback active (swappiness=100, disksize ~half of RAM)"
    fi
fi

sleep 10

minijailSrc=/system/system_ext/apex/com.android.vndk.v28/lib/libminijail.so
minijailSrc64=/system/system_ext/apex/com.android.vndk.v28/lib64/libminijail.so
if [ "$vndk" = 27 ];then
    mount $minijailSrc64 /vendor/lib64/libminijail_vendor.so
    mount $minijailSrc /vendor/lib/libminijail_vendor.so
fi

if [ "$vndk" = 28 ];then
    mount $minijailSrc64 /vendor/lib64/libminijail_vendor.so
    mount $minijailSrc /vendor/lib/libminijail_vendor.so
    mount $minijailSrc64 /system/lib64/vndk-28/libminijail.so
    mount $minijailSrc /system/lib/vndk-28/libminijail.so
    mount $minijailSrc64 /vendor/lib64/libminijail.so
    mount $minijailSrc /vendor/lib/libminijail.so
fi

#Clear looping services
sleep 30
getprop | \
    grep restarting | \
    sed -nE -e 's/\[([^]]*).*/\1/g'  -e 's/init.svc.(.*)/\1/p' |
    while read -r svc ;do
        setprop ctl.stop "$svc"
    done
