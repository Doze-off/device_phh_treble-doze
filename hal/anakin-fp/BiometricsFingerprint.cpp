/*
 * Copyright (C) 2017 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#define LOG_TAG "android.hardware.biometrics.fingerprint@2.3-service.anakin"
#define LOG_VERBOSE "android.hardware.biometrics.fingerprint@2.3-service.anakin"

#include <android-base/logging.h>
#include <hardware/hw_auth_token.h>

#include <hardware/hardware.h>
#include <hardware/fingerprint.h>
#include "BiometricsFingerprint.h"

#include <inttypes.h>
#include <atomic>
#include <chrono>
#include <cstring>
#include <errno.h>
#include <link.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/system_properties.h>
#include <thread>
#include <unistd.h>

#define CMD_FINGER_DOWN 200001
#define CMD_FINGER_UP 200003
#define CMD_LIGHT_AREA_CLOSE 200000
#define CMD_LIGHT_AREA_STABLE 200002
#define CMD_PARTIAL_FINGER_DETECTED 200004

#define FOD_UI_PATH "/sys/class/drm/spot_on_achieved"
#define GHBM_REQUESTED_PATH "/sys/class/drm/ghbm_on_requested"
#define GHBM_ACHIEVED_PATH "/sys/class/drm/ghbm_on_achieved"
#define HBM_PROPERTY "sys.phh.oplus.fppress"
// ANAKIN's ASUS display path is driven through /proc/globalHbm and
// /sys/class/drm/fod_touched by phh-prop-handler.  The generic DRM
// "*_achieved" nodes remain at zero, so waiting for them for 800 ms lets
// the normal UDFPS press end before Goodix receives 200002.  The handler
// turns HBM on in roughly 70 ms on the device; keep a short, protected
// timer fallback after that transition instead of waiting on the inactive
// generic nodes.
#define HBM_WAIT_TIMEOUT_MS 120
#define HBM_POLL_INTERVAL_MS 10
#define GOODIX_PROC_FP_XY_PATH "/proc/driver/fp_xy"
#define GOODIX_USER_FP_XY_PATH "/data/vendor/fp_xy"

namespace android {
namespace hardware {
namespace biometrics {
namespace fingerprint {
namespace V2_3 {
namespace implementation {

// Supported fingerprint HAL version
static const uint16_t kVersion = HARDWARE_MODULE_API_VERSION(2, 1);

using RequestStatus =
        android::hardware::biometrics::fingerprint::V2_1::RequestStatus;

BiometricsFingerprint *BiometricsFingerprint::sInstance = nullptr;

struct GoodixPathPatch {
    bool patched = false;
};

static int patchGoodixPathInObject(struct dl_phdr_info* info, size_t,
        void* opaque) {
    auto* result = static_cast<GoodixPathPatch*>(opaque);
    if (result->patched || info->dlpi_name == nullptr ||
            strstr(info->dlpi_name, "libgf_hal.so") == nullptr) {
        return 0;
    }

    constexpr size_t pathLength = sizeof(GOODIX_PROC_FP_XY_PATH);
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) {
        ALOGE("invalid page size while patching Goodix coordinate path");
        return 0;
    }

    for (size_t i = 0; i < info->dlpi_phnum; ++i) {
        const ElfW(Phdr)& phdr = info->dlpi_phdr[i];
        if ((phdr.p_flags & (PF_R | PF_W)) != PF_R || phdr.p_filesz < pathLength) {
            continue;
        }

        auto* start = reinterpret_cast<char*>(info->dlpi_addr + phdr.p_vaddr);
        auto* end = start + phdr.p_filesz - pathLength + 1;
        for (char* cursor = start; cursor < end; ++cursor) {
            if (memcmp(cursor, GOODIX_PROC_FP_XY_PATH, pathLength) != 0) {
                continue;
            }

            const uintptr_t address = reinterpret_cast<uintptr_t>(cursor);
            const uintptr_t pageStart = address &
                    ~(static_cast<uintptr_t>(pageSize) - 1);
            const uintptr_t pageEnd = (address + pathLength + pageSize - 1) &
                    ~(static_cast<uintptr_t>(pageSize) - 1);
            const int restoreProtection = PROT_READ |
                    ((phdr.p_flags & PF_X) ? PROT_EXEC : 0);
            if (mprotect(reinterpret_cast<void*>(pageStart),
                    pageEnd - pageStart,
                    PROT_READ | PROT_WRITE) != 0) {
                ALOGE("cannot make Goodix coordinate path writable: %s",
                        strerror(errno));
                return 0;
            }

            memcpy(cursor, GOODIX_USER_FP_XY_PATH, pathLength);
            __builtin___clear_cache(cursor, cursor + pathLength);
            if (mprotect(reinterpret_cast<void*>(pageStart),
                    pageEnd - pageStart, restoreProtection) != 0) {
                ALOGE("cannot restore Goodix coordinate path protection: %s",
                        strerror(errno));
                return 0;
            }

            ALOGI("redirected Goodix coordinate path to %s", GOODIX_USER_FP_XY_PATH);
            result->patched = true;
            return 1;
        }
    }

    return 0;
}

static bool patchGoodixCoordinatePath() {
    GoodixPathPatch result;
    dl_iterate_phdr(patchGoodixPathInObject, &result);
    if (!result.patched) {
        ALOGE("Goodix coordinate path was not found in loaded libgf_hal.so");
    }
    return result.patched;
}

static bool writeGoodixTouchXY(uint32_t x, uint32_t y) {
    const uint32_t fixedX = x << 16;
    const uint32_t fixedY = y << 16;
    char coordinates[64];
    const int length = snprintf(coordinates, sizeof(coordinates), "%u,%u\n",
            fixedX, fixedY);
    if (length <= 0 || static_cast<size_t>(length) >= sizeof(coordinates)) {
        ALOGE("failed to format Goodix touch coordinates x=%u y=%u", x, y);
        return false;
    }

    const int fd = open(GOODIX_USER_FP_XY_PATH,
            O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) {
        ALOGE("cannot open %s: %s", GOODIX_USER_FP_XY_PATH, strerror(errno));
        return false;
    }

    const ssize_t written = write(fd, coordinates, length);
    const int savedErrno = errno;
    close(fd);
    if (written != length) {
        ALOGE("cannot write %s: %s", GOODIX_USER_FP_XY_PATH,
                written < 0 ? strerror(savedErrno) : "short write");
        return false;
    }

    ALOGD("Goodix touch coordinates x=%u y=%u fixed=%u,%u", x, y,
            fixedX, fixedY);
    return true;
}

static bool readBool(int fd) {
    char c;
    int rc;

    rc = lseek(fd, 0, SEEK_SET);
    if (rc) {
        LOG(ERROR) << "failed to seek fd, err: " << rc;
        return false;
    }

    rc = read(fd, &c, sizeof(char));
    if (rc != 1) {
        LOG(ERROR) << "failed to read bool from fd, err: " << rc;
        return false;
    }

    return c != '0';
}

static bool readBoolPath(const char* path, bool* readable) {
    const int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        *readable = false;
        return false;
    }

    char value[16] = {};
    const ssize_t count = read(fd, value, sizeof(value) - 1);
    const int savedErrno = errno;
    close(fd);
    if (count <= 0) {
        *readable = false;
        ALOGD("cannot read HBM node %s: %s", path,
                count < 0 ? strerror(savedErrno) : "empty node");
        return false;
    }

    *readable = true;
    return value[0] != '0';
}

static bool hbmAchieved() {
    bool ghbmReadable = false;
    bool spotReadable = false;
    const bool ghbm = readBoolPath(GHBM_ACHIEVED_PATH, &ghbmReadable);
    const bool spot = readBoolPath(FOD_UI_PATH, &spotReadable);
    return (ghbmReadable && ghbm) || (spotReadable && spot);
}

static void requestHbm(bool enabled) {
    const char* value = enabled ? "1" : "0";
    if (__system_property_set(HBM_PROPERTY, value) != 0) {
        ALOGE("failed to set %s=%s", HBM_PROPERTY, value);
        return;
    }

    ALOGD("requested HBM %s=%s", HBM_PROPERTY, value);
}

static bool waitForHbm(const std::atomic<bool>& fingerDown,
        const std::atomic<uint64_t>& fingerSequence, uint64_t sequence) {
    const auto deadline = std::chrono::steady_clock::now() +
            std::chrono::milliseconds(HBM_WAIT_TIMEOUT_MS);
    bool loggedReadable = false;

    while (fingerDown.load() && fingerSequence.load() == sequence &&
            std::chrono::steady_clock::now() < deadline) {
        bool ghbmReadable = false;
        bool spotReadable = false;
        const bool ghbm = readBoolPath(GHBM_ACHIEVED_PATH, &ghbmReadable);
        const bool spot = readBoolPath(FOD_UI_PATH, &spotReadable);
        if (ghbmReadable || spotReadable) {
            loggedReadable = true;
        }
        if ((ghbmReadable && ghbm) || (spotReadable && spot)) {
            ALOGD("HBM achieved sequence=%" PRIu64 " ghbm=%d spot=%d",
                    sequence, ghbm, spot);
            return true;
        }

        std::this_thread::sleep_for(
                std::chrono::milliseconds(HBM_POLL_INTERVAL_MS));
    }

    ALOGW("HBM not achieved before fallback sequence=%" PRIu64
            " readable=%d", sequence, loggedReadable);
    return false;
}

BiometricsFingerprint::BiometricsFingerprint() : mClientCallback(nullptr), mDevice(nullptr) {
    sInstance = this; // keep track of the most recent instance
    mDevice = openHal();
    if (!mDevice) {
        ALOGE("Can't open HAL module");
    }
    patchGoodixCoordinatePath();
    this->mGoodixFingerprintDaemon = IGoodixFingerprintDaemon::getService();

    std::thread([this]() {
        while (true) {
            std::unique_lock<std::mutex> lock(mCommandMutex);
            mCommandCondition.wait(lock, [this]() {
                return !mCommandQueue.empty();
            });

            const GoodixCommand command = mCommandQueue.front();
            mCommandQueue.pop_front();

            const uint64_t currentSequence = mFingerSequence.load();
            if (command.sequence != currentSequence) {
                ALOGD("drop stale Goodix command %u sequence=%" PRIu64
                        " current=%" PRIu64, command.command,
                        command.sequence, currentSequence);
                continue;
            }

            if (command.command == CMD_LIGHT_AREA_STABLE &&
                    !mFingerDown.load()) {
                ALOGD("skip stale light area stable after finger up");
                continue;
            }
            if (command.command == CMD_LIGHT_AREA_CLOSE &&
                    mFingerDown.load()) {
                ALOGD("skip light area close while finger is down");
                continue;
            }

            ALOGD("send Goodix command %u sequence=%" PRIu64,
                    command.command, command.sequence);
            if (this->mGoodixFingerprintDaemon == nullptr) {
                ALOGE("cannot send Goodix command %u: daemon is unavailable",
                        command.command);
            } else if (!this->mGoodixFingerprintDaemon->sendCommand(
                        command.command, {},
                        [](int, const hidl_vec<signed char>&) {}).isOk()) {
                ALOGE("Goodix command %u failed", command.command);
            }

            // Keep HBM enabled until Goodix has received the corresponding
            // finger-up command.  The next press cannot update the state or
            // enqueue a command until this serialized operation returns.
            if (command.command == CMD_FINGER_UP) {
                requestHbm(false);
            }
        }
    }).detach();

    std::thread([this]() {
        int fd = open(FOD_UI_PATH, O_RDONLY);
        if (fd < 0) {
            ALOGE("spot node unavailable: %s", FOD_UI_PATH);
            return;
        }

        ALOGI("watching spot node: %s", FOD_UI_PATH);

        struct pollfd fodUiPoll = {
            .fd = fd,
            .events = POLLERR | POLLPRI,
            .revents = 0,
        };

        while (true) {
            int rc = poll(&fodUiPoll, 1, -1);
            if (rc < 0) {
                LOG(ERROR) << "failed to poll fd, err: " << rc;
                continue;
            }

            if (readBool(fd)) {
                if (mFingerDown.load() && !mLightAreaStable.exchange(true)) {
                    ALOGD("spot ready, queue light area stable");
                    enqueueGoodixCommand(CMD_LIGHT_AREA_STABLE,
                            mFingerSequence.load());
                }
            } else {
                mLightAreaStable.store(false);
                if (!mFingerDown.load()) {
                    ALOGD("spot not ready, queue light area close");
                    enqueueGoodixCommand(CMD_LIGHT_AREA_CLOSE,
                            mFingerSequence.load());
                }
            }
        }

        close(fd);
    }).detach();
}

void BiometricsFingerprint::enqueueGoodixCommand(unsigned int command,
        uint64_t sequence) {
    {
        std::lock_guard<std::mutex> lock(mCommandMutex);
        if (sequence != mFingerSequence.load()) {
            ALOGD("drop enqueue of stale Goodix command %u sequence=%" PRIu64
                    " current=%" PRIu64, command, sequence,
                    mFingerSequence.load());
            return;
        }

        if (command == CMD_LIGHT_AREA_STABLE && !mFingerDown.load()) {
            ALOGD("drop light area stable after finger up sequence=%" PRIu64,
                    sequence);
            return;
        }
        if (command == CMD_LIGHT_AREA_CLOSE && mFingerDown.load()) {
            ALOGD("drop light area close while finger is down sequence=%" PRIu64,
                    sequence);
            return;
        }

        mCommandQueue.push_back({sequence, command});
    }
    mCommandCondition.notify_one();
}

BiometricsFingerprint::~BiometricsFingerprint() {
    ALOGV("~BiometricsFingerprint()");
    if (mDevice == nullptr) {
        ALOGE("No valid device");
        return;
    }
    int err;
    if (0 != (err = mDevice->common.close(
            reinterpret_cast<hw_device_t*>(mDevice)))) {
        ALOGE("Can't close fingerprint module, error: %d", err);
        return;
    }
    mDevice = nullptr;
}

Return<bool> BiometricsFingerprint::isUdfps(uint32_t) {
    return true;
}

Return<void> BiometricsFingerprint::onFingerDown(uint32_t x, uint32_t y,
        float minor, float major) {
    std::unique_lock<std::mutex> lock(mCommandMutex);
    const uint64_t sequence = mFingerSequence.fetch_add(1) + 1;
    mFingerDown.store(true);
    mLightAreaStable.store(false);
    mCommandQueue.clear();
    ALOGD("finger down x=%u y=%u minor=%f major=%f sequence=%" PRIu64,
            x, y, minor, major, sequence);
    writeGoodixTouchXY(x, y);
    requestHbm(true);
    mCommandQueue.push_back({sequence, CMD_FINGER_DOWN});
    lock.unlock();
    mCommandCondition.notify_one();

    // Goodix starts sampling after 200002.  The old 120 ms fallback raced the
    // display driver's HBM transition and caused the first samples to be
    // classified as dirty or too fast.  Wait for a real achieved indication;
    // use a protected timeout only when the vendor display node is absent.
    std::thread([this, sequence]() {
        waitForHbm(mFingerDown, mFingerSequence, sequence);
        if (mFingerDown.load() && mFingerSequence.load() == sequence &&
                !mLightAreaStable.exchange(true)) {
            ALOGD("queue light area stable after HBM wait sequence=%" PRIu64,
                    sequence);
            enqueueGoodixCommand(CMD_LIGHT_AREA_STABLE, sequence);
        }
    }).detach();

    return Void();
}

Return<void> BiometricsFingerprint::onFingerUp() {
    std::unique_lock<std::mutex> lock(mCommandMutex);
    if (!mFingerDown.load()) {
        ALOGD("ignore duplicate finger up");
        return Void();
    }

    const uint64_t sequence = mFingerSequence.fetch_add(1) + 1;
    mFingerDown.store(false);
    mLightAreaStable.store(false);
    mCommandQueue.clear();
    ALOGD("finger up sequence=%" PRIu64, sequence);
    mCommandQueue.push_back({sequence, CMD_FINGER_UP});
    lock.unlock();
    mCommandCondition.notify_one();

    return Void();
}

Return<RequestStatus> BiometricsFingerprint::ErrorFilter(int32_t error) {
    switch(error) {
        case 0: return RequestStatus::SYS_OK;
        case -2: return RequestStatus::SYS_ENOENT;
        case -4: return RequestStatus::SYS_EINTR;
        case -5: return RequestStatus::SYS_EIO;
        case -11: return RequestStatus::SYS_EAGAIN;
        case -12: return RequestStatus::SYS_ENOMEM;
        case -13: return RequestStatus::SYS_EACCES;
        case -14: return RequestStatus::SYS_EFAULT;
        case -16: return RequestStatus::SYS_EBUSY;
        case -22: return RequestStatus::SYS_EINVAL;
        case -28: return RequestStatus::SYS_ENOSPC;
        case -110: return RequestStatus::SYS_ETIMEDOUT;
        default:
            ALOGE("An unknown error returned from fingerprint vendor library: %d", error);
            return RequestStatus::SYS_UNKNOWN;
    }
}

// Translate from errors returned by traditional HAL (see fingerprint.h) to
// HIDL-compliant FingerprintError.
FingerprintError BiometricsFingerprint::VendorErrorFilter(int32_t error,
            int32_t* vendorCode) {
    *vendorCode = 0;
    switch(error) {
        case FINGERPRINT_ERROR_HW_UNAVAILABLE:
            return FingerprintError::ERROR_HW_UNAVAILABLE;
        case FINGERPRINT_ERROR_UNABLE_TO_PROCESS:
            return FingerprintError::ERROR_UNABLE_TO_PROCESS;
        case FINGERPRINT_ERROR_TIMEOUT:
            return FingerprintError::ERROR_TIMEOUT;
        case FINGERPRINT_ERROR_NO_SPACE:
            return FingerprintError::ERROR_NO_SPACE;
        case FINGERPRINT_ERROR_CANCELED:
            return FingerprintError::ERROR_CANCELED;
        case FINGERPRINT_ERROR_UNABLE_TO_REMOVE:
            return FingerprintError::ERROR_UNABLE_TO_REMOVE;
        case FINGERPRINT_ERROR_LOCKOUT:
            return FingerprintError::ERROR_LOCKOUT;
        default:
            if (error >= FINGERPRINT_ERROR_VENDOR_BASE) {
                // vendor specific code.
                *vendorCode = error - FINGERPRINT_ERROR_VENDOR_BASE;
                return FingerprintError::ERROR_VENDOR;
            }
    }
    ALOGE("Unknown error from fingerprint vendor library: %d", error);
    return FingerprintError::ERROR_UNABLE_TO_PROCESS;
}

// Translate acquired messages returned by traditional HAL (see fingerprint.h)
// to HIDL-compliant FingerprintAcquiredInfo.
FingerprintAcquiredInfo BiometricsFingerprint::VendorAcquiredFilter(
        int32_t info, int32_t* vendorCode) {
    *vendorCode = 0;
    switch(info) {
        case FINGERPRINT_ACQUIRED_GOOD:
            return FingerprintAcquiredInfo::ACQUIRED_GOOD;
        case FINGERPRINT_ACQUIRED_PARTIAL:
            return FingerprintAcquiredInfo::ACQUIRED_PARTIAL;
        case FINGERPRINT_ACQUIRED_INSUFFICIENT:
            return FingerprintAcquiredInfo::ACQUIRED_INSUFFICIENT;
        case FINGERPRINT_ACQUIRED_IMAGER_DIRTY:
            return FingerprintAcquiredInfo::ACQUIRED_IMAGER_DIRTY;
        case FINGERPRINT_ACQUIRED_TOO_SLOW:
            return FingerprintAcquiredInfo::ACQUIRED_TOO_SLOW;
        case FINGERPRINT_ACQUIRED_TOO_FAST:
            return FingerprintAcquiredInfo::ACQUIRED_TOO_FAST;
        default:
            if (info >= FINGERPRINT_ACQUIRED_VENDOR_BASE) {
                // vendor specific code.
                *vendorCode = info - FINGERPRINT_ACQUIRED_VENDOR_BASE;
                return FingerprintAcquiredInfo::ACQUIRED_VENDOR;
            }
    }
    ALOGE("Unknown acquiredmsg from fingerprint vendor library: %d", info);
    return FingerprintAcquiredInfo::ACQUIRED_INSUFFICIENT;
}

Return<uint64_t> BiometricsFingerprint::setNotify(
        const sp<IBiometricsFingerprintClientCallback>& clientCallback) {
    std::lock_guard<std::mutex> lock(mClientCallbackMutex);
    mClientCallback = clientCallback;
    // This is here because HAL 2.3 doesn't have a way to propagate a
    // unique token for its driver. Subsequent versions should send a unique
    // token for each call to setNotify(). This is fine as long as there's only
    // one fingerprint device on the platform.
    return reinterpret_cast<uint64_t>(mDevice);
}

Return<uint64_t> BiometricsFingerprint::preEnroll()  {
    return mDevice->pre_enroll(mDevice);
}

Return<RequestStatus> BiometricsFingerprint::enroll(const hidl_array<uint8_t, 69>& hat,
        uint32_t gid, uint32_t timeoutSec) {
    const hw_auth_token_t* authToken =
        reinterpret_cast<const hw_auth_token_t*>(hat.data());
    return ErrorFilter(mDevice->enroll(mDevice, authToken, gid, timeoutSec));
}

Return<RequestStatus> BiometricsFingerprint::postEnroll() {
    return ErrorFilter(mDevice->post_enroll(mDevice));
}

Return<uint64_t> BiometricsFingerprint::getAuthenticatorId() {
    return mDevice->get_authenticator_id(mDevice);
}

Return<RequestStatus> BiometricsFingerprint::cancel() {
    return ErrorFilter(mDevice->cancel(mDevice));
}

Return<RequestStatus> BiometricsFingerprint::enumerate()  {
    return ErrorFilter(mDevice->enumerate(mDevice));
}

Return<RequestStatus> BiometricsFingerprint::remove(uint32_t gid, uint32_t fid) {
    return ErrorFilter(mDevice->remove(mDevice, gid, fid));
}

Return<RequestStatus> BiometricsFingerprint::setActiveGroup(uint32_t gid,
        const hidl_string& storePath) {
    if (storePath.size() >= PATH_MAX || storePath.size() <= 0) {
        ALOGE("Bad path length: %zd", storePath.size());
        return RequestStatus::SYS_EINVAL;
    }
    if (access(storePath.c_str(), W_OK)) {
        return RequestStatus::SYS_EINVAL;
    }

    return ErrorFilter(mDevice->set_active_group(mDevice, gid,
                                                    storePath.c_str()));
}

Return<RequestStatus> BiometricsFingerprint::authenticate(uint64_t operationId,
        uint32_t gid) {
    return ErrorFilter(mDevice->authenticate(mDevice, operationId, gid));
}

IBiometricsFingerprint* BiometricsFingerprint::getInstance() {
    if (!sInstance) {
      sInstance = new BiometricsFingerprint();
    }
    return sInstance;
}

fingerprint_device_t* BiometricsFingerprint::openHal() {
    int err;
    const hw_module_t *hw_mdl = nullptr;
    ALOGD("Opening fingerprint hal library...");
    if (0 != (err = hw_get_module(FINGERPRINT_HARDWARE_MODULE_ID, &hw_mdl))) {
        ALOGE("Can't open fingerprint HW Module, error: %d", err);
        return nullptr;
    }

    if (hw_mdl == nullptr) {
        ALOGE("No valid fingerprint module");
        return nullptr;
    }

    fingerprint_module_t const *module =
        reinterpret_cast<const fingerprint_module_t*>(hw_mdl);
    if (module->common.methods->open == nullptr) {
        ALOGE("No valid open method");
        return nullptr;
    }

    hw_device_t *device = nullptr;

    if (0 != (err = module->common.methods->open(hw_mdl, nullptr, &device))) {
        ALOGE("Can't open fingerprint methods, error: %d", err);
        return nullptr;
    }

    if (kVersion != device->version) {
        // enforce version on new devices because of HIDL@2.3 translation layer
        ALOGE("Wrong fp version. Expected %d, got %d", kVersion, device->version);
        return nullptr;
    }

    fingerprint_device_t* fp_device =
        reinterpret_cast<fingerprint_device_t*>(device);

    if (0 != (err =
            fp_device->set_notify(fp_device, BiometricsFingerprint::notify))) {
        ALOGE("Can't register fingerprint module callback, error: %d", err);
        return nullptr;
    }

    return fp_device;
}

void BiometricsFingerprint::notify(const fingerprint_msg_t *msg) {
    BiometricsFingerprint* thisPtr = static_cast<BiometricsFingerprint*>(
            BiometricsFingerprint::getInstance());
    std::lock_guard<std::mutex> lock(thisPtr->mClientCallbackMutex);
    if (thisPtr == nullptr || thisPtr->mClientCallback == nullptr) {
        ALOGE("Receiving callbacks before the client callback is registered.");
        return;
    }
    const uint64_t devId = reinterpret_cast<uint64_t>(thisPtr->mDevice);
    switch (msg->type) {
        case FINGERPRINT_ERROR: {
                int32_t vendorCode = 0;
                FingerprintError result = VendorErrorFilter(msg->data.error, &vendorCode);
                ALOGD("onError(%d)", result);
                if (!thisPtr->mClientCallback->onError(devId, result, vendorCode).isOk()) {
                    ALOGE("failed to invoke fingerprint onError callback");
                }
            }
            break;
        case FINGERPRINT_ACQUIRED: {
                // Goodix reports 1001/1002 as internal UI-state messages
                // (the vendor HAL translates them from 1003/1002).  They
                // are not image-quality results and Android 16's generic
                // GSI has no matching fingerprint_acquired_vendor strings.
                // Forwarding them as HIDL ACQUIRED_VENDOR makes the
                // framework log "Invalid acquired message: 6, 1/2" and
                // repeatedly rebuild the UDFPS overlay while the finger is
                // still down.  Keep real standard acquired values, including
                // ACQUIRED_IMAGER_DIRTY (3), visible to the framework.
                if (msg->data.acquired.acquired_info == 1001 ||
                        msg->data.acquired.acquired_info == 1002) {
                    ALOGD("suppress Goodix internal acquired info=%d",
                            msg->data.acquired.acquired_info);
                    break;
                }
                int32_t vendorCode = 0;
                FingerprintAcquiredInfo result =
                    VendorAcquiredFilter(msg->data.acquired.acquired_info, &vendorCode);
                ALOGD("onAcquired(%d)", result);
                if (!thisPtr->mClientCallback->onAcquired(devId, result, vendorCode).isOk()) {
                    ALOGE("failed to invoke fingerprint onAcquired callback");
                }
            }
            break;
        case FINGERPRINT_TEMPLATE_ENROLLING:
            ALOGD("onEnrollResult(fid=%d, gid=%d, rem=%d)",
                msg->data.enroll.finger.fid,
                msg->data.enroll.finger.gid,
                msg->data.enroll.samples_remaining);
            if (!thisPtr->mClientCallback->onEnrollResult(devId,
                    msg->data.enroll.finger.fid,
                    msg->data.enroll.finger.gid,
                    msg->data.enroll.samples_remaining).isOk()) {
                ALOGE("failed to invoke fingerprint onEnrollResult callback");
            }
            break;
        case FINGERPRINT_TEMPLATE_REMOVED:
            ALOGD("onRemove(fid=%d, gid=%d, rem=%d)",
                msg->data.removed.finger.fid,
                msg->data.removed.finger.gid,
                msg->data.removed.remaining_templates);
            if (!thisPtr->mClientCallback->onRemoved(devId,
                    msg->data.removed.finger.fid,
                    msg->data.removed.finger.gid,
                    msg->data.removed.remaining_templates).isOk()) {
                ALOGE("failed to invoke fingerprint onRemoved callback");
            }
            break;
        case FINGERPRINT_AUTHENTICATED:
            if (msg->data.authenticated.finger.fid != 0) {
                ALOGD("onAuthenticated(fid=%d, gid=%d)",
                    msg->data.authenticated.finger.fid,
                    msg->data.authenticated.finger.gid);
                const uint8_t* hat =
                    reinterpret_cast<const uint8_t *>(&msg->data.authenticated.hat);
                const hidl_vec<uint8_t> token(
                    std::vector<uint8_t>(hat, hat + sizeof(msg->data.authenticated.hat)));
                if (!thisPtr->mClientCallback->onAuthenticated(devId,
                        msg->data.authenticated.finger.fid,
                        msg->data.authenticated.finger.gid,
                        token).isOk()) {
                    ALOGE("failed to invoke fingerprint onAuthenticated callback");
                    getInstance()->onFingerUp();
                }
            } else {
                // Not a recognized fingerprint
                if (!thisPtr->mClientCallback->onAuthenticated(devId,
                        msg->data.authenticated.finger.fid,
                        msg->data.authenticated.finger.gid,
                        hidl_vec<uint8_t>()).isOk()) {
                    ALOGE("failed to invoke fingerprint onAuthenticated callback");
                }
            }
            break;
        case FINGERPRINT_TEMPLATE_ENUMERATING:
            ALOGD("onEnumerate(fid=%d, gid=%d, rem=%d)",
                msg->data.enumerated.finger.fid,
                msg->data.enumerated.finger.gid,
                msg->data.enumerated.remaining_templates);
            if (!thisPtr->mClientCallback->onEnumerate(devId,
                    msg->data.enumerated.finger.fid,
                    msg->data.enumerated.finger.gid,
                    msg->data.enumerated.remaining_templates).isOk()) {
                ALOGE("failed to invoke fingerprint onEnumerate callback");
            }
            break;
    }
}

} // namespace implementation
}  // namespace V2_3
}  // namespace fingerprint
}  // namespace biometrics
}  // namespace hardware
}  // namespace android
