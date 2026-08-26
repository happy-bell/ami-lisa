package jp.amiplus.lisa

/**
 * TCL居室TV付属USBカメラの旧ヒス対策値。
 * VID 0x0411 / PID 730 の通話試験は [CameraUsb20BProfile] を使う。
 */
object CameraTclUsbProfile {
    const val ID = "tcl_usb"
    const val VID = 0x0411
    const val PID = 730

    val mic = MicProfile(
        name = ID,
        gateOpenLevel = 620f,
        gateCloseLevel = 340f,
        gateFloor = 0.035f,
        gateAttack = 0.08f,
        gateRelease = 0.00045f,
        lpCoeff = 0.52f,
        duckGain = 0.006f,
        duckAttack = 0.025f,
        duckRelease = 0.00008f,
        inputGain = 1f,
    )

    fun matches(vendorId: Int, productId: Int, productName: String?): Boolean {
        if (vendorId == VID) return true
        val n = productName?.lowercase() ?: return false
        return n.contains("sonix")
    }
}
