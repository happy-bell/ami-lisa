package jp.amiplus.lisa

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.util.Log

/**
 * TCLなどHALがUSBマイクを拒否するTV向けの直接UACキャプチャ。
 * UsbManagerで開いたfdをネイティブ(libusb/libuac)に渡してPCMを取得する。
 */
object UsbAudioCapture {
    private const val TAG = "AmiUsbAudio"

    init {
        System.loadLibrary("ami_usb_audio")
    }

    private external fun nativeStart(fd: Int, preferredRate: Int): Int
    private external fun nativeStop()
    private external fun nativeGetChannels(): Int
    private external fun nativeAvailable(): Int
    private external fun nativeReadPcm(out: ShortArray, maxShorts: Int): Int
    private external fun nativeTrim(keepSamples: Int)
    private external fun nativeStats(out: DoubleArray)
    private external fun nativeLastError(): String

    @Volatile
    var running = false
        private set

    @Volatile
    var sampleRate = 0
        private set

    @Volatile
    var channels = 0
        private set

    @Volatile
    var vendorId = 0
        private set

    @Volatile
    var productId = 0
        private set

    @Volatile
    var productName: String? = null
        private set

    private var connection: UsbDeviceConnection? = null

    /** UAC入力(オーディオクラスIF)を持つUSBデバイスを探す。既知カメラを優先。 */
    fun findMicDevice(context: Context): UsbDevice? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val withAudio = usbManager.deviceList.values.filter { dev ->
            (0 until dev.interfaceCount).any { i ->
                dev.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_AUDIO
            }
        }
        return withAudio.firstOrNull { CameraProfiles.matchesKnown(it) }
            ?: withAudio.firstOrNull {
                CameraProfiles.looksLikeCamera(it.vendorId, it.productId, it.productName)
            }
            ?: withAudio.firstOrNull()
    }

    @Synchronized
    fun start(context: Context, preferredRate: Int = 48000): Map<String, Any?> {
        if (running) {
            return mapOf("ok" to true, "already" to true, "rate" to sampleRate, "channels" to channels)
        }
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = findMicDevice(context)
            ?: return mapOf("ok" to false, "reason" to "no_uac_device")
        if (!usbManager.hasPermission(device)) {
            return mapOf("ok" to false, "reason" to "no_permission", "device" to device.productName)
        }
        val conn = usbManager.openDevice(device)
            ?: return mapOf("ok" to false, "reason" to "open_failed", "device" to device.productName)

        val rate = nativeStart(conn.fileDescriptor, preferredRate)
        if (rate <= 0) {
            val err = nativeLastError()
            conn.close()
            Log.e(TAG, "UAC start failed: $err")
            return mapOf("ok" to false, "reason" to "native_start_failed", "error" to err)
        }
        connection = conn
        sampleRate = rate
        channels = nativeGetChannels()
        vendorId = device.vendorId
        productId = device.productId
        productName = device.productName
        running = true
        Log.i(TAG, "UAC capture started: ${device.productName} rate=$rate ch=$channels")
        return mapOf(
            "ok" to true,
            "device" to device.productName,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "rate" to rate,
            "channels" to channels
        )
    }

    @Synchronized
    fun stop() {
        if (!running && connection == null) return
        running = false
        try {
            nativeStop()
        } catch (e: Exception) {
            Log.e(TAG, "nativeStop failed", e)
        }
        try {
            connection?.close()
        } catch (_: Exception) {
        }
        connection = null
        sampleRate = 0
        channels = 0
        vendorId = 0
        productId = 0
        productName = null
        Log.i(TAG, "UAC capture stopped")
    }

    fun readPcm(out: ShortArray, maxShorts: Int): Int =
        if (running) nativeReadPcm(out, maxShorts) else 0

    fun available(): Int = if (running) nativeAvailable() else 0

    /** リングに溜まりすぎた古いサンプルを捨てて遅延を抑える */
    fun trim(keepSamples: Int) {
        if (running) nativeTrim(keepSamples)
    }

    /** [totalSamples, rmsWindow, peakWindow, buffered] */
    fun stats(): DoubleArray {
        val out = DoubleArray(4)
        if (running) nativeStats(out)
        return out
    }

    /**
     * 検証用: 指定時間キャプチャして信号レベルを返す(開始→計測→停止)。
     */
    fun probe(context: Context, durationMs: Long = 2000): Map<String, Any?> {
        val startRes = start(context)
        if (startRes["ok"] != true) return startRes
        val wasAlready = startRes["already"] == true
        try {
            stats() // reset window
            Thread.sleep(durationMs)
            val s = stats()
            return mapOf(
                "ok" to true,
                "device" to startRes["device"],
                "rate" to sampleRate,
                "channels" to channels,
                "totalSamples" to s[0].toLong(),
                "rms" to s[1],
                "peak" to s[2].toInt(),
                "buffered" to s[3].toInt(),
                "hasSignal" to (s[2] > 200)
            )
        } finally {
            if (!wasAlready) stop()
        }
    }
}
