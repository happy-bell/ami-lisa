package jp.amiplus.lisa

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.Display
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView

/**
 * テレビ視聴中でも「着信あり」オーバーレイを出し、はい/いいえを受け取る。
 * はい → MainActivity を全面起動（accept）
 * いいえ → オーバーレイを閉じる（reject）
 */
class IncomingCallOverlayService : Service() {
    companion object {
        private const val TAG = "AmiIncomingOverlay"
        const val CHANNEL_ID = "ami_call_waiting"
        const val INCOMING_CHANNEL_ID = "ami_incoming_call"
        const val NOTIF_ID = 7101
        const val INCOMING_NOTIF_ID = 7102

        const val ACTION_START_WAITING = "jp.amiplus.lisa.action.START_WAITING"
        const val ACTION_STOP_WAITING = "jp.amiplus.lisa.action.STOP_WAITING"
        const val ACTION_SHOW_OVERLAY = "jp.amiplus.lisa.action.SHOW_OVERLAY"
        const val ACTION_ACCEPT_INCOMING = "jp.amiplus.lisa.action.ACCEPT_INCOMING"
        const val ACTION_DISMISS_OVERLAY = "jp.amiplus.lisa.action.DISMISS_OVERLAY"
        const val ACTION_BRING_TO_FRONT = "jp.amiplus.lisa.action.BRING_TO_FRONT"
        const val ACTION_SHOW_SAFETY_UI = "jp.amiplus.lisa.action.SHOW_SAFETY_UI"
        const val ACTION_HIDE_SAFETY_UI = "jp.amiplus.lisa.action.HIDE_SAFETY_UI"

        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_SAFETY_COLOR = "safety_clock_color"

        /** 設定／時計のデフォルト（明るい RGB 110,151,81）。 */
        const val DEFAULT_CLOCK_COLOR = 0xFF6E9751.toInt()

        @Volatile
        private var safetyClockColor = DEFAULT_CLOCK_COLOR

        const val PREFS = "ami_tv_call"
        const val KEY_WAITING = "call_waiting_enabled"
        const val KEY_RESTORE_ON_SCREEN_ON = "restore_on_screen_on"
        const val KEY_PENDING_ACTION = "pending_incoming_action"
        const val KEY_PENDING_CALLER_ID = "pending_caller_id"
        const val KEY_PENDING_CALLER_NAME = "pending_caller_name"
        const val KEY_PREV_PACKAGE = "prev_watch_package"
        const val KEY_PREV_TASK_ID = "prev_watch_task_id"
        const val KEY_PREV_CLASS = "prev_watch_class"
        const val KEY_INTERRUPTED = "prev_watch_interrupted"
        /** 番犬(:watch)による再起動を MainActivity に知らせる。 */
        const val EXTRA_WATCHDOG_RESTART = "watchdog_restart"
        const val KEY_AMI_WAS_TOP = "ami_was_top_at_screen_off"
        // 着信到達時に画面オフ(TV電源オフ)だったか。通話終了後に電源オフへ戻す判定に使う。
        /** 着信が届いた瞬間に画面オフ(TV電源オフ)だったか。wake前に立てる。 */
        const val KEY_SCREEN_OFF_AT_INCOMING = "screen_off_at_incoming"
        const val KEY_SCREEN_OFF_AT_CALL = "screen_off_at_call"
        /** ACTION_SCREEN_OFF 等で立てる待機フラグ。Android12はこれが頼り。 */
        const val KEY_STANDBY = "tv_standby"
        private const val KEY_ADMIN_PROMPTED = "device_admin_prompted"
        const val KEY_LAST_MEDIA_PKG = "last_media_pkg"
        const val KEY_LAST_MEDIA_CLASS = "last_media_class"
        const val KEY_PI_LAYOUT = "pi_tv_layout"
        private const val PLAYER_STATE_STARTED = 2
        private const val KIOSK_INTERVAL_MS = 25_000L

        @Volatile
        private var serviceAlive = false

        @Volatile
        private var running: IncomingCallOverlayService? = null

        /** 見守り前面化の再試行期限。終了後の直前復帰とぶつからないようにする。 */
        @Volatile
        private var bringFrontUntil = 0L

        /** 見守り前面化で startActivity したか。2回目のスプラッシュを出さない。 */
        @Volatile
        private var safetyActivityStarted = false

        /** 電源オフ発のとき、POWER は1回だけ送る（トグルなので連打すると消灯・フリーズする）。 */
        @Volatile
        private var pendingPowerWake = false

        /** この見守り／起床セッションですでに POWER を送ったか。 */
        @Volatile
        private var powerKeySent = false

        @Volatile
        var incomingUiActive = false

        @Volatile
        var acceptInProgress = false

        @Volatile
        private var acceptGuardUntil = 0L

        private const val DISPLAY_NAME = "着信中"
        private const val OVERLAY_TIMEOUT_MS = 29_000L
        private const val CANCEL_GRACE_MS = 8_000L

        @Volatile
        var ringingCallerId = ""

        @Volatile
        private var cancelledCallerId = ""

        @Volatile
        private var cancelledUntil = 0L

        @Volatile
        private var timeoutContext: Context? = null

        private fun shouldSkipIncomingUi(): Boolean {
            if (acceptInProgress) return true
            if (incomingUiActive) return true
            if (IncomingCallActivity.isOpen()) return true
            if (System.currentTimeMillis() < acceptGuardUntil) return true
            return false
        }

        private fun markAcceptGuard() {
            acceptInProgress = true
            acceptGuardUntil = System.currentTimeMillis() + 12_000L
            Handler(Looper.getMainLooper()).postDelayed({
                acceptInProgress = false
            }, 12_000L)
        }

        fun wasIncomingCancelled(callerId: String): Boolean {
            if (callerId.isEmpty()) return false
            return callerId == cancelledCallerId && System.currentTimeMillis() < cancelledUntil
        }

        fun markIncomingCancelled(callerId: String) {
            if (callerId.isNotEmpty()) {
                cancelledCallerId = callerId
                cancelledUntil = System.currentTimeMillis() + CANCEL_GRACE_MS
            }
            if (ringingCallerId == callerId || callerId.isEmpty()) {
                ringingCallerId = ""
            }
            wakeHandler.removeCallbacks(overlayTimeout)
        }

        /** スマホ切断。着信画面を消し、はいが遅れても通話に入らない。 */
        fun cancelIncomingUi(context: Context, callerId: String) {
            val app = context.applicationContext
            val accepting = acceptInProgress
            markIncomingCancelled(callerId)
            IncomingCallActivity.finishIfOpen()
            dismissOverlay(app)
            if (!accepting) {
                if (wasScreenOffAtCall(app)) {
                    lockScreenForStandby(app)
                } else {
                    returnToPreviousFromService(app)
                }
            }
            Log.i(TAG, "cancelIncomingUi caller=$callerId accepting=$accepting")
        }

        /**
         * 29秒で着信画面だけ消す。電源は切らない。
         * 着信あり表示時点の画面（地デジ等）へ戻す。
         */
        fun timeoutIncomingUi(context: Context, callerId: String) {
            val app = context.applicationContext
            val accepting = acceptInProgress
            markIncomingCancelled(callerId)
            IncomingCallActivity.finishIfOpen()
            dismissOverlay(app)
            if (!accepting) {
                val restored = returnToPreviousFromService(app)
                Log.i(TAG, "timeoutIncomingUi restore=$restored caller=$callerId")
            } else {
                Log.i(TAG, "timeoutIncomingUi skip restore: accepting caller=$callerId")
            }
        }

        private val overlayTimeout = Runnable {
            val id = ringingCallerId
            val app = timeoutContext ?: return@Runnable
            if (id.isEmpty()) return@Runnable
            Log.i(TAG, "incoming overlay timeout 29s caller=$id")
            timeoutIncomingUi(app, id)
        }

        private data class WatchApp(val pkg: String, val taskId: Int, val className: String)

        private val ignoredPackages = setOf(
            "android",
            "com.android.systemui",
            "com.google.android.tvlauncher",
            "com.google.android.apps.tv.launcherx",
            "com.google.android.tungsten.setupwraith",
            "com.google.android.katniss",
            "com.tcl.home",
            "com.tcl.t_home",
            "com.tcl.guard",
            "com.tcl.dashboard",
            "com.google.android.tvrecommendations",
            "com.google.android.backdrop",
            "com.google.android.leanbacklauncher",
            "com.android.tv.settings",
        )

        private fun isIgnoredPackage(pkg: String): Boolean {
            if (pkg.isEmpty()) return true
            if (ignoredPackages.contains(pkg)) return true
            if (pkg == "com.android.systemui" || pkg.startsWith("com.android.systemui")) return true
            if (pkg.startsWith("com.android.providers.")) return true
            return false
        }

        /** Google TV / Android TV のホームランチャー。 */
        private fun isTvLauncherPackage(pkg: String): Boolean {
            if (pkg.isEmpty()) return false
            return pkg == "com.google.android.apps.tv.launcherx" ||
                pkg == "com.google.android.tvlauncher" ||
                pkg == "com.google.android.leanbacklauncher" ||
                pkg.startsWith("com.google.android.apps.tv.launcher")
        }

        private fun isLiveTvPackage(pkg: String): Boolean {
            if (pkg.isEmpty() || pkg.contains("service")) return false
            return pkg == "com.tcl.tv" ||
                pkg == "com.dragontec.grefplus.dtv" ||
                pkg == "com.droidlogic.android.tv" ||
                pkg == "com.mediatek.wwtv.tvcenter" ||
                pkg == "com.google.android.tv" ||
                pkg == "com.android.tv" ||
                pkg.endsWith(".dtv")
        }

        private fun packageForPlaybackUid(context: Context, uid: Int): String? {
            val pkgs = context.packageManager.getPackagesForUid(uid) ?: return null
            val preferred = arrayOf(
                "com.tcl.tv",
                "com.dragontec.grefplus.dtv",
                "com.netflix.ninja",
                "com.google.android.youtube.tv",
                "com.google.android.tv",
                "com.android.tv",
                "com.droidlogic.android.tv",
            )
            preferred.firstOrNull { pkgs.contains(it) }?.let { return it }
            pkgs.firstOrNull { isLiveTvPackage(it) }?.let { return it }
            if (uid == 1000) return null
            val my = context.packageName
            return pkgs.firstOrNull { it != my && !isIgnoredPackage(it) }
        }

        fun clearWatchRestore(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .remove(KEY_PREV_PACKAGE)
                .remove(KEY_PREV_TASK_ID)
                .remove(KEY_PREV_CLASS)
                .putBoolean(KEY_INTERRUPTED, false)
                .apply()
        }

        /**
         * 着信で全面化する直前の視聴アプリを覚える。
         * ami が既に前面なら記録しない（ホームからの発信で地デジへ飛ばない）。
         * 全面化後の再呼び出しでは、先に撮った記録を上書きしない。
         */
        fun captureForegroundApp(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val existing = prefs.getString(KEY_PREV_PACKAGE, "") ?: ""
            if (prefs.getBoolean(KEY_INTERRUPTED, false) || existing.isNotEmpty()) {
                Log.i(TAG, "capture keep existing prev=$existing")
                return
            }
            val amiFg = MainActivity.isInForeground()
            val amiWasTop = prefs.getBoolean(KEY_AMI_WAS_TOP, false)
            val inAmi = amiFg || (!isScreenOn(context) && amiWasTop)
            if (inAmi) {
                Log.i(TAG, "capture skip: ami is current (fg=$amiFg wasTop=$amiWasTop)")
                return
            }
            val found = findInterruptedApp(context)
            val edit = prefs.edit().putBoolean(KEY_INTERRUPTED, true)
            if (found != null) {
                edit.putString(KEY_PREV_PACKAGE, found.pkg)
                    .putInt(KEY_PREV_TASK_ID, found.taskId)
                    .putString(KEY_PREV_CLASS, found.className)
                Log.i(
                    TAG,
                    "captured previous app ${found.pkg} class=${found.className} task=${found.taskId}"
                )
            } else {
                Log.i(TAG, "interrupted other UI; package unknown (restore via moveTaskToBack)")
            }
            edit.apply()
        }

        fun rememberPlayingMedia(context: Context, pkg: String, className: String) {
            if (pkg.isEmpty() || pkg == context.packageName || isIgnoredPackage(pkg)) return
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_LAST_MEDIA_PKG, pkg)
                .putString(KEY_LAST_MEDIA_CLASS, className)
                .apply()
            Log.i(TAG, "last media $pkg")
        }

