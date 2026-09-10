package jp.amiplus.lisa

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
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

        /**
         * 端末起動後、本体（Flutter）を背面で起こすまでの待ち。
         * 地デジ等の起動を妨げないよう、起動完了からしばらく置く。
         */
        private const val BOOT_RELAUNCH_DELAY_MS = 60_000L
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
        if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            try {
                IncomingCallOverlayService.restoreMainActivity(app)
                Log.i(TAG, "main activity restored after update")
            } catch (e: Exception) {
                Log.e(TAG, "restoreMainActivity failed", e)
            }
            return
        }

        // 端末起動後も、少し待ってから本体を**背面で**起こす（2026-09-08 追加）。
        //
        // 以前は「地デジ等の起動を妨げないよう、更新時のみ」として起こして
        // いなかった。ところが本体（Flutter）が動かないと、呼び出しボタンの
        // 聞き取り（RatocButtonService。room_page の didChangeDependencies で
        // 始まる）が始まらない。実機（TV005・2026-09-08 17:21 再起動）で、
        // 本体プロセスはサービスで生きているのに Flutter が起動せず、BLE の
        // スキャナが登録されないまま、ボタンが効かない状態が続いた。
        // 番犬（LisaWatchdogService）はプロセスの有無しか見ないので拾えない。
        //
        // 番犬の再起動と同じ経路（EXTRA_WATCHDOG_RESTART → MainActivity が
        // 1.5秒後に自分で背面へ回る）で起こす。地デジの起動は待つ。
        // すでに利用者が開いていれば何もしない。テレビ以外では行わない。
        if (!AmiIncomingFcmReceiver.isTelevision(app)) return
        Handler(Looper.getMainLooper()).postDelayed({
            if (MainActivity.currentActivity() != null) {
                Log.i(TAG, "main already open; skip boot relaunch")
                return@postDelayed
            }
            try {
                IncomingCallOverlayService.restoreMainAfterCrash(app)
                Log.i(TAG, "main activity relaunched after boot (background)")
            } catch (e: Exception) {
                Log.e(TAG, "boot relaunch failed", e)
            }
        }, BOOT_RELAUNCH_DELAY_MS)
    }
}
