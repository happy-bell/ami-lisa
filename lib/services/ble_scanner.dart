import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:amiapp/ble/and_vital_codec.dart';
import 'package:amiapp/ble/checkme_ring_protocol.dart';
import 'package:amiapp/services/ble_bus.dart';
import 'package:amiapp/services/ratoc_button_store.dart';

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

  /// これより古い電波は「もう居ない」とみなす。
  ///
  /// 止めないスキャンなので、去った機器がいつまでも一覧に残る。
  /// 血圧計が「まだ居る」と勘違いして繋ぎにいかないよう、
  /// 受け取る側で新しさを確かめる。
  ///
  /// flutter_blue_plus の removeIfGone は使わない。受け取る側で
  /// 確かめれば足りる。（一時 removeIfGone を疑ったが、実機で
  /// 4通り試して無関係だと分かった。2026-09-05）
  static const fresh = Duration(seconds: 20);

  /// その電波が [fresh] 以内に届いたものか。
  static bool isFresh(ScanResult r) =>
      DateTime.now().difference(r.timeStamp) <= fresh;

  /// 生存確認の間隔。
  static const _watchSpan = Duration(seconds: 5);

  /// ■ 掛け直し（2026-09-08 追加）
  ///
  /// Android は、1本のスキャンが長く続くと「opportunistic」へ格下げする。
  /// 格下げされると自分では電波を探しに行かず、他のアプリが探している
  /// 時のおこぼれしか拾えない。テレビでは他に探している者がほぼ居ないので、
  /// 受信が3分の1〜5分の1に落ち、何分も途切れる。
  ///
  /// このテレビ（TV005）では絞り込み（ScanFilter）を本体側に置く枠が
  /// 0個しかない（dumpsys: mMaxScanFilters=0）。Android のソースでは
  /// 絞り込みが本体側に載っている間は格下げを免除するが、枠が無いため
  /// 「絞り込み無し」と同じ扱いになり、免除されない。
  ///
  ///   ScanManager.shouldUseAllPassFilter:
  ///     return client.filters.size() > mFilterIndexStack.size();  // 5 > 0
  ///   ScanManager.isExemptFromScanDowngrade:
  ///     opportunistic || firstMatch || !shouldUseAllPassFilter   // すべて偽
  ///
  /// 格下げからは**自動では戻らない**。戻す手は、スキャンを止めて
  /// 始め直す（新しい客として登録し直す）ことだけ。同ソースの
  /// handleResumeScans にも逆戻しの処理は無い。
  ///
  /// 実測（2026-09-08 TV005）
  ///   12:22:01 画面オフ → 12:23:30 格下げ → 16:00 まで格下げのまま
  ///   その間の記録91分で、無受信が31%（最長13分）。6回押して3回失敗。
  ///   失敗した3回はすべて無受信のさなか、成功した3回はすべて受信中。
  ///
  /// ■ 掛け直しの決め方
  ///
  ///   時間で   [_renewSpan] ごとに掛け直す。格下げの時間切れ
  ///            （AdapterService.getScanTimeoutMillis、機種ごとに違う）
  ///            より十分に短くする。実測は 1363秒〜1813秒。
  ///   沈黙で   [_silence] のあいだ何も届かなければ掛け直す。
  ///            格下げ以外（黙って止められた等）にも効く。
  ///            届かないまま繰り返す時は待ちを倍にしていく
  ///            （ボタンが遠い・無い時に連打しないため。上限 [_renewSpan]）。
  ///   しない   BLE を健康機器（血圧計・Ring・Checkme）へ譲っている間。
  ///            排他的に使っている最中に割り込まない。
  ///
  /// 2026-09-04 に32秒ごとの掛け直しでリモコンが壊れた経緯がある。
  /// ここは最短でも60秒、通常は10分に1回。間隔は必ずこの定数で管理し、
  /// 短くする時はリモコンへの影響を実機で確かめること。
  static const _renewSpan = Duration(minutes: 10);
  static const _silence = Duration(seconds: 60);

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

  /// 今のスキャンを始めた時刻。時間による掛け直しの起点。
  DateTime? _openedAt;

  /// 最後に何かが届いた時刻。沈黙による掛け直しの起点。
  DateTime? _lastResultAt;

  /// 沈黙で掛け直すまでの待ち。届かないまま続く間は倍にしていく。
  Duration _silenceWait = _silence;

  /// 掛け直した回数（記録用）。
  int _renewed = 0;

  /// 何回掛け直したか（記録用）。
  int get renewed => _renewed;

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
        if (r.isNotEmpty) {
          // 一覧が流れてくるのは新しい電波が届いた時だけ。
          _lastResultAt = DateTime.now();
          _silenceWait = _silence; // 届いたので、沈黙の待ちを元に戻す
        }
        if (!_results.isClosed) _results.add(r);
      },
      onError: (e) => _log('受信でエラー $e'),
    );

    // 止めた直後に始めると、前のスキャンの片付けと重なることがある。
    // 少しだけ間を置く。
    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      await FlutterBluePlus.startScan(
        // 絞り込みは OR で重なる。ここに挙げた機器だけが届く。
        // ボタンはメーカーIDで拾う。MAC指定は足さない。
        // 4通り（MAC有無 × removeIfGone有無）すべてで押下が届くことを
        // 2026-09-05 に実機で確かめた。絞り込みは少ないほうがよい。
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
        // 時間で切らない。掛け直しは _startWatch が自分の判断で行う
        // （格下げ対策。2026-09-08）。32秒ごとの掛け直しでリモコンが
        // 壊れた経緯があるので、間隔は _renewSpan / _silence で管理する。
        timeout: null,
        // 強さは1つに固定する。途中で変えると停止→再開が要り、
        // その1〜2秒で発信を取り逃す。
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
      );
      final now = DateTime.now();
      _openedAt = now;
      _lastResultAt = now;
      _log('スキャン開始（1本にまとめて、ずっと聞き続ける）');
    } catch (e) {
      _log('スキャンを始められません $e');
    }
  }

  /// 掛け直す。理由は記録に残す。
  Future<void> _renew(String reason) async {
    _renewed++;
    _log('掛け直します（$reason／通算$_renewed回目）');
    await _open();
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
      // 健康機器が使っている最中は触らない（排他）。
      if (BleBus.instance.busy) return;
      if (!FlutterBluePlus.isScanningNow) {
        _revived++;
        _log('スキャンが止まっていました → 掛け直します（通算$_revived回目）');
        await _open();
        return;
      }
      final now = DateTime.now();
      final opened = _openedAt;
      final last = _lastResultAt;
      if (opened == null || last == null) return;

      // 時間による掛け直し。格下げの時間切れより先に新しくする。
      final age = now.difference(opened);
      if (age >= _renewSpan) {
        await _renew('${age.inMinutes}分たった');
        return;
      }
      // 沈黙による掛け直し。格下げ以外の止まり方にも効く。
      final quiet = now.difference(last);
      if (quiet >= _silenceWait) {
        final waited = _silenceWait;
        // 届かないまま繰り返す時は待ちを倍にする（上限は時間の間隔）。
        final next = waited * 2;
        _silenceWait = next > _renewSpan ? _renewSpan : next;
        await _renew('${quiet.inSeconds}秒なにも届かない'
            '（次は${_silenceWait.inSeconds}秒待つ）');
      }
    });
  }

  void _log(String m) => debugPrint('[BleScanner] $m');
}
