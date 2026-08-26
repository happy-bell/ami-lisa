package jp.amiplus.mulch

import android.util.Log

/**
 * USBカメラ(マイク)ごとの音声処理パラメータのセット。
 * 実値はカメラ別プロファイルファイルに置く。
 */
data class MicProfile(
    val name: String,
    val gateOpenLevel: Float,
    val gateCloseLevel: Float,
    val gateFloor: Float,
    val gateAttack: Float,
    val gateRelease: Float,
    val lpCoeff: Float,
    val duckGain: Float,
    val duckAttack: Float,
    val duckRelease: Float,
    val inputGain: Float,
    val uacTargetMs: Int = 120,
    val uacMaxKeepMs: Int = 300,
    val uacWarmupMs: Int = 8000,
)

object MicProfiles {
    private const val TAG = "AmiUsbAudio"

    /** 接続中のカメラのVID/PID/名前からマイクプロファイルを選ぶ */
    fun select(vendorId: Int, productId: Int, productName: String?): MicProfile {
        val info = CameraProfiles.select(vendorId, productId, productName)
        Log.i(
            TAG,
            "mic profile selected: ${info.mic.name} for '$productName' " +
                "(vid=0x%04X pid=0x%04X)".format(vendorId, productId)
        )
        return info.mic
    }
}
