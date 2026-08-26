import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/lisa/lisa_activation_page.dart';
import 'package:amiapp/services/lisa_device_service.dart';

/// 契約が続いているかを見張る。
///
/// ログインしたあと、テレビは何もしなければサーバーに問い合わせない。
/// そのままだと会員ページで解除しても、電源を入れ直すまで使えてしまう。
/// 譲渡や返却のときに困るため、定期的に確かめて、解除されていたら
/// 登録画面へ戻す。
///
/// 止めるのはサーバーがはっきり「解除された」と答えたときだけ。
/// 通信できないだけで見守りを止めてはいけない。
class LisaWatchdog with WidgetsBindingObserver {
  LisaWatchdog._();
  static final LisaWatchdog instance = LisaWatchdog._();

  /// 確認の間隔。解除から最大1時間で止まる。
  /// これ以上短くしてもサーバーの負担が増えるだけで、実害の差は小さい。
  static const _interval = Duration(hours: 1);

  /// 復帰直後は通信が整っていないことがあるので、少し置いてから確かめる。
  static const _resumeDelay = Duration(seconds: 20);

  Timer? _timer;
  Timer? _resumeTimer;
  bool _running = false;
  bool _handling = false;

  /// 画面を切り替えるために使う。app.dart で MaterialApp に渡している。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// ログインが済んだら呼ぶ。何度呼んでも二重には動かない。
  ///
  /// 端末トークンを持っている場合だけ見張る。従来のID・パスワードで
  /// ログインしたテレビはトークンを持たないため、見張ると誤って
  /// 解除扱いになってしまう。
  Future<void> start() async {
    if (_running || !TvUtil.isTelevision) return;

    final token = await LisaDeviceService.savedToken();
    if (token.isEmpty) {
      // ignore: avoid_print
      print('[LisaWatchdog] 端末トークンが無いため見張らない');
      return;
    }
    if (_running) return;   // 待っている間に始まっていたら何もしない

    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => _check());
    // ignore: avoid_print
    print('[LisaWatchdog] 見張りを開始（${_interval.inHours}時間ごと）');
  }

  void stop() {
    _timer?.cancel();
    _resumeTimer?.cancel();
    _timer = null;
    _resumeTimer = null;
    if (_running) WidgetsBinding.instance.removeObserver(this);
    _running = false;
  }

  /// 電源を入れ直した直後も確かめる。
  /// 夜のあいだに解除された場合、朝いちばんで気づけるようにするため。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running || state != AppLifecycleState.resumed) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _check);
  }

  Future<void> _check() async {
    if (_handling) return;
    final state = await LisaDeviceService.instance.checkEntitlement();
    if (state != 'revoked') return;   // active / unknown / offline は止めない
    await _onRevoked();
  }

  /// 解除されていた。案内を出してから登録画面へ戻す。
  ///
  /// 黙って画面が変わると、高齢の利用者は故障だと思って不安になる。
  /// 何が起きたのか、どうすればよいのかを必ず伝える。
  Future<void> _onRevoked() async {
    if (_handling) return;
    _handling = true;
    stop();

    // ignore: avoid_print
    print('[LisaWatchdog] 解除されました。登録画面へ戻します');
    await LisaDeviceService.clearToken();

    // ログイン済みの印も消す。ここを残すと、アプリを開き直したときに
    // また居室画面へ入れてしまう。トークンが無いので見張りも動かず、
    // 解除したはずのテレビが使い続けられる。
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('login', false);
      await prefs.remove('login_code');
      await prefs.remove('login_id');
    } catch (e) {
      // ignore: avoid_print
      print('[LisaWatchdog] ログイン情報の消去に失敗 $e');
    }

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    await showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'ご利用の登録が解除されました',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'このテレビの登録が解除されたため、いったんご利用を停止します。\n\n'
          'ふたたびお使いになるときは、次の画面に出る番号を\n'
          'ご家族の方に伝えてください。',
          style: TextStyle(fontSize: 20, height: 1.7),
        ),
        actions: [
          Builder(
            builder: (context) => TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const Color(0xFF6B70BE)
                      : null,
                ),
              ),
              child: const Text('OK', style: TextStyle(fontSize: 22)),
            ),
          ),
        ],
      ),
    );

    nav.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LisaActivationPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (_) => false,
    );
    _handling = false;
  }
}
