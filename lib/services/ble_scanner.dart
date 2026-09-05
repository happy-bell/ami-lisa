import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:amiapp/ble/and_vital_codec.dart';
import 'package:amiapp/ble/checkme_ring_protocol.dart';
import 'package:amiapp/services/ble_bus.dart';

/// BLEのスキャンを1本にまとめる。
///
/// ■ なぜ1本にするのか
///
/// BLEアダプタは1つで、flutter_blue_plus は同時に1つのスキャンしか
/// 持てない。誰かが startScan を呼ぶと前のスキャンは黙って止められる。
/// そのため今までは、機器ごとにスキャンを立てては奪い合っていた。
///
/// とくに困るのが A&D血圧計で、ペアリングされている限り
/// **12秒スキャン → 3秒休む を永久に繰り返す。**
/// 測定していなくても止まらない。その間、呼び出しボタンは何も聞けない。
/// 2026-09-05 の実測で、ボタンが聞けるのは15秒のうち3秒だけだった。
///
///     21:23:01.979  血圧計 が使います
///     21:23:14.003  血圧計 が返しました        ← 12.02秒 聞こえない
///     21:23:14.004  押された（解放の1ミリ秒後）← 待たされていた
///
/// ■ どうするか
///
/// スキャンは**ここだけ**が持つ。止めない。
/// 受け取りたい人は [results] を聞く。何人が聞いても構わない。
/// スキャンが1本しかないので、もう奪い合いは起きない。
///
/// 絞り込みは重ねられる（OR）ので、必要な機器をまとめて指定する。
/// 本体側（Androidの ScanFilter）で絞るため、関係ない電波でアプリが
/// 起こされることはない。リモコンへの負担も増えない。
///
///     ボタン RS-SCBTN2   メーカーID 0x0B60
///     A&D血圧計          血圧 0x1810 / 体温 0x1809 / 体重 0x181D
///     Checkme Ring       14839ac4-…（Checkme Pro と共通）
///
/// ■ ここに載せていないもの
///
/// Checkme Pro は名前でしか見分けていない（サービスUUIDを広告して
/// いるか確かめられていない）ため、従来どおり自前でスキャンする。
/// 利用者が画面で開始する短い操作なので、その間だけボタンが譲る。
class BleScanner {
  BleScanner._();
  static final BleScanner instance = BleScanner._();

  /// ラトックのスマートボタン。
  static const buttonMsdId = 0x0B60;

  /// しばらく電波が途絶えた機器は一覧から外す。
  ///
  /// 止めないスキャンなので、これが無いと去った機器がいつまでも
  /// 残り、血圧計が「まだ居る」と勘違いして繋ぎにいってしまう。
  static const _forget = Duration(seconds: 20);

  /// 生存確認の間隔。
  static const _watchSpan = Duration(seconds: 5);

  final _results = StreamController<List<ScanResult>>.broadcast();

  /// 受け取った電波。誰でも聞いてよい。
  Stream<List<ScanResult>> get results => _results.stream;

  /// 直近の一覧。聞き始める前に、すでに来ているものを見るのに使う。
  List<ScanResult> get latest => FlutterBluePlus.lastScanResults;

  StreamSubscription<List<ScanResult>>? _sub;
  Timer? _watch;

  bool _running = false;
  bool _yielding = false;
  int _revived = 0;

  /// スキャンを持っているか。
  ///
  /// これが false の機器は、従来どおり自前でスキャンしてよい。
  /// ボタンが未登録のテレビでは動かないので、そこは今までと変わらない。
  bool get isRunning => _running;

