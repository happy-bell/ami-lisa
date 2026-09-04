package jp.amiplus.lisa

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 端末起動後・アプリ更新後にアミを自動復帰させる。
 *
 * これが無いと、APK を入れ替えた直後や TV を再起動した直後にアプリが起動せず、
 * ソケットが繋がらないため「オフライン」のまま着信を受けられない。
 *
 * - BOOT_COMPLETED / QUICKBOOT_POWERON : 端末起動後
 * - MY_PACKAGE_REPLACED                : このアプリが更新された後
 *
 * 着信待機サービスを起動し、Pi レイアウト(ami-EX)では画面も復帰させる。
 */
class AmiAutoStartReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AmiAutoStart"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "onReceive $action")

        val known = action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        if (!known) return

        val app = context.applicationContext

        // 着信待機(フォアグラウンドサービス)を復帰させる。これでソケットが繋がり
        // オンライン状態に戻る。
        try {
            IncomingCallOverlayService.startWaiting(app)
            Log.i(TAG, "call waiting restarted")
        } catch (e: Exception) {
            Log.e(TAG, "startWaiting failed", e)
        }

        // 本体プロセスの見張り番も起こす（LMK対策）。
        try {
            LisaWatchdogService.start(app)
        } catch (e: Exception) {
            Log.e(TAG, "watchdog start failed", e)
        }

        // アプリ更新直後はアプリ本体も開いてソケット接続を確実にする。
        // 端末起動直後は他アプリ(地デジ等)の起動を妨げないよう、更新時のみ。
        if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            try {
                IncomingCallOverlayService.restoreMainActivity(app)
                Log.i(TAG, "main activity restored after update")
            } catch (e: Exception) {
                Log.e(TAG, "restoreMainActivity failed", e)
            }
        }
    }
}
