package jp.amiplus.lisa

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager

/**
 * LiSA 本体プロセスの見張り番（4.6.3(97) の復元）。
 *
 * 別プロセス(:watch)で動き、本体プロセスが LMK（メモリ不足）に殺されたら
 * 待受サービスと MainActivity を自動で立て直す。
 * TCL は startForeground を拒否するため、通常サービス + 1px 不可視オーバーレイで
 * adj を上げて生き残る（本体の v58 対策と同じ手法）。
 */
class LisaWatchdogService : Service() {

    companion object {
        private const val TAG = "LisaWatchdog"
        private const val CHECK_INTERVAL_MS = 10_000L
        private const val MAIN_PROCESS = "jp.amiplus.lisa"

        fun start(context: Context) {
            try {
                val app = context.applicationContext
                app.startService(Intent(app, LisaWatchdogService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "start failed: ${e.message}")
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var mainWasAlive = true

    private val checker = object : Runnable {
        override fun run() {
            checkMainProcess()
            handler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        addKeepAliveOverlay()
        handler.postDelayed(checker, CHECK_INTERVAL_MS)
        Log.i(TAG, "watchdog started pid=${android.os.Process.myPid()}")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        start(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        handler.removeCallbacks(checker)
        removeOverlay()
        // 自分が止められても再起動を試みる。
        try {
            start(applicationContext)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun checkMainProcess() {
        val alive = isMainProcessAlive()
        if (alive) {
            mainWasAlive = true
            return
        }
        if (mainWasAlive) {
            logLastExitReason()
        }
        mainWasAlive = false
        Log.w(TAG, "main process dead — relaunching")
        try {
            IncomingCallOverlayService.startWaiting(this)
        } catch (e: Exception) {
            Log.w(TAG, "startWaiting failed: ${e.message}")
        }
        try {
            IncomingCallOverlayService.restoreMainAfterCrash(this)
        } catch (e: Exception) {
            Log.w(TAG, "restoreMain failed: ${e.message}")
        }
    }

    private fun isMainProcessAlive(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.runningAppProcesses?.any { it.processName == MAIN_PROCESS } == true
        } catch (_: Exception) {
            true
        }
    }

    private fun logLastExitReason() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val infos = am.getHistoricalProcessExitReasons(packageName, 0, 1)
            for (info in infos) {
                Log.w(
                    TAG,
                    "main exit: reason=${info.reason} " +
                        "importance=${info.importance} desc=${info.description}"
                )
            }
        } catch (_: Exception) {
        }
    }

    private fun addKeepAliveOverlay() {
        if (overlay != null) return
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "no overlay permission; watchdog runs without adj boost")
            return
        }
        try {
            val v = View(this)
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
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.TOP or Gravity.START }
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(v, lp)
            overlay = v
            Log.i(TAG, "1px overlay added (keep adj)")
        } catch (e: Exception) {
            Log.w(TAG, "overlay failed: ${e.message}")
        }
    }

    private fun removeOverlay() {
        val v = overlay ?: return
        overlay = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
    }
}
