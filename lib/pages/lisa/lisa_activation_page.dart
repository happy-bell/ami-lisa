import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/lisa/lisa_terms_page.dart';
import 'package:amiapp/pages/room/room_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/lisa_device_service.dart';
import 'package:amiapp/services/lisa_watchdog.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';

/// テレビの初期画面。6桁の番号を表示し、家族が会員ページで入力するのを待つ。
///
/// リモコンで文字を打たせないための画面。従来のID・パスワード入力も
/// 「番号で設定できないとき」の逃げ道として残してある。
class LisaActivationPage extends StatefulWidget {
  const LisaActivationPage({super.key});

  @override
  State<LisaActivationPage> createState() => _LisaActivationPageState();
}

class _LisaActivationPageState extends State<LisaActivationPage> {
  LisaCode? _code;
  String _message = '準備しています…';
  bool _linking = false;

  Timer? _pollTimer;
  Timer? _countdown;
  int _remain = 0;

  /// 番号の確認間隔。短すぎるとサーバーに負担がかかる。
  static const _pollSeconds = 3;

  /// 画面下の2つのボタン。autofocus だけに任せると、番号の取得中に
  /// 画面が作り直されてフォーカスが外れたままになることがあるため、
  /// 明示的に持たせて拾い直せるようにしている。
  final FocusNode _backFocus = FocusNode(debugLabel: 'lisaBack');
  final FocusNode _manualFocus = FocusNode(debugLabel: 'lisaManual');

