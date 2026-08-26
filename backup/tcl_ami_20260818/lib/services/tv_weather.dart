import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:amiapp/services/appmanager.dart';

class TvWeatherDay {
  TvWeatherDay({
    required this.date,
    required this.weekday,
    required this.telop,
    required this.temp,
  });

  final String date;
  final String weekday;
  final String telop;
  final String temp;
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
    if (todaySeries is List && todaySeries.isNotEmpty) {
      final areas = todaySeries[0]['areas'];
      if (areas is List && areas.isNotEmpty) {
        state.areaName = (areas[0]['area']?['name'] ?? '').toString();
        final codes = areas[0]['weatherCodes'];
        final weathers = areas[0]['weathers'];
        final dates = todaySeries[0]['timeDefines'];
        String temp = '-';
        if (todaySeries.length > 2) {
          final tempAreas = todaySeries[2]['areas'];
          if (tempAreas is List && tempAreas.isNotEmpty) {
            final temps = tempAreas[0]['temps'];
            if (temps is List && temps.isNotEmpty) {
              temp = temps.last?.toString() ?? '-';
            }
          }
        }
        if (dates is List && dates.isNotEmpty) {
          final dt = DateTime.tryParse(dates[0].toString());
          if (dt != null) {
            final code = (codes is List && codes.isNotEmpty)
                ? codes[0].toString()
                : '';
            var telop = telops[code];
            if (telop == null && weathers is List && weathers.isNotEmpty) {
              telop = weathers[0].toString().split('　').first;
            }
            state.days.add(TvWeatherDay(
              date: '${dt.month}/${dt.day}',
              weekday: weekChars[dt.weekday % 7],
              telop: telop ?? '天気',
              temp: temp,
            ));
          }
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
      final raw = dates[i].toString();
      final dt = DateTime.tryParse(raw);
      if (dt == null) continue;
      if (state.days.any((d) => d.date == '${dt.month}/${dt.day}')) continue;
      final code = codes[i].toString();
      var temp = '-';
      if (temps is List && i < temps.length) {
        final t = temps[i]?.toString() ?? '';
        if (t.isNotEmpty && t != 'null') temp = t;
      }
      state.days.add(TvWeatherDay(
        date: '${dt.month}/${dt.day}',
        weekday: weekChars[dt.weekday % 7],
        telop: telops[code] ?? '天気',
        temp: temp,
      ));
    }
    return state;
  }
}
