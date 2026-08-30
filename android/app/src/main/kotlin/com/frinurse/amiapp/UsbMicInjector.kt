package jp.amiplus.lisa

import android.content.Context
import android.os.Build
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 相手側(再生)音声の活動を監視するモニタ。renderPreProcessing に登録する。
 * TVスピーカーから相手の声が出ている間を検出し、エコーサプレッサの制御に使う。
 */
object FarEndMonitor : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    // 2026-08-26 干渉対策を少し緩めた。
    // 220/1100 では小さな物音でもマイクが絞られ、相手が話し終えてからも
    // 1.1秒はこちらの声が届かなかった。ハウリングが出るようなら戻す。
    private const val ACTIVE_LEVEL = 300f   // これ未満の再生音では絞らない
    private const val HOLD_MS = 700L        // TVスピーカー遅延+部屋の残響

    @Volatile
    private var activeUntilMs = 0L

    val farEndActive: Boolean
        get() = System.currentTimeMillis() < activeUntilMs

    override fun initialize(sampleRateHz: Int, numChannels: Int) {}

    override fun reset(newRate: Int) {}

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        val fb = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val n = minOf(numFrames, fb.capacity())
        var maxAbs = 0f
        for (i in 0 until n) {
            val v = fb.get(i)
            val a = if (v < 0) -v else v
            if (a > maxAbs) maxAbs = a
        }
        if (maxAbs > ACTIVE_LEVEL) {
            activeUntilMs = System.currentTimeMillis() + HOLD_MS
        }
    }
}

/**
 * WebRTCのキャプチャ後段フック(ExternalAudioProcessing)で、内蔵マイクの
 * 無音フレームをUSBマイク(UAC直接取得)のPCMで置き換える。
 *
 * フレーム形式: float(int16値域)・モノラル・10ms(numFramesサンプル)。
 */
