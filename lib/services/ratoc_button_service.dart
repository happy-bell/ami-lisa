import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:amiapp/services/ble_bus.dart';
import 'package:amiapp/services/ble_scanner.dart';
import 'package:amiapp/services/ratoc_button_store.dart';

/// ラトックのスマートボタン RS-SCBTN2 を聞き取る。
///
/// 繋ぐ相手を持たず電波を撒くだけの機器なので、ペアリングも接続もしない。
/// こちらは黙って聞いていればよい。
///
/// 仕様
///   押されると 2秒間隔で発信し、8〜10秒で眠る
///   Manufacturer Specific データ  60 0B 00 32
///     0-1  メーカーID  下位・上位の順。0x0B60 = ラトック
///     2    ボタン      0x00=押されていない  0x01=押された
///     3    電池残量    0x32 = 50%
///   ※ manufacturerData の鍵がメーカーIDなので、中身は 00 32 の部分だけ届く。
///
/// ■ テレビのリモコンと電波を奪い合わないための作り
///
///   このテレビのリモコンは Bluetooth（BLE）で繋がっている。
///     TVC0GWBT  A4:C1:38:8B:9D:85 [LE]
///   強いスキャンを回し続けるとリモコンの通信を妨げ、効かなくなる。
///   2026-09-04 に実際そうなった。原因は2つで、どちらも避けている。
///     ・強さを指定せず既定の lowLatency（電波を100%占有）が使われた
///     ・32秒ごとに停止→再開を繰り返し、そのたび接続が壊れた
///
/// ■ 一度きりのスキャンで、切り替えない（2026-09-05 やり直し）
///
///   はじめは「1回目を捕まえたら強いスキャンへ切り替えて2回目で確定」
///   という作りにした。ところが**切り替えが間に合わなかった。**
///   停止→再開に1〜2秒かかり、その間の発信を取り逃す。
///   実測で4回押して呼出0回。
///
///     14:52:07.796  [01] 1回目を捕捉
///     14:52:07.804  [01] 8ミリ秒後（同じ発信の重複）
///                   強いスキャンへ切り替え
///                   …6秒間なにも来ず、諦めた
///
///   そこで切り替えをやめ、**中くらいの強さで回しっぱなしにして、
///   押下の印を受けたらその場で呼び出す。**
///
///     待機   1024ms 聞いて 4096ms 休む（25%）
///     判定   押下の印を受けたら即座に一斉呼出
///     呼出後 スキャンを止めて BLE を解放する
///
///   ボタンは2秒間隔で発信するので、押されている間に何度も機会がある。
///   誤検知は、MAC・メーカーID・押下ビットの3つが揃わないと起きない。
///
/// ■ スキャンを1本にまとめた（2026-09-05）
///
///   BLEアダプタは1本しかなく、flutter_blue_plus は同時に1つの
///   スキャンしか持てない。血圧計・Ring・Checkme Pro が測定のため
///   startScan を呼ぶと、こちらのスキャンは**黙って止められる。**
///   止められたことは知らされないので、Ring を接続したあと
///   ボタンが二度と反応しなくなった。
///
///   さらに血圧計は、ペアリングされている限り
///   12秒スキャン → 3秒休む を永久に繰り返す。実測すると
///   ボタンが聞けるのは15秒のうち3秒（20%）だけだった。
///
///   そこで**スキャンは [BleScanner] が1本だけ持ち、ボタンも
///   血圧計もそこへ相乗りする**形に変えた。奪い合いが起きないので、
///   聞き取りが途切れることはない。
///
///   Ring と Checkme Pro は、測定している間だけ BLE を占有する。
///   繋いだまま強いスキャンを回すと測定が乱れるおそれがあるため。
///   その間はボタンも聞こえないが、利用者が自分で始めた操作なので
///   決め事で運用できる。探すだけの段階は共有スキャンを使う。
///
class RatocButtonService {
  RatocButtonService._();
  static final RatocButtonService instance = RatocButtonService._();

  /// ラトックのメーカーID。0x0B60。
  static const int manufacturerId = 0x0B60;

  /// 同じ押下で何度も呼び出さないための間隔。
  ///
  /// ボタンは押されている間 2秒ごとに発信する。聞き続けているので
  /// 1回の押下で何通も届く。この間隔だけは置かないと、
  /// 1回押しただけで呼出が連続して出てしまう。
  static const _debounce = Duration(seconds: 10);


  final _pressed = StreamController<RatocButtonPress>.broadcast();

  /// ボタンが押されたら流れてくる。
  Stream<RatocButtonPress> get onPressed => _pressed.stream;

  StreamSubscription<List<ScanResult>>? _sub;

  bool _running = false;
  DateTime? _lastFiredAt;



  /// 受信できているかを確かめるための数え上げ（調査用）。
  int _recv = 0;
  DateTime? _lastRecvLog;

  bool get isRunning => _running;

  /// 聞き取りを始める。
  ///
  /// スキャンは自分で持たない。[BleScanner] が1本だけ持っていて、
  /// そこへ相乗りする。血圧計も同じ1本に相乗りしているので、
  /// 奪い合いは起きず、聞き取りが途切れることもない。
  Future<void> start() async {
    if (_running) return;
    if (!RatocButtonStore.instance.isRegistered) {
      _log('ボタンが未登録のため聞き取りません');
      return;
    }
    _running = true;
    await BleScanner.instance.start();
    await _sub?.cancel();
    _sub = BleScanner.instance.results.listen(
      _onResults,
      onError: (e) => _log('受信でエラー $e'),
    );
    _log('聞き取り中（共有スキャンに相乗り）');
  }

