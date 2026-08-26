package jp.amiplus.lisa

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 画面オフ、または SYSTEM_ALERT_WINDOW が使えない Google TV 向け着信パネル。
 * メーカー不問。はい／いいえを画面上部に出す。
 */
class IncomingCallActivity : Activity() {
    companion object {
        private var current: java.lang.ref.WeakReference<IncomingCallActivity>? = null
        fun finishIfOpen() {
            try {
                current?.get()?.finish()
            } catch (_: Exception) {
            }
        }

        fun isOpen(): Boolean = current?.get() != null
    }

    // 電源オフ(CECスタンバイ)から起動した際、ウィンドウがフォーカスを得る前の
    // requestFocus は効かないことがある。onWindowFocusChanged で再フォーカスするため保持。
    private var yesButton: Button? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = java.lang.ref.WeakReference(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        )
        IncomingCallOverlayService.wakeDisplay(this)

        val callerId = intent.getStringExtra(IncomingCallOverlayService.EXTRA_CALLER_ID) ?: ""
        val callerName = intent.getStringExtra(IncomingCallOverlayService.EXTRA_CALLER_NAME) ?: "着信"

        val root = FrameLayout(this)
        root.setBackgroundColor(Color.TRANSPARENT)
        val panel = buildPanel(callerId, callerName)
        val lp = FrameLayout.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.55f).toInt().coerceAtMost(dp(640)),
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(48)
        }
        root.addView(panel, lp)
        setContentView(root)
        window.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
        window.setLayout(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.WRAP_CONTENT
        )
        panel.requestFocus()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // ウィンドウがフォーカスを得たタイミングで「はい」へ確実にフォーカスを当てる。
        // 電源オフ→着信で起動した場合、onCreate内のrequestFocusでは効かないことへの対策。
        if (hasFocus) {
            val btn = yesButton ?: return
            btn.requestFocus()
            btn.post { if (!btn.isFocused) btn.requestFocus() }
        }
    }

    override fun onDestroy() {
        if (current?.get() === this) {
            current = null
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onBackPressed() {
        val callerId = intent.getStringExtra(IncomingCallOverlayService.EXTRA_CALLER_ID) ?: ""
        IncomingCallOverlayService.rejectFromUi(this, callerId)
        finish()
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            resources.displayMetrics
        ).toInt()

    private fun buildPanel(callerId: String, callerName: String): View {
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
        panel.addView(TextView(this).apply {
            text = "着信あり"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            gravity = Gravity.CENTER
        })
        panel.addView(TextView(this).apply {
            text = "着信"
            setTextColor(Color.parseColor("#DDEEFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(20))
        })

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
                v.background = GradientDrawable().apply {
                    setColor(if (hasFocus) focusedBg else bg)
                    cornerRadius = dp(10).toFloat()
                    if (hasFocus) setStroke(dp(3), Color.WHITE)
                }
            }
        }

        val yes = Button(this).apply {
            text = "はい"
            styleButton(this, Color.parseColor("#0A7A3E"), Color.parseColor("#12A855"))
            setOnClickListener {
                IncomingCallOverlayService.acceptFromUi(this@IncomingCallActivity, callerId, callerName)
                finish()
            }
            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
                        keyCode == KeyEvent.KEYCODE_ENTER ||
                        keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER)
                ) {
                    IncomingCallOverlayService.acceptFromUi(this@IncomingCallActivity, callerId, callerName)
                    finish()
                    true
                } else false
            }
        }
        val no = Button(this).apply {
            text = "いいえ"
            styleButton(this, Color.parseColor("#8A1F2B"), Color.parseColor("#C62828"))
            setOnClickListener {
                IncomingCallOverlayService.rejectFromUi(this@IncomingCallActivity, callerId)
                finish()
            }
            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
                        keyCode == KeyEvent.KEYCODE_ENTER ||
                        keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER)
                ) {
                    IncomingCallOverlayService.rejectFromUi(this@IncomingCallActivity, callerId)
                    finish()
                    true
                } else false
            }
        }
        buttons.addView(yes)
        buttons.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(24), 1)
        })
        buttons.addView(no)
        panel.addView(buttons)
        yesButton = yes
        yes.requestFocus()
        return panel
    }
}
