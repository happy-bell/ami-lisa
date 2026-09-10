import 'dart:async';

import 'package:flutter/foundation.dart';

/// BLEの順番待ち（交通整理）。
///
/// ■ なぜ要るのか
///
/// このテレビには BLEアダプタが1本しかない。しかも
/// flutter_blue_plus は **同時に1つのスキャンしか持てない。**
/// 誰かが startScan を呼ぶと、前のスキャンは黙って止められる。
///
///     flutter_blue_plus 1.36.8 / FlutterBluePlus.startScan
///       // already scanning?
///       await _stopScan();
///
/// 呼び出しボタン RS-SCBTN2 は、押されたその瞬間を捕まえるために
/// ずっとスキャンし続けている。ところが血圧計・Ring・Checkme Pro が
/// 測定のためにスキャンを始めると、ボタンのスキャンが黙って消える。
/// 止められたことは誰にも知らされないので、測定が終わってもボタンは
/// 二度と反応しない。2026-09-05、Ring を接続したあとに実際そうなった。
///
/// ■ ここでやること
///
/// BLEを使う人は、使う前に [take]、終わったら [give] を呼ぶ。
/// 誰かが取った時点で、譲る側（ボタン）は聞き取りを止める。
/// [take] は譲り終わるまで待つので、譲る前に相手がスキャンを
/// 始めてしまう取り合いは起きない。全員が返したら、譲った側は
/// ひとりでに聞き取りへ戻る。
///
/// 入れ子で取っても構わない。人ごとに何回取ったかを数えていて、
/// 全部返し終わった時にだけ空きになる。
///
/// ■ 取りっぱなしへの備え
///
/// 返し忘れや不具合で誰かが握ったままになると、呼び出しボタンが
/// 永久に効かなくなる。命に関わるので [_maxHold] を過ぎたら
/// 強制的に取り上げて記録を残す。
class BleBus {
  BleBus._();
  static final BleBus instance = BleBus._();

  /// これを超えて握り続けている人からは取り上げる。
  static const _maxHold = Duration(minutes: 3);

  final Map<String, int> _held = {};
  final Map<String, DateTime> _since = {};

  Future<void> Function()? _pause;
  Future<void> Function()? _resume;

  Timer? _guard;

  /// 誰かがBLEを使っているか。
  bool get busy => _held.isNotEmpty;

  /// 今使っている人の名前（記録用）。
  List<String> get holders => _held.keys.toList();

  /// 譲る側（呼び出しボタン）を登録する。
  ///
  /// [pause] は誰かがBLEを取る前に呼ばれ、終わるまで待たれる。
  /// [resume] は全員が返したあとに呼ばれる。
  void yieldTo({
    required Future<void> Function() pause,
    required Future<void> Function() resume,
  }) {
    _pause = pause;
    _resume = resume;
  }

  /// BLEを使い始める。譲る側が止め終わるまで待ってから戻る。
  Future<void> take(String owner) async {
    final first = _held.isEmpty;
    _held[owner] = (_held[owner] ?? 0) + 1;
    _since[owner] = DateTime.now();
    if (!first) return;

    _log('$owner が使います');
    _guard?.cancel();
    _guard = Timer.periodic(const Duration(seconds: 20), (_) => _checkStuck());
    try {
      await _pause?.call();
    } catch (e) {
      _log('譲る側の停止でエラー $e');
    }
  }

  /// 使い終わった。全員が返したら譲った側を元へ戻す。
  Future<void> give(String owner) async {
    final n = _held[owner];
    if (n == null) return; // 取っていない人の返却は無視する
    if (n > 1) {
      _held[owner] = n - 1;
      return;
    }
    _held.remove(owner);
    _since.remove(owner);
    if (_held.isNotEmpty) return;

    _guard?.cancel();
    _guard = null;
    _log('$owner が返しました → 空き');
    try {
      await _resume?.call();
    } catch (e) {
      _log('譲った側の再開でエラー $e');
    }
  }

  /// 握ったままの人がいないか見張る。
  void _checkStuck() {
    final now = DateTime.now();
    final stuck = _since.entries
        .where((e) => now.difference(e.value) > _maxHold)
        .map((e) => e.key)
        .toList();
    if (stuck.isEmpty) return;
    for (final owner in stuck) {
      _log('$owner が${_maxHold.inMinutes}分以上返さないため取り上げます');
      _held.remove(owner);
      _since.remove(owner);
    }
    if (_held.isNotEmpty) return;
    _guard?.cancel();
    _guard = null;
    _resume?.call();
  }

  void _log(String m) => debugPrint('[BleBus] $m');
}
