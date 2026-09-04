import 'dart:async';
import 'dart:io';
import 'package:amiapp/services/appmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google TV / Android TV 向けの端末判定とキャッシュ。
class TvUtil {
  TvUtil._();

  static const MethodChannel _channel = MethodChannel('jp.amiplus.lisa/tv');

  static bool _resolved = false;
  static bool _isTelevision = false;
  static bool _navSoundAttached = false;
  static FocusNode? _lastNavFocus;
  static DateTime? _lastNavAt;
  static bool _navMuted = false;
  static Timer? _navMuteTimer;
  static DateTime? _navQuietUntil;

  /// [init] 後に同期参照できる。未初期化時は false。
  static bool get isTelevision => _isTelevision;

  static bool get isTvLayout => _isTelevision;

  static Future<bool> init() async {
    if (_resolved) return _isTelevision;
    if (kIsWeb || !Platform.isAndroid) {
      _resolved = true;
      _isTelevision = false;
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isTelevision');
      _isTelevision = result == true;
    } catch (e) {
      debugPrint('TvUtil.init failed: $e');
      _isTelevision = false;
    }
    _resolved = true;
    debugPrint('TvUtil.isTelevision=$_isTelevision');
    attachFocusNavSound();

    // USBカメラマイクは VOICE_COMMUNICATION 経路だと無音になりやすい。
    // TVでは MIC + media 設定で初期化し、後で Helper.selectAudioInput(USB) する。
    if (_isTelevision) {
      try {
        await WebRTC.initialize(options: {
          'bypassVoiceProcessing': true,
          'androidAudioConfiguration': AndroidAudioConfiguration(
            manageAudioFocus: true,
            androidAudioMode: AndroidAudioMode.normal,
            androidAudioFocusMode: AndroidAudioFocusMode.gain,
            androidAudioStreamType: AndroidAudioStreamType.music,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.media,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.speech,
            forceHandleAudioRouting: true,
          ).toMap(),
        });
        debugPrint('TvUtil: WebRTC initialized for USB mic (MIC/media)');
      } catch (e) {
        debugPrint('TvUtil: WebRTC.initialize failed: $e');
      }
    }
    return _isTelevision;
  }

  /// WebRTC が開ける内蔵マイク。UAC 占有中に USB を指定すると AudioRecord が失敗する。
  static Future<String?> findBuiltinMicDeviceId() async {
    try {
      final raw = await _channel.invokeMethod('listAudioInputs');
      if (raw is! List) return null;
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (map['isSource'] != true) continue;
        if ((map['type'] as int? ?? -1) != 15) continue;
        final id = map['webrtcDeviceId']?.toString() ?? map['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (e) {
      debugPrint('findBuiltinMicDeviceId failed: $e');
    }
    return null;
  }

  /// ネイティブの入力一覧から USB マイクの WebRTC deviceId を返す。
  static Future<String?> findUsbAudioDeviceId() async {
    try {
      final raw = await _channel.invokeMethod('listAudioInputs');
      if (raw is! List) return null;
      String? usbId;
      String? anyId;
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = map['type'] as int? ?? -1;
        final id = map['webrtcDeviceId']?.toString() ?? map['id']?.toString();
        final name = (map['productName']?.toString() ?? '').toLowerCase();
        final isSource = map['isSource'] == true;
        if (id == null || id.isEmpty || !isSource) continue;
        anyId ??= id;
        // AudioDeviceInfo: USB_DEVICE=11, USB_ACCESSORY=12, USB_HEADSET=22
        final isUsb = type == 11 || type == 12 || type == 22;
        final looksUsb = name.contains('usb') ||
            name.contains('camera') ||
            name.contains('webcam') ||
            name.contains('sonix') ||
            name.contains('uac') ||
            name.contains('emeet') ||
            name.contains('smartcam') ||
            name.contains('c270') ||
            name.contains('logitech') ||
            name.contains('logicool') ||
            name.contains('tzz') ||
            name.contains('buffalo') ||
            name.contains('bsw');
        if (isUsb || looksUsb) {
          usbId = id;
          if (isUsb) break;
        }
      }
      return usbId ?? anyId;
    } catch (e) {
      debugPrint('findUsbAudioDeviceId failed: $e');
      return null;
    }
  }

  /// EMEET の UVC 電源周波数を 60Hz にする（照明フリッカー／波うち対策）。
  static Future<Map<String, dynamic>?> setUvcAntiFlicker60() async {
    if (!_isTelevision) return null;
    try {
      final raw = await _channel.invokeMethod('setUvcAntiFlicker60');
      debugPrint('setUvcAntiFlicker60: $raw');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setUvcAntiFlicker60 failed: $e');
    }
    return null;
  }

