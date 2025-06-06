import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import '../../services/appmanager.dart';
import 'elan_tab_page.dart';

class ElanHomePage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  const ElanHomePage({super.key, required this.tabPageState});

  @override
  State<ElanHomePage> createState() => ElanHomePageState();
}

class ElanHomePageState extends State<ElanHomePage> {
  late final WebViewController _controller;
  late final String _url;

  dynamic _tv;
  String _myName = '';
  String _today = WidgetUtil.dateFormat(DateTime.now(), 'yyyy/M/d(EEE)');

  @override
  void initState() {
    super.initState();

    _url =
        '${AppDefine.baseURL}elan/home?token=${AppManager.settings['api_token']}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('flutterApp', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => setState(() {})))
      ..loadRequest(Uri.parse(_url));

    _fetchTvAccount();
  }

  /* ---------- JS からの通知 ---------- */
  void _onJsMessage(JavaScriptMessage msg) {
    switch (msg.message) {
      case 'drug':
        widget.tabPageState.selectTabIndex(1);
        break;
      case 'health':
        widget.tabPageState.selectTabIndex(2);
        break;
      case 'dayService':
        widget.tabPageState.selectTabIndex(4);
        break;
    }
  }

  Future<void> _fetchTvAccount() async {
    final dio = Dio();
    final url =
        '${AppDefine.baseURL}elan/api/tv_account?token=${AppManager.settings['api_token']}';
    try {
      final res = await dio.get(url);
      setState(() {
        _tv = res.data['user'];
        _myName = res.data['my_name'];
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void updateAppBar() {
    _controller.loadRequest(Uri.parse(_url));
    setState(
        () => _today = WidgetUtil.dateFormat(DateTime.now(), 'yyyy/M/d(EEE)'));
    _fetchTvAccount();
  }

  Future<void> _toSettingPage() async {
    final url =
        '${AppDefine.baseURL}elan/setting?token=${AppManager.settings['api_token']}';
    _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 48.0;

    return Scaffold(
      appBar: WidgetUtil.homeAppBar(
        _myName,
        _today,
        _toSettingPage,
        actions: [
          GestureDetector(
            onTap: () => widget.tabPageState.toProfileImage(),
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              width: iconSize,
              height: iconSize,
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(iconSize / 2),
                child: Image.network(
                  "${AppDefine.baseURL}elan/api/profile_image?token=${AppManager.settings['api_token']}",
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
