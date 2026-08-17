package jp.amiplus.mulch

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log

/**
 * EMEET C960 の蛍光灯フリッカー対策。
 * UVC Processing Unit の Power Line Frequency を 60Hz にセットする。
 * Android Camera HAL は antibanding=auto しか出さず、既定が 50Hz のままだと
 * 60Hz 照明下で横帯の波うちになる。C270n には触れない。
 */
object UvcAntiFlicker {
    private const val TAG = "AmiUvcAntiFlicker"

    private const val USB_CLASS_VIDEO = 14
    private const val SC_VIDEOCONTROL = 1
    private const val SET_CUR = 0x01
    private const val GET_CUR = 0x81
    private const val PU_POWER_LINE_FREQUENCY = 0x05
    private const val PLF_60HZ = 2
    private const val USB_RECIP_INTERFACE = 0x01
    private const val TIMEOUT_MS = 1000

    fun set60Hz(context: Context): Map<String, Any?> {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = usbManager.deviceList.values.firstOrNull {
            CameraEmeetProfile.matches(it.vendorId, it.productName)
        } ?: return mapOf("ok" to false, "reason" to "no_emeet")

        if (!usbManager.hasPermission(device)) {
            return mapOf(
                "ok" to false,
                "reason" to "no_permission",
                "device" to device.productName,
            )
        }
        val conn = usbManager.openDevice(device)
            ?: return mapOf("ok" to false, "reason" to "open_failed", "device" to device.productName)

        try {
            val vcIfaces = videoControlInterfaces(device)
            val parsedUnits = parseProcessingUnitIds(conn)
            Log.i(
                TAG,
                "EMEET ${device.productName} vcIfaces=${vcIfaces.map { it.id }} puIds=$parsedUnits"
            )
            val unitIds = (parsedUnits + (1..16).toList()).distinct()
            val tried = mutableListOf<Map<String, Any?>>()

            for (iface in vcIfaces.ifEmpty { (0 until device.interfaceCount).map { device.getInterface(it) } }) {
                val claimed = tryClaim(conn, iface)
                try {
                    for (unitId in unitIds) {
                        val before = getPowerLine(conn, iface.id, unitId)
                        if (before == null && parsedUnits.isNotEmpty() && unitId !in parsedUnits) {
                            continue
                        }
                        if (before == null && parsedUnits.isEmpty()) {
                            // brute force: skip units that do not answer GET_CUR
                            continue
                        }
                        val setOk = setPowerLine(conn, iface.id, unitId, PLF_60HZ)
                        val after = getPowerLine(conn, iface.id, unitId)
                        val row = mapOf(
                            "iface" to iface.id,
                            "unit" to unitId,
                            "claimed" to claimed,
                            "before" to (before ?: -1),
                            "setOk" to setOk,
                            "after" to (after ?: -1),
                            "label" to label(after ?: before),
                        )
                        tried.add(row)
                        Log.i(TAG, "PU_POWER_LINE $row")
                        if (after == PLF_60HZ || (setOk && before != null)) {
                            return mapOf(
                                "ok" to (after == PLF_60HZ || setOk),
                                "device" to device.productName,
                                "iface" to iface.id,
                                "unit" to unitId,
                                "before" to (before ?: -1),
                                "after" to (after ?: -1),
                                "beforeLabel" to label(before),
                                "afterLabel" to label(after),
                            )
                        }
                    }
                    if (parsedUnits.isEmpty()) {
                        for (unitId in 1..16) {
                            val setOk = setPowerLine(conn, iface.id, unitId, PLF_60HZ)
                            if (!setOk) continue
                            val after = getPowerLine(conn, iface.id, unitId)
                            tried.add(
                                mapOf(
                                    "iface" to iface.id,
                                    "unit" to unitId,
                                    "claimed" to claimed,
                                    "setOk" to true,
                                    "after" to (after ?: -1),
                                )
                            )
                            if (after == PLF_60HZ || after != null) {
                                return mapOf(
                                    "ok" to true,
                                    "device" to device.productName,
                                    "iface" to iface.id,
                                    "unit" to unitId,
                                    "after" to (after ?: -1),
                                    "afterLabel" to label(after),
                                    "brute" to true,
                                )
                            }
                        }
                    }
                } finally {
                    if (claimed) {
                        try {
                            conn.releaseInterface(iface)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
            return mapOf(
                "ok" to false,
                "reason" to "control_failed",
                "device" to device.productName,
                "tried" to tried,
            )
        } catch (e: Exception) {
            Log.e(TAG, "set60Hz failed", e)
            return mapOf("ok" to false, "reason" to (e.message ?: "exception"))
        } finally {
            try {
                conn.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun videoControlInterfaces(device: UsbDevice): List<UsbInterface> {
        val out = mutableListOf<UsbInterface>()
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == USB_CLASS_VIDEO && iface.interfaceSubclass == SC_VIDEOCONTROL) {
                out.add(iface)
            }
        }
        return out
    }

    private fun tryClaim(conn: UsbDeviceConnection, iface: UsbInterface): Boolean {
        return try {
            conn.claimInterface(iface, false)
        } catch (e: Exception) {
            Log.w(TAG, "claimInterface(${iface.id}) failed", e)
            false
        }
    }

    private fun getPowerLine(conn: UsbDeviceConnection, ifaceId: Int, unitId: Int): Int? {
        val buf = ByteArray(1)
        val n = conn.controlTransfer(
            UsbConstants.USB_DIR_IN or UsbConstants.USB_TYPE_CLASS or USB_RECIP_INTERFACE,
            GET_CUR,
            PU_POWER_LINE_FREQUENCY shl 8,
            (unitId shl 8) or ifaceId,
            buf,
            buf.size,
            TIMEOUT_MS,
        )
        if (n < 1) return null
        val v = buf[0].toInt() and 0xff
        return if (v <= 3) v else null
    }

    private fun setPowerLine(
        conn: UsbDeviceConnection,
        ifaceId: Int,
        unitId: Int,
        value: Int,
    ): Boolean {
        val buf = byteArrayOf(value.toByte())
        val n = conn.controlTransfer(
            UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_CLASS or USB_RECIP_INTERFACE,
            SET_CUR,
            PU_POWER_LINE_FREQUENCY shl 8,
            (unitId shl 8) or ifaceId,
            buf,
            buf.size,
            TIMEOUT_MS,
        )
        return n == 1
    }

    private fun label(value: Int?): String = when (value) {
        0 -> "off"
        1 -> "50Hz"
        2 -> "60Hz"
        3 -> "auto"
        else -> "unknown"
    }

    private fun parseProcessingUnitIds(conn: UsbDeviceConnection): List<Int> {
        val raw = try {
            conn.rawDescriptors ?: return emptyList()
        } catch (_: Exception) {
            return emptyList()
        }
        val ids = mutableListOf<Int>()
        var off = 0
        var ifaceClass = -1
        var ifaceSub = -1
        while (off + 2 <= raw.size) {
            val len = raw[off].toInt() and 0xff
            val type = raw[off + 1].toInt() and 0xff
            if (len < 2 || off + len > raw.size) break
            if (type == 0x04 && len >= 6) {
                ifaceClass = raw[off + 5].toInt() and 0xff
                ifaceSub = raw[off + 6].toInt() and 0xff
            } else if (type == 0x24 && len >= 4) {
                val subtype = raw[off + 2].toInt() and 0xff
                if (subtype == 0x05 && ifaceClass == USB_CLASS_VIDEO && ifaceSub == SC_VIDEOCONTROL) {
                    ids.add(raw[off + 3].toInt() and 0xff)
                }
            }
            off += len
        }
        return ids.distinct()
    }
}
