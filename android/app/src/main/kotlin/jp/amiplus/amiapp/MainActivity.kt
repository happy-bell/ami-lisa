package jp.amiplus.amiapp

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "jp.amiplus.lisa/tv"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isTelevisionDevice())
                    "prepareCommunicationAudio" -> {
                        result.success(prepareCommunicationAudio())
                    }
                    "listAudioInputs" -> result.success(listAudioInputs())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isTelevisionDevice(): Boolean {
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        ) {
            return true
        }
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return uiMode == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private fun prepareCommunicationAudio(): Map<String, Any?> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_NORMAL
        am.isSpeakerphoneOn = true
        am.isMicrophoneMute = false

        var outputSelected: String? = null
        var usbInputSeen: String? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            val usbIn = inputs.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
            }
            if (usbIn != null) {
                usbInputSeen = "${usbIn.productName} type=${usbIn.type}"
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.clearCommunicationDevice()
            val outs = am.availableCommunicationDevices
            val preferred = outs.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
                    it.type == AudioDeviceInfo.TYPE_HDMI ||
                    it.type == AudioDeviceInfo.TYPE_HDMI_ARC ||
                    it.type == AudioDeviceInfo.TYPE_TELEPHONY
            } ?: outs.firstOrNull {
                it.type != AudioDeviceInfo.TYPE_USB_DEVICE &&
                    it.type != AudioDeviceInfo.TYPE_USB_HEADSET &&
                    it.type != AudioDeviceInfo.TYPE_USB_ACCESSORY &&
                    it.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                    it.type != AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
            }
            if (preferred != null) {
                am.setCommunicationDevice(preferred)
                outputSelected = "${preferred.productName} type=${preferred.type}"
            }
        }

        return mapOf(
            "mode" to am.mode,
            "micMute" to am.isMicrophoneMute,
            "speakerOn" to am.isSpeakerphoneOn,
            "output" to outputSelected,
            "usbInputSeen" to usbInputSeen
        )
    }

    private fun listAudioInputs(): List<Map<String, Any?>> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        return am.getDevices(AudioManager.GET_DEVICES_INPUTS).map {
            val webrtcId = when (it.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> {
                    val address =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.address else ""
                    "microphone-$address"
                }
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired-headset"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
                else -> it.id.toString()
            }
            mapOf(
                "id" to it.id,
                "webrtcDeviceId" to webrtcId,
                "type" to it.type,
                "productName" to it.productName?.toString(),
                "isSource" to it.isSource
            )
        }
    }
}
