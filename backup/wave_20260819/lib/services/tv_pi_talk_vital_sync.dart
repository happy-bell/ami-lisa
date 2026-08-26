import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/ble_exclusive.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:amiapp/services/tv_pi_checkme_share.dart';
import 'package:amiapp/services/tv_pi_vitals.dart';

/// ラズパイ版の通話中バイタル共有（46amip4 spo2share / checkmeshare / ringctl）。
class TvPiTalkVitalSync extends ChangeNotifier {
  TvPiTalkVitalSync._();
  static final TvPiTalkVitalSync instance = TvPiTalkVitalSync._();

  TvPiVitalValues vitals = TvPiVitalValues();
  String displayName = '';
  bool remoteRingOn = false;
  int? remoteSpo2;
  int? remotePr;
  DateTime? lastSpo2ShareAt;

  bool _running = false;
  bool _applyingRemote = false;
  Timer? _vitalTimer;
  Timer? _shareTimer;
  final _socket = SocketIOService();

  bool get receivingSpo2Share {
    final t = lastSpo2ShareAt;
    if (t == null) return false;
    return DateTime.now().difference(t).inSeconds < 20;
  }

  bool get ringButtonOn =>
      CheckmeRingService.instance.userEnabled ||
      remoteRingOn ||
      receivingSpo2Share;

  bool get checkmeButtonOn =>
      CheckmeProService.instance.userEnabled ||
      CheckmeShareView.instance.active;

  bool get spo2PopupVisible {
    if (receivingSpo2Share) return true;
    if (CheckmeRingService.instance.userEnabled) return true;
    return CheckmeRingService.instance.popupVisible;
  }

  String get spo2Text {
    if (receivingSpo2Share) return remoteSpo2?.toString() ?? '-';
    return CheckmeRingService.instance.spo2?.toString() ?? '-';
  }

  String get prText {
    if (receivingSpo2Share) return remotePr?.toString() ?? '-';
    return CheckmeRingService.instance.pulse?.toString() ?? '-';
  }

