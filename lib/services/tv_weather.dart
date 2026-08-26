import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:amiapp/services/appmanager.dart';

class TvWeatherDay {
  TvWeatherDay({
    required this.date,
    required this.weekday,
    required this.telop,
    required this.temp,
    this.weatherCode = '',
  });

  final String date;
  final String weekday;
  final String telop;
  final String temp;
  final String weatherCode;

  /// 46amip4 weather.php と同じ気象庁アイコン。
  String get iconUrl {
    final file = TvWeatherService.iconFile(weatherCode);
    return 'https://www.jma.go.jp/bosai/forecast/img/$file';
  }
}

class TvWeatherState {
  String areaName = '';
  String office = '';
  String published = '';
  List<TvWeatherDay> days = [];
}

/// ラズパイ版ホームの気象庁天気予報。TCLアミでは呼ばない。
class TvWeatherService {
  TvWeatherService._();
  static final TvWeatherService instance = TvWeatherService._();

  static const telops = {
    '100': '晴',
    '101': '晴時々曇',
    '102': '晴一時雨',
    '104': '晴一時雪',
    '110': '晴後時々曇',
    '111': '晴後曇',
    '112': '晴後一時雨',
    '200': '曇',
    '201': '曇時々晴',
    '202': '曇一時雨',
    '203': '曇時々雨',
    '204': '曇一時雪',
    '210': '曇後時々晴',
    '211': '曇後晴',
    '212': '曇後一時雨',
    '300': '雨',
    '301': '雨時々晴',
    '302': '雨時々止む',
    '303': '雨時々雪',
    '311': '雨後晴',
    '313': '雨後曇',
    '400': '雪',
    '401': '雪時々晴',
    '402': '雪時々止む',
    '411': '雪後晴',
    '413': '雪後曇',
  };

  static const weekChars = ['日', '月', '火', '水', '木', '金', '土'];

  /// TELOPS の日中アイコンファイル名。未登録コードは code.svg を使う。
  static const iconFiles = {
    '100': '100.svg',
    '101': '101.svg',
    '102': '102.svg',
    '104': '104.svg',
    '110': '110.svg',
    '111': '110.svg',
    '112': '112.svg',
    '200': '200.svg',
    '201': '201.svg',
    '202': '202.svg',
    '203': '202.svg',
    '204': '204.svg',
    '210': '210.svg',
    '211': '210.svg',
    '212': '212.svg',
    '300': '300.svg',
    '301': '301.svg',
    '302': '302.svg',
    '303': '303.svg',
    '311': '311.svg',
    '313': '313.svg',
    '400': '400.svg',
    '401': '401.svg',
    '402': '402.svg',
    '411': '411.svg',
    '413': '413.svg',
  };

  static String iconFile(String code) {
    if (code.isEmpty) return '100.svg';
    return iconFiles[code] ?? '$code.svg';
  }

