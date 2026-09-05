import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:amiapp/services/ble_bus.dart';
import 'package:amiapp/services/ble_scanner.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/ble/checkme_pro_protocol.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/tv_vital_serial.dart';

/// Checkme Pro のチェックモニター配信を受信する。
/// スタッフでは start しない。Ring と BLE アダプタを排他する。
/// 有効値が3秒安定したら checkme_result へPOST（以降30秒間隔）。
/// セッション終了時に未送信なら最後の有効値を送信する。
class CheckmeProService extends ChangeNotifier {
  CheckmeProService._();
  static final CheckmeProService instance = CheckmeProService._();

  static const _minRssi = -85;
  static const _scanSeconds = 8;
  static const _idleRecheckSeconds = 5;
  static const _idleTimeoutSeconds = 8;
  static const _saveIntervalSeconds = 30;
  static const _stableSeconds = 3;
  static const _popupLingerSeconds = 120;
  static const _noDataCloseSeconds = 60; // 46amip4 NO_DATA_CLOSE_MS
  static const _waveKeep = 125 * 8; // 125Hz × 8秒
  static const _uiIntervalMs = 200;

  bool measuring = false;
  int session = 0;
  int? hr;
  int? spo2;
  int? pr;
  double? pi;
  DateTime? measureEndedAt;
  String statusText = '停止中';
  List<int> ecg = const [];
  List<int> pleth = const [];
  int waveVersion = 0;

  bool get popupVisible {
    if (session == 0) return false;
    if (measuring) return true;
    final ended = measureEndedAt;
    if (ended == null) return false;
    return DateTime.now().difference(ended).inSeconds < _popupLingerSeconds;
  }

  bool _started = false;
  bool _paused = false;
  bool _loopRunning = false;
  bool _permissionReady = false;
  String _serialNo = '';

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notifySub;
  final List<int> _buffer = [];
  Timer? _popupTimer;

  DateTime _lastPacketAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _stableSince;
  DateTime _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool userEnabled = false;
  bool _postedThisSession = false;
  final List<int> _ecgBuf = [];
  final List<int> _plethBuf = [];

  DateTime get lastDataAt => _lastPacketAt;

  int get closeRemainSeconds {
    final left = _noDataCloseSeconds -
        DateTime.now().difference(_lastPacketAt).inSeconds;
    if (left < 0) return 0;
    return left;
  }

  void _log(String line) {
    print('[CheckmeProSvc] $line');
  }

  void _setStatus(String text) {
    if (statusText == text) return;
    statusText = text;
    notifyListeners();
  }

  /// ホームから呼ぶ。有効化は [setEnabled]（Checkmeボタン）。
  void start() {
    if (kIsWeb || !Platform.isAndroid) return;
    _paused = false;
    _started = true;
    _runLoop();
  }

  Future<void> stop() async {
    _started = false;
    await _disconnect('停止');
    _setStatus('停止中');
  }

  Future<void> pause() async {
    _paused = true;
    await _disconnect('テスト画面のため一時停止');
  }

  void resume() {
    _paused = false;
  }

