import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';

/// ラズパイ版だけ使う健康管理（お薬・体調・デイサービス）。
/// TCLアミ／スタッフには呼ばないこと。
class TvHealthState {
  bool showMedical = false;
  int medicalTime = 0;
  bool showHealth = false;
  int healthTime = 0;
  bool showDayService = false;
  bool showDayServiceCheck = false;
  int dayServiceTime = 0;
  String dayServiceText = '';

  bool get hasAny => showMedical || showHealth || showDayService;

  String get signature =>
      '$showHealth:$healthTime|$showMedical:$medicalTime|$showDayService:$dayServiceTime';
}

class TvHealthNotify {
  TvHealthNotify._();
  static final TvHealthNotify instance = TvHealthNotify._();

  /// 46amip4 `health.php` / `get_notify.php` と同じ `api/info`。
  /// 写真取得と同じ応答の `notify` を読む。
  Future<TvHealthState> fetch() async {
    final state = TvHealthState();
    final ids = _mstIds();
    if (AppManager.delegatorCode.isEmpty || ids.isEmpty) {
      print('[TvHealth] skip empty id code=${AppManager.delegatorCode} myId=${AppManager.myId}');
      return state;
    }
    for (final mstId in ids) {
      final url =
          '${AppDefine.baseURL}api/info?code=${AppManager.delegatorCode}&mst_id=$mstId&notify=1';
      try {
        final response = await http.get(Uri.parse(url));
        print('[TvHealth] ${response.statusCode} $url');
        if (response.statusCode != 200) continue;
        final applied = await applyResponse(response.body);
        print(
            '[TvHealth] health=${applied.showHealth} medical=${applied.showMedical} day=${applied.showDayService} text=${applied.dayServiceText}');
        if (applied.hasAny || _hasNotifyObject(response.body)) {
          return applied;
        }
      } catch (e) {
        print('[TvHealth] fetch error $e');
      }
    }
    return state;
  }

  Future<TvHealthState> applyResponse(dynamic raw) async {
    final data = _asMap(_maybeDecode(raw));
    if (data == null) return TvHealthState();
    final notify = data['notify'] ??
        ((data.containsKey('health') ||
                data.containsKey('medical') ||
                data.containsKey('dayService'))
            ? data
            : null);
    return applyNotify(notify);
  }

  Future<TvHealthState> applyNotify(dynamic raw) async {
    final state = TvHealthState();
    final notify = _asMap(raw);
    if (notify == null) return state;
    await _apply(state, notify);
    return state;
  }

  Future<void> send(String type, String time, String value) async {
    final url = '${AppDefine.baseURL}api/result';
    final mstId = _mstIds().isNotEmpty ? _mstIds().first : AppManager.myId;
    try {
      await http.post(Uri.parse(url), body: {
        'code': AppManager.delegatorCode,
        'mst_id': mstId,
        'type': type,
        'time': time,
        'value': value,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_today()}_$type', time);
    } catch (e) {
      print('[TvHealth] send error $e');
    }
  }

  Future<void> _apply(TvHealthState state, Map<String, dynamic> notify) async {
    final now = _jstNow();
    final prefs = await SharedPreferences.getInstance();
    final day = _today();

    final health = _asMap(notify['health']);
    if (health != null) {
      final time = _asInt(health['time']);
      if (time > 0 && _isDue(now, _asNotifyMap(health['notify']))) {
        final done = prefs.getString('${day}_health');
        if (done != time.toString()) {
          state.showHealth = true;
          state.healthTime = time;
        }
      }
    }

    final medical = _asMap(notify['medical']);
    if (medical != null) {
      final time = _asInt(medical['time']);
      if (time > 0 && _isDue(now, _asNotifyMap(medical['notify']))) {
        final done = prefs.getString('${day}_medical');
        if (done != time.toString()) {
          state.showMedical = true;
          state.medicalTime = time;
        }
      }
    }

    final dayService = _asMap(notify['dayService']) ??
        _asMap(notify['day_service']) ??
        _asMap(notify['dayservice']);
    if (dayService != null && dayService['time1']?.toString() != 'o') {
      final text = _dayServiceText(dayService);
      final time = _asInt(dayService['time']);
      final nt = _asNotifyMap(dayService['notify']);
      final done = prefs.getString('${day}_dayservice');
      final confirmed = time > 0 && done == time.toString();
      if (!confirmed && text.isNotEmpty) {
        state.showDayService = true;
        state.dayServiceText = text;
        if (time > 0) {
          state.showDayServiceCheck = true;
          state.dayServiceTime = time;
        }
      } else if (!confirmed && time > 0 && _isDue(now, nt)) {
        state.showDayService = true;
        state.showDayServiceCheck = true;
        state.dayServiceTime = time;
        state.dayServiceText = '${_formatHm(nt)}です';
      }
    }
  }

  String _dayServiceText(Map<String, dynamic> dayService) {
    for (final key in ['time_text', 'timeText', 'text']) {
      final text = (dayService[key] ?? '').toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    final nt = _asNotifyMap(dayService['notify']);
    final hm = _formatHm(nt);
    return hm.isEmpty ? '' : '$hmです';
  }

  String _formatHm(Map<String, dynamic>? nt) {
    if (nt == null) return '';
    final h = _asInt(nt['h']);
    final m = _asInt(nt['m']);
    if (h <= 0 && m <= 0) return '';
    return '$h時${m.toString().padLeft(2, '0')}分';
  }

  /// 46amip4 `isShow`。notify が無いときは time>0 を期限到来とみなす。
  bool _isDue(DateTime now, Map<String, dynamic>? notify) {
    if (notify == null) return true;
    final h = _asInt(notify['h']);
    final m = _asInt(notify['m']);
    if (h <= 0 && m <= 0 && !notify.containsKey('h')) return true;
    if (now.hour == h) return now.minute >= m;
    return now.hour > h;
  }

  List<String> _mstIds() {
    final raw = (AppManager.settings['MYID'] ??
            AppManager.settings['myId'] ??
            AppManager.myId)
        .toString()
        .trim();
    final code = AppManager.delegatorCode.trim();
    final ids = <String>[];
    void add(String v) {
      if (v.isNotEmpty && !ids.contains(v)) ids.add(v);
    }

    add(raw);
    if (code.isNotEmpty && raw.startsWith('${code}_')) {
      add(raw.substring(code.length + 1));
    } else if (raw.contains('_')) {
      add(raw.substring(raw.indexOf('_') + 1));
    }
    add((AppManager.settings['LOGINID'] ??
            AppManager.settings['loginid'] ??
            '')
        .toString()
        .trim());
    add((AppManager.settings['MYID'] ?? '').toString().trim());
    return ids;
  }

  bool _hasNotifyObject(String body) {
    final data = _asMap(_maybeDecode(body));
    if (data == null) return false;
    return data['notify'] != null;
  }

  dynamic _maybeDecode(dynamic raw) {
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return raw;
      try {
        return json.decode(text);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    final decoded = _maybeDecode(v);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  Map<String, dynamic>? _asNotifyMap(dynamic v) {
    if (v == null) return null;
    if (v is String && (v.isEmpty || v == 'null')) return null;
    return _asMap(v);
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final text = v.toString().trim();
    return int.tryParse(text.split('.').first) ?? 0;
  }

  DateTime _jstNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 9));

  /// JST の年月日（46amip4 の完了キーと同形式）。
  String _today() {
    final n = _jstNow();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
