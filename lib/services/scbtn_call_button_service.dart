import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/ble/scbtn_protocol.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';

/// RS-SCBTN2 の BLE 広告を受け、押下で呼び出しする受け口。
///
/// 登録・削除は Web 管理画面（基本設定 → コールボタン）。
/// アプリは POST `app/lisa/ble/list` で MAC 一覧を読み、載っているものだけ拾う。
class ScbtnCallButtonService extends ChangeNotifier {
  ScbtnCallButtonService._();
  static final ScbtnCallButtonService instance = ScbtnCallButtonService._();

  static const typeButton = 1;
  static const _scanSeconds = 8;
  static const _idleSeconds = 4;
  static const _listInterval = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 8);
  static const _cacheKey = 'ble_call_buttons';

  bool _started = false;
  bool _loopRunning = false;
  int _pressSeq = 0;
  int _consumedSeq = 0;
  DateTime? _lastPressAt;
  DateTime? _lastListAt;
  ScbtnAdvertisement? _lastSeen;
  List<ScbtnRegisteredDevice> _devices = [];
  StreamSubscription<List<ScanResult>>? _sub;

  ScbtnAdvertisement? get lastSeen => _lastSeen;
  List<ScbtnRegisteredDevice> get devices => List.unmodifiable(_devices);

  List<String> get registeredIds => _devices
      .where((d) => d.deviceType == typeButton)
      .map((d) => d.deviceId)
      .toList();

  String get registeredId => registeredIds.isEmpty ? '' : registeredIds.first;

  bool get hasRegistration => registeredIds.isNotEmpty;

  Future<void> start() async {
    if (!TvUtil.isTelevision) return;
    if (_started) return;
    _started = true;
    await _ensurePermissions();
    await _loadCache();
    _sub ??= FlutterBluePlus.scanResults.listen(_onResults);
    unawaited(refreshList());
    unawaited(_loop());
    debugPrint('[SCBTN] start ids=$registeredIds');
  }

  Future<void> _ensurePermissions() async {
    try {
      final sdk = await TvUtil.getSdkInt();
      if (sdk >= 31) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
      }
    } catch (e) {
      debugPrint('[SCBTN] permission: $e');
    }
  }

  Future<void> stop() async {
    _started = false;
    await _sub?.cancel();
    _sub = null;
  }

  bool takePress() {
    if (_pressSeq == _consumedSeq) return false;
    _consumedSeq = _pressSeq;
    return true;
  }

  /// 管理画面で登録したボタン一覧を取り直す。
  Future<bool> refreshList({bool force = false}) async {
    if (!force) {
      final last = _lastListAt;
      if (last != null && DateTime.now().difference(last) < _listInterval) {
        return hasRegistration;
      }
    }
    final auth = _auth();
    if (auth == null) return hasRegistration;
    try {
      final res = await http.post(
        Uri.parse('${AppDefine.baseURL}app/lisa/ble/list'),
        body: auth,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('[SCBTN] list HTTP ${res.statusCode}');
        return hasRegistration;
      }
      final data = json.decode(res.body);
      if (data is! Map || data['status'] != 'ok') {
        debugPrint('[SCBTN] list ng ${data is Map ? data['reason'] : data}');
        return hasRegistration;
      }
      final raw = data['devices'];
      final next = <ScbtnRegisteredDevice>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is! Map) continue;
          final id = (row['device_id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          next.add(ScbtnRegisteredDevice(
            deviceId: id,
            deviceType: (row['device_type'] is int)
                ? row['device_type'] as int
                : int.tryParse('${row['device_type']}') ?? 0,
            name: (row['name'] ?? '').toString(),
          ));
        }
      }
      _devices = next;
      _lastListAt = DateTime.now();
      await _saveCache();
      notifyListeners();
      debugPrint('[SCBTN] list ${next.length} devices');
      return true;
    } catch (e) {
      debugPrint('[SCBTN] list error $e');
      return hasRegistration;
    }
  }

  /// 設定画面用。近くの SCBTN を数秒スキャンして返す。
  Future<List<ScbtnAdvertisement>> scanNearby({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final found = <String, ScbtnAdvertisement>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final adv = _parse(r);
          if (adv == null) continue;
          found[adv.id] = adv;
        }
      });
      try {
        await FlutterBluePlus.startScan(
          timeout: timeout,
          androidUsesFineLocation: false,
        );
      } catch (_) {}
      await Future<void>.delayed(timeout);
    } catch (e) {
      debugPrint('[SCBTN] scanNearby: $e');
    } finally {
      await sub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    return found.values.toList();
  }

  bool isRegistered(ScbtnAdvertisement adv) {
    for (final id in registeredIds) {
      if (ScbtnProtocol.matchesId(id, adv.name, adv.mac)) return true;
    }
    return false;
  }

  Future<void> _loop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    while (_started) {
      try {
        unawaited(refreshList());
        if (await FlutterBluePlus.isSupported == false) {
          await Future<void>.delayed(const Duration(seconds: 10));
          continue;
        }
        final adapter = await FlutterBluePlus.adapterState.first;
        if (adapter != BluetoothAdapterState.on) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        try {
          await FlutterBluePlus.startScan(
            timeout: const Duration(seconds: _scanSeconds),
            androidUsesFineLocation: false,
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: _scanSeconds));
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
      } catch (e) {
        debugPrint('[SCBTN] loop: $e');
      }
      await Future<void>.delayed(const Duration(seconds: _idleSeconds));
    }
    _loopRunning = false;
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final adv = _parse(r);
      if (adv == null) continue;
      _lastSeen = adv;
      if (!adv.pressed) continue;
      if (!isRegistered(adv)) continue;
      final last = _lastPressAt;
      if (last != null && DateTime.now().difference(last) < _cooldown) {
        continue;
      }
      _lastPressAt = DateTime.now();
      _pressSeq++;
      debugPrint('[SCBTN] pressed id=${adv.id} battery=${adv.battery}');
      notifyListeners();
    }
  }

  ScbtnAdvertisement? _parse(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    final mac = r.device.remoteId.str;
    return ScbtnProtocol.parse(
      name: name,
      mac: mac,
      manufacturerData: r.advertisementData.manufacturerData,
    );
  }

  Map<String, String>? _auth() {
    final code = (AppManager.settings['DELEGATORCODE'] ??
            AppManager.delegatorCode)
        .toString();
    final token = (AppManager.settings['api_token'] ?? '').toString();
    if (code.isEmpty || token.isEmpty) return null;
    var mst = AppManager.myId;
    if (mst.startsWith('${code}_')) {
      mst = mst.substring(code.length + 1);
    }
    if (mst.isEmpty) {
      mst = (AppManager.settings['MYID'] ?? '').toString().replaceAll('${code}_', '');
    }
    if (mst.isEmpty) return null;
    return {'code': code, 'mst_id': mst, 'token': token};
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = json.decode(raw);
      if (list is! List) return;
      final next = <ScbtnRegisteredDevice>[];
      for (final row in list) {
        if (row is! Map) continue;
        next.add(ScbtnRegisteredDevice(
          deviceId: (row['device_id'] ?? '').toString(),
          deviceType: (row['device_type'] as int?) ?? 0,
          name: (row['name'] ?? '').toString(),
        ));
      }
      _devices = next;
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        json.encode(_devices.map((d) => d.toJson()).toList()),
      );
    } catch (_) {}
  }
}

class ScbtnRegisteredDevice {
  const ScbtnRegisteredDevice({
    required this.deviceId,
    required this.deviceType,
    required this.name,
  });

  final String deviceId;
  final int deviceType;
  final String name;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_type': deviceType,
        'name': name,
      };
}
