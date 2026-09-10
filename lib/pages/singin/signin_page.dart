import 'dart:convert';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/family/family.dart';
import 'package:amiapp/pages/room/room_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:amiapp/widgets/tv_on_screen_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FocusNode _phoneCodeFocus = FocusNode();
  final FocusNode _phoneIdFocus = FocusNode();
  final FocusNode _phonePassFocus = FocusNode();
  final FocusNode _tvKeyboardFocus = FocusNode();
  final FocusNode _tvActionFocus = FocusNode();

  var _loginMode = 'user';
  var _loading = false;

  /// Google TV のみ: 0=コード, 1=ユーザーID, 2=パスワード
  int _tvStep = 0;

  static const _tvTitles = ['コード', 'ユーザーID', 'パスワード'];

  TextEditingController get _tvController {
    switch (_tvStep) {
      case 1:
        return _idController;
      case 2:
        return _passController;
      default:
        return _codeController;
    }
  }

  bool get _tvIsLast => _tvStep == 2;
  bool get _tvIsPassword => _tvStep == 2;

  @override
  void initState() {
    super.initState();

    Future(() async {
      if (await Permission.camera.status == PermissionStatus.denied) {
        await Permission.camera.request();
      }
      if (await Permission.microphone.status == PermissionStatus.denied) {
        await Permission.microphone.request();
      }

      final prefs = await SharedPreferences.getInstance();
      final loginCode = prefs.getString('login_code');
      if (loginCode != null) {
        _codeController.text = loginCode;
      }

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (TvUtil.isTelevision) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _tvKeyboardFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _idController.dispose();
    _passController.dispose();
    _phoneCodeFocus.dispose();
    _phoneIdFocus.dispose();
    _phonePassFocus.dispose();
    _tvKeyboardFocus.dispose();
    _tvActionFocus.dispose();
    super.dispose();
  }

  void _tvFocusKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      // ボタン側にフォーカスが残らないよう、キーボードへ強制移動
      if (_tvActionFocus.hasFocus) {
        _tvActionFocus.unfocus();
      }
      _tvKeyboardFocus.requestFocus();
    });
  }

  String _loginURL() {
    if (AppDefine.amiApp) {
      return '${AppDefine.baseURL}app/login';
    }
    return '${AppDefine.baseURL}app/v4/loginv6.php';
  }

  Future<void> _login() async {
    if (primaryFocus != null) {
      primaryFocus?.unfocus();
    }
    setState(() {
      _loading = true;
    });

    final url = _loginURL();
    print(url);

    final code = _codeController.text;
    final id = _idController.text;
    final password = _passController.text;

    if (code.isEmpty || id.isEmpty || password.isEmpty) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('確認'),
            content: const Text('ログイン情報を入力してください。'),
            actions: <Widget>[
              SimpleDialogOption(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
      setState(() => _loading = false);
      if (TvUtil.isTelevision) _tvFocusKeyboard();
      return;
    }

    final dio = Dio();
    final data = await dio.post(
      url,
      data: FormData.fromMap({
        'delegatorCode': code,
        'userID': id,
        'password': password,
        'code': code,
        'user_id': id,
      }),
    ).then((response) {
      print(response.data);
      if (response.data['cnt'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _loading = false;
    });

    if (data == null) {
      // ダイアログを待たずにフォーカスを動かすと、OKが押せなくなる。
      await WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
      if (!mounted) return;
      if (TvUtil.isTelevision) _tvRestart();
      return;
    }

    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', true);
    await prefs.setString('login_code', code);
    await prefs.setString('login_id', id);
    await prefs.setString('address', json.encode(data['address']));
    await prefs.setString('autoreceive', json.encode(data['autoreceive']));
    try {
      final family = data['family'];
      String familyName = '';
      if (family is Map) {
        familyName =
            (family['User']?['name'] ?? family['name'] ?? '').toString();
      }
      if (familyName.isNotEmpty) {
        await prefs.setString('family_name', familyName);
      } else {
        await prefs.remove('family_name');
      }
    } catch (_) {
      await prefs.remove('family_name');
    }
    await prefs.setString(
        'login_at', WidgetUtil.dateFormat(DateTime.now(), 'yyyyMMddHHmmss'));

    Map<String, dynamic> settings = data['settings'];

    bool isAnminMode = false;
    for (var k in settings.keys) {
      if (k == 'ANMINMODEFLG' && settings[k] != '0') {
        isAnminMode = true;
      }
    }
    if (isAnminMode) {
      settings['SLEEPMODE'] = '0';
    }
    var mcsType = settings['MCSTYPE'];
    if (mcsType == '3') {
      settings['DISPTYPE'] = '1';
    }
    if (TvUtil.isTelevision) {
      settings['DISPTYPE'] = '1';
    }

    await prefs.setString('settings', json.encode(settings));
    AppManager.saveAppSetting('ANMINMODEFLG', isAnminMode ? '1' : '0');

    if (mcsType == '5') {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, a1, a2) => StaffPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (_) => false,
      );
    } else if (mcsType == '4') {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, a1, a2) => FamilyPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (_) => false,
      );
    } else if (mcsType == '3') {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, a1, a2) => RoomPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (_) => false,
      );
    } else {
      await WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
      if (!mounted) return;
      if (TvUtil.isTelevision) _tvRestart();
    }
  }

  Future<void> _staffLogin() async {
    setState(() {
      _loading = true;
    });
    var url = '${AppDefine.baseURL}app/staff_login';

    var code = _codeController.text;
    var id = _idController.text;
    var password = _passController.text;

    if (code.isEmpty || id.isEmpty || password.isEmpty) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('確認'),
            content: const Text('ログイン情報を入力してください。'),
            actions: <Widget>[
              SimpleDialogOption(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
      setState(() => _loading = false);
      return;
    }

    final dio = Dio();
    var data = await dio.post(
      url,
      data: FormData.fromMap({
        'delegatorCode': code,
        'userID': id,
        'password': password,
        'code': code,
        'user_id': id,
      }),
    ).then((response) {
      print(response.data);
      if (response.data['cnt'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _loading = false;
    });

    if (data == null) {
      WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
      return;
    }

    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', true);
    await prefs.setBool('manager', true);
    await prefs.setString('login_code', code);
    await prefs.setString('address', json.encode(data['address']));
    await prefs.setString('autoreceive', json.encode(data['autoreceive']));
    await prefs.setString('codes', json.encode(data['codes']));

    Map<String, dynamic> settings = data['settings'];

    var mcsType = settings['MCSTYPE'];
    if (mcsType == '3') {
      settings['DISPTYPE'] = '1';
    }
    if (TvUtil.isTelevision) {
      settings['DISPTYPE'] = '1';
    }

    await prefs.setString('settings', json.encode(settings));

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, a1, a2) => StaffPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (_) => false,
    );
  }

  // ---------------------------------------------------------------------------
  // Google TV: 1画面1入力
  // ---------------------------------------------------------------------------

  /// ログインに失敗したとき、最初の「コード」入力からやり直せるようにする。
  /// どこで間違えたか分からないため、3つとも入れ直してもらう。
  void _tvRestart() {
    setState(() {
      _tvStep = 0;
      _codeController.clear();
      _idController.clear();
      _passController.clear();
    });
    _tvFocusKeyboard();
  }

  void _tvGoNext() {
    final text = _tvController.text.trim();
    if (text.isEmpty) {
      WidgetUtil.showSimpleDialog(
        context,
        '${_tvTitles[_tvStep]}を入力してください。',
      );
      _tvFocusKeyboard();
      return;
    }
    if (_tvIsLast) {
      _login();
      return;
    }
    setState(() => _tvStep += 1);
    _tvFocusKeyboard();
  }

  Widget _tvStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _tvStep;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: active ? 28 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF4FC3F7)
                : const Color.fromARGB(255, 200, 200, 200),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }

  Widget _tvValueDisplay() {
    final raw = _tvController.text;
    final shown = _tvIsPassword ? ('•' * raw.length) : raw;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4FC3F7), width: 3),
      ),
      child: Text(
        shown.isEmpty ? '入力してください' : shown,
        style: TextStyle(
          fontSize: 28,
          color: shown.isEmpty ? Colors.grey : Colors.black,
          letterSpacing: _tvIsPassword ? 4 : 1,
        ),
      ),
    );
  }

  Widget _tvSideActionButton() {
    return Focus(
      focusNode: _tvActionFocus,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _tvGoNext();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          // 通常: 明るい青 / フォーカス時: 少し濃い青
          final bg = focused
              ? const Color(0xFF0A4F9C)
              : const Color.fromARGB(255, 115, 176, 236);
          return SizedBox(
            width: 160,
            height: 64,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _tvGoNext,
                child: Center(
                  child: Text(
                    _tvIsLast ? 'ログイン' : '次へ',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTvBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    // 以前はほぼ全幅 → 40%短く（= 60%幅）
    final formWidth = (screenWidth - 160) * 0.6;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _codeController,
          _idController,
          _passController,
        ]),
        builder: (context, _) {
          return Column(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 80, vertical: 24),
                    child: Column(
                      children: [
                        const Text(
                          'テレビ電話ａｍｉシリーズ LiSA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _tvStepIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          '${_tvStep + 1} / 3　${_tvTitles[_tvStep]}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // フォーム（短縮） + 右に次へ/ログイン
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: formWidth,
                              child: _tvValueDisplay(),
                            ),
                            const SizedBox(width: 20),
                            _tvSideActionButton(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // キーボードをフォーカス順の先頭にして入力できるようにする
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: TvOnScreenKeyboard(
                  controller: _tvController,
                  firstKeyFocusNode: _tvKeyboardFocus,
                  // 次へ/ログインはフォーム右のボタンを使う
                  onNext: null,
                  onDone: null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // スマホ: 従来どおり1画面に3項目 + スタッフトグル
  // ---------------------------------------------------------------------------

  Widget _buildPhoneBody() {
    final Size size = MediaQuery.of(context).size;
    double verticalPadding = 150.0;
    double verticalPadding2 = 50.0;
    if (size.height < 700) {
      verticalPadding = 80.0;
      verticalPadding2 = 10.0;
    }
    double paddingX = 50;
    if (size.width > 700) {
      paddingX = 200;
    }

    return Container(
      padding:
          EdgeInsets.symmetric(vertical: verticalPadding, horizontal: paddingX),
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 247, 247, 247),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding:
            EdgeInsets.symmetric(vertical: verticalPadding2, horizontal: 22.0),
        child: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('コード'),
                const SizedBox(height: 4),
                TextField(
                  controller: _codeController,
                  focusNode: _phoneCodeFocus,
                  decoration: const InputDecoration(
                    fillColor: Colors.white,
                    filled: false,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color.fromARGB(255, 220, 220, 220),
                      ),
                    ),
                    hintText: '',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12.0),
                const Text('ユーザーID'),
                const SizedBox(height: 4),
                TextField(
                  controller: _idController,
                  focusNode: _phoneIdFocus,
                  decoration: const InputDecoration(
                    fillColor: Colors.white,
                    filled: false,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color.fromARGB(255, 220, 220, 220),
                      ),
                    ),
                    hintText: '',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12.0),
                const Text('パスワード'),
                const SizedBox(height: 4),
                TextField(
                  controller: _passController,
                  focusNode: _phonePassFocus,
                  decoration: const InputDecoration(
                    fillColor: Colors.white,
                    filled: false,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color.fromARGB(255, 220, 220, 220),
                      ),
                    ),
                    hintText: '',
                    isDense: true,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 50),
                Center(
                  child: SizedBox(
                    width: size.width - 60 > 200 ? 200 : size.width - 60,
                    height: 40,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _loginMode == 'user'
                            ? const Color.fromARGB(255, 115, 176, 236)
                            : const Color.fromARGB(255, 115, 206, 146),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (_loginMode == 'staff') {
                          _staffLogin();
                          return;
                        }
                        _login();
                      },
                      child: const Text('ログイン'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: () {
                      setState(() {
                        _loginMode = _loginMode == 'user' ? 'staff' : 'user';
                      });
                    },
                    child: Text(
                        _loginMode == 'user' ? 'スタッフはこちら' : 'ユーザーはこちら'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvUtil.isTelevision;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 238, 239, 243),
      // ソフトキーボードで画面を縮めない。
      //
      // 縮めると、下の SingleChildScrollView が足している
      // viewInsets.bottom の余白と二重になり、二度押し上げられる。
      // そのうえ上下の余白（verticalPadding=150）は縮まないので、
      // 使える高さが潰れて入力フォームが隠れてしまう。
      // スマホ・タブレット（isTv=false）でだけ起きていた。
      // ami_tv 側と同じ false に戻す。（2026-09-05）
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (isTv) _buildTvBody() else _buildPhoneBody(),
          if (_loading)
            Align(
              alignment: FractionalOffset.center,
              child: Container(
                color: Colors.grey.withOpacity(0.3),
                child: const Padding(
                  padding: EdgeInsets.all(5.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