  /// USBカメラ（Camera2 または UVC / 既知機種）が挿さっているか。
  /// Wi‑Fiドングルだけのときは false。
  static Future<bool> hasUsbCamera() async {
    if (!_isTelevision) return true;
    try {
      final raw = await _channel.invokeMethod('hasUsbCamera');
      return raw == true;
    } catch (e) {
      debugPrint('hasUsbCamera failed: $e');
      return true;
    }
  }

  /// 接続中USBカメラのプロファイル (c270n / emeet / tzz / usb20a / usb20b / tcl_usb / generic)。
  static Future<Map<String, dynamic>?> getUsbCameraProfile() async {
    if (!_isTelevision) return null;
    try {
      final raw = await _channel.invokeMethod('getUsbCameraProfile');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('getUsbCameraProfile failed: $e');
    }
    return null;
  }

  // ---- USBマイク直接キャプチャ (TCL等HAL非対応TV向け) ----

  /// UAC直接キャプチャ+WebRTC注入を開始。通話セットアップ後に呼ぶ。
  static Future<Map<String, dynamic>?> usbMicStart() async {
    if (!_isTelevision) return null;
    try {
      final raw = await _channel.invokeMethod('usbUacStart');
      debugPrint('usbMicStart: $raw');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('usbMicStart failed: $e');
    }
    return null;
  }

