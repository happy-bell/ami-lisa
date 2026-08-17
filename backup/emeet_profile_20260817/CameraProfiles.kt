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
)

/**
 * 接続中のUSBカメラからプロファイルを選ぶ。
 * C270n / EMEET / TCL付属はそれぞれ別ファイルの値を使う。
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
                mic = CameraTclUsbProfile.mic.copy(name = "generic"),
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
            CameraTclUsbProfile.matches(device.vendorId, device.productId, name)
    }

    fun looksLikeCamera(vendorId: Int, productId: Int, productName: String?): Boolean {
        val n = productName?.lowercase() ?: ""
        if (n.contains("camera") || n.contains("webcam") || n.contains("mic") ||
            n.contains("emeet") || n.contains("smartcam") || n.contains("c270") ||
            n.contains("logitech") || n.contains("logicool") || n.contains("sonix")
        ) {
            return true
        }
        return CameraEmeetProfile.matches(vendorId, productName) ||
            CameraC270nProfile.matches(vendorId, productName) ||
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
        )
}
