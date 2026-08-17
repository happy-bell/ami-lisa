package jp.amiplus.mulch

import android.hardware.usb.UsbDevice
import android.util.Log

data class CameraProfileInfo(
    val id: String,
    val mic: MicProfile,
    val videoMinWidth: Int = 640,
    val videoMinHeight: Int = 360,
    val videoMaxWidth: Int = 1280,
    val videoMaxHeight: Int = 720,
    val videoFps: Int = 30,
    val skipUacInjection: Boolean = false,
    val forceUacInjection: Boolean = false,
    val uvcAntiFlicker60: Boolean = false,
)

/**
 * 接続中のUSBカメラからプロファイルを選ぶ。
 * 機種ごとの値は別ファイルに凍結する。横断して書き換えない。
 */
object CameraProfiles {
    private const val TAG = "AmiUsbAudio"

    fun select(vendorId: Int, productId: Int, productName: String?): CameraProfileInfo {
        val info = when {
            CameraEmeetProfile.matches(vendorId, productName) ->
                CameraProfileInfo(
                    id = CameraEmeetProfile.ID,
                    mic = CameraEmeetProfile.mic,
                    videoMinWidth = CameraEmeetProfile.videoMinWidth,
                    videoMinHeight = CameraEmeetProfile.videoMinHeight,
                    videoMaxWidth = CameraEmeetProfile.videoMaxWidth,
                    videoMaxHeight = CameraEmeetProfile.videoMaxHeight,
                    videoFps = CameraEmeetProfile.videoFps,
                    skipUacInjection = CameraEmeetProfile.skipUacInjection,
                    uvcAntiFlicker60 = CameraEmeetProfile.uvcAntiFlicker60,
                )
            CameraTzzProfile.matches(vendorId, productId, productName) ->
                CameraProfileInfo(
                    id = CameraTzzProfile.ID,
                    mic = CameraTzzProfile.mic,
                    videoMinWidth = CameraTzzProfile.videoMinWidth,
                    videoMinHeight = CameraTzzProfile.videoMinHeight,
                    videoMaxWidth = CameraTzzProfile.videoMaxWidth,
                    videoMaxHeight = CameraTzzProfile.videoMaxHeight,
                    videoFps = CameraTzzProfile.videoFps,
                    forceUacInjection = CameraTzzProfile.forceUacInjection,
                )
            CameraUsb20BProfile.matches(vendorId, productId, productName) ->
                CameraProfileInfo(
                    id = CameraUsb20BProfile.ID,
                    mic = CameraUsb20BProfile.mic,
                    videoMinWidth = CameraUsb20BProfile.videoMinWidth,
                    videoMinHeight = CameraUsb20BProfile.videoMinHeight,
                    videoMaxWidth = CameraUsb20BProfile.videoMaxWidth,
                    videoMaxHeight = CameraUsb20BProfile.videoMaxHeight,
                    videoFps = CameraUsb20BProfile.videoFps,
                    forceUacInjection = CameraUsb20BProfile.forceUacInjection,
                )
            CameraC270nProfile.matches(vendorId, productName) ->
                CameraProfileInfo(
                    id = CameraC270nProfile.ID,
                    mic = CameraC270nProfile.mic,
                )
            CameraTclUsbProfile.matches(vendorId, productId, productName) ->
                CameraProfileInfo(
                    id = CameraTclUsbProfile.ID,
                    mic = CameraTclUsbProfile.mic,
                )
            else -> CameraProfileInfo(
                id = "generic",
                mic = CameraC270nProfile.mic.copy(name = "generic"),
            )
        }
        Log.i(
            TAG,
            "camera profile selected: ${info.id} for '$productName' " +
                "(vid=0x%04X pid=0x%04X)".format(vendorId, productId)
        )
        return info
    }

    fun matchesKnown(device: UsbDevice): Boolean {
        val name = device.productName
        return CameraEmeetProfile.matches(device.vendorId, name) ||
            CameraC270nProfile.matches(device.vendorId, name) ||
            CameraTzzProfile.matches(device.vendorId, device.productId, name) ||
            CameraUsb20BProfile.matches(device.vendorId, device.productId, name) ||
            CameraTclUsbProfile.matches(device.vendorId, device.productId, name)
    }

    fun looksLikeCamera(vendorId: Int, productId: Int, productName: String?): Boolean {
        val n = productName?.lowercase() ?: ""
        if (n.contains("camera") || n.contains("webcam") || n.contains("mic") ||
            n.contains("emeet") || n.contains("smartcam") || n.contains("c270") ||
            n.contains("logitech") || n.contains("logicool") || n.contains("sonix") ||
            n.contains("tzz") || n.contains("usb20")
        ) {
            return true
        }
        return CameraEmeetProfile.matches(vendorId, productName) ||
            CameraC270nProfile.matches(vendorId, productName) ||
            CameraTzzProfile.matches(vendorId, productId, productName) ||
            CameraUsb20BProfile.matches(vendorId, productId, productName) ||
            CameraTclUsbProfile.matches(vendorId, productId, productName)
    }

    fun toMap(info: CameraProfileInfo, vendorId: Int, productId: Int, productName: String?): Map<String, Any?> =
        mapOf(
            "id" to info.id,
            "vendorId" to vendorId,
            "productId" to productId,
            "productName" to productName,
            "videoMinWidth" to info.videoMinWidth,
            "videoMinHeight" to info.videoMinHeight,
            "videoMaxWidth" to info.videoMaxWidth,
            "videoMaxHeight" to info.videoMaxHeight,
            "videoFps" to info.videoFps,
            "skipUacInjection" to info.skipUacInjection,
            "forceUacInjection" to info.forceUacInjection,
            "uvcAntiFlicker60" to info.uvcAntiFlicker60,
        )
}