class UsbMicInjector(private val profile: MicProfile) :
    AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private val tag = "AmiUsbAudio"

    private var startedAtMs = 0L
    @Volatile
    private var outRate = 48000
    private var srcBuf = ShortArray(0)
    private var workBuf = FloatArray(0)
    private var lastValue = 0f
    private var logged = false

    // ---- ノイズ低減 (安価なUSBマイクのヒス対策) ----
    // ノイズゲート: 無音時はヒスを絞り、発話でスムーズに開く
    private var envelope = 0f          // 信号レベル追従
    private var gateGain = 0.05f       // 現在のゲートゲイン
    private var gateOpen = false
    // 一次ローパス: 高域ヒスを軽く抑える (fc≈8kHz@48k)
    private var lpState = 0f
    // エコーサプレッサ: 相手発話中はマイクを絞る(ダッキング)
    private var duckGain = 1f

    // ---- 診断: 途切れ原因の切り分け用カウンタ(10秒ごとにログ) ----
    private var statFrames = 0
    private var statUnderruns = 0   // 供給ゼロ(無音化)の回数
    private var statPartials = 0    // 供給不足(引き伸ばし)の回数
    private var statTrims = 0       // 溜まりすぎ破棄の回数
    private var statDucked = 0      // エコー抑制でマイクを絞っていたフレーム数
    private var statGateClosed = 0  // ノイズゲートが閉じていたフレーム数
    private var statLastLogMs = 0L

    private fun logSupplyStats(available: Int) {
        statFrames++
        if (FarEndMonitor.farEndActive) statDucked++
        if (!gateOpen) statGateClosed++
        val now = System.currentTimeMillis()
        if (statLastLogMs == 0L) statLastLogMs = now
        if (now - statLastLogMs >= 10_000) {
            Log.i(
                tag,
                "supply stats(10s): frames=$statFrames underruns=$statUnderruns " +
                    "partials=$statPartials trims=$statTrims avail=$available " +
                    "ducked=$statDucked gateClosed=$statGateClosed"
            )
            statFrames = 0
            statUnderruns = 0
            statPartials = 0
            statTrims = 0
            statDucked = 0
            statGateClosed = 0
            statLastLogMs = now
        }
    }

    private companion object {
        const val ENV_DECAY = 0.9995f
    }

    private fun denoise(sample: Float): Float {
        // エンベロープ追従
        val a = if (sample < 0) -sample else sample
        envelope = if (a > envelope) a else envelope * ENV_DECAY

        // ゲート開閉判定(ヒステリシス)
        if (gateOpen) {
            if (envelope < profile.gateCloseLevel) gateOpen = false
        } else {
            if (envelope > profile.gateOpenLevel) gateOpen = true
        }
        val target = if (gateOpen) 1f else profile.gateFloor
        val alpha = if (target > gateGain) profile.gateAttack else profile.gateRelease
        gateGain += (target - gateGain) * alpha

        // エコーサプレッサ: 相手の声がTVスピーカーから出ている間は絞る
        val duckTarget = if (FarEndMonitor.farEndActive) profile.duckGain else 1f
        val duckAlpha = if (duckTarget < duckGain) profile.duckAttack else profile.duckRelease
        duckGain += (duckTarget - duckGain) * duckAlpha

        // ローパスで高域ヒスを軽減
        lpState += profile.lpCoeff * (sample - lpState)
        return lpState * gateGain * duckGain
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        outRate = sampleRateHz
        startedAtMs = System.currentTimeMillis()
        Log.i(tag, "injector initialize rate=$sampleRateHz ch=$numChannels")
    }

    override fun reset(newRate: Int) {
        outRate = newRate
        Log.i(tag, "injector reset rate=$newRate")
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (!UsbAudioCapture.running) return
        val srcRate = UsbAudioCapture.sampleRate
        val ch = UsbAudioCapture.channels
        if (srcRate <= 0 || numFrames <= 0) return

        // 遅延制御: 上限を超えたら目標量まで捨てる（音が映像より遅れるのを防ぐ）
        val maxKeep = srcRate * ch * profile.uacMaxKeepMs / 1000
        val availableNow = UsbAudioCapture.available()
        val warming = profile.uacWarmupMs > 0 &&
            (startedAtMs == 0L ||
                System.currentTimeMillis() - startedAtMs < profile.uacWarmupMs)
        if (!warming && availableNow > maxKeep) {
            val keep = (srcRate * ch * profile.uacTargetMs / 1000).coerceAtLeast(1)
            UsbAudioCapture.trim(keep)
            statTrims++
        }
        logSupplyStats(availableNow)

        // ドリフト補正: カメラとWebRTCのクロック差でバッファが枯渇/肥大しないよう、
        // 残量を目標に保つ方向へ消費量を±1〜2サンプル微調整する。
        val baseNeed = ((numFrames.toLong() * srcRate) / outRate).toInt().coerceAtLeast(1)
        val availFrames = availableNow / ch
        val targetFrames = srcRate * profile.uacTargetMs / 1000
        val bandFrames = srcRate / 100  // ±10msは調整不要の許容帯
        val adjust = when {
            availFrames > targetFrames * 3 / 2 -> 2
            availFrames > targetFrames + bandFrames -> 1
            availFrames < targetFrames / 2 -> -2
            availFrames < targetFrames - bandFrames -> -1
            else -> 0
        }
        val needSrcFrames = (baseNeed + adjust).coerceAtLeast(1)
        val needSamples = needSrcFrames * ch
        if (srcBuf.size < needSamples) srcBuf = ShortArray(needSamples)
        val got = UsbAudioCapture.readPcm(srcBuf, needSamples)
        val gotFrames = got / ch

        if (!logged) {
            logged = true
            Log.i(
                tag,
                "injector first frame: profile=${profile.name} outRate=$outRate numFrames=$numFrames " +
                    "bands=$numBands bufCap=${buffer.capacity()} srcRate=$srcRate ch=$ch gotFrames=$gotFrames"
            )
        }

        val fb = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val n = minOf(numFrames, fb.capacity())

        if (gotFrames <= 0) {
            statUnderruns++
            // アンダーラン: 直前値からフェードアウトして無音化
            for (i in 0 until n) {
                lastValue *= 0.95f
                fb.put(i, lastValue)
            }
            return
        }
        if (gotFrames < needSrcFrames) statPartials++

        // 線形補間リサンプル + モノラル化 + 入力ゲイン補正
        if (workBuf.size < n) workBuf = FloatArray(n)
        val ratio = gotFrames.toDouble() / n
        var frameMax = 0f
        for (i in 0 until n) {
            val srcPos = i * ratio
            val i0 = srcPos.toInt().coerceAtMost(gotFrames - 1)
            val i1 = (i0 + 1).coerceAtMost(gotFrames - 1)
            val frac = (srcPos - i0).toFloat()
            val s0 = monoAt(srcBuf, i0, ch)
            val s1 = monoAt(srcBuf, i1, ch)
            val v = (s0 + (s1 - s0) * frac) * profile.inputGain
            workBuf[i] = v
            val a = if (v < 0) -v else v
            if (a > frameMax) frameMax = a
        }

        // フレーム先読み: このフレームに声があれば頭からゲートを開く(頭欠け防止)
        if (frameMax > profile.gateOpenLevel && !gateOpen) {
            gateOpen = true
            gateGain = 1f
        }

        for (i in 0 until n) {
            val v = denoise(workBuf[i])
            fb.put(i, v)
            lastValue = v
        }
    }

    private fun monoAt(buf: ShortArray, frame: Int, ch: Int): Float {
        if (ch == 1) return buf[frame].toFloat()
        var sum = 0f
        for (c in 0 until ch) sum += buf[frame * ch + c]
        return sum / ch
    }
}

