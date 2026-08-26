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

  bool get hasAny =>
      showMedical || showHealth || showDayService;
}

class TvHealthNotify {
  TvHealthNotify._();
  static final TvHealthNotify instance = TvHealthNotify._();

  Future<TvHealthState> fetch() async {
    final state = TvHealthState();
    final url =
        '${AppDefine.baseURL}api/info?code=${AppManager.delegatorCode}&mst_id=${AppManager.myId}&notify=1';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return state;
      final data = json.decode(response.body);
      if (data is! Map) return state;
      final notify = data['notify'];
      if (notify is! Map) return state;
      await _apply(state, Map<String, dynamic>.from(notify));
    } catch (e) {
      print('[TvHealth] fetch error $e');
    }
    return state;
  }

  Future<void> send(String type, String time, String value) async {
    final url = '${AppDefine.baseURL}api/result';
    try {
      await http.post(Uri.parse(url), body: {
        'code': AppManager.delegatorCode,
        'mst_id': AppManager.myId,
        'type': type,
        'time': time,
        'value': value,
      });
      final prefs = await SharedPreferences.getInstance();
      final day = _today();
      await prefs.setString('${day}_$type', time);
    } catch (e) {
      print('[TvHealth] send error $e');
    }
  }

  Future<void> _apply(TvHealthState state, Map<String, dynamic> notify) async {
    final prefs = await SharedPreferences.getInstance();
    final day = _today();
    final now = DateTime.now();

    final health = notify['health'];
    if (health is Map) {
      final time = _asInt(health['time']);
      final nt = health['notify'];
      if (time > 0 && nt is Map && _isDue(now, nt)) {
        final done = prefs.getString('${day}_health');
        if (done != time.toString()) {
          state.showHealth = true;
          state.healthTime = time;
        }
      }
    }

    final medical = notify['medical'];
    if (medical is Map) {
      final time = _asInt(medical['time']);
      final nt = medical['notify'];
      if (time > 0 && nt is Map && _isDue(now, nt)) {
        final done = prefs.getString('${day}_medical');
        if (done != time.toString()) {
          state.showMedical = true;
          state.medicalTime = time;
        }
      }
    }

    final dayService = notify['dayService'];
    if (dayService is Map) {
      final text = (dayService['time_text'] ?? '').toString();
      if (text.isNotEmpty && dayService['time1']?.toString() != 'o') {
        state.showDayService = true;
        state.dayServiceText = text;
        final time = _asInt(dayService['time']);
        if (time > 0) {
          final done = prefs.getString('${day}_dayservice');
          if (done != time.toString()) {
            state.showDayServiceCheck = true;
            state.dayServiceTime = time;
          }
        }
      }
    }
  }

  bool _isDue(DateTime now, Map notify) {
    final h = _asInt(notify['h']);
    final m = _asInt(notify['m']);
    if (now.hour == h) return now.minute >= m;
    return now.hour > h;
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }
}