        private fun lastRememberedMedia(context: Context): WatchApp? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pkg = prefs.getString(KEY_LAST_MEDIA_PKG, "") ?: ""
            if (pkg.isEmpty() || pkg == context.packageName || isIgnoredPackage(pkg)) return null
            val className = prefs.getString(KEY_LAST_MEDIA_CLASS, "") ?: ""
            return WatchApp(pkg, -1, className)
        }

        /**
         * いま画面に出ているアプリだけを返す。
         * ami / ランチャーが先頭なら null（2番目の Netflix を「視聴中」と誤らない）。
         */
        private fun topVisibleWatchApp(context: Context): WatchApp? {
            val my = context.packageName
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            try {
                @Suppress("DEPRECATION")
                val task = am.getRunningTasks(1).firstOrNull()
                val cn = task?.topActivity ?: task?.baseActivity
                if (cn != null) {
                    if (cn.packageName == my || isIgnoredPackage(cn.packageName)) {
                        return null
                    }
                    return WatchApp(cn.packageName, task?.id ?: -1, cn.className ?: "")
                }
            } catch (e: Exception) {
                Log.w(TAG, "getRunningTasks: ${e.message}")
            }
            try {
                @Suppress("DEPRECATION")
                val recents = am.getRecentTasks(8, ActivityManager.RECENT_WITH_EXCLUDED)
                for (task in recents) {
                    if (task.baseIntent?.hasCategory(Intent.CATEGORY_HOME) == true) continue
                    if (task.numActivities <= 0) continue
                    val cn = task.topActivity ?: task.baseIntent?.component ?: continue
                    if (cn.packageName == my || isIgnoredPackage(cn.packageName)) {
                        return null
                    }
                    return WatchApp(cn.packageName, recentTaskId(task), cn.className ?: "")
                }
            } catch (e: Exception) {
                Log.w(TAG, "getRecentTasks: ${e.message}")
            }
            return null
        }

        private fun rawTopApp(context: Context): WatchApp? {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            try {
                @Suppress("DEPRECATION")
                val task = am.getRunningTasks(1).firstOrNull()
                val cn = task?.topActivity ?: task?.baseActivity ?: return null
                return WatchApp(cn.packageName, task?.id ?: -1, cn.className ?: "")
            } catch (e: Exception) {
                Log.w(TAG, "rawTopApp: ${e.message}")
                return null
            }
        }

        /**
         * ami-EX のキオスク復帰で奪ってはいけない前面。
         * ランチャー／スクリーンセーバーはここには入れない（ホームへ戻す対象）。
         */
        private fun isKioskProtected(pkg: String, className: String): Boolean {
            if (pkg.isEmpty()) return false
            // TVランチャー(Google TV ホーム)は保護する。電源オン直後は地デジ等へ戻る
            // 過渡状態で一時的にランチャーが前面に出るため、ここでアミを前面化すると
            // 「電源オン→地デジ→数十秒後にアミへ遷移」になってしまう。
            if (isTvLauncherPackage(pkg)) return true
            if (className.contains("UsbPermission")) return true
            if (className.contains("GrantPermissions")) return true
            if (isLiveTvPackage(pkg)) return true
            if (isYoutubePackage(pkg)) return true
            if (isStreamingWatchPackage(pkg)) return true
            if (pkg.startsWith("com.android.tv.settings")) return true
            if (pkg.startsWith("com.android.settings")) return true
            if (pkg == "com.google.android.gms") return true
            if (pkg.startsWith("com.google.android.packageinstaller")) return true
            if (pkg == "com.google.android.katniss") return true
            if (pkg == "com.google.android.tungsten.setupwraith") return true
            if (pkg.startsWith("com.android.systemui")) return true
            return false
        }

        private fun topIsOurApp(context: Context): Boolean {
            val my = context.packageName
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            try {
                @Suppress("DEPRECATION")
                val p = am.getRunningTasks(1).firstOrNull()?.topActivity?.packageName
                if (p == my) return true
            } catch (_: Exception) {
            }
            try {
                @Suppress("DEPRECATION")
                val t = am.getRecentTasks(1, ActivityManager.RECENT_WITH_EXCLUDED).firstOrNull()
                val p = t?.topActivity?.packageName ?: t?.baseIntent?.component?.packageName
                if (p == my) return true
            } catch (_: Exception) {
            }
            return MainActivity.isInForeground()
        }

        private fun findInterruptedApp(context: Context): WatchApp? {
            val top = topVisibleWatchApp(context)
            if (top != null) {
                Log.i(TAG, "capture from visible top ${top.pkg}")
                return top
            }
            val playing = currentStartedMedia(context)
            if (playing != null) {
                Log.i(TAG, "capture from playing audio ${playing.pkg}")
                return playing
            }
            if (topIsOurApp(context)) {
                val remembered = lastRememberedMedia(context)
                if (remembered != null) {
                    Log.i(TAG, "capture from last media ${remembered.pkg}")
                    return remembered
                }
            }
            Log.i(TAG, "capture no visible/playing app")
            return null
        }

        @Suppress("DEPRECATION")
        private fun recentTaskId(info: ActivityManager.RecentTaskInfo): Int {
            return try {
                val m = info.javaClass.methods.firstOrNull { it.name == "getTaskId" && it.parameterCount == 0 }
                val v = m?.invoke(info) as? Int
                if (v != null && v > 0) v else info.id
            } catch (_: Exception) {
                info.id
            }
        }

        private fun currentStartedMedia(context: Context): WatchApp? {
            if (Build.VERSION.SDK_INT < 26) return null
            return try {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                pickStartedMedia(context, audio.activePlaybackConfigurations)
            } catch (e: Exception) {
                Log.w(TAG, "audio playback: ${e.message}")
                null
            }
        }

        private fun pickStartedMedia(
            context: Context,
            configs: List<AudioPlaybackConfiguration>
        ): WatchApp? {
            val my = context.packageName
            val myUid = Process.myUid()
            val started = mutableListOf<WatchApp>()
            for (cfg in configs) {
                if (playbackState(cfg) != PLAYER_STATE_STARTED) continue
                val usage = try {
                    cfg.audioAttributes.usage
                } catch (_: Exception) {
                    -1
                }
                if (usage == AudioAttributes.USAGE_ASSISTANCE_SONIFICATION ||
                    usage == AudioAttributes.USAGE_NOTIFICATION ||
                    usage == AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                ) {
                    continue
                }
                val uid = playbackClientUid(cfg)
                if (uid < 0 || uid == myUid) continue
                val pkg = packageForPlaybackUid(context, uid) ?: continue
                if (pkg == my || isIgnoredPackage(pkg)) continue
                started.add(WatchApp(pkg, -1, ""))
            }
            started.firstOrNull { isLiveTvPackage(it.pkg) }?.let { return it }
            return started.firstOrNull()
        }

        private fun playbackState(cfg: AudioPlaybackConfiguration): Int {
            try {
                val m = cfg.javaClass.methods.firstOrNull { it.name == "getPlayerState" && it.parameterCount == 0 }
                val v = m?.invoke(cfg) as? Int
                if (v != null) return v
            } catch (_: Exception) {
            }
            return try {
                val f = cfg.javaClass.getDeclaredField("mPlayerState")
                f.isAccessible = true
                f.getInt(cfg)
            } catch (_: Exception) {
                -1
            }
        }

        private fun playbackClientUid(cfg: AudioPlaybackConfiguration): Int {
            try {
                val m = cfg.javaClass.methods.firstOrNull { it.name == "getClientUid" && it.parameterCount == 0 }
                val v = m?.invoke(cfg) as? Int
                if (v != null && v >= 0) return v
            } catch (_: Exception) {
            }
            return try {
                val f = cfg.javaClass.getDeclaredField("mClientUid")
                f.isAccessible = true
                f.getInt(cfg)
            } catch (_: Exception) {
                -1
            }
        }

        /** 通話終了後、直前の視聴アプリへ戻す。Netflix/YouTube は再起動せず既存タスクへ。 */
        fun returnToPreviousApp(activity: Activity): Boolean {
            bringFrontUntil = 0L
            safetyActivityStarted = false
            val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pkg = prefs.getString(KEY_PREV_PACKAGE, "") ?: ""
            val taskId = prefs.getInt(KEY_PREV_TASK_ID, -1)
            val className = prefs.getString(KEY_PREV_CLASS, "") ?: ""
            val interrupted = prefs.getBoolean(KEY_INTERRUPTED, false)
            clearWatchRestore(activity)
            if (!interrupted && (pkg.isEmpty() || pkg == activity.packageName || isIgnoredPackage(pkg))) {
                Log.i(TAG, "returnToPreviousApp: nothing to restore")
                return false
            }
            var broughtTask = false
            if (pkg.isNotEmpty() && pkg != activity.packageName && !isIgnoredPackage(pkg)) {
                if (isYoutubePackage(pkg)) {
                    // YouTube の ShellActivity を前面に出すと再起動が走り、アミが落ちる。
                    // 本編は通話の裏に残っているので、ami を下げるだけで戻す。
                    Log.i(TAG, "youtube restore via moveTaskToBack only")
                    broughtTask = true
                } else {
                    broughtTask = moveMatchingTaskToFront(activity, pkg, taskId)
                    if (!broughtTask && isLiveTvPackage(pkg)) {
                        broughtTask = launchLiveTv(activity, pkg, className)
                        if (!broughtTask) {
                            Handler(Looper.getMainLooper()).postDelayed({ sendLiveTvKey() }, 250)
                            broughtTask = true
                        }
                    }
                }
            }
            if (interrupted) {
                try {
                    activity.moveTaskToBack(true)
                    Log.i(TAG, "moveTaskToBack after restore pkg=$pkg task=$broughtTask")
                    return true
                } catch (e: Exception) {
                    Log.w(TAG, "moveTaskToBack: ${e.message}")
                }
            }
            Log.i(TAG, "returnToPreviousApp pkg=$pkg interrupted=$interrupted brought=$broughtTask")
            return broughtTask
        }

        /** サービス／着信Activityから直前アプリへ戻す。 */
        fun returnToPreviousFromService(context: Context): Boolean {
            val act = MainActivity.currentActivity()
            if (act != null) {
                return returnToPreviousApp(act)
            }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pkg = prefs.getString(KEY_PREV_PACKAGE, "") ?: ""
            val interrupted = prefs.getBoolean(KEY_INTERRUPTED, false)
            clearWatchRestore(context)
            if (!interrupted || pkg.isEmpty() || pkg == context.packageName || isIgnoredPackage(pkg)) {
                return false
            }
            return try {
                val launch = context.packageManager.getLeanbackLaunchIntentForPackage(pkg)
                    ?: context.packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launch)
                    Log.i(TAG, "returnToPreviousFromService launched $pkg")
                    true
                } else {
                    false
                }
            } catch (e: Exception) {
                Log.w(TAG, "returnToPreviousFromService: ${e.message}")
                false
            }
        }

        private fun isYoutubePackage(pkg: String): Boolean {
            return pkg.startsWith("com.google.android.youtube.tv") ||
                pkg == "com.google.android.youtube"
        }

        private fun isStreamingWatchPackage(pkg: String): Boolean {
            if (pkg.contains("netflix")) return true
            if (pkg.contains("amazon.avod") || pkg.contains("amazonvideo")) return true
            if (pkg.startsWith("jp.unext.")) return true
            if (pkg == "tv.abema" || pkg.startsWith("tv.abema.")) return true
            if (pkg.contains(".tver") || pkg.endsWith(".tvapp")) return true
            if (pkg.contains("disneyplus") || pkg.contains("disney.star")) return true
            if (pkg == "jp.happyon.android" || pkg.contains("hulu")) return true
            if (pkg.startsWith("com.apple.atve.")) return true
            if (pkg == "com.dazn" || pkg.startsWith("com.dazn.")) return true
            if (pkg.startsWith("jp.or.nhk.")) return true
            if (pkg.contains("lemino")) return true
            if (pkg == "com.dmm.tv") return true
            if (pkg.contains("wowow")) return true
            if (pkg.contains("telasa")) return true
            return false
        }

        private fun skipWatchTaskClass(className: String?): Boolean {
            val n = className ?: return false
            return n.contains("ShellActivity") || n.contains("DispatchActivity")
        }

        private fun watchTaskRank(pkg: String, className: String?): Int {
            val n = className ?: ""
            if (skipWatchTaskClass(n)) return -1
            if (isYoutubePackage(pkg) && n.contains("MainActivity")) return 3
            if (n.contains("MainActivity") || n.contains("TVActivity") || n.contains("TVPlayer")) return 2
            return 1
        }

        private fun sameWatchPackage(expected: String, actual: String?): Boolean {
            if (actual.isNullOrEmpty()) return false
            if (actual == expected) return true
            if (expected == "com.google.android.youtube.tv" &&
                actual.startsWith("com.google.android.youtube.tv")
            ) {
                return true
            }
            return false
        }

        @Suppress("DEPRECATION")
        private fun moveMatchingTaskToFront(context: Context, pkg: String, savedTaskId: Int): Boolean {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            data class Cand(val id: Int, val rank: Int, val why: String)
            val cands = mutableListOf<Cand>()
            fun add(id: Int, className: String?, why: String) {
                if (id <= 0) return
                val rank = watchTaskRank(pkg, className)
                if (rank < 0) return
                cands.add(Cand(id, rank, why))
            }
            try {
                for (task in am.getRunningTasks(20)) {
                    if (task.numActivities <= 0) continue
                    val cn = task.topActivity ?: task.baseActivity
                    if (sameWatchPackage(pkg, cn?.packageName)) {
                        add(task.id, cn?.className, "running")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "running for restore: ${e.message}")
            }
            try {
                for (task in am.getRecentTasks(20, ActivityManager.RECENT_WITH_EXCLUDED)) {
                    if (task.numActivities <= 0) continue
                    val cn = task.topActivity ?: task.baseIntent?.component
                    if (sameWatchPackage(pkg, cn?.packageName)) {
                        add(recentTaskId(task), cn?.className, "recent")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "recent for restore: ${e.message}")
            }
            if (savedTaskId > 0 && cands.none { it.id == savedTaskId }) {
                add(savedTaskId, "", "saved")
            }
            val best = cands.maxByOrNull { it.rank } ?: return false
            return try {
                am.moveTaskToFront(best.id, 0)
                Log.i(TAG, "moved task ${best.id} ($pkg) ${best.why} rank=${best.rank}")
                true
            } catch (e: Exception) {
                Log.w(TAG, "moveTaskToFront ${best.id}: ${e.message}")
                false
            }
        }

        private fun launchLiveTv(context: Context, pkg: String, className: String): Boolean {
            val flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            fun tryStart(intent: Intent, why: String): Boolean {
                return try {
                    intent.addFlags(flags)
                    context.startActivity(intent)
                    Log.i(TAG, "launched $pkg via $why")
                    true
                } catch (e: Exception) {
                    Log.w(TAG, "launch $why $pkg: ${e.message}")
                    false
                }
            }
            if (pkg == "com.tcl.tv") {
                val view = Intent(Intent.ACTION_VIEW, Uri.parse("livetv://tvactivity"))
                view.setPackage(pkg)
                if (tryStart(view, "livetv://")) return true
                val tv = Intent("tcl.sys.intent.action.TV")
                tv.setPackage(pkg)
                if (tryStart(tv, "tcl.TV")) return true
            }
            if (pkg == "com.dragontec.grefplus.dtv") {
                val player = className.ifEmpty {
                    "cn.com.dragontec.dtv4k.ui.player.TVPlayerActivity"
                }
                if (tryStart(Intent().setClassName(pkg, player), "dtv-player")) return true
            }
            return false
        }

        private fun sendLiveTvKey() {
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", "170"))
                Log.i(TAG, "sent KEYCODE_TV")
            } catch (e: Exception) {
                Log.w(TAG, "KEYCODE_TV: ${e.message}")
            }
        }

        fun canDrawOverlays(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }

        fun startWaiting(context: Context, piLayout: Boolean? = null) {
            if (piLayout != null) {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_PI_LAYOUT, piLayout)
                    .apply()
            }
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_START_WAITING
            }
            // 起動済みなら startService。startForegroundService を重ねると
            // 5秒以内にもう一度 startForeground が必須になり、落ちる。
            if (serviceAlive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                context.startService(i)
            } else {
                context.startForegroundService(i)
            }
        }

        /** ami-EX のみ。Flutter の tv_TV_LAYOUT を優先する。 */
        fun isPiTvLayout(context: Context): Boolean {
            val flutter = try {
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getString("flutter.tv_TV_LAYOUT", "") ?: ""
            } catch (_: Exception) {
                ""
            }
            if (flutter == "pi") return true
            if (flutter == "tcl") return false
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_PI_LAYOUT, false)
        }

        fun stopWaiting(context: Context) {
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_STOP_WAITING
            }
            context.startService(i)
        }

        /** 着信到達時に画面オフ(TV電源オフ)だったかを記録。通話終了後の復帰判定に使う。 */
        fun markScreenStateAtCall(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_SCREEN_OFF_AT_CALL, !isScreenOn(context))
                .apply()
        }

        /**
         * 着信ごとに、その時点の画面オフ状態を正確に記録する(上書き)。
         * Socket着信ハンドラが wake 前の screenOn 値を渡して呼ぶ。ラッチしないので
         * 前回の着信値を持ち越さない(電源オン中の着信で誤って電源オフしない)。
         */
        fun showOverlay(context: Context, callerId: String, callerName: String) {
            if (shouldSkipIncomingUi()) {
                Log.i(TAG, "showOverlay skip: incoming already shown")
                return
            }
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_SHOW_OVERLAY
                putExtra(EXTRA_CALLER_ID, callerId)
                putExtra(EXTRA_CALLER_NAME, callerName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        /** 確認なしで画面を点け、アプリを全面化して応答する */
        fun acceptIncoming(context: Context, callerId: String, callerName: String) {
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_ACCEPT_INCOMING
                putExtra(EXTRA_CALLER_ID, callerId)
                putExtra(EXTRA_CALLER_NAME, callerName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        /** 確認なしでアプリを前面へ。バックグラウンド制限を避けるためサービスから出す。 */
        fun showSafetyWatchUi(context: Context, color: Int = DEFAULT_CLOCK_COLOR) {
            safetyClockColor = color
            val app = context.applicationContext
            val i = Intent(app, IncomingCallOverlayService::class.java).apply {
                action = ACTION_SHOW_SAFETY_UI
                putExtra(EXTRA_SAFETY_COLOR, color)
            }
            try {
                if (serviceAlive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    app.startService(i)
                } else {
                    app.startForegroundService(i)
                }
            } catch (e: Exception) {
                Log.w(TAG, "showSafetyWatchUi: ${e.message}")
            }
        }

        fun hideSafetyWatchUi(context: Context) {
            val app = context.applicationContext
            val i = Intent(app, IncomingCallOverlayService::class.java).apply {
                action = ACTION_HIDE_SAFETY_UI
            }
            try {
                app.startService(i)
            } catch (e: Exception) {
                Log.w(TAG, "hideSafetyWatchUi: ${e.message}")
            }
        }

        fun bringToFront(context: Context) {
            val app = context.applicationContext
            val now = System.currentTimeMillis()
            if (now > bringFrontUntil) {
                safetyActivityStarted = false
            }
            bringFrontUntil = now + 8_000L
            wakeDisplay(app)
            val i = Intent(app, IncomingCallOverlayService::class.java).apply {
                action = ACTION_BRING_TO_FRONT
            }
            try {
                if (serviceAlive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    app.startService(i)
                } else {
                    app.startForegroundService(i)
                }
            } catch (e: Exception) {
                Log.w(TAG, "bringToFront start: ${e.message}")
                restoreMainActivity(app)
            }
        }

        /**
         * 番犬(:watch)からの再起動。LMK で本体が死んだあとに MainActivity を
         * 立て直す。視聴の邪魔をしないよう、MainActivity 側で
         * EXTRA_WATCHDOG_RESTART を見て背面へ回る。
         */
        fun restoreMainAfterCrash(context: Context) {
            val app = context.applicationContext
            try {
                val intent = Intent(app, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    putExtra(EXTRA_WATCHDOG_RESTART, true)
                }
                app.startActivity(intent)
                Log.i(TAG, "restoreMainAfterCrash startActivity")
            } catch (e: Exception) {
                Log.w(TAG, "restoreMainAfterCrash: ${e.message}")
            }
        }

        fun restoreMainActivity(context: Context) {
            val app = context.applicationContext
            val standby = isTvStandby(app) || pendingPowerWake
            applyTurnScreenOn(MainActivity.currentActivity())
            // 見守り前面化中は「すでに前面」でも startActivity する。
            // TCL はスクリーンレスで isInForeground=true のまま他アプリが乗ることがある。
            val forcing = System.currentTimeMillis() <= bringFrontUntil
            if (!forcing && !standby && MainActivity.isInForeground()) {
                Log.i(TAG, "restoreMainActivity skip: already front")
                return
            }
            if (!forcing && !standby && moveAmiTaskToFront(app)) {
                return
            }
            moveAmiTaskToFront(app)
            // 見守り再試行では startActivity を1回だけ。2回目がスプラッシュになる。
            if (forcing && safetyActivityStarted) {
                Log.i(TAG, "restoreMainActivity skip startActivity: already started")
                return
            }
            val i = Intent(app, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            }
            try {
                app.startActivity(i)
                if (forcing) safetyActivityStarted = true
                Log.i(TAG, "restoreMainActivity started")
            } catch (e: Exception) {
                Log.w(TAG, "restoreMainActivity: ${e.message}")
            }
        }

        @Suppress("DEPRECATION")
        private fun moveAmiTaskToFront(context: Context): Boolean {
            try {
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val my = context.packageName
                for (task in am.getRunningTasks(20)) {
                    val pkg = task.topActivity?.packageName ?: task.baseActivity?.packageName
                    if (pkg == my && task.id > 0) {
                        am.moveTaskToFront(task.id, 0)
                        Log.i(TAG, "moved ami task ${task.id} to front")
                        return true
                    }
                }
                for (task in am.getRecentTasks(20, ActivityManager.RECENT_WITH_EXCLUDED)) {
                    val cn = task.topActivity ?: task.baseIntent?.component
                    if (cn?.packageName == my) {
                        val id = recentTaskId(task)
                        if (id > 0) {
                            am.moveTaskToFront(id, 0)
                            Log.i(TAG, "moved ami recent task $id to front")
                            return true
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "moveAmiTaskToFront: ${e.message}")
            }
            return false
        }

        fun dismissOverlay(context: Context) {
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_DISMISS_OVERLAY
            }
            context.startService(i)
        }

        fun acceptFromUi(context: Context, callerId: String, callerName: String) {
            if (wasIncomingCancelled(callerId)) {
                Log.i(TAG, "acceptFromUi ignored: cancelled $callerId")
                IncomingCallActivity.finishIfOpen()
                dismissOverlay(context)
                return
            }
            acceptIncoming(context, callerId, callerName)
        }

        fun rejectFromUi(context: Context, callerId: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_PENDING_ACTION, "reject")
                .putString(KEY_PENDING_CALLER_ID, callerId)
                .putString(KEY_PENDING_CALLER_NAME, "")
                .apply()
            dismissOverlay(context)
            MainActivity.dispatchIncomingAction("reject", callerId, "")
            if (wasScreenOffAtCall(context)) {
                lockScreenForStandby(context)
            } else {
                returnToPreviousFromService(context)
            }
        }

        fun finishIncomingUi() {
            IncomingCallActivity.finishIfOpen()
        }

        fun isScreenOn(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isInteractive
        }

        /** TCL スクリーンレス／Android 画面オフ。isInteractive だけでは足りない。 */
        fun isTvStandby(context: Context): Boolean {
            if (!isScreenOn(context)) return true
            val screen = sysProp("sys.tcl.screen").lowercase()
            if (screen == "off" || screen == "standby" || screen == "sleep") return true
            val status = sysProp("sys.tcl.powerstatus").lowercase()
            if (status == "suspend" || status == "standby" || status == "sleep") return true
            return isDisplayAsleep(context)
        }

        fun isDisplayAsleep(context: Context): Boolean {
            if (!isScreenOn(context)) return true
            return try {
                val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                val st = dm.getDisplay(Display.DEFAULT_DISPLAY)?.state ?: return false
                st != Display.STATE_ON && st != Display.STATE_UNKNOWN
            } catch (_: Exception) {
                false
            }
        }

        private fun sysProp(key: String): String {
            return try {
                val c = Class.forName("android.os.SystemProperties")
                val m = c.getMethod("get", String::class.java, String::class.java)
                (m.invoke(null, key, "") as? String) ?: ""
            } catch (_: Exception) {
                ""
            }
        }

        /** 点灯する前に、電源オフ発かどうかを覚える。先に起こすと判定が消える。 */
        fun rememberScreenOffAtIncoming(context: Context) {
            val app = context.applicationContext
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val standby = prefs.getBoolean(KEY_STANDBY, false)
            val asleep = isTvStandby(app)
            if (!asleep && !standby) return
            prefs.edit()
                .putBoolean(KEY_SCREEN_OFF_AT_INCOMING, true)
                .putBoolean(KEY_SCREEN_OFF_AT_CALL, true)
                .apply()
            Log.i(TAG, "marked screen off at incoming standby=$standby asleep=$asleep screen=${sysProp("sys.tcl.screen")} power=${sysProp("sys.tcl.powerstatus")}")
        }

        private fun consumeScreenOffIncoming(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val off = prefs.getBoolean(KEY_SCREEN_OFF_AT_INCOMING, false) ||
                prefs.getBoolean(KEY_SCREEN_OFF_AT_CALL, false)
            if (!off) return false
            prefs.edit()
                .putBoolean(KEY_SCREEN_OFF_AT_INCOMING, false)
                .putBoolean(KEY_SCREEN_OFF_AT_CALL, false)
                .putBoolean(KEY_STANDBY, false)
                .putBoolean(KEY_RESTORE_ON_SCREEN_ON, false)
                .putBoolean(KEY_AMI_WAS_TOP, false)
                .apply()
            return true
        }

        /**
         * 着信ごとに画面オフ状態を記録する（上書き）。
         * Socket 側は wake 前の値を渡す。FCM で既に起こした後でも、
         * ネイティブが付けた電源オフ印は消さない。
         */
        fun setScreenOffAtCall(context: Context, wasOff: Boolean) {
            val app = context.applicationContext
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val already = prefs.getBoolean(KEY_SCREEN_OFF_AT_CALL, false) ||
                prefs.getBoolean(KEY_SCREEN_OFF_AT_INCOMING, false)
            // 起こしたあとの isTvStandby / KEY_STANDBY は見ない。
            // 地デジ視聴中の着信を「電源オフ発」と誤ると、終了後に消灯してしまう。
            val marked = wasOff || already
            prefs.edit()
                .putBoolean(KEY_SCREEN_OFF_AT_CALL, marked)
                .putBoolean(KEY_SCREEN_OFF_AT_INCOMING, marked)
                .apply()
            Log.i(
                TAG,
                "setScreenOffAtCall wasOff=$wasOff marked=$marked already=$already " +
                    "standby=${prefs.getBoolean(KEY_STANDBY, false)} " +
                    "asleep=${isTvStandby(app)}"
            )
        }

        fun wasScreenOffAtCall(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_SCREEN_OFF_AT_CALL, false) ||
                prefs.getBoolean(KEY_SCREEN_OFF_AT_INCOMING, false)
        }

        fun isIrisChanghong(): Boolean {
            val man = Build.MANUFACTURER.lowercase()
            val brand = Build.BRAND.lowercase()
            return man.contains("changhong") ||
                brand.contains("iris") ||
                brand.contains("chiq")
        }

        fun requestDeviceAdminIfNeeded(activity: Activity) {
            try {
                val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val comp = ComponentName(activity, AmiDeviceAdminReceiver::class.java)
                if (dpm.isAdminActive(comp)) return
                val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                // 一度拒否すると lockNow が使えず、電源オフへ戻せない。
                // Iris は拒否後も聞き直す。他機種は従来どおり一度だけ。
                if (!isIrisChanghong() && prefs.getBoolean(KEY_ADMIN_PROMPTED, false)) return
                prefs.edit().putBoolean(KEY_ADMIN_PROMPTED, true).apply()
                val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                i.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, comp)
                i.putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "電源オフ中の着信で通話したあと、TVを電源オフに戻すために使います。"
                )
                activity.startActivity(i)
                Log.i(TAG, "requested device admin iris=${isIrisChanghong()}")
            } catch (e: Exception) {
                Log.w(TAG, "requestDeviceAdmin: ${e.message}")
            }
        }

        /**
         * 電源オフ発の着信なら、地デジを出さずに画面をオフへ戻す。
         *
         * Android 12 TCL では com.tcl.action.sleep は署名権限付きで届かず、
         * キー注入も拒否される。その状態で moveTaskToBack すると地デジが見える。
         * TV-TV(Android 11) と同じ lockNow / goToSleep で画面を落とす。
         */
        fun lockScreenForStandby(context: Context): Boolean {
            bringFrontUntil = 0L
            safetyActivityStarted = false
            pendingPowerWake = false
            powerKeySent = false
            if (!wasScreenOffAtCall(context)) return false
            IncomingCallActivity.finishIfOpen()
            releaseIncomingWakeLocks()
            try {
                val act = MainActivity.currentActivity()
                act?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    act?.setTurnScreenOn(false)
                    act?.setShowWhenLocked(false)
                }
            } catch (_: Exception) {
            }
            // 時計オーバーレイは残して ami-EX を隠す。KEEP_SCREEN_ON だけ外す。
            running?.releaseSafetyWatchKeepOn()
            // Iris はキー注入がグローバル電源に届かない。lockNow が本丸。
            val locked = tryLockNow(context)
            if (locked) {
                Log.i(TAG, "lockNow ok; skip power-key toggle")
            } else {
                tryGoToSleep(context)
                sleepDisplay(context)
            }
            consumeScreenOffIncoming(context)
            scheduleHideAfterSleep(context, lockOnly = locked)
            Log.i(
                TAG,
                "lockScreenForStandby requested locked=$locked " +
                    "interactive=${isScreenOn(context)} " +
                    "standby=${isTvStandby(context)} screen=${sysProp("sys.tcl.screen")}"
            )
            // 失敗しても地デジ／ホームへは戻さない（returnToPreviousApp を止める）。
            return true
        }

        private fun scheduleHideAfterSleep(context: Context, lockOnly: Boolean) {
            val app = context.applicationContext
            for (delay in longArrayOf(300, 800, 1600, 2800, 4000)) {
                wakeHandler.postDelayed({
                    if (!isTvStandby(app) && isScreenOn(app)) {
                        Log.i(TAG, "sleep retry delay=$delay lockOnly=$lockOnly")
                        val locked = tryLockNow(app)
                        if (!lockOnly && !locked) {
                            tryGoToSleep(app)
                            sleepDisplay(app)
                        }
                        return@postDelayed
                    }
                    // 消灯できたときだけ背面へ。点灯中の moveTaskToBack はホームが出る。
                    // オーバーレイは消灯後に外す。先に外すと ami-EX が一瞬見える。
                    running?.hideSafetyWatchInternal()
                    try {
                        MainActivity.currentActivity()?.moveTaskToBack(true)
                    } catch (_: Exception) {
                    }
                    Log.i(
                        TAG,
                        "sleep settled delay=$delay screen=${sysProp("sys.tcl.screen")} " +
                            "interactive=${isScreenOn(app)}"
                    )
                }, delay)
            }
        }

        private fun tryGoToSleep(context: Context) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                val methods = PowerManager::class.java.methods.filter { it.name == "goToSleep" }
                var invoked = false
                for (m in methods) {
                    try {
                        when (m.parameterTypes.size) {
                            1 -> {
                                m.invoke(pm, SystemClock.uptimeMillis())
                                invoked = true
                            }
                            3 -> {
                                m.invoke(pm, SystemClock.uptimeMillis(), 4, 0)
                                invoked = true
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "goToSleep ${m.parameterTypes.size}: ${e.cause?.message ?: e.message}")
                    }
                }
                Log.i(TAG, "goToSleep invoked=$invoked")
            } catch (e: Exception) {
                Log.w(TAG, "goToSleep: ${e.message}")
            }
        }

        private fun tryLockNow(context: Context): Boolean {
            return try {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val comp = ComponentName(context, AmiDeviceAdminReceiver::class.java)
                if (!dpm.isAdminActive(comp)) {
                    Log.w(TAG, "lockNow skip: device admin inactive")
                    return false
                }
                dpm.lockNow()
                Log.i(TAG, "lockNow()")
                true
            } catch (e: Exception) {
                Log.e(TAG, "lockNow failed", e)
                false
            }
        }

        /** 通話終了後。電源オフ発なら電源オフへ戻す。 */
        fun finishToTvPowerOff(context: Context): Boolean {
            return lockScreenForStandby(context)
        }

        @Volatile
        private var incomingWakeLock: PowerManager.WakeLock? = null

        fun releaseIncomingWakeLocks() {
            try {
                if (incomingWakeLock?.isHeld == true) incomingWakeLock?.release()
            } catch (_: Exception) {
            }
            incomingWakeLock = null
        }

        /**
         * 電源オフ発の着信後、パネルを消す。
         * KEYCODE_TV_POWER はトグルなので、まだ点灯しているときだけ最後に使う。
         */
        fun sleepDisplay(context: Context): Boolean {
            val app = context.applicationContext
            releaseIncomingWakeLocks()
            try {
                val act = MainActivity.currentActivity()
                act?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    act?.setTurnScreenOn(false)
                    act?.setShowWhenLocked(false)
                }
            } catch (_: Exception) {
            }
            sendTclSleepBroadcast(app)
            sendIrisSleepBroadcasts(app)
            sendSleepKey(app, KeyEvent.KEYCODE_SLEEP)
            // POWER / TV_POWER はトグル。SLEEP の直後に送ると点灯し直す。
            // lockNow が使えない機種だけ、まだ点灯しているとき遅れて1回送る。
            wakeHandler.postDelayed({
                if (isTvStandby(app) || !isScreenOn(app)) {
                    Log.i(TAG, "sleepDisplay already off")
                    return@postDelayed
                }
                Log.i(TAG, "sleepDisplay retry SLEEP")
                sendTclSleepBroadcast(app)
                sendIrisSleepBroadcasts(app)
                sendSleepKey(app, KeyEvent.KEYCODE_SLEEP)
            }, 400)
            wakeHandler.postDelayed({
                if (isTvStandby(app) || !isScreenOn(app)) return@postDelayed
                Log.i(TAG, "sleepDisplay retry POWER (still on)")
                sendSleepKey(app, KeyEvent.KEYCODE_POWER)
            }, 900)
            Log.i(TAG, "sleepDisplay requested")
            return true
        }

        /** Iris/Changhong: アプリからのキー注入はグローバル電源に届かない。メーカー側へ渡す。 */
        private fun sendIrisSleepBroadcasts(app: Context) {
            if (!isIrisChanghong()) return
            try {
                val now = SystemClock.uptimeMillis()
                val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_POWER, 0)
                val up = KeyEvent(now, now + 50, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_POWER, 0)
                for (ev in arrayOf(down, up)) {
                    val i = Intent("android.intent.action.GLOBAL_BUTTON").apply {
                        setClassName(
                            "com.mediatek.tv.service",
                            "com.mediatek.hotkey.dispatcher.GlobalKeyReceiver"
                        )
                        putExtra(Intent.EXTRA_KEY_EVENT, ev)
                        addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                    }
                    app.sendBroadcast(i)
                }
                Log.i(TAG, "sent GLOBAL_BUTTON POWER to MTK")
            } catch (e: Exception) {
                Log.w(TAG, "mtk global power: ${e.message}")
            }
            try {
                val i = Intent(
                    "com.google.android.apps.tv.launcherx.sleeptimer.schedule_device_sleep"
                ).apply {
                    setClassName(
                        "com.google.android.apps.tv.launcherx",
                        "com.google.android.apps.tv.launcherx.sleeptimer.SleepTimerBroadcastReceiver_Receiver"
                    )
                }
                app.sendBroadcast(i)
                Log.i(TAG, "sent launcherx schedule_device_sleep")
            } catch (e: Exception) {
                Log.w(TAG, "launcherx sleep: ${e.message}")
            }
        }

        private fun sendTclSleepBroadcast(app: Context) {
            try {
                val i = Intent("com.tcl.action.sleep").addCategory(Intent.CATEGORY_DEFAULT)
                app.sendBroadcast(Intent(i))
                i.setClassName(
                    "com.android.tv.settings",
                    "com.tcl.settings.receiver.ShortCutMenuReceiver"
                )
                app.sendBroadcast(i)
                Log.i(TAG, "sent com.tcl.action.sleep")
            } catch (e: Exception) {
                Log.w(TAG, "tcl.sleep: ${e.message}")
            }
        }

        private fun sendSleepKey(app: Context, code: Int) {
            try {
                val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
            } catch (e: Exception) {
                Log.w(TAG, "media key $code: ${e.message}")
            }
            try {
                val imc = Class.forName("android.hardware.input.InputManager")
                val im = imc.getMethod("getInstance").invoke(null)
                val inject = imc.methods.firstOrNull { it.name == "injectInputEvent" }
                if (inject != null) {
                    val now = SystemClock.uptimeMillis()
                    val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0)
                    val up = KeyEvent(now, now + 30, KeyEvent.ACTION_UP, code, 0)
                    if (inject.parameterTypes.size >= 2) {
                        inject.invoke(im, down, 0)
                        inject.invoke(im, up, 0)
                    } else {
                        inject.invoke(im, down)
                        inject.invoke(im, up)
                    }
                    Log.i(TAG, "injected key $code")
                }
            } catch (e: Exception) {
                Log.w(TAG, "inject $code: ${e.message}")
            }
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", code.toString()))
            } catch (_: Exception) {
            }
        }

        private val wakeHandler = Handler(Looper.getMainLooper())

        /** 画面オフ／待機からパネルを起こす。メーカー不問。点灯したら再試行しない（視聴中のTCL等を邪魔しない）。 */
        fun wakeDisplay(context: Context, forcePowerOn: Boolean = false) {
            // 先に起こすと判定が消える。TCL は isInteractive のままスクリーンレス。
            rememberScreenOffAtIncoming(context)
            val app = context.applicationContext
            if ((forcePowerOn || isTvStandby(app)) && !powerKeySent) {
                pendingPowerWake = true
            }
            tryWakeOnce(app)
            if (!isTvStandby(app) && !pendingPowerWake) return
            for (delay in longArrayOf(400, 1200)) {
                wakeHandler.postDelayed({
                    if (isTvStandby(app)) tryWakeOnce(app)
                }, delay)
            }
        }

        private fun needsPanelWake(context: Context): Boolean {
            if (isTvStandby(context)) return true
            if (pendingPowerWake) return true
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_STANDBY, false) && !isScreenOn(context)
        }

        private fun applyTurnScreenOn(act: Activity?) {
            if (act == null) return
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    act.setTurnScreenOn(true)
                    act.setShowWhenLocked(true)
                }
                act.window?.addFlags(
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            } catch (e: Exception) {
                Log.w(TAG, "applyTurnScreenOn: ${e.message}")
            }
        }

        private fun sendTclWakeBroadcast(app: Context) {
            for (action in arrayOf(
                "tcl.sys.intent.action.SCREEN_ON",
                "com.tcl.action.wakeup",
                "com.tcl.action.unsleep",
                "com.tcl.action.screenon",
            )) {
                try {
                    app.sendBroadcast(Intent(action).addCategory(Intent.CATEGORY_DEFAULT))
                } catch (e: Exception) {
                    Log.w(TAG, "tcl wake $action: ${e.message}")
                }
            }
        }

        private fun tryWakeOnce(context: Context) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            try {
                @Suppress("DEPRECATION")
                val wl = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "ami:incoming_wake"
                )
                wl.acquire(8_000)
                Log.i(TAG, "wakeDisplay lock interactive=${pm.isInteractive}")
            } catch (e: Exception) {
                Log.e(TAG, "wakeDisplay wakeLock failed", e)
            }
            try {
                val wakeUp = PowerManager::class.java.methods.firstOrNull {
                    it.name == "wakeUp" && it.parameterTypes.isNotEmpty() &&
                        it.parameterTypes[0] == Long::class.javaPrimitiveType
                }
                when (wakeUp?.parameterTypes?.size) {
                    1 -> wakeUp.invoke(pm, SystemClock.uptimeMillis())
                    3 -> wakeUp.invoke(pm, SystemClock.uptimeMillis(), 0, "ami:incoming")
                    else -> { }
                }
            } catch (e: Exception) {
                Log.w(TAG, "wakeUp: ${e.message}")
            }
            applyTurnScreenOn(MainActivity.currentActivity())
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", "224"))
            } catch (_: Exception) {
            }
            if (!needsPanelWake(context)) return
            sendTclWakeBroadcast(context)
            sendOneKey(context, KeyEvent.KEYCODE_WAKEUP)
            // POWER はトグル。1回だけ。連打すると消灯やフリーズになる。
            if (pendingPowerWake && !powerKeySent) {
                pendingPowerWake = false
                powerKeySent = true
                sendOneKey(context, KeyEvent.KEYCODE_POWER)
                Log.i(TAG, "wakeDisplay POWER once")
            }
        }

        private fun sendOneKey(app: Context, code: Int) {
            try {
                val imc = Class.forName("android.hardware.input.InputManager")
                val im = imc.getMethod("getInstance").invoke(null)
                val inject = imc.methods.firstOrNull { it.name == "injectInputEvent" } ?: return
                val now = SystemClock.uptimeMillis()
                val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0)
                val up = KeyEvent(now, now + 30, KeyEvent.ACTION_UP, code, 0)
                if (inject.parameterTypes.size >= 2) {
                    inject.invoke(im, down, 0)
                    inject.invoke(im, up, 0)
                } else {
                    inject.invoke(im, down)
                    inject.invoke(im, up)
                }
            } catch (e: Exception) {
                Log.w(TAG, "sendOneKey $code: ${e.message}")
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var safetyWatchView: View? = null
    private var keepAliveView: View? = null
    private var ringtone: Ringtone? = null
    private var waiting = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private var screenReceiverRegistered = false
    private var playbackCallback: AudioManager.AudioPlaybackCallback? = null
    private val kioskHandler = Handler(Looper.getMainLooper())
    private var kioskWatchPosted = false
    private var foregroundStarted = false
    private val kioskWatch = object : Runnable {
        override fun run() {
            kioskWatchPosted = false
            if (!waiting) return
            // TCL は startForeground を default_borbid で恒久拒否するため
            // FGS では優先度を上げられない。不可視オーバーレイで
            // perceptible(adj200) を保ち、CPUロックも維持する。
            acquireCpuLock()
            ensureKeepAliveOverlay()
            scheduleKioskWatch()
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF,
                Intent.ACTION_DREAMING_STARTED,
                "com.tcl.action.sleep",
                "tcl.sys.intent.action.SCREEN_OFF" -> {
                    val ours = MainActivity.isInForeground() || isOurTaskOnTop()
                    // Android 12 の TCL は電源オフでも isInteractive=true のままなので、
                    // 「消灯したという事実」をここで残しておかないと後から判定できない。
                    prefs().edit()
                        .putBoolean(KEY_STANDBY, true)
                        .putBoolean(KEY_AMI_WAS_TOP, ours)
                        .putBoolean(KEY_RESTORE_ON_SCREEN_ON, ours)
                        .apply()
                    // 消灯したら POWER 1回制限をリセット。
                    // 残したままだと次の電源オフ発見守りで電源が入らない。
                    pendingPowerWake = false
                    powerKeySent = false
                    keepProcessAlive("standby ${intent?.action}")
                    Log.i(TAG, "${intent?.action} ours=$ours waiting=$waiting standby=true")
                }
                Intent.ACTION_DREAMING_STOPPED -> {
                    keepProcessAlive("dream stopped")
                }
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT,
                "tcl.sys.intent.action.SCREEN_ON" -> {
                    if (!waiting) return
                    if (incomingUiActive || overlayView != null || IncomingCallActivity.isOpen()) {
                        Log.i(TAG, "SCREEN_ON skip restore: incoming UI")
                        return
                    }
                    // 電源オフ着信の最中は待機フラグを消さない（通話終了後に電源オフへ戻すため）。
                    if (prefs().getBoolean(KEY_SCREEN_OFF_AT_INCOMING, false) ||
                        prefs().getBoolean(KEY_SCREEN_OFF_AT_CALL, false)) {
                        prefs().edit().putBoolean(KEY_RESTORE_ON_SCREEN_ON, false).apply()
                        Log.i(TAG, "SCREEN_ON keep standby mark: power-off incoming")
                        return
                    }
                    prefs().edit().putBoolean(KEY_STANDBY, false).apply()
                    // 電源オン時はアミへ強制復帰しない。電源オフ直前の状態(地デジ/Netflix/
                    // アミ等、その時点で表示していたもの)をOSの自然復元に任せる。
                    // フラグはクリアだけしておく。
                    prefs().edit().putBoolean(KEY_RESTORE_ON_SCREEN_ON, false).apply()
                    Log.i(TAG, "SCREEN_ON: keep pre-off state (no forced ami restore)")
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        serviceAlive = true
        running = this
        ensureChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        ensurePlaybackMonitor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        serviceAlive = true
        // startForegroundService から来た場合、ここで必ず startForeground する。
        if (intent?.action != ACTION_STOP_WAITING) {
            waiting = true
            prefs().edit().putBoolean(KEY_WAITING, true).apply()
            ensureForeground("onStart ${intent?.action ?: "restart"}")
        }
        when (intent?.action) {
            ACTION_START_WAITING -> {
                waiting = true
                prefs().edit().putBoolean(KEY_WAITING, true).apply()
                ensureForeground("start waiting")
                ensureStandbyGuard()
                Log.i(TAG, "call waiting started fg=$foregroundStarted")
            }
            ACTION_STOP_WAITING -> {
                waiting = false
                foregroundStarted = false
                prefs().edit().putBoolean(KEY_WAITING, false).apply()
                stopKioskWatch()
                dismissOverlayInternal()
                removeKeepAliveOverlay()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.i(TAG, "call waiting stopped")
            }
            ACTION_SHOW_OVERLAY -> {
                if (shouldSkipIncomingUi() || overlayView != null) {
                    Log.i(TAG, "ACTION_SHOW_OVERLAY skip: incoming already shown")
                    return START_STICKY
                }
                if (!waiting) {
                    waiting = true
                    prefs().edit().putBoolean(KEY_WAITING, true).apply()
                }
                ensureForeground("show overlay")
                ensureStandbyGuard()
                val id = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
                showOverlayInternal(id, DISPLAY_NAME)
            }
            ACTION_ACCEPT_INCOMING -> {
                val id = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
                if (wasIncomingCancelled(id)) {
                    Log.i(TAG, "ACTION_ACCEPT_INCOMING ignored: cancelled $id")
                    dismissOverlayInternal()
                    return START_STICKY
                }
                markAcceptGuard()
                if (!waiting) {
                    waiting = true
                    prefs().edit().putBoolean(KEY_WAITING, true).apply()
                }
                ensureForeground("accept incoming")
                captureForegroundApp(this)
                val name = DISPLAY_NAME
                dismissOverlayInternal()
                wakeDisplayInternal()
                prefs().edit()
                    .putString(KEY_PENDING_ACTION, "accept")
                    .putString(KEY_PENDING_CALLER_ID, id)
                    .putString(KEY_PENDING_CALLER_NAME, name)
                    .apply()
                Log.i(TAG, "auto-accept incoming $id")
                launchAppAccept(id, name)
            }
            ACTION_DISMISS_OVERLAY -> dismissOverlayInternal()
            ACTION_SHOW_SAFETY_UI -> {
                safetyClockColor = intent.getIntExtra(EXTRA_SAFETY_COLOR, safetyClockColor)
                ensureForeground("safety ui")
                showSafetyWatchInternal()
            }
            ACTION_HIDE_SAFETY_UI -> hideSafetyWatchInternal()
            ACTION_BRING_TO_FRONT -> {
                if (!waiting) {
                    waiting = true
                    prefs().edit().putBoolean(KEY_WAITING, true).apply()
                }
                ensureForeground("bring to front")
                ensureStandbyGuard()
                wakeDisplayInternal()
                restoreMainActivity(this)
                val h = Handler(Looper.getMainLooper())
                for (delay in longArrayOf(300, 800, 1600, 2800)) {
                    h.postDelayed({
                        if (System.currentTimeMillis() <= bringFrontUntil) {
                            restoreMainActivity(this)
                        }
                    }, delay)
                }
            }
            else -> {
                // サービス再起動時
                if (prefs().getBoolean(KEY_WAITING, false)) {
                    waiting = true
                    ensureForeground("restart")
                    ensureStandbyGuard()
                }
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        keepProcessAlive("onTaskRemoved")
        try {
            startWaiting(this)
        } catch (e: Exception) {
            Log.w(TAG, "onTaskRemoved restart: ${e.message}")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val keep = waiting || prefs().getBoolean(KEY_WAITING, false)
        stopKioskWatch()
        dismissOverlayInternal()
        hideSafetyWatchInternal()
        removeKeepAliveOverlay()
        releaseCpuLock()
        unregisterScreenReceiver()
        unregisterPlaybackMonitor()
        foregroundStarted = false
        serviceAlive = false
        running = null
        super.onDestroy()
        if (keep) {
            Log.i(TAG, "onDestroy: restart waiting")
            try {
                startWaiting(this)
            } catch (e: Exception) {
                Log.w(TAG, "onDestroy restart: ${e.message}")
            }
        }
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun isOurTaskOnTop(): Boolean {
        return try {
            @Suppress("DEPRECATION")
            val task = (getSystemService(ACTIVITY_SERVICE) as ActivityManager)
                .getRunningTasks(1)
                .firstOrNull()
            val pkg = task?.topActivity?.packageName ?: task?.baseActivity?.packageName
            pkg == packageName
        } catch (_: Exception) {
            false
        }
    }

    /** ホーム／Netflix／スクリーンセーバー中もプロセスだけ残す。前面には出さない。 */
    private fun keepProcessAlive(reason: String) {
        waiting = true
        prefs().edit().putBoolean(KEY_WAITING, true).apply()
        try {
            ensureForeground("keep $reason")
            ensureStandbyGuard()
            Log.i(TAG, "keep process: $reason fg=$foregroundStarted")
        } catch (e: Exception) {
            Log.w(TAG, "keep process failed ($reason): ${e.message}")
        }
    }

    /** startForegroundService のあとは必ず startForeground する。省略すると即落ちる。 */
    private fun ensureForeground(reason: String) {
        try {
            startForeground(NOTIF_ID, buildWaitingNotification())
            foregroundStarted = true
            Log.i(TAG, "startForeground ok ($reason)")
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed ($reason): ${e.message}")
        }
        acquireCpuLock()
    }

    /**
     * TCL(TclAppBoot) は startForeground を恒久拒否するため、FGS では
     * バックグラウンド優先度を上げられない。代わりに不可視 1px の
     * オーバーレイを保持すると hasOverlayUi で perceptible(adj 200) に
     * 固定され、Netflix→YouTube のメモリ圧でも LMK の犠牲順が後になる。
     */
    private fun ensureKeepAliveOverlay() {
        if (keepAliveView != null) return
        if (!canDrawOverlays(this)) return
        try {
            val v = View(this).apply {
                // 完全透明だと非表示扱いになる恐れがあるため、ほぼ透明の1pxにする。
                setBackgroundColor(Color.argb(1, 0, 0, 0))
            }
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val lp = WindowManager.LayoutParams(
                1,
                1,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 0
                y = 0
            }
            windowManager?.addView(v, lp)
            keepAliveView = v
            Log.i(TAG, "keep-alive overlay added")
        } catch (e: Exception) {
            Log.w(TAG, "keep-alive overlay: ${e.message}")
        }
    }

    private fun removeKeepAliveOverlay() {
        val v = keepAliveView ?: return
        keepAliveView = null
        try {
            windowManager?.removeView(v)
            Log.i(TAG, "keep-alive overlay removed")
        } catch (_: Exception) {
        }
    }

    private fun showSafetyWatchInternal() {
        val clockColor = safetyClockColor
        val existing = safetyWatchView
        if (existing != null) {
            applySafetyWatchColor(existing, clockColor)
            Log.i(TAG, "safety watch ui color updated")
            return
        }
        if (!canDrawOverlays(this)) {
            Log.w(TAG, "safety watch ui: no overlay permission")
            return
        }
        try {
            val date = TextClock(this).apply {
                format12Hour = null
                format24Hour = "yyyy年M月d日（E）"
                setTextColor(clockColor)
                setTextSize(TypedValue.COMPLEX_UNIT_PX, 96f)
                gravity = Gravity.CENTER
            }
            val clock = TextClock(this).apply {
                format12Hour = null
                format24Hour = "HH:mm"
                setTextColor(clockColor)
                setTextSize(TypedValue.COMPLEX_UNIT_PX, 240f)
                gravity = Gravity.CENTER
            }
            val label = TextView(this).apply {
                text = "見守り中"
                setTextColor(clockColor)
                setTextSize(TypedValue.COMPLEX_UNIT_PX, 30f)
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 0)
            }
            val col = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                addView(date)
                addView(clock)
                addView(label)
            }
            val root = FrameLayout(this).apply {
                setBackgroundColor(Color.BLACK)
                addView(
                    col,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        Gravity.CENTER
                    )
                )
            }
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
                PixelFormat.OPAQUE
            )
            windowManager?.addView(root, lp)
            safetyWatchView = root
            Log.i(TAG, "safety watch ui added")
        } catch (e: Exception) {
            Log.w(TAG, "safety watch ui: ${e.message}")
        }
    }

    private fun applySafetyWatchColor(root: View, color: Int) {
        val col = (root as? FrameLayout)?.getChildAt(0) as? LinearLayout ?: return
        for (i in 0 until col.childCount) {
            (col.getChildAt(i) as? TextView)?.setTextColor(color)
        }
    }

    private fun hideSafetyWatchInternal() {
        val v = safetyWatchView ?: return
        safetyWatchView = null
        try {
            windowManager?.removeView(v)
            Log.i(TAG, "safety watch ui removed")
        } catch (_: Exception) {
        }
    }

    /** 消灯できるように KEEP_SCREEN_ON だけ外し、黒画面は残して ami-EX を隠す。 */
    private fun releaseSafetyWatchKeepOn() {
        val v = safetyWatchView ?: return
        try {
            val wm = windowManager ?: return
            val lp = v.layoutParams as? WindowManager.LayoutParams ?: return
            lp.flags = (lp.flags and
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv() and
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON.inv())
            wm.updateViewLayout(v, lp)
            Log.i(TAG, "safety watch keep-on released")
        } catch (e: Exception) {
            Log.w(TAG, "releaseSafetyWatchKeepOn: ${e.message}")
        }
    }

    private fun ensureStandbyGuard() {
        acquireCpuLock()
        ensureKeepAliveOverlay()
        ensurePlaybackMonitor()
        scheduleKioskWatch()
        if (screenReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            // TCL(Android12)は独自アクションで消灯を通知してくる。
            addAction(Intent.ACTION_DREAMING_STARTED)
            addAction(Intent.ACTION_DREAMING_STOPPED)
            addAction("com.tcl.action.sleep")
            addAction("tcl.sys.intent.action.SCREEN_OFF")
            addAction("tcl.sys.intent.action.SCREEN_ON")
            addAction(Intent.ACTION_USER_PRESENT)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenReceiver, filter, RECEIVER_EXPORTED)
            } else {
                registerReceiver(screenReceiver, filter)
            }
            screenReceiverRegistered = true
        } catch (e: Exception) {
            Log.w(TAG, "register screen receiver: ${e.message}")
        }
    }

    private fun scheduleKioskWatch() {
        if (!waiting || kioskWatchPosted) return
        kioskWatchPosted = true
        kioskHandler.postDelayed(kioskWatch, KIOSK_INTERVAL_MS)
    }

    private fun stopKioskWatch() {
        kioskWatchPosted = false
        kioskHandler.removeCallbacks(kioskWatch)
    }

    /**
     * ami-EX 待ち受け中、ランチャーやスクリーンセーバーに奪われたらホームへ戻す。
     * 地デジ／Netflix／YouTube／設定は奪わない。
     */

    private fun unregisterScreenReceiver() {
        if (!screenReceiverRegistered) return
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        screenReceiverRegistered = false
    }

    private fun ensurePlaybackMonitor() {
        if (Build.VERSION.SDK_INT < 24) return
        if (playbackCallback != null) return
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val cb = object : AudioManager.AudioPlaybackCallback() {
            override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>) {
                val playing = pickStartedMedia(this@IncomingCallOverlayService, configs)
                if (playing != null) {
                    rememberPlayingMedia(
                        this@IncomingCallOverlayService,
                        playing.pkg,
                        playing.className
                    )
                }
            }
        }
        try {
            am.registerAudioPlaybackCallback(cb, Handler(Looper.getMainLooper()))
            playbackCallback = cb
            currentStartedMedia(this)?.let {
                rememberPlayingMedia(this, it.pkg, it.className)
            }
            Log.i(TAG, "playback monitor registered")
        } catch (e: Exception) {
            Log.w(TAG, "playback monitor: ${e.message}")
        }
    }

    private fun unregisterPlaybackMonitor() {
        val cb = playbackCallback ?: return
        playbackCallback = null
        if (Build.VERSION.SDK_INT < 24) return
        try {
            (getSystemService(AUDIO_SERVICE) as AudioManager)
                .unregisterAudioPlaybackCallback(cb)
        } catch (_: Exception) {
        }
    }

    private fun acquireCpuLock() {
        if (cpuWakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            cpuWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ami:tv_standby")
            cpuWakeLock?.setReferenceCounted(false)
            cpuWakeLock?.acquire()
            Log.i(TAG, "cpu wake lock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "cpu wake lock failed: ${e.message}")
        }
    }

    private fun releaseCpuLock() {
        try {
            if (cpuWakeLock?.isHeld == true) cpuWakeLock?.release()
        } catch (_: Exception) {
        }
        cpuWakeLock = null
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val waiting = NotificationChannel(
            CHANNEL_ID,
            "着信待機",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "テレビ電話の着信待機中"
            setShowBadge(false)
        }
        val incoming = NotificationChannel(
            INCOMING_CHANNEL_ID,
            "着信",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "テレビ電話の着信"
            setShowBadge(false)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(waiting)
        nm.createNotificationChannel(incoming)
    }

    private fun incomingActivityIntent(callerId: String, callerName: String): Intent {
        return Intent(this, IncomingCallActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            )
            putExtra(EXTRA_CALLER_ID, callerId)
            putExtra(EXTRA_CALLER_NAME, callerName)
        }
    }

    private fun buildIncomingNotification(
        callerId: String,
        callerName: String,
        useFullScreen: Boolean
    ): Notification {
        val fullScreen = PendingIntent.getActivity(
            this,
            21,
            incomingActivityIntent(callerId, callerName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, INCOMING_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle("着信あり")
            .setContentText(if (callerName.isNotBlank()) callerName else "電話がかかってきました")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(fullScreen)
        if (useFullScreen) {
            builder.setFullScreenIntent(fullScreen, true)
        }
        return builder.build()
    }

    private fun launchIncomingActivity(callerId: String, callerName: String) {
        if (IncomingCallActivity.isOpen() || overlayView != null) {
            Log.i(TAG, "IncomingCallActivity skip: already showing")
            return
        }
        try {
            startActivity(incomingActivityIntent(callerId, DISPLAY_NAME))
            Log.i(TAG, "IncomingCallActivity started")
        } catch (e: Exception) {
            Log.e(TAG, "IncomingCallActivity start failed", e)
        }
    }

    private fun buildWaitingNotification(): Notification {
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("テレビ電話アミ")
            .setContentText("着信待機中")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            resources.displayMetrics
        ).toInt()

    private fun showOverlayInternal(callerId: String, callerName: String) {
        if (shouldSkipIncomingUi() || overlayView != null) {
            Log.i(TAG, "showOverlayInternal skip: incoming already shown")
            return
        }
        incomingUiActive = true
        ringingCallerId = callerId
        timeoutContext = applicationContext
        wakeHandler.removeCallbacks(overlayTimeout)
        wakeHandler.postDelayed(overlayTimeout, OVERLAY_TIMEOUT_MS)
        val label = DISPLAY_NAME
        // 先に起こすと判定が消えるため、点灯前に電源オフ発かどうかを残す。
        rememberScreenOffAtIncoming(this)
        // 点灯時のホーム復帰が着信UIを消さないようにする。
        prefs().edit().putBoolean(KEY_RESTORE_ON_SCREEN_ON, false).apply()
        captureForegroundApp(this)
        wakeDisplay(this)
        startRingtone()
        val overlayOk = canDrawOverlays(this)
        val screenOn = isScreenOn(this)
        val fromPowerOff = wasScreenOffAtCall(this)
        // 電源オフ発／画面オフ／オーバーレイ不可は着信用 Activity（はい／いいえ）。
        val needActivity = fromPowerOff || !screenOn || !overlayOk
        startForeground(
            INCOMING_NOTIF_ID,
            buildIncomingNotification(callerId, label, useFullScreen = needActivity)
        )
        if (needActivity) {
            launchIncomingActivity(callerId, label)
        }
        if (overlayOk && screenOn) {
            addOverlayPanel(callerId, label)
        }
        Log.i(
            TAG,
            "incoming UI shown callerId=$callerId overlay=$overlayOk screenOn=$screenOn activity=$needActivity"
        )
    }

    private fun addOverlayPanel(callerId: String, callerName: String) {
        val density = resources.displayMetrics
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(28), dp(24), dp(28), dp(24))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E6121A2A"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(2), Color.parseColor("#4FC3F7"))
            }
            isFocusable = true
            isFocusableInTouchMode = true
        }

        val title = TextView(this).apply {
            text = "着信あり"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = DISPLAY_NAME
            setTextColor(Color.parseColor("#DDEEFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(20))
        }

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        fun styleButton(b: Button, bg: Int, focusedBg: Int) {
            b.setTextColor(Color.WHITE)
            b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            b.background = GradientDrawable().apply {
                setColor(bg)
                cornerRadius = dp(10).toFloat()
            }
            b.setPadding(dp(28), dp(14), dp(28), dp(14))
            b.isFocusable = true
            b.isFocusableInTouchMode = true
            b.setOnFocusChangeListener { v, hasFocus ->
                val d = GradientDrawable().apply {
                    setColor(if (hasFocus) focusedBg else bg)
                    cornerRadius = dp(10).toFloat()
                    if (hasFocus) setStroke(dp(3), Color.WHITE)
                }
                v.background = d
            }
        }

        val yes = Button(this).apply {
            text = "はい"
            styleButton(this, Color.parseColor("#0A7A3E"), Color.parseColor("#12A855"))
            setOnClickListener { onAccept(callerId, callerName) }
            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
                        keyCode == KeyEvent.KEYCODE_ENTER ||
                        keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER)
                ) {
                    onAccept(callerId, callerName)
                    true
                } else false
            }
        }
        val no = Button(this).apply {
            text = "いいえ"
            styleButton(this, Color.parseColor("#8A1F2B"), Color.parseColor("#C62828"))
            setOnClickListener { onReject(callerId, callerName) }
            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
                        keyCode == KeyEvent.KEYCODE_ENTER ||
                        keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER)
                ) {
                    onReject(callerId, callerName)
                    true
                } else false
            }
        }

        val gap = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(24), 1)
        }
        buttons.addView(yes)
        buttons.addView(gap)
        buttons.addView(no)
        panel.addView(title)
        panel.addView(subtitle)
        panel.addView(buttons)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            (density.widthPixels * 0.55f).toInt().coerceAtMost(dp(640)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(48)
        }

        try {
            overlayView?.let { old ->
                try {
                    windowManager?.removeView(old)
                } catch (_: Exception) {
                }
            }
            windowManager?.addView(panel, params)
            overlayView = panel
            yes.requestFocus()
            Log.i(TAG, "overlay shown callerId=$callerId name=$callerName")
        } catch (e: Exception) {
            Log.e(TAG, "failed to add overlay; IncomingCallActivity", e)
            startForeground(
                INCOMING_NOTIF_ID,
                buildIncomingNotification(callerId, callerName, useFullScreen = true)
            )
            launchIncomingActivity(callerId, callerName)
        }
    }

    private fun wakeDisplayInternal() {
        wakeDisplay(this)
    }

    private fun dismissOverlayInternal() {
        incomingUiActive = false
        if (ringingCallerId.isNotEmpty()) ringingCallerId = ""
        wakeHandler.removeCallbacks(overlayTimeout)
        IncomingCallActivity.finishIfOpen()
        stopRingtone()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        val v = overlayView
        overlayView = null
        if (v != null) {
            try {
                windowManager?.removeView(v)
            } catch (_: Exception) {
            }
        }
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(INCOMING_NOTIF_ID)
        } catch (_: Exception) {
        }
        if (waiting) {
            foregroundStarted = false
            ensureForeground("after overlay")
        }
    }

    private fun startRingtone() {
        try {
            stopRingtone()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(this, uri)?.also {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    it.isLooping = true
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    it.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
                it.play()
            }
        } catch (e: Exception) {
            Log.e(TAG, "ringtone failed", e)
        }
    }

    private fun stopRingtone() {
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
    }

    private fun onAccept(callerId: String, callerName: String) {
        if (wasIncomingCancelled(callerId)) {
            Log.i(TAG, "accept ignored: cancelled $callerId")
            dismissOverlayInternal()
            return
        }
        Log.i(TAG, "accept $callerId")
        markAcceptGuard()
        dismissOverlayInternal()
        prefs().edit()
            .putString(KEY_PENDING_ACTION, "accept")
            .putString(KEY_PENDING_CALLER_ID, callerId)
            .putString(KEY_PENDING_CALLER_NAME, callerName)
            .apply()
        launchAppAccept(callerId, callerName)
        MainActivity.dispatchIncomingAction("accept", callerId, callerName)
    }

    private fun onReject(callerId: String, callerName: String) {
        Log.i(TAG, "reject $callerId")
        dismissOverlayInternal()
        prefs().edit()
            .putString(KEY_PENDING_ACTION, "reject")
            .putString(KEY_PENDING_CALLER_ID, callerId)
            .putString(KEY_PENDING_CALLER_NAME, callerName)
            .apply()
        // アプリを全面化せず、着信拒否だけ Flutter に渡す
        MainActivity.dispatchIncomingAction("reject", callerId, callerName)
        returnToPreviousFromService(this)
    }

    private fun launchAppAccept(callerId: String, callerName: String) {
        stopRingtone()
        wakeDisplay(this)
        val i = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
            putExtra("incoming_action", "accept")
            putExtra(EXTRA_CALLER_ID, callerId)
            putExtra(EXTRA_CALLER_NAME, callerName)
        }
        startActivity(i)
    }
}
