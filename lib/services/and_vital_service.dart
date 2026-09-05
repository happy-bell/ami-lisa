import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/services/ble_bus.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/ble/and_vital_codec.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/services/tv_vital_serial.dart';

export 'package:amiapp/ble/and_vital_codec.dart' show AndVitalKind;

/// A&D 血圧計・体温計・体重計。
/// Ring / Checkme が測定中は BLE を譲る（x-amibl789/ble.py の排他と同じ意図）。
class AndVitalService extends ChangeNotifier {
  AndVitalService._();
  static final AndVitalService instance = AndVitalService._();

  static const _prefsKey = 'and_vital_paired';
  static const _popupLingerSeconds = 120;
  static const _scanSeconds = 12;
  static const _quietTimeout = Duration(seconds: 4);
  static const _firstTimeout = Duration(seconds: 20);

  bool pairing = false;
  String pairStatus = '';
  bool popupVisible = false;

  AndVitalKind lastKind = AndVitalKind.blood;
  int? systolic;
  int? diastolic;
  int? pulse;
  double? temperature;
  double? weightKg;
  DateTime? lastAt;

  String statusText = '待機中';

  bool _started = false;
  bool _loopRunning = false;
  bool _paused = false;
  int _bleHold = 0;
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _indicateSub;

  AndBpReading? _lastBp;
  double? _lastTemp;
  double? _lastWeight;
  DateTime? _lastNotifyAt;
  bool _gotAny = false;

  Timer? _popupTimer;
  String _serialNo = '';

  void _log(String line) {
    // ignore: avoid_print
    print('[AndVital] $line');
  }

  void start() {
    if (_started) return;
    if (kIsWeb || !Platform.isAndroid) return;
    if (!TvUtil.isTelevision) return;
    _started = true;
    _runLoop();
  }

  Future<void> pause() async {
    _paused = true;
    await _disconnect();
  }

  void resume() {
    _paused = false;
  }

  bool get _otherMeasuring {
    final ring = CheckmeRingService.instance;
    final pro = CheckmeProService.instance;
    if (ring.measuring || pro.measuring) return true;
    // ラズパイ版はボタンONの時点でBLEを占有する。待機スキャンで奪わない。
    if (AppManager.isPiTvLayout) {
      return ring.userEnabled || pro.userEnabled;
    }
    return false;
  }

  Future<void> _yieldToOthers() async {
    if (_device != null) {
      await _disconnect();
    }
    while (_bleHold > 0) {
      await _releaseOthers();
    }
  }

  Future<void> _runLoop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    await _ensurePermission();
    while (_started) {
      try {
        if (_paused || pairing || _otherMeasuring) {
          if (_otherMeasuring) {
            await _yieldToOthers();
          }
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        await _scanAndRead();
      } catch (e) {
        _log('loop error: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    _loopRunning = false;
  }

  Future<void> _ensurePermission() async {
    try {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    } catch (_) {}
  }

  Future<List<Map<String, String>>> loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => {
                'id': e['id']?.toString() ?? '',
                'name': e['name']?.toString() ?? '',
              })
          .where((e) => e['id']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePaired(List<Map<String, String>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(items));
  }

  /// ami_blepair.py の「開始」相当。
  Future<Map<String, bool>> pairDevices({
    void Function(String msg)? log,
  }) async {
    void say(String m) {
      pairStatus = m;
      notifyListeners();
      log?.call(m);
      _log(m);
    }

    pairing = true;
    notifyListeners();
    await _holdOthers();
    await _disconnect();
    final results = <String, bool>{};
    try {
      say('スキャン中... 15秒');
      final found = await _scanTargets(const Duration(seconds: 15));
      final paired = await loadPaired();
      final pairedIds = paired.map((e) => e['id']).toSet();

      if (found.isEmpty) {
        say('対象機器が見つかりませんでした');
        return results;
      }

      for (final d in found) {
        final name = _deviceName(d);
        if (pairedIds.contains(d.remoteId.str)) {
          continue;
        }
        say('$name ペアリング中...');
        final ok = await _bondDevice(d);
        results[name] = ok;
        if (ok) {
          paired.add({'id': d.remoteId.str, 'name': name});
          pairedIds.add(d.remoteId.str);
          await _savePaired(paired);
        }
        say('$name: ${ok ? '成功' : '失敗'}');
      }
    } finally {
      pairing = false;
      await _releaseOthers();
      notifyListeners();
    }
    return results;
  }

  /// ami_blepair.py の「初期化」相当。
  Future<void> clearPairing({void Function(String msg)? log}) async {
    pairing = true;
    notifyListeners();
    await _holdOthers();
    await _disconnect();
    try {
      log?.call('初期化中です。しばらくお待ちください');
      final paired = await loadPaired();
      for (final item in paired) {
        try {
          final d = BluetoothDevice.fromId(item['id']!);
          await d.removeBond();
        } catch (e) {
          _log('removeBond failed: $e');
        }
      }
      await _savePaired([]);
      log?.call('初期化しました End');
    } finally {
      pairing = false;
      await _releaseOthers();
      notifyListeners();
    }
  }

  Future<bool> _isBonded(BluetoothDevice d) async {
    try {
      final s = await d.bondState.first.timeout(const Duration(seconds: 3));
      return s == BluetoothBondState.bonded;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _bondDevice(BluetoothDevice d) async {
    try {
      await d.connect(timeout: const Duration(seconds: 20), autoConnect: false);
    } catch (e) {
      _log('connect for pair: $e');
    }
    try {
      if (await _isBonded(d)) {
        try {
          await d.disconnect();
        } catch (_) {}
        return true;
      }
      await d.createBond(timeout: 35);
      final bonded = await _isBonded(d);
      try {
        await d.disconnect();
      } catch (_) {}
      return bonded;
    } catch (e) {
      _log('createBond failed: $e');
      try {
        await d.disconnect();
      } catch (_) {}
      return _isBonded(d);
    }
  }

  Future<List<BluetoothDevice>> _scanTargets(Duration timeout) async {
    final found = <String, BluetoothDevice>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = _advName(r);
          final uuids = r.advertisementData.serviceUuids.map((g) => g.str);
          final hitName = AndVitalCodec.nameMatches(name);
          final hitUuid = uuids.any((u) => AndVitalCodec.kindForService(u) != null);
          if (hitName || hitUuid) {
            found[r.device.remoteId.str] = r.device;
          }
        }
      });
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      await FlutterBluePlus.isScanning.where((v) => v == false).first.timeout(
            timeout + const Duration(seconds: 2),
            onTimeout: () => false,
          );
    } catch (e) {
      _log('scan failed: $e');
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await sub?.cancel();
    }
    return found.values.toList();
  }