  /// スキャンを始める。二度呼んでも害はない。
  Future<void> start() async {
    if (_running) return;
    try {
      if (!(await FlutterBluePlus.isSupported)) {
        _log('この端末はBLEに対応していません');
        return;
      }
    } catch (e) {
      _log('BLEの確認に失敗 $e');
      return;
    }
    _running = true;

    // Ring / Checkme Pro が自前でスキャンする間は譲る。
    BleBus.instance.yieldTo(pause: _yieldBle, resume: _takeBackBle);

    if (BleBus.instance.busy) {
      _yielding = true;
      _log('他が使用中のため待ちます（${BleBus.instance.holders.join(",")}）');
    } else {
      await _open();
    }
    _startWatch();
  }

  /// スキャンを止めて BLE を解放する。
  Future<void> stop() async {
    _running = false;
    _yielding = false;
    _watch?.cancel();
    _watch = null;
    await _close();
    _log('スキャンを止めました（BLEを解放）');
  }

  Future<void> _open() async {
    await _sub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _sub = FlutterBluePlus.scanResults.listen(
      (r) {
        if (!_results.isClosed) _results.add(r);
      },
      onError: (e) => _log('受信でエラー $e'),
    );

    try {
      await FlutterBluePlus.startScan(
        // 絞り込みは OR で重なる。ここに挙げた機器だけが届く。
        withMsd: [MsdFilter(buttonMsdId)],
        withServices: [
          Guid(AndVitalCodec.bpService),
          Guid(AndVitalCodec.tempService),
          Guid(AndVitalCodec.weightService),
          Guid(CheckmeRingProtocol.serviceUuid),
        ],
        // 同じ機器の値が変わるたびに知らせてほしい。
        // これが無いと、一度見つけた機器の2回目以降が届かない。
        continuousUpdates: true,
        // 去った機器は一覧から外す。
        removeIfGone: _forget,
        // 時間で切らない。切ると掛け直しが要り、そのたび
        // リモコンの接続が壊れる（2026-09-04 に実際そうなった）。
        timeout: null,
        // 強さは1つに固定する。途中で変えると停止→再開が要り、
        // その1〜2秒で発信を取り逃す。
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
      );
      _log('スキャン開始（1本にまとめて、ずっと聞き続ける）');
    } catch (e) {
      _log('スキャンを始められません $e');
    }
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// 自前でスキャンしたい機器へ譲る。
  ///
  /// [BleBus.take] はこれが終わるまで待つ。先に止め終わってから
  /// 相手に始めさせないと、こちらの停止が相手のスキャンを
  /// 巻き添えにして消してしまう。
  Future<void> _yieldBle() async {
    if (_yielding) return;
    _yielding = true;
    await _close();
    _log('BLEを譲ります（${BleBus.instance.holders.join(",")}）');
  }

  /// 相手が使い終わったのでスキャンへ戻る。
  Future<void> _takeBackBle() async {
    if (!_yielding) return;
    _yielding = false;
    if (!_running) return;
    _log('BLEが空いたのでスキャンへ戻ります');
    await _open();
  }

  /// 外から止められたスキャンを、その場で掛け直す。
  ///
  /// Ring / Checkme Pro を止めるための `FlutterBluePlus.stopScan()` は、
  /// 相手を選べないので共有スキャンも巻き添えにする。呼んだ側が
  /// すぐここを呼べば、見張り（最大5秒待ち）を待たずに戻せる。
  Future<void> reopen() async {
    if (!_running || _yielding) return;
    if (FlutterBluePlus.isScanningNow) return;
    _log('外から止められたので掛け直します');
    await _open();
  }

  /// スキャンが生きているかを確かめる。
  ///
  /// 他の機器の startScan で黙って止められることがあり、
  /// それに気づく手立てがこれしかない。譲っている間は何もしない。
  void _startWatch() {
    _watch?.cancel();
    _watch = Timer.periodic(_watchSpan, (_) async {
      if (!_running || _yielding) return;
      if (FlutterBluePlus.isScanningNow) return;
      _revived++;
      _log('スキャンが止まっていました → 掛け直します（通算$_revived回目）');
      await _open();
    });
  }

  void _log(String m) => debugPrint('[BleScanner] $m');
}
