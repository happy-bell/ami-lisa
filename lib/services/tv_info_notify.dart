import 'package:shared_preferences/shared_preferences.dart';

/// お知らせ（広報・ハザードマップ）の自動配信判定。
///
/// サーバー（`api/info` の `infoTime`）は、配信予定時刻を過ぎると値を空に戻す。
/// 30秒間隔のポーリングでは「時刻ちょうど」を捉えられないため、
///   1) infoTime に値がある間に「配信予定」としてアプリ側に控える（予約）
///   2) 予約時刻を過ぎたら、infoTime が空になっていても配信する
/// という方式にしている。
///
/// 電源オン／画面前面化は呼び出し側（room_page）が行う。
class TvInfoNotify {
  TvInfoNotify._();
  static final TvInfoNotify instance = TvInfoNotify._();

  /// 予約時刻を過ぎてから自動表示を受け付ける猶予（分）。
  /// これを過ぎた古い予約では起動しない（電源を入れ直した深夜に
  /// 昼間の配信が突然出るのを防ぐ）。
  static const int _graceMinutes = 60;

  static const String _keyPending = 'tv_info_pending_at';
  static const String _keyDelivered = 'tv_info_delivered_at';

  void _log(String line) {
    // ignore: avoid_print
    print('[TvInfoNotify] $line');
  }

  /// 今この瞬間に自動配信すべきか。
  /// [infoTime] は `api/info` の infoTime（例 "2026-08-22 17:30:00"、配信後は ""）。
  Future<bool> shouldDeliver(String infoTime) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = infoTime.trim();

    // 1) 値がある間に予約として控える（後で空になっても配信できるように）。
    if (raw.isNotEmpty && raw != 'null' && raw != '0') {
      final due = _parseDue(raw);
      if (due != null) {
        final saved = prefs.getString(_keyPending);
        if (saved != raw) {
          await prefs.setString(_keyPending, raw);
          _log('reserved: $raw');
        }
      } else {
        _log('parse failed infoTime=$raw');
      }
    }

    // 2) 予約を評価する。
    final pending = prefs.getString(_keyPending) ?? '';
    if (pending.isEmpty) return false;

    final due = _parseDue(pending);
    if (due == null) {
      await prefs.remove(_keyPending);
      return false;
    }

    // 同じ予約を二度配信しない。
    if (prefs.getString(_keyDelivered) == pending) {
      return false;
    }

    final now = DateTime.now();
    if (now.isBefore(due)) {
      _log('not yet: due=$due now=$now');
      return false;
    }

    final elapsed = now.difference(due).inMinutes;
    if (elapsed > _graceMinutes) {
      _log('too old: due=$due elapsed=${elapsed}m (猶予$_graceMinutes分超) → 予約破棄');
      await prefs.remove(_keyPending);
      return false;
    }

    _log('deliver: due=$due now=$now elapsed=${elapsed}m');
    return true;
  }

  /// 自動配信を実施したことを記録する（同じ予約は再配信しない）。
  Future<void> markDelivered(String infoTime) async {
    final prefs = await SharedPreferences.getInstance();
    // 配信対象は「予約」。引数が空でも予約値で記録する。
    final pending = prefs.getString(_keyPending) ?? infoTime.trim();
    if (pending.isEmpty) return;
    await prefs.setString(_keyDelivered, pending);
    await prefs.remove(_keyPending);
    _log('marked delivered $pending');
  }

  /// infoTime をローカル時刻の DateTime に変換する。
  /// 端末は Asia/Tokyo 設定のため、ここで時差を足さないこと（二重加算になる）。
  DateTime? _parseDue(String raw) {
    // 日付付き: yyyy-MM-dd HH:mm(:ss) / yyyy/MM/dd HH:mm(:ss) / ISO風
    final dt = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})[T\s]+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?',
    ).firstMatch(raw);
    if (dt != null) {
      final y = int.tryParse(dt.group(1)!);
      final mo = int.tryParse(dt.group(2)!);
      final d = int.tryParse(dt.group(3)!);
      final h = int.tryParse(dt.group(4)!);
      final mi = int.tryParse(dt.group(5)!);
      final s = int.tryParse(dt.group(6) ?? '0') ?? 0;
      if (y == null || mo == null || d == null || h == null || mi == null) {
        return null;
      }
      if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) {
        return null;
      }
      return DateTime(y, mo, d, h, mi, s);
    }

    // 時刻のみ: "17:30" / "17時30分" → 当日の時刻として扱う
    final hm = RegExp(r'^\D*(\d{1,2})\D+(\d{1,2})\D*$').firstMatch(raw);
    if (hm != null) {
      final h = int.tryParse(hm.group(1)!);
      final mi = int.tryParse(hm.group(2)!);
      if (h == null || mi == null || h > 23 || mi > 59) return null;
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day, h, mi);
    }

    // "1730" 形式
    final only = RegExp(r'^(\d{4})$').firstMatch(raw);
    if (only != null) {
      final v = only.group(1)!;
      final h = int.tryParse(v.substring(0, 2));
      final mi = int.tryParse(v.substring(2));
      if (h == null || mi == null || h > 23 || mi > 59) return null;
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day, h, mi);
    }
    return null;
  }
}
