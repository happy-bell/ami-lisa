package jp.amiplus.lisa

/**
 * EMEET C960 専用。2026-08-17 凍結。
 * 波うちは未解消。値を他カメラへ流用しない。バックアップは
 * backup/emeet_profile_20260817/ 。
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

    /** UAC 直接注入をしない（複合USBの映像保護）。EMEET のみ。 */
    const val skipUacInjection = true

    /** 通話前に UVC 電源周波数 60Hz を指定。EMEET のみ。 */
    const val uvcAntiFlicker60 = true

    fun matches(vendorId: Int, productName: String?): Boolean {
        if (vendorId == VID) return true
        val n = productName?.lowercase() ?: return false
        return n.contains("emeet") || n.contains("e-meet") || n.contains("smartcam")
    }
}