/**
 * UACキャプチャとWebRTC注入のライフサイクル管理。
 * Flutter側から通話開始/終了時に start/stop を呼ぶ。
 */
object UsbMicBridge {
    private const val TAG = "AmiUsbAudio"
    private var injector: UsbMicInjector? = null

    /**
     * メインエンジンのflutter_webrtcプラグイン。
     * sharedSingletonはFCMバックグラウンドエンジンに上書きされ得るため使わない。
     */
    @Volatile
    var webrtcPlugin: FlutterWebRTCPlugin? = null

    private fun audioController(): com.cloudwebrtc.webrtc.audio.AudioProcessingController? {
        val fromEngine = try {
            webrtcPlugin?.audioProcessingController
        } catch (_: Throwable) {
            null
        }
        if (fromEngine != null) return fromEngine
        return try {
            FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController
        } catch (_: Throwable) {
            null
        }
    }

    /// アイリス（Changhong）は HAL が USB マイクを出す。UAC で占有すると
    /// AudioRecord が usbaudio HAL を開けず、スマホが無音になる。
    private fun useHalUsbInsteadOfUac(): Boolean {
        val man = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val model = Build.MODEL.lowercase()
        return man.contains("changhong") ||
            brand.contains("iris") ||
            model.contains("pont")
    }