  @override
  void initState() {
    super.initState();
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusButtons());
  }

  /// どちらのボタンにも当たっていなければ【戻る】へ戻す。
  /// 1秒ごとの再描画でフォーカスが外れることがあるため。
  void _focusButtons() {
    if (!mounted || !TvUtil.isTelevision) return;
    if (_backFocus.hasFocus || _manualFocus.hasFocus) return;
    _backFocus.requestFocus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdown?.cancel();
    _backFocus.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 番号の発行と確認
  // ------------------------------------------------------------------

  Future<void> _start() async {
    _pollTimer?.cancel();
    _countdown?.cancel();

    // 既にトークンを持っているなら、番号を出さずにそのままログインを試す。
    final token = await LisaDeviceService.savedToken();
    if (token.isNotEmpty) {
      setState(() => _message = 'ログインしています…');
      final ok = await _loginAndEnter();
      if (ok) return;
      // 解除されていた場合はトークンが消えているので、番号の発行へ進む。
    }

    setState(() {
      _code = null;
      _message = '番号を取得しています…';
    });

    final androidId = await _androidId();
    final code = await LisaDeviceService.instance.requestCode(androidId);
    if (!mounted) return;

    if (code == null) {
      setState(() => _message = 'インターネットに接続できません。しばらくお待ちください。');
      _pollTimer = Timer(const Duration(seconds: 15), _start);
      return;
    }

    setState(() {
      _code = code;
      _remain = code.expiresIn;
      _message = '';
    });

    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remain = _remain > 0 ? _remain - 1 : 0);
      if (_remain == 0) _start();   // 期限切れ。新しい番号を出す。
    });

    _pollTimer = Timer.periodic(
      const Duration(seconds: _pollSeconds),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final code = _code;
    if (code == null || _linking) return;

    final state = await LisaDeviceService.instance.pollStatus(code.claimToken);
    if (!mounted) return;

    if (state == 'linked') {
      _pollTimer?.cancel();
      _countdown?.cancel();
      setState(() {
        _linking = true;
        _message = 'テレビを登録しました。準備しています…';
      });
      final ok = await _loginAndEnter();
      if (!ok && mounted) {
        setState(() {
          _linking = false;
          _message = '登録できましたが、接続に失敗しました。やり直します。';
        });
        _start();
      }
      return;
    }

    if (state == 'expired') _start();
  }

  Future<String> _androidId() async {
    try {
      return await TvUtil.getAndroidId();
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------------
  // ログインして居室画面へ
  // ------------------------------------------------------------------

  /// 端末トークンでログインし、既存のサインインと同じ形で設定を保存する。
  Future<bool> _loginAndEnter() async {
    final data = await LisaDeviceService.instance.loginWithToken();
    if (data == null || !mounted) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('login', true);
      await prefs.setString('login_code', (data['code'] ?? '').toString());
      await prefs.setString('login_id', (data['user_id'] ?? '').toString());
      await prefs.setString('address', json.encode(data['address']));
      await prefs.setString('autoreceive', json.encode(data['autoreceive']));
      await prefs.setString(
          'login_at', WidgetUtil.dateFormat(DateTime.now(), 'yyyyMMddHHmmss'));

      final Map<String, dynamic> settings =
          Map<String, dynamic>.from(data['settings'] as Map);

      bool isAnminMode = false;
      for (final k in settings.keys) {
        if (k == 'ANMINMODEFLG' && settings[k] != '0') isAnminMode = true;
      }
      if (isAnminMode) settings['SLEEPMODE'] = '0';
      // テレビは常に居室レイアウト。
      settings['DISPTYPE'] = '1';

      await prefs.setString('settings', json.encode(settings));
      AppManager.saveAppSetting('ANMINMODEFLG', isAnminMode ? '1' : '0');
      await AppManager.loadSetting();
    } catch (e) {
      // ignore: avoid_print
      print('[Lisa] 保存に失敗 $e');
      return false;
    }

    if (!mounted) return false;
    // ここから先は契約が続いているかを見張る。
    LisaWatchdog.instance.start();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, a1, a2) => RoomPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (_) => false,
    );
    return true;
  }

  void _openManualLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SignInPage()))
        .then((_) => _focusButtons());   // 戻ってきたらボタンを選び直す
  }

  /// 戻るキーで規約画面へ。読み直したくなったときの逃げ道。
  /// ここでアプリを終わらせると、電源を入れ直すしかなくなる。
  void _backToTerms() {
    Navigator.of(context, rootNavigator: true).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LisaTermsPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ------------------------------------------------------------------
  // 画面
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 1秒ごとの再描画でフォーカスが外れることがあるため、毎回確かめる。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusButtons());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToTerms();
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        // テレビは横長。番号と手順を左右に並べ、1画面に収める。
        // 縦に積むと1080pでもはみ出し、高齢の利用者はスクロールできない。
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 28, 56, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'テレビのご登録',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: Center(child: _codeBox())),
                    const SizedBox(width: 28),
                    Expanded(flex: 7, child: _steps()),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (TvUtil.isTelevision) _bottomButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeBox() {
    final code = _code;

    if (code == null || _linking) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, color: Color(0xFF444444)),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'この番号を入力してください',
          style: TextStyle(fontSize: 19, color: Color(0xFF444444)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF0099FF), width: 4),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              code.spaced,
              style: const TextStyle(
                fontSize: 76,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                color: Color(0xFF14181F),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _remain > 0
              ? 'あと ${_remain ~/ 60} 分 ${_remain % 60} 秒 で番号が変わります'
              : '番号を更新しています…',
          style: const TextStyle(fontSize: 16, color: Color(0xFF777777)),
        ),
      ],
    );
  }

  /// QRを読み取ると番号まで入った状態で会員ページが開く。
  /// テレビでURLを読み上げて手で打たせるのは現実的でないため。
  String get _mypageUrl {
    final base = '${AppDefine.baseURL}lisa/mypage';
    final code = _code;
    return code == null ? base : '$base?c=${code.code}';
  }

  Widget _steps() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _stepText()),
          const SizedBox(width: 20),
          _qr(),
        ],
      ),
    );
  }

  Widget _qr() {
    if (_code == null) return const SizedBox(width: 156);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFC3CCD8)),
          ),
          child: QrImageView(
            data: _mypageUrl,
            version: QrVersions.auto,
            size: 138,
            gapless: true,
            backgroundColor: Colors.white,
            // テレビは離れて見るため、読み取りやすさを優先して誤り訂正を上げる。
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 156,
          child: Text(
            'スマホのカメラで',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
          ),
        ),
      ],
    );
  }

  Widget _stepText() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
          Text('ご家族の方へ',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Text('1.  QRコードを読み取る',
              style: TextStyle(fontSize: 18, height: 1.4)),
          SizedBox(height: 12),
          Text('2.  ログインする',
              style: TextStyle(fontSize: 18, height: 1.4)),
          SizedBox(height: 12),
          Text('3.  「追加する」を押す',
              style: TextStyle(fontSize: 18, height: 1.4)),
          SizedBox(height: 18),
          Text('登録が済むと自動で始まります',
              style: TextStyle(fontSize: 15, color: Color(0xFF555555))),

        ],
      );
  }

  /// 画面下のボタン列。【戻る】と【番号で登録できない方はこちら】を横に並べる。
  ///
  /// 最初のフォーカスは【戻る】に置く。ここで唯一目立つボタンが
  /// 「番号で登録できない方」だと、番号で登録する人が押してしまう。
  Widget _bottomButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 180,
          height: 52,
          child: TvPiFocusButton(
            label: '戻る',
            onPressed: _backToTerms,
            color: const Color(0xFF5A6472),
            focusNode: _backFocus,
            autofocus: true,
            fontSize: 18,
            borderRadius: 10,
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 400,
          height: 52,
          child: TvPiFocusButton(
            label: '番号で登録できない方はこちら',
            onPressed: _openManualLogin,
            color: const Color(0xFF5A6472),
            focusNode: _manualFocus,
            fontSize: 18,
            borderRadius: 10,
          ),
        ),
      ],
    );
  }
}
