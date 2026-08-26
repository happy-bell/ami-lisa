import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/jma_area_location.dart';

/// 気象庁の防災情報（警報・注意報／地震情報）を取得する。
///
/// 気象庁サイトが配信している JSON をそのまま読む。契約・APIキーは不要で、
/// 天気予報（[TvWeatherService]）と同じ方式・同じ地域コードを使う。
///
/// ※Jアラート／Lアラートは Lアラート受信者登録（マルチメディア振興センター）と
///   事業者契約が必要なため、ここでは扱わない。
class JmaAlertService {
  JmaAlertService._();
  static final JmaAlertService instance = JmaAlertService._();

  static const _base = 'https://www.jma.go.jp/bosai';

  /// 直近に警報を取得した発表官署名（画面に「どこの情報か」を出すため）。
  String lastAreaLabel = '';

  void _log(String line) {
    // ignore: avoid_print
    print('[JmaAlert] $line');
  }

  /// 警報・注意報コードの名称。気象庁の標準コード。
  static const warningNames = <String, String>{
    '02': '暴風雪警報',
    '03': '大雨警報',
    '04': '洪水警報',
    '05': '暴風警報',
    '06': '大雪警報',
    '07': '波浪警報',
    '08': '高潮警報',
    '10': '大雨注意報',
    '12': '大雪注意報',
    '13': '風雪注意報',
    '14': '雷注意報',
    '15': '強風注意報',
    '16': '波浪注意報',
    '17': '融雪注意報',
    '18': '洪水注意報',
    '19': '高潮注意報',
    '20': '濃霧注意報',
    '21': '乾燥注意報',
    '22': 'なだれ注意報',
    '23': '低温注意報',
    '24': '霜注意報',
    '25': '着氷注意報',
    '26': '着雪注意報',
    '32': '暴風雪特別警報',
    '33': '大雨特別警報',
    '35': '暴風特別警報',
    '36': '大雪特別警報',
    '37': '波浪特別警報',
    '38': '高潮特別警報',
  };

  /// 発表中の警報・注意報を取得する。無ければ空。
  Future<List<JmaWarning>> fetchWarnings() async {
    final area = AppManager.weatherArea.trim();
    // 警報APIは府県コード。天気予報で選んだ地域コードから求める
    // （北海道・沖縄・鹿児島は末尾0000ではないため JmaAreaLocation に任せる）。
    final pref = JmaAreaLocation.toPrefCode(area);
    if (area.isEmpty) {
      _log('weatherArea 未設定のため $pref を使用');
    }
    // 官署名が取れないときも「どこの情報か」を出せるよう地域名を入れておく。
    if (lastAreaLabel.isEmpty) lastAreaLabel = JmaAreaLocation.labelOf(area);
    final url = '$_base/warning/data/warning/$pref.json';
    try {
      final res = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode != 200) {
        _log('warning $pref status=${res.statusCode}');
        return const [];
      }
      final data = json.decode(res.body);
      if (data is! Map) return const [];

      // 「どこの情報か」を画面に出せるよう発表官署名を控える。
      final office = (data['publishingOffice'] ?? '').toString();
      if (office.isNotEmpty) lastAreaLabel = office;

      final out = <JmaWarning>[];
      final seen = <String>{};
      final areaTypes = data['areaTypes'];
      if (areaTypes is List) {
        for (final at in areaTypes) {
          final areas = (at is Map) ? at['areas'] : null;
          if (areas is! List) continue;
          for (final a in areas) {
            if (a is! Map) continue;
            final ws = a['warnings'];
            if (ws is! List) continue;
            for (final w in ws) {
              if (w is! Map) continue;
              final status = (w['status'] ?? '').toString();
              // 「解除」「発表警報・注意報はなし」は出さない。
              if (status.isEmpty || status.contains('解除')) continue;
              final code = (w['code'] ?? '').toString();
              final name = warningNames[code] ?? '警報・注意報($code)';
              if (!seen.add(name)) continue;
              out.add(JmaWarning(name: name, status: status));
            }
          }
        }
      }
      _log('warnings pref=$pref count=${out.length}');
      return out;
    } catch (e) {
      _log('warning fetch error $e');
      return const [];
    }
  }

  /// 直近の地震情報を取得する。[limit] 件まで。
  Future<List<JmaQuake>> fetchQuakes({int limit = 3}) async {
    final url = '$_base/quake/data/list.json';
    try {
      final res = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode != 200) {
        _log('quake status=${res.statusCode}');
        return const [];
      }
      final data = json.decode(res.body);
      if (data is! List) return const [];

      final out = <JmaQuake>[];
      for (final q in data) {
        if (q is! Map) continue;
        // 震源・震度情報のみ（津波予報等は別扱い）。
        final title = (q['ttl'] ?? '').toString();
        final place = (q['anm'] ?? '').toString();
        if (place.isEmpty) continue;
        out.add(JmaQuake(
          title: title,
          place: place,
          magnitude: (q['mag'] ?? '').toString(),
          maxIntensity: (q['maxi'] ?? '').toString(),
          datetime: _formatDatetime((q['rdt'] ?? '').toString()),
        ));
        if (out.length >= limit) break;
      }
      _log('quakes count=${out.length}');
      return out;
    } catch (e) {
      _log('quake fetch error $e');
      return const [];
    }
  }

  /// "2026-08-22T22:49:00+09:00" → "8/22 22:49"
  String _formatDatetime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final m = dt.month;
    final d = dt.day;
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$m/$d $h:$mi';
  }
}

class JmaWarning {
  JmaWarning({required this.name, required this.status});
  final String name;
  final String status;

  /// 特別警報 > 警報 > 注意報 の順で重大。
  bool get isEmergency => name.contains('特別警報');
  bool get isWarning => !isEmergency && name.contains('警報');
}

class JmaQuake {
  JmaQuake({
    required this.title,
    required this.place,
    required this.magnitude,
    required this.maxIntensity,
    required this.datetime,
  });
  final String title;
  final String place;
  final String magnitude;
  final String maxIntensity;
  final String datetime;
}
