import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';

/// 46amip4 `health_json.php` / `health_json_by_udid.php` と同じキー。
class TvPiVitalValues {
  String name = '';
  String bp1 = '-';
  String bp2 = '-';
  String bp4 = '-';
  String bt1 = '-';
  String bw1 = '-';
  String temp = '-';
  String pressure = '-';
  String spo2 = '-';
  String spo2Pr = '-';
  String hr = '-';
  String pi = '-';

  void applyLiveAndKeep(TvPiVitalValues previous) {
    final pro = CheckmeProService.instance;
    final ring = CheckmeRingService.instance;
    if (pro.hr != null) {
      hr = '${pro.hr}';
    } else if (hr == '-') {
      hr = previous.hr;
    }
    if (pro.pi != null) {
      pi = pro.pi!.toStringAsFixed(1);
    } else if (ring.pi != null) {
      pi = '${ring.pi}';
    } else if (pi == '-') {
      pi = previous.pi;
    }
  }
}

/// ラズパイ版ホームのバイタル表。TCLアミでは呼ばない。
class TvPiVitals {
  TvPiVitals._();
  static final TvPiVitals instance = TvPiVitals._();

  Future<TvPiVitalValues> fetch({String? udid}) async {
    final values = TvPiVitalValues();
    final id = (udid ?? AppManager.myId).trim();
    if (id.isEmpty) return values;

    final urls = <String>[
      '${AppDefine.mcsaURL}newhealthcare46docp/health_json_by_udid.php?udid=$id',
      '${AppDefine.mcsaURL}newhealthcare46amip3/health_json_by_udid.php?udid=$id',
      '${AppDefine.mcsaURL}newhealthcare46amip4/health_json_by_udid.php?udid=$id',
    ];

    for (final url in urls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(
              const Duration(seconds: 8),
            );
        if (response.statusCode != 200) continue;
        final data = json.decode(response.body);
        if (data is! Map) continue;
        if (data['status']?.toString() != 'ok') continue;
        values.name = _asValue(data['name']);
        if (values.name == '-') values.name = '';
        values.bp1 = _asValue(data['bp1']);
        values.bp2 = _asValue(data['bp2']);
        values.bp4 = _asValue(data['bp4']);
        values.bt1 = _asValue(data['bt1']);
        values.bw1 = _asValue(data['bw1']);
        values.temp = _asValue(data['temp']);
        values.pressure = _asValue(data['pressure']);
        values.spo2 = _asValue(data['spo2']);
        values.spo2Pr = _asValue(data['spo2_pr']);
        values.hr = _asValue(
            data['hr'] ?? data['checkme_hr'] ?? data['hr1'] ?? data['result4']);
        values.pi = _asValue(data['pi'] ??
            data['spo2_pi'] ??
            data['checkme_pi'] ??
            data['result3'] ??
            data['result5']);
        return values;
      } catch (e) {
        print('[TvPiVitals] $url $e');
      }
    }
    return values;
  }

  String _asValue(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return '-';
    return text;
  }
}
