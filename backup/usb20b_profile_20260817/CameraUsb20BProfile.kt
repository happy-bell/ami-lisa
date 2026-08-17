package jp.amiplus.mulch

/**
 * USB2.0-B。権限ダイアログの名称は「USB 2.0 Camera」。
 * VID 0x0411 / PID 730（Sonix）。TZZ（0x0C45/0x636B）とは別機種。
 * 2026-08-17 実機で良好だった値を保存。音量・同期・エコーはこのファイルだけを触ること。
 */
object CameraUsb20BProfile {
    const val ID = "usb20b"
    const val VID = 0x0411
    const val PID = 730

    val mic = MicProfile(
        name = ID,
        gateOpenLevel = 280f,
        gateCloseLevel = 150f,
        gateFloor = 0.35f,
        gateAttack = 0.12f,
        gateRelease = 0.0003f,
        lpCoeff = 0.74f,
        duckGain = 0.20f,
        duckAttack = 0.012f,
        duckRelease = 0.0003f,
        inputGain = 11f,
        uacTargetMs = 80,
        uacMaxKeepMs = 140,
        uacWarmupMs = 0,
    )

    const val videoMinWidth = 640
    const val videoMinHeight = 360
    const val videoMaxWidth = 640
    const val videoMaxHeight = 360
    const val videoFps = 15
    const val forceUacInjection = true

    fun matches(vendorId: Int, productId: Int, productName: String?): Boolean {
        return vendorId == VID && productId == PID
    }
}
