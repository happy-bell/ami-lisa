package jp.amiplus.mulch

import android.app.Activity
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
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
        const val NOTIF_ID = 7101

        const val ACTION_START_WAITING = "jp.amiplus.mulch.action.START_WAITING"
        const val ACTION_STOP_WAITING = "jp.amiplus.mulch.action.STOP_WAITING"
        const val ACTION_SHOW_OVERLAY = "jp.amiplus.mulch.action.SHOW_OVERLAY"
        const val ACTION_ACCEPT_INCOMING = "jp.amiplus.mulch.action.ACCEPT_INCOMING"
        const val ACTION_DISMISS_OVERLAY = "jp.amiplus.mulch.action.DISMISS_OVERLAY"

        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"

        const val PREFS = "ami_tv_call"
        const val KEY_WAITING = "call_waiting_enabled"
        const val KEY_PENDING_ACTION = "pending_incoming_action"
        const val KEY_PENDING_CALLER_ID = "pending_caller_id"
        const val KEY_PENDING_CALLER_NAME = "pending_caller_name"
        const val KEY_PREV_PACKAGE = "prev_watch_package"
        const val KEY_PREV_TASK_ID = "prev_watch_task_id"

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
        )

        private fun isIgnoredPackage(pkg: String): Boolean {
            if (pkg.isEmpty()) return true
            if (ignoredPackages.contains(pkg)) return true
            if (pkg.startsWith("com.android.")) return true
            return false
        }

        /** 着信で全面化する直前の視聴アプリ（Netflix / 地デジ 等）を覚える */
        fun captureForegroundApp(context: Context) {
            val my = context.packageName
            var pkg: String? = null
            var taskId = -1
            try {
                @Suppress("DEPRECATION")
                val tasks = (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
                    .getRunningTasks(12)
                for (task in tasks) {
                    val p = task.topActivity?.packageName ?: task.baseActivity?.packageName
                    if (p != null && p != my && !isIgnoredPackage(p)) {
                        pkg = p
                        taskId = task.id
                        break
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "getRunningTasks: ${e.message}")
            }
            if (pkg == null) {
                try {
                    val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    val now = System.currentTimeMillis()
                    val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 180_000, now)
                    pkg = stats
                        .filter {
                            it.packageName != my &&
                                !isIgnoredPackage(it.packageName) &&
                                it.lastTimeUsed > 0
                        }
                        .maxByOrNull { it.lastTimeUsed }
                        ?.packageName
                } catch (e: Exception) {
                    Log.w(TAG, "usageStats: ${e.message}")
                }
            }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (pkg != null) {
                prefs.edit()
                    .putString(KEY_PREV_PACKAGE, pkg)
                    .putInt(KEY_PREV_TASK_ID, taskId)
                    .apply()
                Log.i(TAG, "captured previous app $pkg task=$taskId")
            } else {
                Log.i(TAG, "no previous watch app captured")
            }
        }

        /** 通話終了後、直前の視聴アプリへ戻す。タスクが残っていれば続き、無ければ起動。 */
        fun returnToPreviousApp(activity: Activity): Boolean {
            val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pkg = prefs.getString(KEY_PREV_PACKAGE, "") ?: ""
            val taskId = prefs.getInt(KEY_PREV_TASK_ID, -1)
            prefs.edit().remove(KEY_PREV_PACKAGE).remove(KEY_PREV_TASK_ID).apply()
            if (pkg.isEmpty() || pkg == activity.packageName || isIgnoredPackage(pkg)) {
                Log.i(TAG, "returnToPreviousApp: nothing to restore")
                return false
            }
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (taskId > 0) {
                try {
                    @Suppress("DEPRECATION")
                    am.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_NO_USER_ACTION)
                    Log.i(TAG, "moved task $taskId ($pkg) to front")
                    return true
                } catch (e: Exception) {
                    Log.w(TAG, "moveTaskToFront failed: ${e.message}")
                }
            }
            try {
                val launch = activity.packageManager.getLeanbackLaunchIntentForPackage(pkg)
                    ?: activity.packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    activity.startActivity(launch)
                    Log.i(TAG, "launched $pkg")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "launch $pkg failed: ${e.message}")
            }
            try {
                activity.moveTaskToBack(true)
                Log.i(TAG, "moveTaskToBack fallback")
                return true
            } catch (_: Exception) {
            }
            return false
        }

        fun canDrawOverlays(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }

        fun startWaiting(context: Context) {
            val i = Intent(context, IncomingCallOverlayService::class.java).apply {
                action = ACTION_START_WAITING
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
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
            captureForegroundApp(context)
            wakeDisplay(context)
            val i = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
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

        fun isScreenOn(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isInteractive
        }

        /** スクリーンレス／待機からパネルを起こす */
        fun wakeDisplay(context: Context) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isInteractive) {
                    @Suppress("DEPRECATION")
                    val wl = pm.newWakeLock(
                        PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                        "ami:incoming_wake"
                    )
                    wl.acquire(60_000)
                    Log.i(TAG, "wakeDisplay: acquired wake lock")
                } else {
                    Log.i(TAG, "wakeDisplay: already interactive")
                }
            } catch (e: Exception) {
                Log.e(TAG, "wakeDisplay wakeLock failed", e)
            }
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", "224"))
            } catch (e: Exception) {
                Log.w(TAG, "wakeDisplay KEYCODE_WAKEUP failed: ${e.message}")
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var ringtone: Ringtone? = null
    private var waiting = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_WAITING -> {
                waiting = true
                prefs().edit().putBoolean(KEY_WAITING, true).apply()
                startForeground(NOTIF_ID, buildWaitingNotification())
                Log.i(TAG, "call waiting started")
            }
            ACTION_STOP_WAITING -> {
                waiting = false
                prefs().edit().putBoolean(KEY_WAITING, false).apply()
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
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        dismissOverlayInternal()
        super.onDestroy()
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(
            CHANNEL_ID,
            "着信待機",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "テレビ電話の着信待機中"
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
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
        wakeDisplayInternal()
        if (!canDrawOverlays(this)) {
            Log.e(TAG, "SYSTEM_ALERT_WINDOW not granted")
            // 権限なし → 全面起動フォールバック
            launchAppAccept(callerId, callerName)
            return
        }
        dismissOverlayInternal()

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
            // リモコン操作のためフォーカス可能。視聴側のフォーカスは一時的にこちらへ。
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
            windowManager?.addView(panel, params)
            overlayView = panel
            yes.requestFocus()
            startRingtone()
            Log.i(TAG, "overlay shown callerId=$callerId name=$callerName")
        } catch (e: Exception) {
            Log.e(TAG, "failed to add overlay", e)
            launchAppAccept(callerId, callerName)
        }
    }

    private fun wakeDisplayInternal() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (wakeLock?.isHeld != true) {
                @Suppress("DEPRECATION")
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "ami:incoming_overlay"
                )
                wakeLock?.acquire(90_000)
            }
            Log.i(TAG, "wakeDisplayInternal interactive=${pm.isInteractive}")
        } catch (e: Exception) {
            Log.e(TAG, "wakeDisplayInternal failed", e)
        }
        try {
            Runtime.getRuntime().exec(arrayOf("input", "keyevent", "224"))
        } catch (_: Exception) {
        }
    }

    private fun dismissOverlayInternal() {
        stopRingtone()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        val v = overlayView ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: Exception) {
        }
        overlayView = null
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
    }

    private fun launchAppAccept(callerId: String, callerName: String) {
        stopRingtone()
        captureForegroundApp(this)
        val i = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra("incoming_action", "accept")
            putExtra(EXTRA_CALLER_ID, callerId)
            putExtra(EXTRA_CALLER_NAME, callerName)
        }
        startActivity(i)
    }
}
