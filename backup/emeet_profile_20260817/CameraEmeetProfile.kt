package jp.amiplus.mulch

/**
 * EMEET USBカメラ専用。C270n とは別プロファイル。
 * 音声は C270n を起点に、EMEET の感度（やや大きめ）へ合わせた初期値。
 * 映像は 1080p30。波うちは UVC 電源周波数（既定50Hz）を 60Hz にして抑える。
 */
object CameraEmeetProfile {
    const val ID = "emeet"
    const val VID = 0x328F // Shenzhen EMEET Technology Co., Ltd.

    val mic = MicProfile(
        name = ID,
        gateOpenLevel = 420f,
        gateCloseLevel = 260f,
        gateFloor = 0.10f,
        gateAttack = 0.05f,
        gateRelease = 0.0006f,
        lpCoeff = 0.70f,
        duckGain = 0.02f,
        duckAttack = 0.012f,
        duckRelease = 0.00015f,
        inputGain = 0.85f,
    )

    const val videoMinWidth = 1920
    const val videoMinHeight = 1080
    const val videoMaxWidth = 1920
    const val videoMaxHeight = 1080
    const val videoFps = 30

    fun matches(vendorId: Int, productName: String?): Boolean {
        if (vendorId == VID) return true
        val n = productName?.lowercase() ?: return false
        return n.contains("emeet") || n.contains("e-meet") || n.contains("smartcam")
    }
}