    /** AudioManagerがUSB入力を公開している端末(正規経路が動く)か */
    private fun halSupportsUsbInput(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            am.getDevices(android.media.AudioManager.GET_DEVICES_INPUTS).any {
                it.type == android.media.AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == android.media.AudioDeviceInfo.TYPE_USB_ACCESSORY
            }
        } catch (_: Exception) {
            false
        }
    }

    @Synchronized
    fun start(context: Context): Map<String, Any?> {
        val device = UsbAudioCapture.findMicDevice(context)
        if (device != null) {
            val profile = CameraProfiles.select(device.vendorId, device.productId, device.productName)
            if (profile.skipUacInjection) {
                Log.i(TAG, "UsbMicBridge: skip UAC for profile=${profile.id} device=${device.productName}")
                return mapOf(
                    "ok" to true,
                    "skipped" to true,
                    "reason" to "${profile.id}_skip_uac",
                    "device" to device.productName,
                )
            }
            if (profile.forceUacInjection &&
                useHalUsbInsteadOfUac() &&
                halSupportsUsbInput(context)
            ) {
                Log.i(
                    TAG,
                    "UsbMicBridge: skip force UAC on Iris HAL USB " +
                        "profile=${profile.id} device=${device.productName}"
                )
                return mapOf(
                    "ok" to true,
                    "skipped" to true,
                    "reason" to "iris_hal_usb",
                    "device" to device.productName,
                )
            }
            if (profile.forceUacInjection) {
                Log.i(TAG, "UsbMicBridge: force UAC for profile=${profile.id} device=${device.productName}")
            } else if (halSupportsUsbInput(context)) {
                Log.i(TAG, "UsbMicBridge: HAL exposes USB input; skip UAC injection")
                return mapOf("ok" to false, "reason" to "hal_supports_usb", "skipped" to true)
            }
        } else if (halSupportsUsbInput(context)) {
            Log.i(TAG, "UsbMicBridge: HAL exposes USB input; skip UAC injection")
            return mapOf("ok" to false, "reason" to "hal_supports_usb", "skipped" to true)
        }
        val res = UsbAudioCapture.start(context)
        if (res["ok"] != true) {
            Log.i(TAG, "UsbMicBridge start: capture failed $res")
            return res
        }
        if (injector == null) {
            try {
                // 初期化レースに備えて少し待つ
                var controller = audioController()
                var waited = 0
                while (controller == null && waited < 2000) {
                    Thread.sleep(50)
                    waited += 50
                    controller = audioController()
                }
                if (controller == null) {
                    UsbAudioCapture.stop()
                    return mapOf("ok" to false, "reason" to "webrtc_not_initialized")
                }
                val profile = MicProfiles.select(
                    UsbAudioCapture.vendorId,
                    UsbAudioCapture.productId,
                    UsbAudioCapture.productName
                )
                val inj = UsbMicInjector(profile)
                controller.capturePostProcessing.addProcessor(inj)
                controller.renderPreProcessing.addProcessor(FarEndMonitor)
                injector = inj
                Log.i(TAG, "UsbMicBridge: injector + far-end monitor registered")
            } catch (e: Throwable) {
                Log.e(TAG, "UsbMicBridge: injector registration failed", e)
                UsbAudioCapture.stop()
                return mapOf("ok" to false, "reason" to "register_failed", "error" to e.message)
            }
        }
        // 通話が流れ始める前にUSBバッファを温める（開始直後の無音・途切れ対策）
        val rate = UsbAudioCapture.sampleRate.coerceAtLeast(8000)
        val ch = UsbAudioCapture.channels.coerceAtLeast(1)
        val need = rate * ch * 80 / 1000
        var waitedBuf = 0
        while (UsbAudioCapture.running &&
            UsbAudioCapture.available() < need &&
            waitedBuf < 1200
        ) {
            Thread.sleep(40)
            waitedBuf += 40
        }
        Log.i(
            TAG,
            "UsbMicBridge ready avail=${UsbAudioCapture.available()} need=$need waited=${waitedBuf}ms"
        )
        return res + mapOf(
            "injected" to true,
            "avail" to UsbAudioCapture.available(),
            "warmupMs" to waitedBuf,
        )
    }

    @Synchronized
    fun stop(): Map<String, Any?> {
        try {
            val inj = injector
            if (inj != null) {
                val controller = audioController()
                controller?.capturePostProcessing?.removeProcessor(inj)
                controller?.renderPreProcessing?.removeProcessor(FarEndMonitor)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "UsbMicBridge: injector removal failed", e)
        }
        injector = null
        UsbAudioCapture.stop()
        return mapOf("ok" to true)
    }
}