  static Future<void> usbMicStop() async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('usbUacStop');
    } catch (e) {
      debugPrint('usbMicStop failed: $e');
    }
  }

  /// 検証用: UACキャプチャで数秒PCMを取得しレベルを返す。
  static Future<Map<String, dynamic>?> usbMicProbe() async {
    if (!_isTelevision) return null;
    try {
      final raw = await _channel.invokeMethod('usbUacProbe');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('usbMicProbe failed: $e');
    }
    return null;
  }

  // ---- 着信待機 / オーバーレイ ----

  static Future<bool> canDrawOverlays() async {
    if (!_isTelevision) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> requestOverlayPermission() async {
    try {
      final raw = await _channel.invokeMethod('requestOverlayPermission');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('requestOverlayPermission failed: $e');
    }
    return {'granted': false, 'needAdb': true};
  }

  /// Google TV（ami-LiSA / ami-EX）は着信待機を常時ON。スタッフ端末は対象外。
  static bool get isTclCallWaitingAlwaysOn {
    if (!_isTelevision) return false;
    if ((AppManager.settings['MCSTYPE'] ?? '').toString() == '5') {
      return false;
    }
    return true;
  }

  static bool get isCallWaitingEnabled {
    if (isTclCallWaitingAlwaysOn) return true;
    return AppManager.appsettings['TV_CALL_WAITING'] == '1';
  }

  /// 起動時に着信待機を有効化し、未許可ならオーバーレイ権限を一度だけ求める。
  static Future<void> ensureTclCallWaiting() async {
    if (!isTclCallWaitingAlwaysOn) return;
    await AppManager.saveAppSetting('TV_CALL_WAITING', '1');
    final can = await canDrawOverlays();
    if (!can) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('tv_overlay_permission_asked') != true) {
        await prefs.setBool('tv_overlay_permission_asked', true);
        await requestOverlayPermission();
      }
    }
    await startCallWaiting();
  }

  /// リモコンでフォーカスが移ったときにシステム移動音を鳴らす。
  static void attachFocusNavSound() {
    if (!_isTelevision || _navSoundAttached) return;
    _navSoundAttached = true;
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }

  /// 設定などから戻るあいだは移動音を止める。ホームへフォーカスしてから [unmuteNavSound] する。
  static void muteNavSound() {
    if (!_isTelevision) return;
    _navMuted = true;
    _navMuteTimer?.cancel();
    _navMuteTimer = Timer(const Duration(milliseconds: 1500), () {
      _navMuted = false;
      _navMuteTimer = null;
    });
  }

  static void unmuteNavSound({bool playOnce = false}) {
    if (!_isTelevision) return;
    _navMuteTimer?.cancel();
    _navMuteTimer = null;
    final wasMuted = _navMuted;
    _navMuted = false;
    _navQuietUntil =
        DateTime.now().add(const Duration(milliseconds: 700));
    if (playOnce && wasMuted) {
      _lastNavAt = DateTime.now();
      playNavClick();
    }
  }

  /// 設定などから戻るときのフォーカス復旧は、移動音を止めてから呼び側が1回だけ鳴らす。
  static void markRouteFocusSettle() {
    muteNavSound();
  }

  static void _onPrimaryFocusChanged() {
    if (!_isTelevision) return;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return;
    if (identical(node, _lastNavFocus)) return;
    final prev = _lastNavFocus;
    _lastNavFocus = node;
    if (_navMuted) return;
    if (_navQuietUntil != null &&
        DateTime.now().isBefore(_navQuietUntil!)) {
      return;
    }
    if (prev == null) return;
    final now = DateTime.now();
    if (_lastNavAt != null &&
        now.difference(_lastNavAt!) < const Duration(milliseconds: 40)) {
      return;
    }
    _lastNavAt = now;
    playNavClick();
  }

  static void playNavClick() {
    if (!_isTelevision) return;
    try {
      _channel.invokeMethod('playNavClick');
    } catch (e) {
      debugPrint('playNavClick failed: $e');
    }
  }

  static Future<void> startCallWaiting() async {
    if (!_isTelevision) return;
    await _channel.invokeMethod('startCallWaiting', {
      'piLayout': AppManager.isPiTvLayout,
    });
  }

  static Future<void> stopCallWaiting() async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('stopCallWaiting');
    } catch (_) {}
  }

  /// Checkme Ring 等のバイタルPOSTの sn に使う端末固有ID。
  static Future<String> getAndroidId() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('getAndroidId') ?? '';
    } catch (e) {
      debugPrint('getAndroidId failed: $e');
      return '';
    }
  }

  static int _sdkInt = 0;

  /// Android の API レベル。取得できないときは 0。
  /// BLE権限の出し分けに使う（SDK31未満は BLUETOOTH_SCAN が存在せず、
  /// 要求すると位置情報の許可を求められてしまう）。
  static Future<int> getSdkInt() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    if (_sdkInt > 0) return _sdkInt;
    try {
      _sdkInt = await _channel.invokeMethod<int>('getSdkInt') ?? 0;
    } catch (e) {
      debugPrint('getSdkInt failed: $e');
      _sdkInt = 0;
    }
    return _sdkInt;
  }

  static Future<bool> isScreenOn() async {
    if (!_isTelevision) return true;
    try {
      return await _channel.invokeMethod<bool>('isScreenOn') == true;
    } catch (_) {
      return true;
    }
  }

  /// TVが待機（電源オフ／TCLスクリーンレス）かどうか。
  ///
  /// Android 12 の TCL は電源オフでも `isInteractive` が true のままなので、
  /// [isScreenOn] だけでは電源オフ着信を判定できない。ネイティブ側で
  /// sys.tcl.screen / powerstatus と Display.state も見る。
  static Future<bool> isTvStandby() async {
    if (!_isTelevision) return false;
    try {
      return await _channel.invokeMethod<bool>('isTvStandby') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> wakeScreen() async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('wakeScreen');
    } catch (e) {
      debugPrint('wakeScreen failed: $e');
    }
  }

  /// 着信で全面化する前に、地デジ／他アプリを記録する。
  static Future<void> captureForegroundApp() async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('captureForegroundApp');
    } catch (e) {
      debugPrint('captureForegroundApp failed: $e');
    }
  }

  /// 視聴中・スクリーンレス待機のどちらでも着信枠を出し、画面を起こす。
  static Future<void> showIncomingCallOverlay({
    required String callerId,
    String callerName = '着信中',
  }) async {
    if (!_isTelevision) return;
    await captureForegroundApp();
    await wakeScreen();
    await _channel.invokeMethod('showIncomingCallOverlay', {
      'callerId': callerId,
      'callerName': callerName,
    });
  }

  /// 確認なしで画面を点け、全面化して通話開始する（自動応答）。
  static Future<void> acceptIncomingCall({
    required String callerId,
    String callerName = '着信中',
  }) async {
    if (!_isTelevision) return;
    await captureForegroundApp();
    await wakeScreen();
    await _channel.invokeMethod('acceptIncomingCall', {
      'callerId': callerId,
      'callerName': callerName,
    });
  }

  /// 視聴中・待機中にアプリを前面へ出す（確認ダイアログは出さない）。
  static Future<void> bringToFront() async {
    if (!_isTelevision) return;
    await wakeScreen();
    try {
      await _channel.invokeMethod('bringToFront');
    } catch (e) {
      debugPrint('bringToFront failed: $e');
    }
  }

  /// 視聴中・待機中の着信。
  /// ami-EX / ami-LiSA とも自動応答ONなら確認なし。OFFならはい／いいえ。
  static Future<void> handleWatchingIncoming({
    required String callerId,
    String callerName = '着信中',
  }) async {
    if (!_isTelevision) return;
    final auto = AppManager.appsettings['AUTO_RECEIVE'] == '1';
    if (AppManager.isPiTvLayout) {
      if (auto) {
        await acceptIncomingCall(callerId: callerId, callerName: callerName);
      } else {
        await showIncomingCallOverlay(callerId: callerId, callerName: callerName);
      }
      return;
    }
    if (auto) {
      await acceptIncomingCall(callerId: callerId, callerName: callerName);
    } else {
      await showIncomingCallOverlay(callerId: callerId, callerName: callerName);
    }
  }

  /// 着信ごとに、その時点の画面オフ状態を正確に記録する（上書き）。
  /// Socket着信で wake する前に、信頼できる screenOn 値を使って呼ぶこと。
  static Future<void> setScreenOffAtCall(bool wasOff) async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('setScreenOffAtCall', {'wasOff': wasOff});
    } catch (e) {
      debugPrint('setScreenOffAtCall failed: $e');
    }
  }

  /// 着信到達時に画面オフ（TV電源オフ）だったか。
  static Future<bool> wasScreenOffAtCall() async {
    if (!_isTelevision) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('wasScreenOffAtCall');
      return ok == true;
    } catch (e) {
      debugPrint('wasScreenOffAtCall failed: $e');
      return false;
    }
  }

  /// 電源オフ発の着信後、地デジへ戻さず画面をオフへ戻す。
  static Future<bool> lockScreenForStandby() async {
    if (!_isTelevision) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('lockScreenForStandby');
      return ok == true;
    } catch (e) {
      debugPrint('lockScreenForStandby failed: \$e');
      return false;
    }
  }

  /// 見守り終了後。電源オフ発なら電源オフへ、それ以外は直前の視聴アプリへ。
  static Future<void> restoreAfterSafety({required bool toPowerOff}) async {
    if (!_isTelevision) return;
    if (toPowerOff) {
      await setScreenOffAtCall(true);
      await lockScreenForStandby();
      return;
    }
    await returnToPreviousApp();
  }

  /// 視聴中アプリ（Netflix / 地デジ等）へ戻す。記録が無ければ false。
  static Future<bool> returnToPreviousApp() async {
    if (!_isTelevision) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('returnToPreviousApp');
      return ok == true;
    } catch (e) {
      debugPrint('returnToPreviousApp failed: $e');
      return false;
    }
  }

  static Future<void> dismissIncomingCallOverlay() async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('dismissIncomingCallOverlay');
    } catch (_) {}
  }

  /// スマホ切断。着信画面を消し、遅れた「はい」を無効にする。
  static Future<void> cancelIncomingCallOverlay({required String callerId}) async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('cancelIncomingCallOverlay', {
        'callerId': callerId,
      });
    } catch (_) {}
  }

  /// 29秒タイムアウト。電源は切らず、着信あり表示時点の画面へ戻す。
  static Future<void> timeoutIncomingCallOverlay({required String callerId}) async {
    if (!_isTelevision) return;
    try {
      await _channel.invokeMethod('timeoutIncomingCallOverlay', {
        'callerId': callerId,
      });
    } catch (_) {}
  }

  static Future<bool> wasIncomingCancelled(String callerId) async {
    if (!_isTelevision) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('wasIncomingCancelled', {
        'callerId': callerId,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getPendingIncomingCall() async {
    if (!_isTelevision) return null;
    try {
      final raw = await _channel.invokeMethod('getPendingIncomingCall');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('getPendingIncomingCall failed: $e');
    }
    return null;
  }

  static void setIncomingCallHandler(
      Future<void> Function(Map<String, dynamic> data)? handler) {
    if (!_isTelevision) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingCallAction' && handler != null) {
        final args = call.arguments;
        if (args is Map) {
          await handler(Map<String, dynamic>.from(args));
        }
      }
    });
  }
}

/// 遷移アニメなし。pop 開始時点で移動音を止め、ホーム側で1回だけ鳴らす。
class TvInstantRoute<T> extends PageRouteBuilder<T> {
  TvInstantRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );

  @override
  bool didPop(T? result) {
    TvUtil.markRouteFocusSettle();
    return super.didPop(result);
  }
}
