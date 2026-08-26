package jp.amiplus.mulch

import android.app.Activity
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
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
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
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

        const val ACTION_START_WAITING = "jp.amiplus.mulch.action.START_WAITING"
        const val ACTION_STOP_WAITING = "jp.amiplus.mulch.action.STOP_WAITING"
        const val ACTION_SHOW_OVERLAY = "jp.amiplus.mulch.action.SHOW_OVERLAY"
        const val ACTION_ACCEPT_INCOMING = "jp.amiplus.mulch.action.ACCEPT_INCOMING"
        const val ACTION_DISMISS_OVERLAY = "jp.amiplus.mulch.action.DISMISS_OVERLAY"

        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"

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
        const val KEY_AMI_WAS_TOP = "ami_was_top_at_screen_off"
        const val KEY_LAST_MEDIA_PKG = "last_media_pkg"
        const val KEY_LAST_MEDIA_CLASS = "last_media_class"
        const val KEY_PI_LAYOUT = "pi_tv_layout"
        private const val PLAYER_STATE_STARTED = 2
        private const val KIOSK_INTERVAL_MS = 25_000L

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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
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

        fun showOverlay(context: Context, callerId: String, callerName: String) {
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

        /** 確認なしでアプリを前面へ（通話開始は Flutter 側） */
        fun bringToFront(context: Context) {
            wakeDisplay(context)
            restoreMainActivity(context)
        }

        fun restoreMainActivity(context: Context) {
            val i = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                )
            }
            context.startActivity(i)
        }

        fun dismissOverlay(context: Context) {
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_DISMISS_OVERLAY
            }
            context.startService(i)
        }

        fun acceptFromUi(context: Context, callerId: String, callerName: String) {
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
            if (context is Activity) {
                returnToPreviousApp(context)
            } else {
                clearWatchRestore(context)
            }
        }

        fun finishIncomingUi() {
            IncomingCallActivity.finishIfOpen()
        }

        fun isScreenOn(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isInteractive
        }

        private val wakeHandler = Handler(Looper.getMainLooper())

        /** 画面オフ／待機からパネルを起こす。メーカー不問。点灯したら再試行しない（視聴中のTCL等を邪魔しない）。 */
        fun wakeDisplay(context: Context) {
            val app = context.applicationContext
            tryWakeOnce(app)
            if (isScreenOn(app)) return
            for (delay in longArrayOf(250, 700, 1400, 2500)) {
                wakeHandler.postDelayed({
                    if (!isScreenOn(app)) tryWakeOnce(app)
                }, delay)
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
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", "224"))
            } catch (_: Exception) {
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var ringtone: Ringtone? = null
    private var waiting = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private var screenReceiverRegistered = false
    private var playbackCallback: AudioManager.AudioPlaybackCallback? = null
    private val kioskHandler = Handler(Looper.getMainLooper())
    private var kioskWatchPosted = false
    private val kioskWatch = object : Runnable {
        override fun run() {
            kioskWatchPosted = false
            if (!waiting) return
            try {
                startForeground(NOTIF_ID, buildWaitingNotification())
            } catch (e: Exception) {
                Log.w(TAG, "kiosk heartbeat: ${e.message}")
            }
            try {
                maybeRestoreKiosk()
            } catch (e: Exception) {
                Log.w(TAG, "kiosk: ${e.message}")
            }
            scheduleKioskWatch()
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    val ours = MainActivity.isInForeground() || isOurTaskOnTop()
                    prefs().edit()
                        .putBoolean(KEY_AMI_WAS_TOP, ours)
                        .putBoolean(KEY_RESTORE_ON_SCREEN_ON, ours)
                        .apply()
                    Log.i(TAG, "SCREEN_OFF ours=$ours waiting=$waiting")
                }
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    if (!waiting) return
                    if (!prefs().getBoolean(KEY_RESTORE_ON_SCREEN_ON, false)) return
                    prefs().edit().putBoolean(KEY_RESTORE_ON_SCREEN_ON, false).apply()
                    Log.i(TAG, "SCREEN_ON restore MainActivity")
                    restoreMainActivity(this@IncomingCallOverlayService)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        ensurePlaybackMonitor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_WAITING -> {
                waiting = true
                prefs().edit().putBoolean(KEY_WAITING, true).apply()
                startForeground(NOTIF_ID, buildWaitingNotification())
                ensureStandbyGuard()
                Log.i(TAG, "call waiting started")
            }
            ACTION_STOP_WAITING -> {
                waiting = false
                prefs().edit().putBoolean(KEY_WAITING, false).apply()
                stopKioskWatch()
                dismissOverlayInternal()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.i(TAG, "call waiting stopped")
            }
            ACTION_SHOW_OVERLAY -> {
                if (!waiting) {
                    waiting = true
                    prefs().edit().putBoolean(KEY_WAITING, true).apply()
                }
                startForeground(NOTIF_ID, buildWaitingNotification())
                ensureStandbyGuard()
                val id = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
                val name = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "着信"
                showOverlayInternal(id, name)
            }
            ACTION_ACCEPT_INCOMING -> {
                if (!waiting) {
                    waiting = true
                    prefs().edit().putBoolean(KEY_WAITING, true).apply()
                }
                startForeground(NOTIF_ID, buildWaitingNotification())
                captureForegroundApp(this)
                val id = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
                val name = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "着信"
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
            else -> {
                // サービス再起動時
                if (prefs().getBoolean(KEY_WAITING, false)) {
                    waiting = true
                    startForeground(NOTIF_ID, buildWaitingNotification())
                    ensureStandbyGuard()
                }
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (waiting || prefs().getBoolean(KEY_WAITING, false)) {
            waiting = true
            try {
                startForeground(NOTIF_ID, buildWaitingNotification())
                ensureStandbyGuard()
                Log.i(TAG, "onTaskRemoved: keep waiting")
            } catch (e: Exception) {
                Log.w(TAG, "onTaskRemoved: ${e.message}")
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val keep = waiting || prefs().getBoolean(KEY_WAITING, false)
        stopKioskWatch()
        dismissOverlayInternal()
        releaseCpuLock()
        unregisterScreenReceiver()
        unregisterPlaybackMonitor()
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

    private fun ensureStandbyGuard() {
        acquireCpuLock()
        ensurePlaybackMonitor()
        scheduleKioskWatch()
        if (screenReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
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
    private fun maybeRestoreKiosk() {
        if (!waiting) return
        if (!isPiTvLayout(this)) return
        if (!isScreenOn(this)) return
        if (overlayView != null) return
        if (MainActivity.isInForeground() || isOurTaskOnTop()) return
        val playing = currentStartedMedia(this)
        if (playing != null && playing.pkg != packageName && !isIgnoredPackage(playing.pkg)) {
            Log.i(TAG, "kiosk skip playing ${playing.pkg}")
            return
        }
        val top = rawTopApp(this)
        val pkg = top?.pkg ?: ""
        val cls = top?.className ?: ""
        if (pkg == packageName) return
        if (isKioskProtected(pkg, cls)) {
            Log.i(TAG, "kiosk skip protected $pkg")
            return
        }
        Log.i(TAG, "kiosk restore from $pkg $cls")
        restoreMainActivity(this)
    }

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
        try {
            startActivity(incomingActivityIntent(callerId, callerName))
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
        captureForegroundApp(this)
        wakeDisplay(this)
        startRingtone()
        val overlayOk = canDrawOverlays(this)
        val screenOn = isScreenOn(this)
        // 画面オフ、またはオーバーレイ不可の機種は着信用 Activity で点灯する（メーカー不問）。
        val needActivity = !screenOn || !overlayOk
        startForeground(
            INCOMING_NOTIF_ID,
            buildIncomingNotification(callerId, callerName, useFullScreen = needActivity)
        )
        if (needActivity) {
            launchIncomingActivity(callerId, callerName)
        }
        if (overlayOk && screenOn) {
            addOverlayPanel(callerId, callerName)
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
            text = if (callerName.isNotBlank()) callerName else "電話がかかってきました"
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
            startForeground(NOTIF_ID, buildWaitingNotification())
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
        Log.i(TAG, "accept $callerId")
        dismissOverlayInternal()
        prefs().edit()
            .putString(KEY_PENDING_ACTION, "accept")
            .putString(KEY_PENDING_CALLER_ID, callerId)
            .putString(KEY_PENDING_CALLER_NAME, callerName)
            .apply()
        launchAppAccept(callerId, callerName)
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
        clearWatchRestore(this)
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
