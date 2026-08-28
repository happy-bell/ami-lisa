package jp.amiplus.lisa

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
        // 2026-08-26 干渉対策を少し緩めた。0.02(-34dB)では相手が話している間
        // こちらの声がほぼ消え、同時に話すと会話が成立しなかった。
        // ハウリングが出るようなら 0.05 → 0.02 と戻す。
        duckGain = 0.10f,        // 約-20dB
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