  /// 46amip4 の Checkme ボタン。有効中だけスキャン／接続する。
  Future<void> setEnabled(bool on) async {
    if (userEnabled == on) {
      notifyListeners();
      return;
    }
    userEnabled = on;
    if (on) {
      hr = null;
      spo2 = null;
      pr = null;
      pi = null;
      measureEndedAt = null;
      _clearWaves();
      _lastPacketAt = DateTime.now();
      _stableSince = null;
      _postedThisSession = false;
      _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
      _setStatus('Checkme Pro 待機中');
    } else {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await _disconnect('ボタンで停止', closePopup: true);
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
        if (_paused || !userEnabled) {
          if (!userEnabled) _setStatus('停止中');
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        if (DateTime.now().difference(_lastPacketAt).inSeconds >=
            _noDataCloseSeconds) {
          _log('データなし60秒 → 自動解除');
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

        _setStatus('Checkme Pro 待機中');
        // 探すのは共有スキャンから。見つからない時だけ自前でスキャンする。
        final target = await _scanForPro();
        if (!userEnabled || _paused) continue;
        if (target == null) {
          await Future<void>.delayed(
              const Duration(seconds: _idleRecheckSeconds));
          continue;
        }
        // 測定の間は BLE を占有する。この間ボタンは聞こえない。
        await BleBus.instance.take('CheckmePro');
        try {
          await _monitor(target);
        } finally {
          await BleBus.instance.give('CheckmePro');
        }
      } catch (e) {
        _log('loop error: $e');
        await _disconnect('エラー');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    _loopRunning = false;
    if (_started) _runLoop();
  }

  bool _isPro(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    if (!CheckmeProProtocol.isProName(name)) return false;
    return r.rssi >= _minRssi;
  }

  /// Checkme Pro を探す。共有スキャンから拾えればそれを使い、
  /// 拾えない時だけ自前でスキャンする（保険）。
  ///
  /// Checkme Pro は名前でしか見分けていない。共有スキャンは
  /// サービスUUIDで絞っているため、届くかどうかは実機で確かめる。
  /// どちらで見つかったかを記録に残す。
  Future<ScanResult?> _scanForPro() async {
    if (BleScanner.instance.isRunning) {
      final shared = await _scanForProShared();
      if (shared != null) {
        _log('found via shared scan');
        return shared;
      }
    }
    await BleBus.instance.take('CheckmePro探索');
    try {
      return await _scanForProOwn();
    } finally {
      await BleBus.instance.give('CheckmePro探索');
    }
  }

  /// 1本にまとめたスキャンから拾う。自分ではスキャンを起こさない。
  Future<ScanResult?> _scanForProShared() async {
    ScanResult? best;
    void collect(List<ScanResult> results) {
      for (final r in results) {
        if (!_isPro(r)) continue;
        if (best == null || r.rssi > best!.rssi) best = r;
      }
    }

    collect(BleScanner.instance.latest);
    if (best != null) return best;

    final sub = BleScanner.instance.results.listen(collect);
    try {
      final deadline =
          DateTime.now().add(const Duration(seconds: _scanSeconds));
      while (DateTime.now().isBefore(deadline)) {
        if (best != null) break;
        if (_paused || !_started || !userEnabled) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      await sub.cancel();
    }
    return best;
  }

  /// 自前でスキャンする（保険）。
  Future<ScanResult?> _scanForProOwn() async {
    ScanResult? best;
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (!_isPro(r)) continue;
          if (best == null || r.rssi > best!.rssi) best = r;
        }
      });
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: _scanSeconds),
        androidUsesFineLocation: false,
      );
      final deadline = DateTime.now().add(const Duration(seconds: _scanSeconds));
      while (DateTime.now().isBefore(deadline)) {
        if (best != null) break;
        if (_paused || !_started || !userEnabled) break;
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

  Future<void> _monitor(ScanResult target) async {
    final name = target.advertisementData.advName.isNotEmpty
        ? target.advertisementData.advName
        : target.device.platformName;
    _setStatus('接続中 $name');

    final device = target.device;
    _device = device;
    _buffer.clear();
    _stableSince = null;
    CheckmeProRealtime? latest;

    try {
      await device.connect(
          timeout: const Duration(seconds: 20), autoConnect: false);
      final services = await device.discoverServices();
      BluetoothCharacteristic? readChar;
      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? statusChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == CheckmeProProtocol.readUuid) readChar = c;
          if (uuid == CheckmeProProtocol.writeUuid) writeChar = c;
          if (uuid == CheckmeProProtocol.statusUuid) statusChar = c;
        }
      }
      if (readChar == null || writeChar == null) {
        throw StateError('Checkme Pro GATT characteristics not found');
      }
      final withoutResponse = writeChar.properties.writeWithoutResponse &&
          !writeChar.properties.write;