  String _advName(ScanResult r) {
    final a = r.advertisementData.advName;
    if (a.isNotEmpty) return a;
    return r.device.platformName;
  }

  String _deviceName(BluetoothDevice d) {
    final n = d.platformName;
    return n.isEmpty ? d.remoteId.str : n;
  }

  Future<void> _holdOthers() async {
    _bleHold++;
    // BLEアダプタは1本しかない。呼び出しボタンにも譲ってもらう。
    await BleBus.instance.take('血圧計');
    if (_bleHold != 1) return;
    await CheckmeRingService.instance.pause();
    await CheckmeProService.instance.pause();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> _releaseOthers() async {
    if (_bleHold > 0) {
      _bleHold--;
      await BleBus.instance.give('血圧計');
    }
    if (_bleHold != 0 || pairing) return;
    CheckmeRingService.instance.resume();
    CheckmeProService.instance.resume();
  }

  Future<void> _scanAndRead() async {
    if (await FlutterBluePlus.isSupported == false) return;
    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) return;

    final paired = await loadPaired();
    if (paired.isEmpty) {
      _setStatus('未ペアリング');
      return;
    }

    _setStatus('血圧計 待機中');
    if (AppManager.isPiTvLayout) {
      if (_otherMeasuring) return;
      // 探索のスキャンから読み取りまで、通して BLE の順番をもらう。
      // ここは Ring/Checkme を止めない（従来どおり）が、呼び出しボタンの
      // 聞き取りとはぶつかるので譲ってもらう必要がある。
      await BleBus.instance.take('血圧計');
      try {
        final pairedIds = paired.map((e) => e['id']).toSet();
        final devices =
            await _scanTargets(const Duration(seconds: _scanSeconds));
        if (devices.isEmpty || _paused || pairing || _otherMeasuring) return;
        BluetoothDevice? target;
        for (final d in devices) {
          if (pairedIds.contains(d.remoteId.str)) {
            target = d;
            break;
          }
        }
        if (target == null) return;
        await _holdOthers();
        try {
          if (_otherMeasuring || _paused || pairing) return;
          await _readFrom(target);
        } finally {
          await _releaseOthers();
        }
      } finally {
        await BleBus.instance.give('血圧計');
      }
      return;
    }
    await _holdOthers();
    try {
      final pairedIds = paired.map((e) => e['id']).toSet();
      final devices = await _scanTargets(const Duration(seconds: _scanSeconds));
      if (devices.isEmpty || _paused || pairing || _otherMeasuring) return;

      BluetoothDevice? target;
      for (final d in devices) {
        if (pairedIds.contains(d.remoteId.str)) {
          target = d;
          break;
        }
      }
      if (target == null) return;
      await _readFrom(target);
    } finally {
      await _releaseOthers();
    }
  }

