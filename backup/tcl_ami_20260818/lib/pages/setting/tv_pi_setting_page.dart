import 'dart:convert';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/setting/setting_select_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
    final mstId = AppManager.myId.replaceAll('${AppManager.delegatorCode}_', '');
    final url =
        '${AppDefine.baseURL}app/address_list?code=${AppManager.delegatorCode}&mst_id=$mstId&token=${AppManager.settings['api_token']}';
    try {
      final dio = Dio();
      final response = await dio.get(url);
      final data = response.data;
      if (data is Map && data['address'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('address', json.encode(data['address']));
        if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E0),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF333333),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: const Text(
                  '設定-ログイン',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(48, 20, 48, 24),
                  children: [
                    _btn('ログアウト', const Color(0xFF555555), _logout,
                        autofocus: true),
                    _btn('アカウント更新', const Color(0xFFB33A3A), _updateAccount),
                    _btn('テレビ電話画面', const Color(0xFF5BA3D9), () {
                      Navigator.of(context).pop();
                    }),
                    const SizedBox(height: 16),
                    _infoRow('コード:', _code),
                    const SizedBox(height: 8),
                    _infoRow('ユーザーID:', AppManager.loginId),
                    const SizedBox(height: 16),
                    _btn(
                      '天気  ${AppManager.weatherAreaLabel()}',
                      const Color(0xFF555555),
                      _openWeather,
                    ),
                    if (AppManager.isDoctorAccount)
                      _btn(
                        'Doc/Pat  ${AppManager.amiModeLabel()}',
                        const Color(0xFF555555),
                        _toggleDocPat,
                      ),
                    _btn(
                      'ホーム画面  ${AppManager.tvLayoutLabel()}',
                      const Color(0xFF555555),
                      _changeLayout,
                    ),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _message,
                          style: const TextStyle(
                            fontSize: 20,
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
      {bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: 8,
        onPressed: onPressed,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(fontSize: 22)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Text(value, style: const TextStyle(fontSize: 22)),
          ),
        ),
      ],
    );
  }
}
