import 'package:amiapp/services/tv_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ラズパイ版ホーム左の天気予報。TCLアミには出さない。
class TvWeatherPanel extends StatelessWidget {
  const TvWeatherPanel({super.key, this.state});

  final TvWeatherState? state;

  @override
  Widget build(BuildContext context) {
    final data = state;
    final days = data?.days ?? const <TvWeatherDay>[];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: days.isEmpty
            ? const Text(
                '天気予報を取得しています…',
                style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '▼${data!.areaName}${data.office.isNotEmpty ? '、${data.office}より' : ''}',
                    style: const TextStyle(
                        fontSize: 13 * 0.9,
                        color: Color(0xFF333333),
                        height: 1.2),
                  ),
                  if (data.published.isNotEmpty)
                    Text(
                      '「${data.published}」発表',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF555555), height: 1.2),
                    ),
                  const SizedBox(height: 6),
                  _dayBlock(days.first, large: true),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final half = constraints.maxWidth / 2;
                      return Wrap(
                        children: [
                          for (final day in days.skip(1).take(6))
                            SizedBox(
                              width: half,
                              child: _dayBlock(day, large: false),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Widget _dayBlock(TvWeatherDay day, {required bool large}) {
    final iconSize = large ? 52.0 : 32.0;
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            '${day.date}(${day.weekday})',
            style: TextStyle(
              fontSize: large ? 20 : 14,
              fontWeight: FontWeight.bold,
              color: _dayColor(day.weekday),
              height: 1.15,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _weatherIcon(day, iconSize),
          ),
          Text(
            // 気温が取れない日（17時発表後の「今日」など）は「-℃」を出さない。
            day.temp == '-' ? day.telop : '${day.telop} ${day.temp}℃',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: large ? 22 : 15,
              fontWeight: large ? FontWeight.bold : FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherIcon(TvWeatherDay day, double size) {
    return SizedBox(
      height: size,
      child: SvgPicture.network(
        day.iconUrl,
        height: size,
        headers: const {'User-Agent': 'Mozilla/5.0 ami-tv'},
        placeholderBuilder: (_) => _fallbackIcon(day, size),
        errorBuilder: (_, __, ___) => _fallbackIcon(day, size),
      ),
    );
  }

  Widget _fallbackIcon(TvWeatherDay day, double size) {
    return Icon(
      _iconData(day.weatherCode),
      size: size * 0.9,
      color: _iconColor(day.weatherCode),
    );
  }

  IconData _iconData(String code) {
    if (code.startsWith('1')) return Icons.wb_sunny;
    if (code.startsWith('2')) return Icons.cloud;
    if (code.startsWith('3')) return Icons.umbrella;
    if (code.startsWith('4')) return Icons.ac_unit;
    return Icons.wb_cloudy;
  }

  Color _iconColor(String code) {
    if (code.startsWith('1')) return const Color(0xFFF5A623);
    if (code.startsWith('2')) return const Color(0xFF7A8A99);
    if (code.startsWith('3')) return const Color(0xFF3B82C4);
    if (code.startsWith('4')) return const Color(0xFF5BA3D9);
    return const Color(0xFF666666);
  }

  Color _dayColor(String weekday) {
    if (weekday == '日') return const Color(0xFFCC3333);
    if (weekday == '土') return const Color(0xFF3366CC);
    return const Color(0xFF222222);
  }
}
