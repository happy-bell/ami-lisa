import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:amiapp/services/appmanager.dart';

/// メッセージ／時計の時間帯。
/// メッセージ明るさ: RGB(180,220,140)〜(80,130,80)
/// 時計明るさ: RGB(110,151,81)〜(13,28,15)
class TvMessageSlot {
  const TvMessageSlot({
    required this.enabled,
    required this.startMin,
    required this.endMin,
    required this.colorIndex,
    this.paletteKey = TvMessageSchedule.messageKey,
  });

  final bool enabled;
  final int startMin;
  final int endMin;
  final int colorIndex;
  final String paletteKey;

  Color get color =>
      TvMessageSchedule.colorAt(colorIndex, key: paletteKey);

  String get colorLabel => TvMessageSchedule.labelAt(colorIndex);

  String get rangeLabel =>
      '${TvMessageSchedule.formatMin(startMin)}〜${TvMessageSchedule.formatMin(endMin)}';

  TvMessageSlot copyWith({
    bool? enabled,
    int? startMin,
    int? endMin,
    int? colorIndex,
  }) {
    return TvMessageSlot(
      enabled: enabled ?? this.enabled,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      colorIndex: colorIndex ?? this.colorIndex,
      paletteKey: paletteKey,
    );
  }

  Map<String, String> toMap() => {
        'on': enabled ? '1' : '0',
        'start': startMin.toString(),
        'end': endMin.toString(),
        'color': colorIndex.toString(),
      };

  static TvMessageSlot fromMap(dynamic raw, {required TvMessageSlot fallback}) {
    if (raw is! Map) return fallback;
    return TvMessageSlot(
      enabled: raw['on']?.toString() == '1',
      startMin: int.tryParse(raw['start']?.toString() ?? '') ?? fallback.startMin,
      endMin: int.tryParse(raw['end']?.toString() ?? '') ?? fallback.endMin,
      colorIndex:
          int.tryParse(raw['color']?.toString() ?? '') ?? fallback.colorIndex,
      paletteKey: fallback.paletteKey,
    );
  }

  bool contains(int nowMin) {
    if (!enabled) return false;
    final start = startMin.clamp(0, 1440);
    final end = endMin.clamp(0, 1440);
    if (start == end) return false;
    if (start < end) {
      return nowMin >= start && nowMin < end;
    }
    return nowMin >= start || nowMin < end;
  }
}

class TvMessageSchedule {
  TvMessageSchedule._();

  static const messageKey = 'TV_MESSAGE_SLOTS';
  static const clockKey = 'TV_CLOCK_SLOTS';
  /// EX 時計の表示形式。'0' デジタル（時刻のみ）、'1' デジタル日付。未設定は日付あり。
  static const clockFaceKey = 'TV_CLOCK_FACE';
  static const slotCount = 3;
  static const brightnessCount = 5;

  static const labels = <String>['明るい', 'やや明るい', '標準', 'やや暗い', '暗い'];

  /// 明るさ5段階の色。指定値をそのまま使う（補間しない）。
  /// 1 明るい / 2 やや明るい / 3 標準 / 4 やや暗い / 5 暗い

  /// メッセージ用。
  static const _messagePalette = <List<int>>[
    [180, 220, 140],
    [155, 198, 125],
    [130, 175, 110],
    [105, 153, 95],
    [80, 130, 80],
  ];

  /// 時計（日付）用。
  static const _clockPalette = <List<int>>[
    [110, 151, 81],
    [86, 120, 65],
    [62, 90, 48],
    [37, 59, 32],
    [13, 28, 15],
  ];

  static Color colorAt(int index, {String key = messageKey}) {
    final i = index.clamp(0, brightnessCount - 1);
    final c = key == clockKey ? _clockPalette[i] : _messagePalette[i];
    return Color.fromARGB(255, c[0], c[1], c[2]);
  }

  static String clockFace() {
    return AppManager.appsettings[clockFaceKey]?.toString() == '0' ? '0' : '1';
  }

  static bool get showClockDate => clockFace() != '0';

  static String labelAt(int index) {
    if (index < 0 || index >= labels.length) return labels.first;
    return labels[index];
  }

  static String formatMin(int min) {
    final m = min.clamp(0, 1440);
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  static List<TvMessageSlot> defaults({String key = messageKey}) {
    return [
      TvMessageSlot(
        enabled: true,
        startMin: 0,
        endMin: 1440,
        colorIndex: 0,
        paletteKey: key,
      ),
      for (var i = 1; i < slotCount; i++)
        TvMessageSlot(
          enabled: false,
          startMin: 0,
          endMin: 0,
          colorIndex: 0,
          paletteKey: key,
        ),
    ];
  }

  static List<TvMessageSlot> load([String key = messageKey]) {
    final fallback = defaults(key: key);
    final raw = AppManager.appsettings[key]?.toString() ?? '';
    if (raw.isEmpty) return fallback;
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return fallback;
      return [
        for (var i = 0; i < slotCount; i++)
          TvMessageSlot.fromMap(
            i < decoded.length ? decoded[i] : null,
            fallback: fallback[i],
          ),
      ];
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> save(List<TvMessageSlot> slots,
      {String key = messageKey}) async {
    final body = json.encode(slots.map((s) => s.toMap()).toList());
    await AppManager.saveAppSetting(key, body);
  }

  static Future<void> saveClockFace(String value) async {
    await AppManager.saveAppSetting(clockFaceKey, value == '0' ? '0' : '1');
  }

  static TvMessageSlot? activeAt(DateTime now, {String key = messageKey}) {
    final nowMin = now.hour * 60 + now.minute;
    for (final slot in load(key)) {
      if (slot.contains(nowMin)) return slot;
    }
    return null;
  }

  static String summaryLabel({String key = messageKey}) {
    final slots = load(key).where((s) => s.enabled).toList();
    if (slots.isEmpty) return '表示しない';
    if (slots.length == 1 &&
        slots.first.startMin == 0 &&
        slots.first.endMin == 1440) {
      return slots.first.colorLabel;
    }
    return '時間指定';
  }
}
