import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:amiapp/services/ble_bus.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/ble/checkme_ring_protocol.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/tv_vital_serial.dart';

/// Checkme Ring ハンズフリー測定サービス（Pi版 ble_checkmering.py と同じ流れ）。
///
/// 待機: 定期的にBLEスキャンし、Ringの電波（=指を入れて起きた状態）を探す。
/// 発見: 最も電波の強いRingへ接続し、2秒ごとにリアルタイム値を要求。
/// 測定: 有効値が2回続いたら測定セッション開始（ホームのポップアップが開く）。
///       30秒ごとに spo2_result へPOST（セッション開始時は即時）。
///       セッション終了時に未送信なら最後の有効値を送信する。
/// 終了: 有効値が10秒途切れたら測定終了、切断して待機に戻る。
class CheckmeRingService extends ChangeNotifier {
  CheckmeRingService._();

  static final CheckmeRingService instance = CheckmeRingService._();

  // Pi版と同じ定数
  static const _intervalSeconds = 30; // DB保存間隔
  static const _validResultStreak = 2;
  static const _realtimeTimeoutLimit = 3;
  static const _noFingerTimeoutSeconds = 10;
  static const _idleRecheckSeconds = 5;
  static const _minRssi = -85;
  static const _scanSeconds = 8;
  /// 測定終了(指を外す／データなし)からポップアップを閉じる秒数。Piは30秒、TCLは2分。
  static int get _popupLingerSeconds => AppManager.isPiTvLayout ? 30 : 120;
  /// 指なしのままボタン解除する秒数。Piは30秒、TCLは2分。
  static int get _noFingerDisableSeconds => AppManager.isPiTvLayout ? 30 : 120;

  // ---- 公開状態（ポップアップ用） ----
  bool userEnabled = false;
  bool measuring = false;
  int session = 0;
  int? spo2;
  int? pulse;
  DateTime? lastValidAt;
  int? get pi => _lastPi > 0 ? _lastPi : null;
  DateTime? measureEndedAt;
  String statusText = '停止中';

  bool get popupVisible {
    if (session == 0) return false;
    if (measuring) return true;
    final ended = measureEndedAt;
    if (ended == null) return false;
    return DateTime.now().difference(ended).inSeconds < _popupLingerSeconds;
  }

  // ---- 内部状態 ----
  bool _started = false;
  bool _paused = false; // BLEテスト画面が開いている間は停止
  bool _loopRunning = false;
  bool _permissionReady = false;
  String _serialNo = '';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  bool _writeWithoutResponse = false;
  StreamSubscription<List<int>>? _notifySub;
  final List<int> _buffer = [];
  final _responses = <CheckmeRingPacket>[];
  Completer<void>? _responseArrived;

  DateTime _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _validStreak = 0;
  int _timeoutCount = 0;
  bool _postedThisSession = false;
  int _lastPi = 0;

  Timer? _popupTimer;
  DateTime? _enabledAt;
  int _sessionAtEnable = 0;

  String get serialNo => _serialNo;

  /// TCLアミと同じ。ボタンで有効化してからスキャンする（Piも同じ）。
  bool get _needsButton => true;

  void _log(String line) {
    // ignore: avoid_print
    print('[CheckmeRingSvc] $line');
  }

  void _setStatus(String text) {
    if (statusText == text) return;
    statusText = text;
    notifyListeners();
  }

  /// アプリ起動後（ホーム表示時）に一度呼ぶ。多重呼び出しは無視。
  void start() {
    if (_started) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _started = true;
    _runLoop();
  }

  /// BLEテスト画面用: 手動操作の間サービスを止める。
  Future<void> pause() async {
    _paused = true;
    await _disconnect('テスト画面のため一時停止');
  }

  void resume() {
    _paused = false;
  }

  /// 46amip4 の Ring ボタン。有効中だけスキャン／接続する。
  Future<void> setEnabled(bool on, {bool closePopup = true}) async {
    if (userEnabled == on) {
      notifyListeners();
      return;
    }
    userEnabled = on;
    if (on) {
      _enabledAt = DateTime.now();
      _sessionAtEnable = session;
      spo2 = null;
      pulse = null;
      measureEndedAt = null;
      _postedThisSession = false;
      _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
      _setStatus('Ring待機中');
    } else {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await _disconnect('ボタンで停止', closePopup: closePopup);
      _setStatus('停止中');
    }
    notifyListeners();
  }