  Future<void> _readFrom(BluetoothDevice device) async {
    _device = device;
    _lastBp = null;
    _lastTemp = null;
    _lastWeight = null;
    _gotAny = false;
    _lastNotifyAt = null;
    try {
      await device.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );
      final services = await device.discoverServices();
      BluetoothCharacteristic? char;
      AndVitalKind? kind;
      for (final s in services) {
        final found = AndVitalCodec.kindForService(s.uuid.str);
        if (found == null) continue;
        kind = found;
        for (final c in s.characteristics) {
          if (c.properties.indicate || c.properties.notify) {
            char = c;
            break;
          }
        }
        if (char != null) break;
      }
      if (char == null || kind == null) {
        _log('no indicate char');
        return;
      }

      _indicateSub?.cancel();
      _indicateSub = char.onValueReceived.listen((value) {
        _onIndicate(kind!, value);
      });
      await char.setNotifyValue(true);
      try {
        final desc = char.descriptors.where(
          (d) => AndVitalCodec.normalizeUuid(d.uuid.str) == AndVitalCodec.cccd,
        );
        if (desc.isNotEmpty) {
          await desc.first.write([0x02, 0x00]);
        }
      } catch (e) {
        _log('cccd write: $e');
      }

      _setStatus('受信中');
      final start = DateTime.now();
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (_paused || pairing || _otherMeasuring) break;
        final last = _lastNotifyAt;
        if (last != null && DateTime.now().difference(last) > _quietTimeout) {
          if (_gotAny) break;
        }
        if (!_gotAny && DateTime.now().difference(start) > _firstTimeout) {
          break;
        }
      }
      await _postLatest();
    } catch (e) {
      _log('read failed: $e');
    } finally {
      await _disconnect();
    }
  }

  void _onIndicate(AndVitalKind kind, List<int> value) {
    _lastNotifyAt = DateTime.now();
    if (kind == AndVitalKind.blood) {
      final bp = AndVitalCodec.parseBp(value);
      if (bp == null) {
        _log('bp error skip');
        return;
      }
      _lastBp = bp;
      _gotAny = true;
    } else if (kind == AndVitalKind.temp) {
      final t = AndVitalCodec.parseTemp(value);
      if (t == null) {
        _log('temp error skip');
        return;
      }
      _lastTemp = t;
      _gotAny = true;
    } else {
      final w = AndVitalCodec.parseWeight(value);
      if (w == null) {
        _log('weight error skip');
        return;
      }
      _lastWeight = w;
      _gotAny = true;
    }
  }

  Future<void> _postLatest() async {
    if (_serialNo.isEmpty) {
      final sns = await TvVitalSerial.instance.resolvePostSerials();
      _serialNo = sns.isEmpty ? '' : sns.first;
    }
    if (_lastBp != null) {
      final bp = _lastBp!;
      systolic = bp.systolic.round();
      diastolic = bp.diastolic.round();
      pulse = bp.pulse.round();
      lastKind = AndVitalKind.blood;
      lastAt = DateTime.now();
      _showPopup();
      await _post('app/blood_pressure_result', {
        'sn': _serialNo,
        'result1': '${bp.systolic}',
        'result2': '${bp.diastolic}',
        'result3': '${bp.map}',
        'result4': '${bp.pulse}',
        'result5': '${bp.rawLen}',
      });
      return;
    }
    if (_lastTemp != null) {
      temperature = _lastTemp;
      lastKind = AndVitalKind.temp;
      lastAt = DateTime.now();
      _showPopup();
      await _post('app/body_temperature_result', {
        'sn': _serialNo,
        'result1': '$_lastTemp',
      });
      return;
    }
    if (_lastWeight != null) {
      weightKg = _lastWeight;
      lastKind = AndVitalKind.weight;
      lastAt = DateTime.now();
      _showPopup();
      await _post('app/body_weight_result', {
        'sn': _serialNo,
        'result1': '$_lastWeight',
      });
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    if (_serialNo.isEmpty) return;
    try {
      final dio = Dio();
      final res = await dio.post('${AppDefine.baseURL}$path', data: body);
      _log('POST $path ${res.statusCode} $body');
    } catch (e) {
      _log('POST $path failed: $e');
    }
  }

  void _showPopup() {
    popupVisible = true;
    _popupTimer?.cancel();
    _popupTimer = Timer(const Duration(seconds: _popupLingerSeconds), () {
      popupVisible = false;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _disconnect() async {
    await _indicateSub?.cancel();
    _indicateSub = null;
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  void _setStatus(String text) {
    if (statusText == text) return;
    statusText = text;
    notifyListeners();
  }
}
