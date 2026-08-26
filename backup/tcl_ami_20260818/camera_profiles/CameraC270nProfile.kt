package jp.amiplus.mulch

/**
 * Logicool HD Webcam C270n。
 * 実機でチューニング済みの値を凍結した専用プロファイル。
 * 他カメラの調整は [CameraEmeetProfile] / [CameraTzzProfile] など別ファイルで行うこと。
 */
object CameraC270nProfile {
    const val ID = "c270n"
    const val VID = 0x046D

    val mic = MicProfile(
        name = ID,
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

    fun matches(vendorId: Int, productName: String?): Boolean {
        if (vendorId == VID) return true
        val n = productName?.lowercase() ?: return false
        return n.contains("c270") || n.contains("logitech") || n.contains("logicool")
    }
}
