import 'dart:convert';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/pages/setting/setting_select_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/and_vital_pair_dialog.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ラズパイ版の設定（46amip4 設定-ログイン相当）。
/// 電源を切る / Wifi・BLE設定 は出さない。TCLアミ／スタッフからは開かない。
class TvPiSettingPage extends StatefulWidget {
  const TvPiSettingPage({super.key});

  @override
  State<TvPiSettingPage> createState() => _TvPiSettingPageState();
}

class _TvPiSettingPageState extends State<TvPiSettingPage> {
  bool _loading = false;
  String _message = '';
  String _version = '';
  final FocusNode _tvPhoneFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    AppManager.appVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvPhoneFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _tvPhoneFocus.dispose();
    super.dispose();
  }

  String get _code =>
      AppManager.delegatorCode.isNotEmpty
          ? AppManager.delegatorCode
          : (AppManager.settings['DELEGATORCODE'] ?? '').toString();

  Future<void> _logout() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TvDialogAction(
            autofocus: TvUtil.isTelevision,
            label: 'キャンセル',
            onPressed: () => Navigator.pop(context, '0'),
          ),
          TvDialogAction(
            label: 'OK',
            onPressed: () => Navigator.pop(context, '1'),
          ),
        ],
      ),
    );
    if (value != '1' || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    await prefs.setBool('manager', false);
    await prefs.remove('codes');
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      pageBuilder: (context, a1, a2) => const SignInPage(),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ));
  }

  Future<void> _updateAccount() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    // 46amip4 get_amiaddress.php と同じ app/address_list。
    final code = (AppManager.settings['DELEGATORCODE'] ??
            AppManager.settings['delegatorcode'] ??
            AppManager.delegatorCode)
        .toString();
    final myId = (AppManager.settings['MYID'] ??
            AppManager.settings['myId'] ??
            AppManager.myId)
        .toString();
    var mstId = myId.replaceAll('${code}_', '');
    if (mstId == myId && myId.contains('_')) {
      mstId = myId.substring(myId.indexOf('_') + 1);
    }
    final token = (AppManager.settings['api_token'] ?? '').toString();
    if (code.isEmpty || mstId.isEmpty || token.isEmpty) {
      setState(() {
        _loading = false;
        _message = 'アカウントを更新できませんでした。';
      });
      return;
    }
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppDefine.baseURL}app/address_list',
        queryParameters: {
          'code': code,
          'mst_id': mstId,
          'token': token,
        },
      );
      dynamic data = response.data;
      if (data is String && data.isNotEmpty) {
        data = json.decode(data);
      }
      final raw = data is Map ? (data['address'] ?? data['ADDRESS']) : null;
      if (raw is List) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('address', json.encode(raw));
        if (mounted) {
          try {
            context.read<AddressStore>().setAddressList(raw);
          } catch (e) {
            print('[TvPiSetting] address store $e');
          }
          setState(() => _message = 'アカウントを更新しました。');
        }
      } else if (mounted) {
        setState(() => _message = 'アカウントを更新できませんでした。');
      }
    } catch (e) {
      print('[TvPiSetting] address update error $e');
      if (mounted) {
        setState(() => _message = 'アカウントを更新できませんでした。');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openWeather() async {
    if (AppManager.weatherAreas.isEmpty) {
      AppManager.weatherAreas =
          List<List<String>>.from(AppManager.defaultWeatherAreas);
    }
    final result = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => SettingSelectPage(
        keyName: 'WEATHER_AREA',
        value: AppManager.weatherArea,
      ),
    ));
    if (result != null) {
      await AppManager.saveWeatherArea(result);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleDocPat() async {
    if (!AppManager.isDoctorAccount) return;
    final next = AppManager.amiMode == AppManager.amiModeDoctor
        ? AppManager.amiModePatient
        : AppManager.amiModeDoctor;
    final msg = next == AppManager.amiModeDoctor
        ? 'ドクターモードへ切り替えます'
        : '患者モードへ切り替えます';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: Text(msg),
        actions: [
          TvDialogAction(
            autofocus: TvUtil.isTelevision,
            label: 'キャンセル',
            onPressed: () => Navigator.pop(context, '0'),
          ),
          TvDialogAction(
            label: 'OK',
            onPressed: () => Navigator.pop(context, '1'),
          ),
        ],
      ),
    );
    if (value != '1') return;
    await AppManager.saveAmiMode(next);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _changeLayout() async {
    final result = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => SettingSelectPage(
        keyName: 'TV_LAYOUT',
        value: AppManager.tvLayout,
      ),
    ));
    if (result != null) {
      await AppManager.saveTvLayout(result);
    }
    if (mounted) {
      if (result == AppManager.tvLayoutTcl) {
        Navigator.of(context).pop();
      } else {
        setState(() {});
      }
    }
  }

  static const _weatherBtnColor = Color(0xFF555555);

  @override
  Widget build(BuildContext context) {
    final contentW = MediaQuery.sizeOf(context).width - 96;
    final menuW = contentW * 0.7;
    final halfW = (menuW - 8) / 2;
    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E0),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF333333),
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 3),
                child: Row(
                  children: [
                    const Text(
                      '設定-ログイン',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    const Spacer(),
                    if (_version.isNotEmpty)
                      Text(
                        'Ver. $_version',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(48, 20, 48, 24),
                  children: [
                    _btn('ログアウト', _weatherBtnColor, _logout, width: menuW),
                    _btn('アカウント更新', _weatherBtnColor, _updateAccount,
                        width: menuW),
                    _btn('テレビ電話', _weatherBtnColor, () {
                      Navigator.of(context).pop();
                    }, width: menuW, autofocus: true, focusNode: _tvPhoneFocus),
                    const SizedBox(height: 16),
                    _infoRow('コード:', _code, menuW),
                    const SizedBox(height: 8),
                    _infoRow('ユーザーID:', AppManager.loginId, menuW),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: menuW,
                        child: Row(
                          children: [
                            SizedBox(
                              width: halfW,
                              child: _btn(
                                '天気  ${AppManager.weatherAreaLabel()}',
                                _weatherBtnColor,
                                _openWeather,
                                width: halfW,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: halfW,
                              child: _btn(
                                'BLE ペアリング',
                                _weatherBtnColor,
                                () {
                                  showDialog<void>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => const AndVitalPairDialog(),
                                  );
                                },
                                width: halfW,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (AppManager.isDoctorAccount)
                      _btn(
                        'Doc/Pat  ${AppManager.amiModeLabel()}',
                        _weatherBtnColor,
                        _toggleDocPat,
                        width: menuW,
                      ),
                    _btn(
                      'ホーム画面  ${AppManager.tvLayoutLabel()}',
                      _weatherBtnColor,
                      _changeLayout,
                      width: menuW,
                    ),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20 * 0.8,
                            color: Color(0xFFCC3333),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_loading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onPressed,
      {required double width, bool autofocus = false, FocusNode? focusNode}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: width,
          child: TvPiFocusButton(
            label: label,
            onPressed: onPressed,
            color: color,
            autofocus: autofocus,
            focusNode: focusNode,
            padding: const EdgeInsets.symmetric(vertical: 11.2 * 0.95),
            fontSize: 20.8,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, double width) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: width,
        child: Row(
          children: [
            SizedBox(
              width: 112,
              child: Text(label, style: const TextStyle(fontSize: 17.6)),
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: Colors.white,
                child: Text(value,
                    style: const TextStyle(fontSize: 17.6 * 1.15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