  /// 聞き取りを止める。
  ///
  /// スキャンそのものは [BleScanner] のものなので、ここでは止めない。
  /// 血圧計も同じスキャンを使っている。
  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _log('聞き取りを止めました');
  }

  /// 待機へ戻す。通話が終わったあとに呼ぶ。
  Future<void> resume() async {
    if (_running) return;
    _log('待機に戻ります');
    await start();
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final data = r.advertisementData.manufacturerData[manufacturerId];
      if (data == null || data.isEmpty) continue;

      final mac = r.device.remoteId.str.toUpperCase();
      // チップ側で絞っているが、念のためここでも確かめる。
      if (!RatocButtonStore.instance.matches(mac)) continue;

      // 押された発信は必ず記録する。押されていない発信は2秒ごとに
      // 延々と出るので、10秒に1度だけ「受信できている」ことを残す。
      final hex = data
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final nowMs = DateTime.now();
      if (data[0] == 0x01) {
        _log('発信 [$hex] rssi=${r.rssi} '
            '${nowMs.toIso8601String().substring(11, 23)}');
      } else {
        _recv++;
        final last = _lastRecvLog;
        if (last == null || nowMs.difference(last).inSeconds >= 10) {
          _lastRecvLog = nowMs;
          _log('受信できています [$hex] rssi=${r.rssi} 累計$_recv件 '
              '${nowMs.toIso8601String().substring(11, 23)}');
        }
      }

      final name = r.advertisementData.advName;
      final battery = data.length >= 2 ? data[1] : -1;
      _onPressAdvert(mac, name, battery, data[0] == 0x01);
    }
  }

  /// 「押された」発信を1つ受け取った。その場で一斉呼出を出す。
  ///
  /// 2回目を待つ作りにしていたが、待っている間に取り逃した。
  /// ボタンは2秒間隔で発信するので、押されている間に何度も届く。
  /// 最初に受け取った1つで判断し、あとは [_debounce] で二重を防ぐ。
  void _onPressAdvert(String mac, String name, int battery, bool pressed) {
    if (!pressed) return; // 押されていない発信は数えない
    final now = DateTime.now();

    // 直前に呼出を出したばかりなら捨てる。ボタンが眠るまで待つ。
    final fired = _lastFiredAt;
    if (fired != null && now.difference(fired) < _debounce) return;
    _lastFiredAt = now;

    _log('押された $name ($mac) 電池=$battery% → 一斉呼出');
    _pressed.add(RatocButtonPress(
      deviceId: mac,
      name: name,
      battery: battery,
      at: now,
    ));

    // 呼出のあとも聞き取りを続ける。
    //
    // 以前は呼出のたびに BLE を解放し、35秒後に戻していた。
    // ところが呼出をリモコンで早く止めると、残りの時間ずっと
    // ボタンが効かなくなる。実測で27.8秒の空白ができた。
    // 呼び出しボタンが効かない時間を作ってはいけないので、
    // 止めずに聞き続ける。（2026-09-05 修正）
  }

  /// 登録画面で使う。近くのラトック機器を数秒だけ探す。
  ///
  /// ここは短く回して必ず止める。既存の Checkme と同じ作法で、
  /// リモコンへの影響は出ない。
  Future<List<RatocFound>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final was = _running;
    if (was) await stop();
    // 登録画面のスキャンも順番待ちに載せる。健康機器と重ならない。
    await BleBus.instance.take('ボタン登録');

    final found = <String, RatocFound>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final data = r.advertisementData.manufacturerData[manufacturerId];
          if (data == null || data.isEmpty) continue;
          final mac = r.device.remoteId.str.toUpperCase();
          found[mac] = RatocFound(
            deviceId: mac,
            name: r.advertisementData.advName,
            rssi: r.rssi,
            pressed: data[0] == 0x01,
            battery: data.length >= 2 ? data[1] : -1,
          );
        }
      });
      await FlutterBluePlus.startScan(
        withMsd: [MsdFilter(manufacturerId)],
        continuousUpdates: true,
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
      );
      await Future<void>.delayed(timeout + const Duration(milliseconds: 300));
    } catch (e) {
      _log('探索でエラー $e');
    } finally {
      await sub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await BleBus.instance.give('ボタン登録');
    }
    _log('探索で ${found.length} 台');
    if (was) await start();
    return found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  void _log(String m) => debugPrint('[RatocButton] $m');
}

/// 登録画面に出す、見つかった機器。
class RatocFound {
  const RatocFound({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.pressed,
    required this.battery,
  });

  final String deviceId;
  final String name;
  final int rssi;
  final bool pressed;
  final int battery;
}

class RatocButtonPress {
  const RatocButtonPress({
    required this.deviceId,
    required this.name,
    required this.battery,
    required this.at,
  });

  final String deviceId;
  final String name;

  /// 電池残量（%）。取れない時は -1。
  final int battery;
  final DateTime at;

  @override
  String toString() => 'RatocButtonPress($name $deviceId 電池$battery% $at)';
}
