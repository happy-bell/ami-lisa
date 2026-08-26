package jp.amiplus.lisa

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * バックグラウンド／電源オフでも FCM から着信枠を出す（メーカー不問）。
 * Flutter MethodChannel はバックグラウンド isolate だと Activity に届かないためネイティブで処理する。
 */
class AmiIncomingFcmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val pending = goAsync()
        try {
            handleIncoming(context.applicationContext, extras)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    pending.finish()
                } catch (_: Exception) {
                }
            }, 2000)
        } catch (e: Exception) {
            Log.e(TAG, "handleIncoming failed", e)
            try {
                pending.finish()
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        private const val TAG = "AmiIncomingFcm"

        @JvmStatic
        fun handleIncoming(context: Context, extras: Bundle) {
            if (!isTelevision(context)) return
            if (MainActivity.isInForeground()) return

            val callerId = callerIdFrom(extras)
            if (callerId.isEmpty()) return

            val flags = readTvFlags(context)
            if (!flags.waiting && !flags.piLayout) {
                // Google TV は着信待機が常時ON。prefs が空でもテレビなら起こす。
                Log.w(TAG, "flags missing; still handling on TV callerId=$callerId")
            }

            // 注: 画面オフ状態の記録は Socket着信ハンドラ(room_page)側で wake 前に
            // setScreenOffAtCall として行う。ここ(FCM)で行うと wakeDisplay 後に
            // 上書きされる恐れがあるため行わない。
            IncomingCallOverlayService.captureForegroundApp(context)
            IncomingCallOverlayService.wakeDisplay(context)

            if (IncomingCallOverlayService.incomingUiActive ||
                IncomingCallOverlayService.acceptInProgress
            ) {
                Log.i(TAG, "fcm skip: incoming already shown")
                return
            }

            val callerName = "着信"
            Log.i(
                TAG,
                "fcm incoming callerId=$callerId pi=${flags.piLayout} auto=${flags.autoReceive}"
            )
            if (flags.autoReceive) {
                IncomingCallOverlayService.acceptIncoming(context, callerId, callerName)
            } else {
                IncomingCallOverlayService.showOverlay(context, callerId, callerName)
            }
        }

        fun isTelevision(context: Context): Boolean {
            val pm = context.packageManager
            if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
            ) {
                return true
            }
            val uiMode =
                context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
            return uiMode == Configuration.UI_MODE_TYPE_TELEVISION
        }

        private data class TvFlags(
            val waiting: Boolean,
            val autoReceive: Boolean,
            val piLayout: Boolean
        )

        private fun readTvFlags(context: Context): TvFlags {
            val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            fun str(key: String): String = sp.getString("flutter.$key", "") ?: ""
            var waiting = str("tv_TV_CALL_WAITING") == "1"
            var autoReceive = str("tv_AUTO_RECEIVE") == "1"
            var piLayout = str("tv_TV_LAYOUT") == "pi"
            val app = str("appsettings")
            if (app.contains("\"TV_CALL_WAITING\":\"1\"") ||
                app.contains("\"TV_CALL_WAITING\": \"1\"")
            ) {
                waiting = true
            }
            if (app.contains("\"AUTO_RECEIVE\":\"1\"") ||
                app.contains("\"AUTO_RECEIVE\": \"1\"")
            ) {
                autoReceive = true
            }
            if (app.contains("\"TV_LAYOUT\":\"pi\"") ||
                app.contains("\"TV_LAYOUT\": \"pi\"")
            ) {
                piLayout = true
            }
            for ((k, v) in sp.all) {
                if (k.startsWith("flutter.tv_layout_") && v?.toString() == "pi") {
                    piLayout = true
                    break
                }
            }
            return TvFlags(waiting, autoReceive, piLayout)
        }

        private fun notificationText(extras: Bundle, field: String): String {
            val keys = arrayOf(
                "gcm.notification.$field",
                "gcm.n.$field",
                field
            )
            for (key in keys) {
                val v = extras.getString(key)
                if (!v.isNullOrEmpty()) return v
            }
            return ""
        }

        private fun callerIdFrom(extras: Bundle): String {
            for (key in arrayOf("udid", "callerId", "id")) {
                val v = extras.getString(key)
                if (!v.isNullOrEmpty()) return v
            }
            val texts = listOf(
                notificationText(extras, "title"),
                notificationText(extras, "body")
            )
            for (text in texts) {
                var pos1 = text.indexOf('[')
                var pos2 = text.indexOf(']')
                if (pos1 < 0 || pos2 <= pos1) {
                    pos1 = text.indexOf('【')
                    pos2 = text.indexOf('】')
                }
                if (pos1 >= 0 && pos2 > pos1) {
                    return text.substring(pos1 + 1, pos2)
                }
            }
            return ""
        }
    }
}