  Future<void> _ensurePermissions() async {
    if (_permissionReady) return;
    try {
      // Android 12(SDK31)未満には BLUETOOTH_SCAN/CONNECT が無く、要求すると
      // permission_handler が位置情報の許可を求めてしまう。TVでは位置情報を
      // 使わないので、SDK31未満では要求しない（BLEはマニフェスト宣言で動く）。
      final sdk = await TvUtil.getSdkInt();
      if (sdk >= 31) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
      } else {
        _log('skip BLE permission request (sdk=$sdk)');
      }
    } catch (e) {
      _log('permission request: $e');
    }
    _permissionReady = true;
  }

  Future<void> _runLoop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    _log('service start');

    _serialNo = await TvUtil.getAndroidId();
    _log('androidId=$_serialNo');
    final bound = await TvVitalSerial.instance.resolvePostSerials();
    if (bound.isNotEmpty) {
      _serialNo = bound.first;
    }
    _log('post serials=$bound primary=$_serialNo');

    await _ensurePermissions();

    while (_started) {
      try {
        if (_paused) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if (_needsButton && !userEnabled) {
          _setStatus('停止中');
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        if (_needsButton &&
            userEnabled &&
            _enabledAt != null &&
            session == _sessionAtEnable &&
            DateTime.now().difference(_enabledAt!).inSeconds >=
                _noFingerDisableSeconds) {
          _log('指の検出なしで${_noFingerDisableSeconds}秒経過 → 自動解除');
          await setEnabled(false);
          continue;
        }

        if (await FlutterBluePlus.isSupported == false) {
          _setStatus('BLE非対応');
          await Future<void>.delayed(const Duration(seconds: 60));
          continue;
        }
        final adapter = await FlutterBluePlus.adapterState.first;
        if (adapter != BluetoothAdapterState.on) {
          _setStatus('Bluetoothオフ');
          await Future<void>.delayed(const Duration(seconds: 30));
          continue;
        }

        _setStatus('Ring待機中');
        // BLEアダプタは1本しかない。呼び出しボタンが聞き取りを
        // 続けているので、使う間だけ順番をもらう。返すまでボタンは
        // 待ち、返した瞬間に自分で聞き取りへ戻る。
        await BleBus.instance.take('Ring');
        try {
          final target = await _scanForRing();
          if (_needsButton && !userEnabled) continue;
          if (_paused) continue;
          if (target == null) {
            await Future<void>.delayed(
                const Duration(seconds: _idleRecheckSeconds));
            continue;
          }

          await _monitor(target);
          if (_needsButton &&
              userEnabled &&
              session > _sessionAtEnable) {
            _log('測定終了 → 自動解除');
            await setEnabled(false, closePopup: false);
          }
        } finally {
          await BleBus.instance.give('Ring');
        }
      } catch (e) {
        _log('loop error: $e');
        await _disconnect('エラー');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    _loopRunning = false;
  }

  /// Ringをスキャンし、最も電波の強い1台を返す（見つからなければnull）。
  Future<ScanResult?> _scanForRing() async {
    ScanResult? best;
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          final uuids = r.advertisementData.serviceUuids
              .map((u) => u.str.toLowerCase());
          final isRing = CheckmeRingProtocol.isRingName(name) ||
              uuids.any(CheckmeRingProtocol.isRingServiceUuid);
          if (!isRing || r.rssi < _minRssi) continue;
          if (name.toLowerCase().contains('checkadv') ||
              name.toLowerCase().contains('checkme pro')) {
            continue;
          }
          if (best == null || r.rssi > best!.rssi) best = r;
        }
      });
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: _scanSeconds),
        androidUsesFineLocation: false,
      );
      // Ringが見つかったら早めに切り上げる
      final deadline = DateTime.now().add(const Duration(seconds: _scanSeconds));
      while (DateTime.now().isBefore(deadline)) {
        if (best != null) break;
        if (_paused || !_started) break;
        if (_needsButton && !userEnabled) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _log('scan error: $e');
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    } finally {
      await sub?.cancel();
    }
    if (best != null) {
      final name = best!.advertisementData.advName.isNotEmpty
          ? best!.advertisementData.advName
          : best!.device.platformName;
      _log('found $name rssi=${best!.rssi}');
    }
    return best;
  }

  /// 接続してリアルタイム監視。切断・指抜けで戻る。
  Future<void> _monitor(ScanResult target) async {
    final name = target.advertisementData.advName.isNotEmpty
        ? target.advertisementData.advName
        : target.device.platformName;
    _setStatus('接続中 $name');
    _log('connect $name ${target.device.remoteId.str}');

    final device = target.device;
    _device = device;
    _buffer.clear();
    _responses.clear();
    _validStreak = 0;
    _timeoutCount = 0;

    try {
      await device.connect(
          timeout: const Duration(seconds: 20), autoConnect: false);
      final services = await device.discoverServices();
      BluetoothCharacteristic? readChar;
      BluetoothCharacteristic? writeChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == CheckmeRingProtocol.readUuid) readChar = c;
          if (uuid == CheckmeRingProtocol.writeUuid) writeChar = c;
        }
      }
      if (readChar == null || writeChar == null) {
        throw StateError('Ring GATT characteristics not found');
      }
      _writeChar = writeChar;
      _writeWithoutResponse = writeChar.properties.writeWithoutResponse &&
          !writeChar.properties.write;

      await readChar.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = readChar.onValueReceived.listen(_onNotify);

      _setStatus('接続済み $name');

      try {
        await _write(CheckmeRingProtocol.buildSetTimeCommand());
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _log('set time skipped: $e');
      }

      var lastValid = DateTime.now();

      while (_started && !_paused && device.isConnected) {
        if (_needsButton && !userEnabled) break;
        _responses.clear();
        try {
          await _write(CheckmeRingProtocol.buildGetRtDataCommand());
        } catch (e) {
          _log('rt request error: $e');
          break;
        }

        final packet = await _waitRealtimeResponse(
            timeout: const Duration(seconds: 2));

        if (packet == null) {
          _timeoutCount++;
          _validStreak = 0;
          if (_timeoutCount >= _realtimeTimeoutLimit) {
            _log('reconnect by rt timeout');
            break;
          }
        } else {
          _timeoutCount = 0;
          CheckmeRingRealtime? result;
          try {
            result = CheckmeRingProtocol.parseRealtimeData(packet.payload);
          } catch (e) {
            _log('$e');
            _validStreak = 0;
          }
          if (result != null) {
            if (result.isValid) {
              _validStreak++;
              if (_validStreak >= _validResultStreak) {
                lastValid = DateTime.now();
                _onValidData(result);
              }
            } else {
              _validStreak = 0;
            }
          }
        }

        // 指なし判定: 有効値が途切れたら測定終了→切断→待機
        if (DateTime.now().difference(lastValid).inSeconds >=
            _noFingerTimeoutSeconds) {
          _log('session $session end (no valid data)');
          break;
        }

        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      _log('monitor error: $e');
    } finally {
      await _disconnect('待機に戻る');
    }
  }

  void _onValidData(CheckmeRingRealtime result) {
    spo2 = result.spo2;
    pulse = result.pulse;
    _lastPi = result.pi;
    lastValidAt = DateTime.now();
    if (!measuring) {
      measuring = true;
      session++;
      measureEndedAt = null;
      _postedThisSession = false;
      _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
      _log('session $session start');
    }
    _setStatus('測定中 SpO2 ${result.spo2} / 脈拍 ${result.pulse}');
    notifyListeners();

    final now = DateTime.now();
    if (!_postedThisSession ||
        now.difference(_lastPostAt).inSeconds >= _intervalSeconds) {
      _lastPostAt = now;
      _postedThisSession = true;
      _postSpo2(result.spo2, result.pulse, result.pi);
    }
  }

  Future<void> _postSpo2(int spo2, int pulse, int pi) async {
    final sns = await TvVitalSerial.instance.resolvePostSerials();
    if (sns.isEmpty) {
      _log('post skipped: serial empty');
      return;
    }
    for (final sn in sns) {
      final body = {
        'sn': sn,
        'result1': '$spo2',
        'result2': '$pulse',
        'result3': '$pi',
      };
      _log('post $body');
      try {
        final dio = Dio();
        final res = await dio.post(
          '${AppDefine.baseURL}app/spo2_result',
          data: body,
          options: Options(
            contentType: Headers.jsonContentType,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        _log('post response: ${res.statusCode} ${res.data}');
      } catch (e) {
        _log('post error: $e');
      }
    }
  }

  void _onNotify(List<int> data) {
    _buffer.addAll(data);
    while (true) {
      CheckmeRingPacket? packet;
      try {
        packet = CheckmeRingProtocol.popResponse(_buffer);
      } catch (e) {
        _log('$e');
        continue;
      }
      if (packet == null) break;
      if (packet.header == 0xA5 &&
          packet.cmd != CheckmeRingProtocol.cmdGetRtData) {
        continue;
      }
      _responses.add(packet);
      _responseArrived?.complete();
      _responseArrived = null;
    }
  }

  Future<CheckmeRingPacket?> _waitRealtimeResponse(
      {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_responses.isNotEmpty) {
        return _responses.removeAt(0);
      }
      final completer = Completer<void>();
      _responseArrived = completer;
      final remain = deadline.difference(DateTime.now());
      if (remain.isNegative) break;
      try {
        await completer.future.timeout(remain);
      } on TimeoutException {
        _responseArrived = null;
        break;
      }
    }
    return _responses.isNotEmpty ? _responses.removeAt(0) : null;
  }

  Future<void> _write(List<int> bytes) async {
    final c = _writeChar;
    if (c == null) throw StateError('not connected');
    await c.write(bytes, withoutResponse: _writeWithoutResponse);
  }

  Future<void> _disconnect(String reason, {bool closePopup = false}) async {
    if (!_postedThisSession && spo2 != null && pulse != null) {
      _log('flush last values before disconnect ($reason)');
      _postedThisSession = true;
      await _postSpo2(spo2!, pulse!, _lastPi);
    }
    if (closePopup) {
      measuring = false;
      measureEndedAt = null;
      session = 0;
      spo2 = null;
      pulse = null;
      _popupTimer?.cancel();
      notifyListeners();
    } else if (measuring) {
      measuring = false;
      measureEndedAt = DateTime.now();
      // ポップアップの残り時間経過後に消すための再描画
      _popupTimer?.cancel();
      _popupTimer = Timer(
        Duration(seconds: _popupLingerSeconds + 1),
        notifyListeners,
      );
      notifyListeners();
    }
    await _notifySub?.cancel();
    _notifySub = null;
    _writeChar = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
      _log('disconnect: $reason');
    }
    _setStatus('Ring待機中');
  }
}
