// USB Audio Class (UAC) direct capture for TVs whose audio HAL rejects
// USB microphones (e.g. TCL/Realtek: setDeviceConnectionState returns -38).
// Bypasses AudioManager entirely: Java opens the device via UsbManager and
// passes the fd here; libusb/libuac stream PCM straight from the mic.

#include <jni.h>
#include <android/log.h>
#include <libuac.h>
#include <libusb.h>

#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#define TAG "AmiUsbAudio"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

namespace {

struct CaptureState {
    std::shared_ptr<uac::uac_context> ctx;
    std::shared_ptr<uac::uac_device_handle> handle;
    std::shared_ptr<uac::uac_stream_handle> stream;

    // ring buffer of interleaved int16 samples
    std::mutex mtx;
    std::vector<int16_t> ring;
    size_t head = 0;     // next write index
    size_t count = 0;    // valid samples in ring

    // stats window (reset on each nativeStats call)
    double sumSq = 0;
    long long sumSqN = 0;
    int peakAbs = 0;
    long long totalSamples = 0;

    int sampleRate = 0;
    int channels = 0;
    std::atomic<bool> running{false};
    std::string lastError;
};

CaptureState g;
std::mutex gLifecycle;

void onPcm(uint8_t *data, unsigned int len) {
    const size_t n = len / 2;
    const int16_t *src = reinterpret_cast<const int16_t *>(data);
    std::lock_guard<std::mutex> lk(g.mtx);
    const size_t cap = g.ring.size();
    if (cap == 0) return;
    for (size_t i = 0; i < n; ++i) {
        const int16_t v = src[i];
        g.ring[g.head] = v;
        g.head = (g.head + 1) % cap;
        if (g.count < cap) {
            g.count++;
        }
        const int a = v < 0 ? -static_cast<int>(v) : static_cast<int>(v);
        if (a > g.peakAbs) g.peakAbs = a;
        g.sumSq += static_cast<double>(v) * v;
        g.sumSqN++;
    }
    g.totalSamples += static_cast<long long>(n);
}

uint32_t pickRate(const std::vector<uint32_t> &rates, uint32_t preferred) {
    if (rates.empty()) return 0;
    for (auto r : rates) {
        if (r == preferred) return r;
    }
    static const uint32_t order[] = {48000, 32000, 24000, 16000, 44100, 11025, 8000};
    for (auto want : order) {
        for (auto r : rates) {
            if (r == want) return r;
        }
    }
    return rates.back();
}

void cleanupLocked() {
    g.running = false;
    g.stream.reset();
    if (g.handle) {
        try {
            g.handle->close();
        } catch (...) {
        }
        g.handle.reset();
    }
    g.ctx.reset();
    std::lock_guard<std::mutex> lk(g.mtx);
    g.ring.clear();
    g.head = 0;
    g.count = 0;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeStart(JNIEnv *env, jobject, jint fd, jint preferredRate) {
    std::lock_guard<std::mutex> lifecycle(gLifecycle);
    if (g.running) {
        return g.sampleRate;
    }
    g.lastError.clear();
    try {
        // Android: usbfs enumeration is not permitted; wrap the fd instead.
        libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
        g.ctx = uac::uac_context::create();
        g.handle = g.ctx->wrap(fd);
        auto dev = g.handle->get_device();
        LOGI("wrapped usb device vid=%04x pid=%04x", dev->get_vid(), dev->get_pid());

        // A mic route ends at the USB streaming output terminal.
        static const uac::uac_terminal_type inTypes[] = {
            uac::UAC_TERMINAL_INPUT_UNDEFINED,      // 0x2xx: microphones
            uac::UAC_TERMINAL_BIDIR_UNDEFINED,      // 0x4xx: headsets/speakerphones
            uac::UAC_TERMINAL_EXTERNAL_UNDEFINED,   // 0x6xx: line-in etc.
        };
        std::vector<uac::ref_uac_audio_route> routes;
        for (auto t : inTypes) {
            routes = dev->query_audio_routes(t, uac::UAC_TERMINAL_USB_STREAMING);
            if (!routes.empty()) break;
        }
        if (routes.empty()) {
            g.lastError = "no capture route (USB streaming terminal not found)";
            LOGE("%s", g.lastError.c_str());
            cleanupLocked();
            return -1;
        }
        const uac::uac_audio_route &route = routes[0];
        const uac::uac_stream_if &streamIf = dev->get_stream_interface(route);

        auto rates = streamIf.get_sample_rates(uac::UAC_FORMAT_DATA_PCM);
        auto chans = streamIf.get_channel_counts(uac::UAC_FORMAT_DATA_PCM);
        std::string ratesStr, chansStr;
        for (auto r : rates) ratesStr += std::to_string(r) + ",";
        for (auto c : chans) chansStr += std::to_string(static_cast<int>(c)) + ",";
        LOGI("PCM rates=[%s] channels=[%s]", ratesStr.c_str(), chansStr.c_str());

        const uint32_t rate = pickRate(rates, static_cast<uint32_t>(preferredRate));
        if (rate == 0) {
            g.lastError = "no PCM sample rates";
            cleanupLocked();
            return -1;
        }
        uint8_t ch = 1;
        bool haveMono = false;
        for (auto c : chans) {
            if (c == 1) haveMono = true;
        }
        if (!haveMono && !chans.empty()) ch = chans[0];

        auto config = streamIf.query_config_uncompressed(uac::UAC_FORMAT_DATA_PCM, ch, rate);
        if (!config && !chans.empty()) {
            ch = chans[0];
            config = streamIf.query_config_uncompressed(uac::UAC_FORMAT_DATA_PCM, ch, rate);
        }
        if (!config) {
            g.lastError = "query_config_uncompressed failed";
            LOGE("%s", g.lastError.c_str());
            cleanupLocked();
            return -1;
        }
        LOGI("config: rate=%u ch=%d bits=%d alt=%d maxPacket=%d",
             config->tSampleRate, config->bChannelCount, config->bBitResolution,
             config->bAlternateSetting, config->wMaxPacketSize);

        {
            std::lock_guard<std::mutex> lk(g.mtx);
            // 1 second of audio; overwrite-oldest on overflow
            g.ring.assign(static_cast<size_t>(rate) * ch, 0);
            g.head = 0;
            g.count = 0;
            g.sumSq = 0;
            g.sumSqN = 0;
            g.peakAbs = 0;
            g.totalSamples = 0;
        }
        g.sampleRate = static_cast<int>(rate);
        g.channels = ch;

        g.stream = g.handle->start_streaming(streamIf, *config, &onPcm);
        g.running = true;
        LOGI("streaming started");
        return g.sampleRate;
    } catch (const std::exception &e) {
        g.lastError = e.what() ? e.what() : "unknown native exception";
        LOGE("nativeStart failed: %s", g.lastError.c_str());
        cleanupLocked();
        return -1;
    }
}

JNIEXPORT void JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeStop(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lifecycle(gLifecycle);
    cleanupLocked();
    LOGI("stopped");
}

JNIEXPORT jint JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeGetChannels(JNIEnv *, jobject) {
    return g.channels;
}

JNIEXPORT jint JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeAvailable(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lk(g.mtx);
    return static_cast<jint>(g.count);
}

// Reads up to maxShorts samples (oldest first). Returns samples copied.
JNIEXPORT jint JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeReadPcm(JNIEnv *env, jobject, jshortArray out, jint maxShorts) {
    std::lock_guard<std::mutex> lk(g.mtx);
    const size_t cap = g.ring.size();
    if (cap == 0 || g.count == 0 || maxShorts <= 0) return 0;
    size_t n = std::min(static_cast<size_t>(maxShorts), g.count);
    size_t tail = (g.head + cap - g.count) % cap;
    std::vector<int16_t> tmp(n);
    for (size_t i = 0; i < n; ++i) {
        tmp[i] = g.ring[(tail + i) % cap];
    }
    g.count -= n;
    env->SetShortArrayRegion(out, 0, static_cast<jsize>(n), tmp.data());
    return static_cast<jint>(n);
}

// Drops all but the newest keepSamples from the ring (latency control).
JNIEXPORT void JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeTrim(JNIEnv *, jobject, jint keepSamples) {
    std::lock_guard<std::mutex> lk(g.mtx);
    if (keepSamples >= 0 && g.count > static_cast<size_t>(keepSamples)) {
        g.count = static_cast<size_t>(keepSamples);
    }
}

// out[0]=totalSamples, out[1]=rms(window), out[2]=peakAbs(window), out[3]=buffered
JNIEXPORT void JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeStats(JNIEnv *env, jobject, jdoubleArray out) {
    double vals[4] = {0, 0, 0, 0};
    {
        std::lock_guard<std::mutex> lk(g.mtx);
        vals[0] = static_cast<double>(g.totalSamples);
        vals[1] = g.sumSqN > 0 ? std::sqrt(g.sumSq / g.sumSqN) : 0.0;
        vals[2] = g.peakAbs;
        vals[3] = static_cast<double>(g.count);
        g.sumSq = 0;
        g.sumSqN = 0;
        g.peakAbs = 0;
    }
    env->SetDoubleArrayRegion(out, 0, 4, vals);
}

JNIEXPORT jstring JNICALL
Java_jp_amiplus_lisa_UsbAudioCapture_nativeLastError(JNIEnv *env, jobject) {
    return env->NewStringUTF(g.lastError.c_str());
}

}  // extern "C"