  Future<TvWeatherState?> fetch() async {
    final area = AppManager.weatherArea;
    if (area.isEmpty) return null;
    final url =
        'https://www.jma.go.jp/bosai/forecast/data/forecast/$area.json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data is! List || data.length < 2) return null;
      return _parse(data);
    } catch (e) {
      print('[TvWeather] fetch error $e');
      return null;
    }
  }

  /// 気象庁のISO8601は "+09:00" 付きで、DateTime.parse は **UTC** を返す。
  /// そのまま month/day を使うと 00:00(JST) の要素が前日にずれるため、必ず toLocal() する。
  static DateTime? _jstDate(Object? raw) =>
      DateTime.tryParse(raw?.toString() ?? '')?.toLocal();

  static String _label(DateTime dt) => '${dt.month}/${dt.day}';

  TvWeatherState _parse(List data) {
    final state = TvWeatherState();
    final today = data[0];
    final week = data.length > 1 ? data[1] : null;
    if (today is! Map) return state;

    state.office = (today['publishingOffice'] ?? '').toString();
    state.published = (today['reportDatetime'] ?? '')
        .toString()
        .replaceAll('+09:00', '')
        .replaceAll('T', ' ')
        .replaceAll('-', '/');
    if (state.published.endsWith(':00')) {
      state.published =
          state.published.substring(0, state.published.length - 3);
    }

    final todaySeries = today['timeSeries'];

    // 気温は timeSeries[2]。同じ日に 00:00=最低 / 09:00=最高 が並ぶので、
    // 日付ごとに大きい方（＝最高気温）を残す。週間予報側の穴埋めにも使う。
    final tempsByDate = <String, String>{};
    if (todaySeries is List && todaySeries.length > 2) {
      final tempAreas = todaySeries[2]['areas'];
      final tempDates = todaySeries[2]['timeDefines'];
      if (tempAreas is List && tempAreas.isNotEmpty && tempDates is List) {
        final temps = tempAreas[0]['temps'];
        if (temps is List) {
          for (var i = 0; i < temps.length && i < tempDates.length; i++) {
            final dt = _jstDate(tempDates[i]);
            final v = temps[i]?.toString() ?? '';
            if (dt == null || v.isEmpty || v == 'null') continue;
            final key = _label(dt);
            final prev = int.tryParse(tempsByDate[key] ?? '');
            final cur = int.tryParse(v);
            if (prev == null || (cur != null && cur > prev)) {
              tempsByDate[key] = v;
            }
          }
        }
      }
    }

    final now = DateTime.now();
    final todayLabel = _label(now);
    final startOfToday = DateTime(now.year, now.month, now.day);

    if (todaySeries is List && todaySeries.isNotEmpty) {
      final areas = todaySeries[0]['areas'];
      final dates = todaySeries[0]['timeDefines'];
      if (areas is List && areas.isNotEmpty && dates is List && dates.isNotEmpty) {
        state.areaName = (areas[0]['area']?['name'] ?? '').toString();
        final codes = areas[0]['weatherCodes'];
        final weathers = areas[0]['weathers'];

        // 17時発表は timeDefines[0] が「発表した日」。日付が変わると前日が残るため、
        // 今日の日付と一致する要素を選ぶ（見つからなければ先頭）。
        var index = 0;
        for (var i = 0; i < dates.length; i++) {
          final dt = _jstDate(dates[i]);
          if (dt != null && _label(dt) == todayLabel) {
            index = i;
            break;
          }
        }

        final dt = _jstDate(dates[index]);
        if (dt != null) {
          final code =
              (codes is List && index < codes.length) ? codes[index].toString() : '';
          var telop = telops[code];
          if (telop == null && weathers is List && index < weathers.length) {
            telop = weathers[index].toString().split('\u3000').first;
          }
          final label = _label(dt);
          state.days.add(TvWeatherDay(
            date: label,
            weekday: weekChars[dt.weekday % 7],
            telop: telop ?? '天気',
            temp: tempsByDate[label] ?? '-',
            weatherCode: code,
          ));
        }
      }
    }

    if (week is! Map) return state;
    final weekSeries = week['timeSeries'];
    if (weekSeries is! List || weekSeries.isEmpty) return state;
    final dates = weekSeries[0]['timeDefines'];
    final areas0 = weekSeries[0]['areas'];
    if (dates is! List || areas0 is! List || areas0.isEmpty) return state;
    final codes = areas0[0]['weatherCodes'];
    dynamic temps;
    if (weekSeries.length > 1) {
      final areas1 = weekSeries[1]['areas'];
      if (areas1 is List && areas1.isNotEmpty) {
        temps = areas1[0]['tempsMax'] ?? areas1[0]['temps'];
      }
    }
    if (codes is! List) return state;

    for (var i = 0; i < dates.length && i < codes.length && i < 7; i++) {
      final dt = _jstDate(dates[i]);
      if (dt == null) continue;
      // 過ぎた日は出さない。
      if (DateTime(dt.year, dt.month, dt.day).isBefore(startOfToday)) continue;
      final label = _label(dt);
      if (state.days.any((d) => d.date == label)) continue;
      final code = codes[i].toString();
      var temp = '-';
      if (temps is List && i < temps.length) {
        final t = temps[i]?.toString() ?? '';
        if (t.isNotEmpty && t != 'null') temp = t;
      }
      // 週間予報の初日は最高気温が空（data[0]側にある）ので補う。
      if (temp == '-') temp = tempsByDate[label] ?? '-';
      state.days.add(TvWeatherDay(
        date: label,
        weekday: weekChars[dt.weekday % 7],
        telop: telops[code] ?? '天気',
        temp: temp,
        weatherCode: code,
      ));
    }
    return state;
  }
}