  void start() {
    if (!AppManager.isPiTvLayout) return;
    if (!_running) {
      _running = true;
      CheckmeRingService.instance.addListener(_onLocal);
      CheckmeProService.instance.addListener(_onLocal);
      CheckmeShareView.instance.addListener(_onLocal);
      _vitalTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshVitals(),
      );
      _shareTimer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => _sendShares(),
      );
    }
    _refreshVitals();
    _kickShares();
    notifyListeners();
  }

  void stop() {
    _running = false;
    _vitalTimer?.cancel();
    _shareTimer?.cancel();
    _vitalTimer = null;
    _shareTimer = null;
    CheckmeRingService.instance.removeListener(_onLocal);
    CheckmeProService.instance.removeListener(_onLocal);
    CheckmeShareView.instance.removeListener(_onLocal);
    CheckmeShareView.instance.clear();
    remoteRingOn = false;
    remoteSpo2 = null;
    remotePr = null;
    lastSpo2ShareAt = null;
    notifyListeners();
  }

  void _onLocal() {
    notifyListeners();
  }

  Future<void> _refreshVitals() async {
    if (!_running) return;
    final doctor = AppManager.isDoctorMode;
    final peerId = AppManager.talkId1;
    if (doctor && peerId.isEmpty) {
      vitals = TvPiVitalValues();
      displayName = '';
      notifyListeners();
      return;
    }
    final udid = doctor ? peerId : AppManager.myId;
    final values = await TvPiVitals.instance.fetch(udid: udid);
    if (!_running) return;
    values.applyLiveAndKeep(vitals);
    vitals = values;
    if (doctor) {
      final peerName = (AppManager.selectUser?.name ?? '').trim();
      displayName = values.name.isNotEmpty
          ? values.name
          : (peerName.isNotEmpty ? peerName : '患者');
    } else {
      final mine = (AppManager.settings['MCSNAME'] ?? '').toString().trim();
      displayName = mine.isNotEmpty ? mine : AppManager.myId;
    }
    notifyListeners();
  }

  void _emit(Map<String, dynamic> payload) {
    final to = AppManager.talkId1;
    if (to.isEmpty) return;
    try {
      payload['to'] = to;
      _socket.io.emit('talk', [payload]);
    } catch (e) {
      print('[TvPiTalkVital] emit $e');
    }
  }

  void _kickShares() {
    _sendShares();
    Timer(const Duration(milliseconds: 500), () {
      if (_running) _sendShares();
    });
  }

  void _sendShares() {
    if (!_running || _applyingRemote) return;
    if (AppManager.talkId1.isEmpty) return;

    final ring = CheckmeRingService.instance;
    if (ring.measuring && ring.spo2 != null && !receivingSpo2Share) {
      _emit({
        'id2': 'spo2share',
        'spo2': '${ring.spo2}',
        'pr': '${ring.pulse ?? ''}',
        'session': '${ring.session}',
      });
    }

    final pro = CheckmeProService.instance;
    // 自分が測定中なら受信共有の recent でも送り続ける（エコーで止まらない）。
    if (pro.userEnabled) {
      _emit({
        'id2': 'checkmeshare',
        'hr': '${pro.hr ?? ''}',
        'spo2': '${pro.spo2 ?? ''}',
        'pr': '${pro.pr ?? ''}',
        'pi': '${pro.pi ?? ''}',
        'session': '${pro.session}',
        'ecg': _shareWave(pro.ecg),
        'pleth': _shareWave(pro.pleth),
      });
    }
  }

  List<int> _tail(List<int> data, int keep) {
    if (data.length <= keep) return List<int>.from(data);
    return data.sublist(data.length - keep);
  }

  /// Chromium checkme_monitor.php と同じ間引き。JSON配列として送る。
  List<dynamic> _shareWave(List<int> data) {
    final keep = _tail(data, 1000);
    final decimated = <int>[];
    for (var i = 0; i < keep.length; i += 2) {
      decimated.add(keep[i]);
    }
    return jsonDecode(jsonEncode(decimated)) as List<dynamic>;
  }

  Future<void> onRingPressed() async {
    if (_applyingRemote) return;
    final wantStop = ringButtonOn || CheckmeRingService.instance.popupVisible;
    if (wantStop) {
      if (CheckmeRingService.instance.userEnabled) {
        await BleExclusive.toggleRing();
      }
      remoteRingOn = false;
      lastSpo2ShareAt = null;
      remoteSpo2 = null;
      remotePr = null;
      _emit({'id2': 'ringctl', 'action': 'stop'});
    } else {
      await BleExclusive.toggleRing();
      _emit({'id2': 'ringctl', 'action': 'start'});
    }
    notifyListeners();
  }

  Future<void> onCheckmePressed() async {
    if (_applyingRemote) return;
    final wantStop = checkmeButtonOn;
    if (wantStop) {
      if (CheckmeProService.instance.userEnabled) {
        await BleExclusive.togglePro();
      }
      CheckmeShareView.instance.clear();
      _emit({'id2': 'checkmectl', 'action': 'stop'});
      _emit({'id2': 'checkmeshare', 'closed': '1'});
    } else {
      CheckmeShareView.instance.clear();
      await BleExclusive.togglePro();
      _emit({'id2': 'checkmectl', 'action': 'start'});
      _kickShares();
    }
    notifyListeners();
  }

  Future<void> handleTalk(dynamic info) async {
    if (!AppManager.isPiTvLayout || info is! Map) return;
    final id2 = info['id2']?.toString() ?? '';
    if (id2 == 'spo2share') {
      lastSpo2ShareAt = DateTime.now();
      remoteRingOn = true;
      remoteSpo2 = _toInt(info['spo2']);
      remotePr = _toInt(info['pr']);
      notifyListeners();
      return;
    }
    if (id2 == 'checkmeshare') {
      if (info['closed']?.toString() == '1') {
        await _applyCheckme(false, relay: false);
        return;
      }
      if (CheckmeProService.instance.userEnabled) {
        return;
      }
      CheckmeShareView.instance.apply(
        hr: _toInt(info['hr']),
        spo2: _toInt(info['spo2']),
        pr: _toInt(info['pr']),
        pi: _toDouble(info['pi']),
        ecg: _toIntList(info['ecg']),
        pleth: _toIntList(info['pleth']),
      );
      notifyListeners();
      return;
    }
    if (id2 == 'checkmeclose') {
      await _applyCheckme(false, relay: false);
      return;
    }
    if (id2 == 'ringctl') {
      final action = info['action']?.toString();
      if (action == 'start') {
        await _applyRing(true);
      } else if (action == 'stop') {
        await _applyRing(false);
      }
      return;
    }
    if (id2 == 'checkmectl') {
      final action = info['action']?.toString();
      if (action == 'start') {
        await _applyCheckme(true, relay: false);
      } else if (action == 'stop') {
        await _applyCheckme(false, relay: false);
      }
    }
  }

  Future<void> _applyRing(bool on) async {
    _applyingRemote = true;
    try {
      final enabled = CheckmeRingService.instance.userEnabled;
      if (on && !enabled) {
        await BleExclusive.toggleRing();
      } else if (!on && enabled) {
        await BleExclusive.toggleRing();
      }
      if (!on) {
        remoteRingOn = false;
        lastSpo2ShareAt = null;
      } else {
        remoteRingOn = true;
      }
    } finally {
      _applyingRemote = false;
      notifyListeners();
    }
  }

  Future<void> _applyCheckme(bool on, {required bool relay}) async {
    _applyingRemote = true;
    try {
      final enabled = CheckmeProService.instance.userEnabled;
      if (on && !enabled) {
        await BleExclusive.togglePro();
      } else if (!on && enabled) {
        await BleExclusive.togglePro();
      }
      if (!on) {
        CheckmeShareView.instance.clear();
      }
    } finally {
      _applyingRemote = false;
      notifyListeners();
    }
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  List<int>? _toIntList(dynamic v) {
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is Map) {
      final keys = v.keys
          .map((k) => int.tryParse(k.toString()))
          .whereType<int>()
          .toList()
        ..sort();
      final out = <int>[];
      for (final k in keys) {
        final n = int.tryParse(v[k]?.toString() ?? v['$k']?.toString() ?? '');
        if (n != null) out.add(n);
      }
      return out;
    }
    if (v is! List) return null;
    final out = <int>[];
    for (final item in v) {
      final n = int.tryParse(item.toString());
      if (n != null) out.add(n);
    }
    return out;
  }
}
