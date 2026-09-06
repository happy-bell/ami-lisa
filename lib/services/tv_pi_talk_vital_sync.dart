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
  bool remoteCheckmeOn = false;
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
      remoteCheckmeOn ||
      CheckmeShareView.instance.active;

  /// このボタンが「相手の機器」を操作するか。
  ///
  ///   患者            いつでも自分の機器（ホームでも通話中でも）
  ///   ドクター ホーム  自分の機器（ホームのボタンは room_page が直接扱う）
  ///   ドクター 通話中  相手の機器。自分の機器は動かさない
  ///
  /// 2026-09-06 追加。それまでは押すと自分と相手の両方が動いていた。
  bool get controlsRemote => _running && AppManager.isDoctorMode;

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
    remoteCheckmeOn = false;
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

  /// 5秒分（125Hz）を送り、表示と同じ30%間引き。長すぎると相手側で心拍が詰まる。
  List<dynamic> _shareWave(List<int> data) {
    final keep = _tail(data, 625);
    final out = <int>[];
    for (var i = 0; i < keep.length; i++) {
      if (i % 10 < 7) out.add(keep[i]);
    }
    return jsonDecode(jsonEncode(out)) as List<dynamic>;
  }

  Future<void> onRingPressed() async {
    if (_applyingRemote) return;

    // ドクターが通話中に押したときは、相手の Ring だけを動かす。
    // 自分の Ring には触らない。
    if (controlsRemote) {
      final wantStop = ringButtonOn;
      _emit({'id2': 'ringctl', 'action': wantStop ? 'stop' : 'start'});
      remoteRingOn = !wantStop;
      if (wantStop) {
        lastSpo2ShareAt = null;
        remoteSpo2 = null;
        remotePr = null;
      }
      notifyListeners();
      return;
    }

    // 自分の Ring だけを動かす。相手へは指示を送らない。
    // 測定値は _sendShares が spo2share で流すので、相手には見えている。
    final ring = CheckmeRingService.instance;
    final wantStop = ring.userEnabled || ring.popupVisible;
    if (wantStop) {
      if (ring.userEnabled) {
        await BleExclusive.toggleRing();
      }
      remoteRingOn = false;
      lastSpo2ShareAt = null;
      remoteSpo2 = null;
      remotePr = null;
      _emit({'id2': 'ringstate', 'on': '0'});
    } else {
      await BleExclusive.toggleRing();
      _emit({'id2': 'ringstate', 'on': '1'});
    }
    notifyListeners();
  }

  Future<void> onCheckmePressed() async {
    if (_applyingRemote) return;

    // ドクターが通話中に押したときは、相手の Checkme だけを動かす。
    if (controlsRemote) {
      final wantStop = checkmeButtonOn;
      _emit({'id2': 'checkmectl', 'action': wantStop ? 'stop' : 'start'});
      if (wantStop) {
        CheckmeShareView.instance.clear();
      }
      remoteCheckmeOn = !wantStop;
      notifyListeners();
      return;
    }

    // 自分の Checkme だけを動かす。波形は _sendShares が流す。
    final pro = CheckmeProService.instance;
    final wantStop = pro.userEnabled;
    CheckmeShareView.instance.clear();
    await BleExclusive.togglePro();
    if (wantStop) {
      // 自分が止めたことを相手の表示にも伝える。
      _emit({'id2': 'checkmeshare', 'closed': '1'});
      _emit({'id2': 'checkmestate', 'on': '0'});
    } else {
      _emit({'id2': 'checkmestate', 'on': '1'});
      _kickShares();
    }
    remoteCheckmeOn = false;
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
    // 相手が自分で入切した知らせ。機器は動かさず、ボタンの表示だけ合わせる。
    // これが無いと、相手が自分で止めてもドクターのボタンが「停止」のまま残る。
    if (id2 == 'ringstate') {
      remoteRingOn = info['on']?.toString() == '1';
      if (!remoteRingOn) {
        lastSpo2ShareAt = null;
        remoteSpo2 = null;
        remotePr = null;
      }
      notifyListeners();
      return;
    }
    if (id2 == 'checkmestate') {
      remoteCheckmeOn = info['on']?.toString() == '1';
      if (!remoteCheckmeOn) CheckmeShareView.instance.clear();
      notifyListeners();
      return;
    }
    // 操作の指示。ドクターが通話中に受け取ることは無い（患者は送らない）が、
    // 古い版の相手から届いても自分の機器を動かさないようにしておく。
    if (id2 == 'ringctl' || id2 == 'checkmectl') {
      if (controlsRemote) return;
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
        remoteCheckmeOn = false;
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