      await readChar.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = readChar.onValueReceived.listen(_onNotify);
      if (statusChar != null) {
        try {
          await statusChar.setNotifyValue(true);
        } catch (_) {}
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await writeChar.write(
        CheckmeProProtocol.monitorStartCommand,
        withoutResponse: withoutResponse,
      );
      _setStatus('受信中');
      _lastPacketAt = DateTime.now();
      session++;
      measuring = true;
      measureEndedAt = null;
      _clearWaves();
      _postedThisSession = false;
      _stableSince = null;
      _lastPostAt = DateTime.fromMillisecondsSinceEpoch(0);
      notifyListeners();

      while (_started && !_paused && userEnabled && device.isConnected) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final idle = DateTime.now().difference(_lastPacketAt).inSeconds;
        if (idle > _idleTimeoutSeconds) {
          _log('無通信 ${idle}秒 → 切断');
          break;
        }
        latest = CheckmeProRealtime(hr: hr, pr: pr, spo2: spo2, pi: pi);
        await _maybeSave(latest);
      }
    } finally {
      await _disconnect('セッション終了');
    }
  }

  void _onNotify(List<int> data) {
    _buffer.addAll(data);
    var got = false;
    while (true) {
      final packet = CheckmeProProtocol.popPacket(_buffer);
      if (packet == null) break;
      final parsed = CheckmeProProtocol.parsePacket(packet);
      if (parsed == null) continue;
      got = true;
      if (parsed.hr != null) hr = parsed.hr;
      if (parsed.pr != null) pr = parsed.pr;
      if (parsed.spo2 != null) spo2 = parsed.spo2;
      if (parsed.pi != null) pi = parsed.pi;
      _ecgBuf.addAll(parsed.ecgSamples);
      _plethBuf.addAll(parsed.plethSamples);
    }
    if (!got) return;
    _lastPacketAt = DateTime.now();
    final overflow = _ecgBuf.length - _waveKeep;
    if (overflow > 0) {
      _ecgBuf.removeRange(0, overflow);
    }
    final po = _plethBuf.length - _waveKeep;
    if (po > 0) {
      _plethBuf.removeRange(0, po);
    }
    final now = DateTime.now();
    if (now.difference(_lastUiAt).inMilliseconds < _uiIntervalMs) return;
    _lastUiAt = now;
    _publishWaves();
    notifyListeners();
  }

  void _publishWaves() {
    ecg = List<int>.from(_ecgBuf);
    pleth = List<int>.from(_plethBuf);
    waveVersion++;
  }

  void _clearWaves() {
    _ecgBuf.clear();
    _plethBuf.clear();
    ecg = const [];
    pleth = const [];
    waveVersion++;
  }

  Future<void> _maybeSave(CheckmeProRealtime latest) async {
    final valid = latest.isValid;
    if (!valid) {
      _stableSince = null;
      return;
    }
    final now = DateTime.now();
    _stableSince ??= now;
    if (now.difference(_stableSince!).inSeconds < _stableSeconds) return;
    if (now.difference(_lastPostAt).inSeconds < _saveIntervalSeconds &&
        _lastPostAt.millisecondsSinceEpoch > 0) {
      return;
    }
    _lastPostAt = now;
    _postedThisSession = true;
    await _post(latest);
  }

  Future<void> _post(CheckmeProRealtime r) async {
    final sns = await TvVitalSerial.instance.resolvePostSerials();
    if (sns.isEmpty) {
      _log('post skipped: serial empty');
      return;
    }
    for (final sn in sns) {
      final body = {
        'sn': sn,
        'result1': '${r.spo2}',
        'result2': '${r.pr}',
        'result3': '0',
        'result4': '${r.hr}',
        'result5': '${r.pi ?? 0}',
      };
      _log('post $body');
      try {
        final dio = Dio();
        final res = await dio.post(
          '${AppDefine.baseURL}app/checkme_result',
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

  Future<void> _disconnect(String reason, {bool closePopup = false}) async {
    final latest = CheckmeProRealtime(hr: hr, pr: pr, spo2: spo2, pi: pi);
    if (!_postedThisSession && latest.isValid) {
      _log('flush last values before disconnect ($reason)');
      _postedThisSession = true;
      await _post(latest);
    }
    await _notifySub?.cancel();
    _notifySub = null;
    final device = _device;
    _device = null;
    if (closePopup) {
      measuring = false;
      measureEndedAt = null;
      session = 0;
      hr = null;
      spo2 = null;
      pr = null;
      pi = null;
      _clearWaves();
      _popupTimer?.cancel();
      notifyListeners();
    } else if (measuring) {
      measuring = false;
      measureEndedAt = DateTime.now();
      _popupTimer?.cancel();
      _popupTimer = Timer(const Duration(seconds: _popupLingerSeconds), () {
        notifyListeners();
      });
      notifyListeners();
    }
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _log('disconnect: $reason');
  }
}
