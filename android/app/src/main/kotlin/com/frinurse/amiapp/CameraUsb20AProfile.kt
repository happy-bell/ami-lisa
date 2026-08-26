package jp.amiplus.lisa

/**
 * USB2.0-A。Buffalo BSW505MBK。
 * 権限ダイアログの名称は「USB 2.0 Camera」。メーカー表示は Sonix。
 * USB 上の VID/PID は USB2.0-B と同じ 0x0411 / 730。この機種が接続中のときは
 * USB2.0-A を使う。[CameraUsb20BProfile] のファイルと数値は触らない。
 * 2026-08-18 実機で良好だった値を保存。音量・同期・減衰はこのファイルだけを触ること。
 */
object CameraUsb20AProfile {
    const val ID = "usb20a"
    const val VID = 0x0411
    const val PID = 730

    val mic = MicProfile(
        name = ID,
        gateOpenLevel = 200f,
        gateCloseLevel = 80f,
        gateFloor = 0.55f,
        gateAttack = 0.12f,
        gateRelease = 0.0003f,
        lpCoeff = 0.74f,
        duckGain = 0.55f,
        duckAttack = 0.005f,
        duckRelease = 0.0012f,
        inputGain = 8f,
        uacTargetMs = 70,
        uacMaxKeepMs = 130,
        uacWarmupMs = 0,
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
        return n.contains("bsw505") || n.contains("buffalo")
    }
}
