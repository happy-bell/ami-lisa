package jp.amiplus.lisa

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.util.Log

/**
 * 通話終了後に「TV電源オフ(画面オフ)状態へ戻す」処理。TV005のみ対象。
 *
 * 判定は ANDROID_ID（権限不要）。画面オフは DevicePolicyManager.lockNow()（要デバイス管理有効化）。
 * 対象外端末・デバイス管理未有効化なら false を返し、呼び出し側は従来どおりホーム表示にフォールバックする。
 *
 * ※独自追加ファイルのため同期(rsync)で上書きされない。
 */
object TvStandbyController {
    private const val TAG = "TvStandby"

    // 対象端末の判定値。ro.serialno は端末により reflection 取得がブロックされる
    // (空になる)ため、アプリの ANDROID_ID を主判定に使う。ANDROID_ID は
    // 「アンインストール→新規インストール」で変わるが、install -r 更新では維持される。
    // 新規インストールし直した場合は、ログの androidId= を見てここを更新すること。
    private val TARGET_SERIALS = setOf(
        "G61JPN0CHOD00058361", // TV005 (Changhong AI PONT JP) の ro.serialno（取得可能な機種用）
    )
    private val TARGET_ANDROID_IDS = setOf(
        "f08aa289889d2136", // TV005 現インストールのアプリ ANDROID_ID
    )

    /** ro.serialno を SystemProperties から取得(権限不要)。 */
    fun deviceSerial(): String {
        return try {
            val c = Class.forName("android.os.SystemProperties")
            val m = c.getMethod("get", String::class.java)
            (m.invoke(null, "ro.serialno") as? String) ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    fun androidId(context: Context): String {
        return try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    /** TV005（対象端末）かどうか。serial か ANDROID_ID のいずれか一致で真。判定値をログに出す。 */
    fun isTargetDevice(context: Context): Boolean {
        val serial = deviceSerial()
        val aid = androidId(context)
        val match = serial in TARGET_SERIALS || aid in TARGET_ANDROID_IDS
        Log.i(TAG, "isTargetDevice serial=$serial androidId=$aid match=$match")
        return match
    }

    private fun adminComponent(context: Context): ComponentName {
        return ComponentName(context.applicationContext, AmiDeviceAdminReceiver::class.java)
    }

    /** デバイス管理が有効化済みか。 */
    fun isAdminActive(context: Context): Boolean {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.isAdminActive(adminComponent(context))
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 画面をオフ（ロック）にして待機状態へ戻す。
     * 対象端末かつデバイス管理有効時のみ実行し、成功したら true。
     * それ以外は false（呼び出し側はホーム表示にフォールバック）。
     */
    fun lockScreenForStandby(context: Context): Boolean {
        if (!isTargetDevice(context)) {
            Log.i(TAG, "not target device; skip lock")
            return false
        }
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            if (!dpm.isAdminActive(adminComponent(context))) {
                Log.w(TAG, "device admin not active; cannot lock")
                return false
            }
            // 電源オン時に直前アプリ(地デジ/Netflix等)が出るよう、画面オフの前に
            // アミを背面へ送って直前アプリを最前面へ戻す。通話中はアミが前面のため、
            // これをしないと電源オン時にアミが開いてしまう。
            (context as? android.app.Activity)?.let { act ->
                try {
                    IncomingCallOverlayService.returnToPreviousApp(act)
                    Log.i(TAG, "restored previous app before lock")
                } catch (e: Exception) {
                    Log.w(TAG, "returnToPreviousApp before lock failed: ${e.message}")
                }
            }
            dpm.lockNow()
            Log.i(TAG, "lockNow(): screen off for standby")
            true
        } catch (e: Exception) {
            Log.e(TAG, "lockScreenForStandby failed", e)
            false
        }
    }
}
