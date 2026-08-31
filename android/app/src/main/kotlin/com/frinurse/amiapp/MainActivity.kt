package jp.amiplus.lisa

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "ami_tv_engine"
        private var current: WeakReference<MainActivity>? = null
        @Volatile
        private var resumed = false

        fun isInForeground(): Boolean = resumed && current?.get() != null

        fun currentActivity(): MainActivity? = current?.get()

        fun dispatchIncomingAction(
            action: String,
            callerId: String,
            callerName: String
        ) {
            val act = current?.get() ?: return
            act.runOnUiThread {
                val i = Intent().apply {
                    putExtra("incoming_action", action)
                    putExtra(IncomingCallOverlayService.EXTRA_CALLER_ID, callerId)
                    putExtra(IncomingCallOverlayService.EXTRA_CALLER_NAME, callerName)
                }
                act.handleIncomingIntent(i)
            }
        }
    }

    private val channelName = "jp.amiplus.lisa/tv"
    private val tag = "AmiTvAudio"
    private val actionUsbPermission = "jp.amiplus.lisa.USB_PERMISSION"
    private var probedOnce = false
    private var methodChannel: MethodChannel? = null

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != actionUsbPermission) return
            val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            Log.i(tag, "USB permission granted=$granted device=${device?.productName}")
            this@MainActivity.logPersistent(
                "USB permission granted=$granted device=${device?.productName}"
            )
            if (granted) {
                Thread {
                    val probe = probeUsbMicLevel()
                    this@MainActivity.logPersistent("probe after USB permission=$probe")
                }.start()
            }
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (!isTelevisionDevice()) return null
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        return try {
            val engine = FlutterEngine(context.applicationContext)
            cache.put(ENGINE_ID, engine)
            Log.i(tag, "cached FlutterEngine $ENGINE_ID")
            engine
        } catch (e: Exception) {
            Log.e(tag, "provideFlutterEngine failed", e)
            null
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // YouTube 復帰で Activity が破棄されても、着信待機と WebRTC を残す。
        return !isTelevisionDevice()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            UsbMicBridge.webrtcPlugin = flutterEngine.plugins
                .get(com.cloudwebrtc.webrtc.FlutterWebRTCPlugin::class.java)
                as? com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
            Log.i(tag, "webrtcPlugin from engine: ${UsbMicBridge.webrtcPlugin != null}")
        } catch (e: Throwable) {
            Log.e(tag, "failed to get FlutterWebRTCPlugin from engine", e)
        }
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isTelevisionDevice())
                "playNavClick" -> {
                    playNavClick()
                    result.success(true)
                }
                "prepareCommunicationAudio" -> {
                    result.success(prepareCommunicationAudio())
                }
                "listAudioInputs" -> result.success(listAudioInputs())
                "ensureUsbAudioPermission" -> {
                    result.success(ensureUsbAudioPermission())
                }
                "getUsbCameraProfile" -> {
                    result.success(getUsbCameraProfile())
                }
                "hasUsbCamera" -> {
                    result.success(hasUsbCamera())
                }
                "setUvcAntiFlicker60" -> {
                    Thread {
                        val res = try {
                            UvcAntiFlicker.set60Hz(this)
                        } catch (e: Throwable) {
                            Log.e(tag, "setUvcAntiFlicker60 failed", e)
                            mapOf("ok" to false, "reason" to (e.message ?: "exception"))
                        }
                        logPersistent("setUvcAntiFlicker60=$res")
                        runOnUiThread { result.success(res) }
                    }.start()
                }
                "probeUsbMicLevel" -> {
                    Thread {
                        val probe = try {
                            probeUsbMicLevel()
                        } catch (e: Exception) {
                            Log.e(tag, "probeUsbMicLevel failed", e)
                            mapOf("ok" to false, "reason" to (e.message ?: "exception"))
                        }
                        runOnUiThread { result.success(probe) }
                    }.start()
                }
                "usbUacProbe" -> {
                    Thread {
                        val probe = try {
                            UsbAudioCapture.probe(this)
                        } catch (e: Throwable) {
                            Log.e(tag, "usbUacProbe failed", e)
                            mapOf("ok" to false, "reason" to (e.message ?: "exception"))
                        }
                        logPersistent("usbUacProbe=$probe")
                        runOnUiThread { result.success(probe) }
                    }.start()
                }
                "usbUacStart" -> {
                    Thread {
                        val res = try {
                            UsbMicBridge.start(this)
                        } catch (e: Throwable) {
                            Log.e(tag, "usbUacStart failed", e)
                            mapOf("ok" to false, "reason" to (e.message ?: "exception"))
                        }
                        logPersistent("usbUacStart=$res")
                        runOnUiThread { result.success(res) }
                    }.start()
                }
                "usbUacStop" -> {
                    Thread {
                        val res = try {
                            UsbMicBridge.stop()
                        } catch (e: Throwable) {
                            Log.e(tag, "usbUacStop failed", e)
                            mapOf("ok" to false, "reason" to (e.message ?: "exception"))
                        }
                        logPersistent("usbUacStop=$res")
                        runOnUiThread { result.success(res) }
                    }.start()
                }
                "canDrawOverlays" ->
                    result.success(IncomingCallOverlayService.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    result.success(requestOverlayPermission())
                }
                "startCallWaiting" -> {
                    IncomingCallOverlayService.startWaiting(
                        this,
                        call.argument<Boolean>("piLayout")
                    )
                    // 通話終了後に電源オフへ戻すには lockNow が要る。
                    // 未許可なら着信待機の開始時に一度だけ許可画面を出す。
                    IncomingCallOverlayService.requestDeviceAdminIfNeeded(this)
                    result.success(true)
                }
                "stopCallWaiting" -> {
                    IncomingCallOverlayService.stopWaiting(this)
                    result.success(true)
                }
                "showIncomingCallOverlay" -> {
                    val callerId = call.argument<String>("callerId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "着信中"
                    IncomingCallOverlayService.showOverlay(this, callerId, callerName)
                    result.success(true)
                }
                "acceptIncomingCall" -> {
                    val callerId = call.argument<String>("callerId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "着信中"
                    IncomingCallOverlayService.acceptIncoming(this, callerId, callerName)
                    result.success(true)
                }
                "captureForegroundApp" -> {
                    IncomingCallOverlayService.captureForegroundApp(this)
                    result.success(true)
                }
                "bringToFront" -> {
                    IncomingCallOverlayService.bringToFront(this)
                    result.success(true)
                }
                "dismissIncomingCallOverlay" -> {
                    IncomingCallOverlayService.dismissOverlay(this)
                    result.success(true)
                }
                "cancelIncomingCallOverlay" -> {
                    val callerId = call.argument<String>("callerId") ?: ""
                    IncomingCallOverlayService.cancelIncomingUi(this, callerId)
                    result.success(true)
                }
                "timeoutIncomingCallOverlay" -> {
                    val callerId = call.argument<String>("callerId") ?: ""
                    IncomingCallOverlayService.timeoutIncomingUi(this, callerId)
                    result.success(true)
                }
                "wasIncomingCancelled" -> {
                    val callerId = call.argument<String>("callerId") ?: ""
                    result.success(IncomingCallOverlayService.wasIncomingCancelled(callerId))
                }
                "getPendingIncomingCall" -> {
                    result.success(consumePendingIncomingCall())
                }
                "isScreenOn" ->
                    result.success(IncomingCallOverlayService.isScreenOn(this))
                // Android のAPIレベル。BLE権限の出し分けに使う
                // (SDK31未満は BLUETOOTH_SCAN が無く、要求すると位置情報を求められる)。
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "getAndroidId" -> {
                    val id = try {
                        android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ANDROID_ID,
                        ) ?: ""
                    } catch (e: Throwable) {
                        ""
                    }
                    result.success(id)
                }
                "wakeScreen" -> {
                    IncomingCallOverlayService.wakeDisplay(this)
                    setTurnScreenOn(true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        setShowWhenLocked(true)
                    }
                    result.success(true)
                }
                "returnToPreviousApp" -> {
                    result.success(IncomingCallOverlayService.returnToPreviousApp(this))
                }
                // 通話終了後、TV電源オフ状態へ戻す（TV005のみ / Device Admin lockNow）
                "setScreenOffAtCall" -> {
                    val wasOff = call.argument<Boolean>("wasOff") ?: false
                    IncomingCallOverlayService.setScreenOffAtCall(this, wasOff)
                    result.success(true)
                }
                "wasScreenOffAtCall" -> {
                    result.success(IncomingCallOverlayService.wasScreenOffAtCall(this))
                }
                "lockScreenForStandby" -> {
                    // 端末を限定せず、電源オフ発の着信かどうかだけで判断する。
                    // Android 11(TV005) は lockNow、Android 12(TV007) は
                    // goToSleep/スリープキーも併用する（サービス側で吸収）。
                    result.success(IncomingCallOverlayService.lockScreenForStandby(this))
                }
                "isTvStandby" -> {
                    result.success(IncomingCallOverlayService.isTvStandby(this))
                }
                "isStandbyTargetDevice" -> {
                    // 旧API。端末限定をやめたので常に true を返す。
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("incoming_action")
        if (action == "accept") {
            setTurnScreenOn(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
            }
            IncomingCallOverlayService.wakeDisplay(this)
        }
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val action = intent?.getStringExtra("incoming_action") ?: return
        val callerId = intent.getStringExtra(IncomingCallOverlayService.EXTRA_CALLER_ID) ?: ""
        val callerName = intent.getStringExtra(IncomingCallOverlayService.EXTRA_CALLER_NAME) ?: ""
        val prefs = getSharedPreferences(IncomingCallOverlayService.PREFS, MODE_PRIVATE)
        prefs.edit()
            .putString(IncomingCallOverlayService.KEY_PENDING_ACTION, action)
            .putString(IncomingCallOverlayService.KEY_PENDING_CALLER_ID, callerId)
            .putString(IncomingCallOverlayService.KEY_PENDING_CALLER_NAME, callerName)
            .apply()
        methodChannel?.invokeMethod(
            "onIncomingCallAction",
            mapOf(
                "action" to action,
                "callerId" to callerId,
                "callerName" to callerName
            )
        )
    }

    private fun consumePendingIncomingCall(): Map<String, Any?>? {
        handleIncomingIntent(intent)
        val prefs = getSharedPreferences(IncomingCallOverlayService.PREFS, MODE_PRIVATE)
        val action = prefs.getString(IncomingCallOverlayService.KEY_PENDING_ACTION, null)
            ?: return null
        val map = mapOf(
            "action" to action,
            "callerId" to (prefs.getString(IncomingCallOverlayService.KEY_PENDING_CALLER_ID, "") ?: ""),
            "callerName" to (prefs.getString(IncomingCallOverlayService.KEY_PENDING_CALLER_NAME, "") ?: "")
        )
        prefs.edit()
            .remove(IncomingCallOverlayService.KEY_PENDING_ACTION)
            .remove(IncomingCallOverlayService.KEY_PENDING_CALLER_ID)
            .remove(IncomingCallOverlayService.KEY_PENDING_CALLER_NAME)
            .apply()
        // Intent extras も消費
        intent?.removeExtra("incoming_action")
        return map
    }

    private fun playNavClick() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.playSoundEffect(AudioManager.FX_FOCUS_NAVIGATION_DOWN, 1.0f)
        } catch (e: Throwable) {
            Log.w(tag, "playNavClick failed", e)
        }
    }

    private fun requestOverlayPermission(): Map<String, Any?> {
        val granted = IncomingCallOverlayService.canDrawOverlays(this)
        if (granted) {
            return mapOf("granted" to true, "needAdb" to false)
        }
        var openedSettings = false
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            openedSettings = true
        } catch (_: Exception) {
            openedSettings = false
        }
        return mapOf(
            "granted" to false,
            "needAdb" to !openedSettings,
            "openedSettings" to openedSettings,
            "adbCommand" to "adb shell appops set $packageName SYSTEM_ALERT_WINDOW allow"
        )
    }

    private fun logPersistent(msg: String) {
        Log.i(tag, msg)
        try {
            val dir = getExternalFilesDir(null) ?: filesDir
            val f = java.io.File(dir, "ami_tv_audio.log")
            f.appendText("${System.currentTimeMillis()} $msg\n")
        } catch (e: Exception) {
            Log.e(tag, "logPersistent failed", e)
        }
    }

    private fun hasCompletedFirstLaunch(): Boolean {
        return try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getBoolean("flutter.isInitialized", false)
        } catch (_: Exception) {
            false
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        if (hasCompletedFirstLaunch()) {
            setTheme(R.style.LaunchThemeNoSplash)
        }
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        try {
            val dir = getExternalFilesDir(null) ?: filesDir
            java.io.File(dir, "ami_tv_audio.log").writeText("")
        } catch (_: Exception) {
        }
        logPersistent("onCreate tv=${isTelevisionDevice()}")
        if (intent?.getStringExtra("incoming_action") != null) {
            setTurnScreenOn(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
            }
            IncomingCallOverlayService.wakeDisplay(this)
        }
        handleIncomingIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        Log.i(tag, "onStart")
        try {
            val filter = IntentFilter(actionUsbPermission)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(usbPermissionReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(usbPermissionReceiver, filter)
            }
        } catch (e: Exception) {
            Log.e(tag, "registerReceiver failed", e)
        }
    }

    override fun onStop() {
        try {
            unregisterReceiver(usbPermissionReceiver)
        } catch (_: Exception) {
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        if (!probedOnce && isTelevisionDevice()) {
            probedOnce = true
            Handler(Looper.getMainLooper()).post {
                if (!resumed) return@post
                try {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    if (!pm.isInteractive) return@post
                    val perm = ensureUsbAudioPermission()
                    logPersistent("ensureUsbAudioPermission=$perm")
                } catch (e: Exception) {
                    Log.e(tag, "onResume usb permission failed", e)
                    logPersistent("onResume usb permission failed: ${e.message}")
                }
            }
        }
    }

    override fun onPause() {
        resumed = false
        if (isTelevisionDevice()) {
            releaseScreenKeepOn()
            markRestoreIfScreenOff()
        }
        super.onPause()
    }

    override fun onDestroy() {
        if (current?.get() === this) {
            current = null
        }
        try {
            super.onDestroy()
        } catch (t: Throwable) {
            Log.w("AmiMain", "onDestroy: ${t.message}")
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isTelevisionDevice() && event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_POWER,
                KeyEvent.KEYCODE_SLEEP,
                KeyEvent.KEYCODE_TV_POWER,
                KeyEvent.KEYCODE_STB_POWER -> {
                    releaseScreenKeepOn()
                    markRestoreOnScreenOn()
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun releaseScreenKeepOn() {
        try {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } catch (_: Exception) {
        }
    }

    private fun markRestoreIfScreenOff() {
        if (!isTelevisionDevice()) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                markRestoreOnScreenOn()
            }
        } catch (_: Exception) {
        }
    }

    private fun markRestoreOnScreenOn() {
        getSharedPreferences(IncomingCallOverlayService.PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(IncomingCallOverlayService.KEY_RESTORE_ON_SCREEN_ON, true)
            .apply()
    }

    private fun isTelevisionDevice(): Boolean {
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        ) {
            return true
        }
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return uiMode == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private fun ensureUsbAudioPermission(): Map<String, Any?> {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = usbManager.deviceList.values.toList()
        val candidates = devices.filter { deviceLikelyHasMic(it) }
        logPersistent(
            "usb devices=${devices.map { "${it.productName}(${it.vendorId}:${it.productId}) perm=${usbManager.hasPermission(it)}" }}"
        )
        logPersistent("usb mic candidates=${candidates.map { it.productName }}")

        var requested = false
        var alreadyGranted = false
        for (device in candidates) {
            if (!shouldRequestUsbPermission(usbManager, device)) continue
            if (usbManager.hasPermission(device)) {
                alreadyGranted = true
                continue
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val intent = Intent(actionUsbPermission).apply {
                setPackage(packageName)
                putExtra(UsbManager.EXTRA_DEVICE, device)
            }
            val pi = PendingIntent.getBroadcast(this, device.deviceId, intent, flags)
            usbManager.requestPermission(device, pi)
            requested = true
            Log.i(tag, "requestPermission for ${device.productName} vid=${device.vendorId} pid=${device.productId}")
        }
        return mapOf(
            "deviceCount" to devices.size,
            "candidateCount" to candidates.size,
            "alreadyGranted" to alreadyGranted,
            "requested" to requested,
            "devices" to devices.map {
                mapOf(
                    "name" to it.productName,
                    "vendorId" to it.vendorId,
                    "productId" to it.productId,
                    "hasPermission" to usbManager.hasPermission(it),
                    "hasAudio" to deviceLikelyHasMic(it)
                )
            }
        )
    }

    private fun shouldRequestUsbPermission(usbManager: UsbManager, device: UsbDevice): Boolean {
        if (usbManager.hasPermission(device)) return false
        if (CameraProfiles.looksLikeCamera(device.vendorId, device.productId, device.productName) ||
            CameraProfiles.matchesKnown(device)
        ) {
            return true
        }
        // 製品名なしは内部USB。システムダイアログが「null」になり、起動のたびに出る。
        if (device.productName.isNullOrBlank()) return false
        var hasAudio = false
        var hasVideo = false
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) hasAudio = true
            if (intf.interfaceClass == UsbConstants.USB_CLASS_VIDEO) hasVideo = true
        }
        return hasAudio && hasVideo
    }

    private fun deviceLikelyHasMic(device: UsbDevice): Boolean {
        if (CameraProfiles.looksLikeCamera(device.vendorId, device.productId, device.productName)) {
            return true
        }
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) return true
            if (intf.interfaceClass == UsbConstants.USB_CLASS_VIDEO) return true
        }
        return false
    }

    private fun hasVideoClass(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            if (device.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_VIDEO) {
                return true
            }
        }
        return false
    }

    /// Wi‑Fiドングルなどは除外し、Camera2 か UVC / 既知カメラだけを「挿さっている」と見る。
    private fun hasUsbCamera(): Boolean {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            if (cm.cameraIdList.isNotEmpty()) {
                return true
            }
        } catch (e: Exception) {
            Log.w(tag, "hasUsbCamera cameraIdList: ${e.message}")
        }
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        return usbManager.deviceList.values.any { device ->
            CameraProfiles.matchesKnown(device) ||
                CameraProfiles.looksLikeCamera(
                    device.vendorId,
                    device.productId,
                    device.productName,
                ) ||
                hasVideoClass(device)
        }
    }

    private fun getUsbCameraProfile(): Map<String, Any?> {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = usbManager.deviceList.values.toList()
        val target = devices.firstOrNull { CameraProfiles.matchesKnown(it) }
            ?: devices.firstOrNull { deviceLikelyHasMic(it) }
            ?: devices.firstOrNull()
        if (target == null) {
            return mapOf("id" to "none", "productName" to null)
        }
        val info = CameraProfiles.select(target.vendorId, target.productId, target.productName)
        return CameraProfiles.toMap(info, target.vendorId, target.productId, target.productName) + mapOf(
            "allUsb" to devices.map { d ->
                mapOf(
                    "productName" to d.productName,
                    "vendorId" to d.vendorId,
                    "productId" to d.productId,
                )
            }
        )
    }

    private fun prepareCommunicationAudio(): Map<String, Any?> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_NORMAL
        am.isSpeakerphoneOn = true
        am.isMicrophoneMute = false

        var outputSelected: String? = null
        var usbInputSeen: String? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            val usbIn = findUsbInput(inputs)
            if (usbIn != null) {
                usbInputSeen = "${usbIn.productName} type=${usbIn.type} id=${usbIn.id}"
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.clearCommunicationDevice()
            val outs = am.availableCommunicationDevices
            val preferred = outs.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
                    it.type == AudioDeviceInfo.TYPE_HDMI ||
                    it.type == AudioDeviceInfo.TYPE_HDMI_ARC ||
                    it.type == AudioDeviceInfo.TYPE_TELEPHONY
            } ?: outs.firstOrNull {
                it.type != AudioDeviceInfo.TYPE_USB_DEVICE &&
                    it.type != AudioDeviceInfo.TYPE_USB_HEADSET &&
                    it.type != AudioDeviceInfo.TYPE_USB_ACCESSORY &&
                    it.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                    it.type != AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
            }
            if (preferred != null) {
                am.setCommunicationDevice(preferred)
                outputSelected = "${preferred.productName} type=${preferred.type}"
            }
        }

        return mapOf(
            "mode" to am.mode,
            "micMute" to am.isMicrophoneMute,
            "speakerOn" to am.isSpeakerphoneOn,
            "output" to outputSelected,
            "usbInputSeen" to usbInputSeen
        )
    }

    private fun findUsbInput(inputs: Array<AudioDeviceInfo>): AudioDeviceInfo? {
        return inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
        } ?: inputs.firstOrNull {
            val n = it.productName?.toString()?.lowercase() ?: ""
            n.contains("camera") || n.contains("usb") || n.contains("sonix") ||
                n.contains("webcam") || n.contains("emeet") || n.contains("smartcam") ||
                n.contains("c270") || n.contains("logitech") || n.contains("logicool") ||
                n.contains("tzz") || n.contains("buffalo") || n.contains("bsw")
        }
    }

    private fun listAudioInputs(): List<Map<String, Any?>> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        // isSource=false のUSBも見えるように ALL で取る
        val devices = am.getDevices(AudioManager.GET_DEVICES_ALL).filter {
            it.isSource ||
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
        }
        return devices.map { describeDevice(it) }
    }

    private fun describeDevice(it: AudioDeviceInfo): Map<String, Any?> {
        val webrtcId = when (it.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> {
                val address =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.address else ""
                "microphone-$address"
            }
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired-headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
            else -> it.id.toString()
        }
        return mapOf(
            "id" to it.id,
            "webrtcDeviceId" to webrtcId,
            "type" to it.type,
            "typeName" to audioTypeName(it.type),
            "productName" to it.productName?.toString(),
            "isSource" to it.isSource,
            "address" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.address else null)
        )
    }

    private fun audioTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "BUILTIN_SPEAKER"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BT_SCO"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BT_A2DP"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB_DEVICE"
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB_ACCESSORY"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB_HEADSET"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_TELEPHONY -> "TELEPHONY"
        AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> "REMOTE_SUBMIX"
        else -> "TYPE_$type"
    }

    private fun probeUsbMicLevel(): Map<String, Any?> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf("ok" to false, "reason" to "sdk_too_old")
        }

        val all = am.getDevices(AudioManager.GET_DEVICES_ALL)
        for (d in all) {
            logPersistent(
                "allDev id=${d.id} type=${audioTypeName(d.type)} name=${d.productName} source=${d.isSource} sink=${d.isSink}"
            )
        }

        val inputs = all.filter { it.isSource }
        val usb = findUsbInput(all)
        val target = usb ?: inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
        } ?: inputs.firstOrNull()

        logPersistent(
            "probe target=${target?.productName} type=${target?.type} id=${target?.id} usbFound=${usb != null} inputs=${inputs.size}"
        )

        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (minBuf <= 0) {
            return mapOf("ok" to false, "reason" to "bad_buffer", "minBuf" to minBuf)
        }

        // 診断は短く: MIC + (USBがあればそれ / なければ default) のみ
        val sources = intArrayOf(MediaRecorder.AudioSource.MIC, MediaRecorder.AudioSource.CAMCORDER)
        val targets = mutableListOf<AudioDeviceInfo?>()
        if (usb != null) targets.add(usb)
        targets.add(target)
        targets.add(null)

        var best: Map<String, Any?>? = null
        var lastError: String? = null

        for (device in targets.distinctBy { it?.id }) {
            for (source in sources) {
                var recorder: AudioRecord? = null
                try {
                    recorder = AudioRecord(source, sampleRate, channelConfig, audioFormat, minBuf * 2)
                    if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                        lastError = "not_initialized source=$source"
                        recorder.release()
                        continue
                    }
                    if (device != null) {
                        val preferred = recorder.setPreferredDevice(device)
                        logPersistent(
                            "setPreferredDevice(${device.productName}/${audioTypeName(device.type)})=$preferred source=$source"
                        )
                    }
                    recorder.startRecording()
                    val buf = ShortArray(minBuf)
                    var maxAbs = 0
                    var sumSq = 0.0
                    var samples = 0
                    val until = System.currentTimeMillis() + 600
                    while (System.currentTimeMillis() < until) {
                        val n = recorder.read(buf, 0, buf.size)
                        if (n <= 0) continue
                        for (i in 0 until n) {
                            val v = abs(buf[i].toInt())
                            if (v > maxAbs) maxAbs = v
                            sumSq += (buf[i] * buf[i]).toDouble()
                            samples++
                        }
                    }
                    recorder.stop()
                    recorder.release()
                    val rms = if (samples > 0) sqrt(sumSq / samples) else 0.0
                    val result = mapOf(
                        "ok" to true,
                        "source" to source,
                        "deviceName" to (device?.productName?.toString() ?: "default"),
                        "deviceType" to (device?.type ?: -1),
                        "deviceTypeName" to audioTypeName(device?.type ?: -1),
                        "deviceId" to (device?.id ?: -1),
                        "usbFound" to (usb != null),
                        "inputCount" to inputs.size,
                        "maxAbs" to maxAbs,
                        "rms" to rms,
                        "samples" to samples,
                        "hasSignal" to (maxAbs > 200)
                    )
                    logPersistent("probe try=$result")
                    if (best == null || (maxAbs > ((best["maxAbs"] as? Int) ?: 0))) {
                        best = result
                    }
                    if (maxAbs > 200) {
                        return result
                    }
                } catch (e: Exception) {
                    lastError = e.message
                    logPersistent("probe failed source=$source device=${device?.productName} err=${e.message}")
                    try {
                        recorder?.release()
                    } catch (_: Exception) {
                    }
                }
            }
        }

        return best ?: mapOf(
            "ok" to false,
            "reason" to (lastError ?: "all_sources_failed"),
            "usbFound" to (usb != null),
            "inputCount" to inputs.size
        )
    }
}
