package jp.amiplus.mulch

import android.util.Log

/**
 * USBカメラ(マイク)ごとの音声処理パラメータのセット。
 * カメラのマイク感度・ノイズ特性の違いをここで吸収する。
 */
data class MicProfile(
    val name: String,
    // ノイズゲート
    val gateOpenLevel: Float,    // int16振幅: これを超えたら開く
    val gateCloseLevel: Float,   // これを下回ったら閉じる(ヒステリシス)
    val gateFloor: Float,        // 閉時ゲイン
    val gateAttack: Float,       // 開く速さ
    val gateRelease: Float,      // 閉じる速さ
    // ローパスフィルタ
    val lpCoeff: Float,          // 大きいほど高域を通す
    // エコーサプレッサ(ダッキング)
    val duckGain: Float,         // 相手発話中のマイクゲイン
    val duckAttack: Float,
    val duckRelease: Float,
    // 入力ゲイン補正(音の小さいマイクの底上げ用)
    val inputGain: Float,
)

object MicProfiles {
    private const val TAG = "AmiUsbAudio"
    private const val VID_LOGITECH = 0x046D  // Logicool (Logitech)

    /**
     * C270n実機でチューニング済みの値(凍結)。
     * このプロファイルは変更しないこと。他カメラの調整は別プロファイルで行う。
     */
    private val LOGICOOL = MicProfile(
        name = "logicool",
        gateOpenLevel = 500f,
        gateCloseLevel = 300f,
        gateFloor = 0.12f,       // 約-18dB; 頭欠け防止で浅め
        gateAttack = 0.05f,      // サブms
        gateRelease = 0.0006f,   // 約35ms
        lpCoeff = 0.70f,         // fc≈8kHz@48kHz
        duckGain = 0.02f,        // 約-34dB
        duckAttack = 0.012f,     // 約2ms
        duckRelease = 0.00015f,  // 約140ms
        inputGain = 1f,
    )

    /** 未知カメラ用。実績のあるLogicool値をそのまま流用する */
    private val GENERIC = LOGICOOL.copy(name = "generic")

    /** 接続中のカメラのVID/PIDからプロファイルを選ぶ */
    fun select(vendorId: Int, productId: Int, productName: String?): MicProfile {
        val profile = when (vendorId) {
            VID_LOGITECH -> LOGICOOL
            else -> GENERIC
        }
        Log.i(
            TAG,
            "mic profile selected: ${profile.name} for '$productName' " +
                "(vid=0x%04X pid=0x%04X)".format(vendorId, productId)
        )
        return profile
    }
}
