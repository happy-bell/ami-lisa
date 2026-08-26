import 'package:amiapp/services/tv_weather.dart';
import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                        fontSize: 13, color: Color(0xFF333333), height: 1.2),
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
                  for (final day in days.skip(1).take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _dayBlock(day, large: false),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _dayBlock(TvWeatherDay day, {required bool large}) {
    return Column(
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
        Text(
          '${day.telop} ${day.temp}℃',
          style: TextStyle(
            fontSize: large ? 22 : 15,
            fontWeight: large ? FontWeight.bold : FontWeight.w600,
            height: 1.15,
          ),
        ),
      ],
    );
  }

  Color _dayColor(String weekday) {
    if (weekday == '日') return const Color(0xFFCC3333);
    if (weekday == '土') return const Color(0xFF3366CC);
    return const Color(0xFF222222);
  }
}
