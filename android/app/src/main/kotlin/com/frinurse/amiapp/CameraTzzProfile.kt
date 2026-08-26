package jp.amiplus.lisa

/**
 * TZZ。権限ダイアログの名称は「USB 2.0 Camera」。
 * VID 0x0C45 / PID 0x636B（Sonix）。有効プロファイル（凍結しない）。
 * 映像は 640x360 で良好。HAL が USB 入力を出しても実録音できないため UAC を強制する。
 */
object CameraTzzProfile {
    const val ID = "tzz"
    const val VID = 0x0C45
    const val PID = 0x636B

    val mic = MicProfile(
        name = ID,
        gateOpenLevel = 260f,
        gateCloseLevel = 130f,
        gateFloor = 0.40f,
        gateAttack = 0.14f,
        gateRelease = 0.00025f,
        lpCoeff = 0.78f,
        duckGain = 0.40f,
        duckAttack = 0.006f,
        duckRelease = 0.0005f,
        inputGain = 1.2f,
        uacTargetMs = 220,
        uacMaxKeepMs = 500,
    )

    const val videoMinWidth = 640
    const val videoMinHeight = 360
    const val videoMaxWidth = 640
    const val videoMaxHeight = 360
    const val videoFps = 15
    const val forceUacInjection = true

    fun matches(vendorId: Int, productId: Int, productName: String?): Boolean {
        if (vendorId == VID && productId == PID) return true
        val n = productName?.lowercase() ?: return false
        return n.contains("tzz")
    }
}
