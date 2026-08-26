import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amiapp/appdefine.dart';
import '../../helpers/widget_util.dart';
import '../../services/appmanager.dart';
import 'elan_tab_page.dart';

class ElanHealthPage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  const ElanHealthPage({super.key, required this.tabPageState});

  @override
  State<ElanHealthPage> createState() => ElanHealthPageState();
}

class ElanHealthPageState extends State<ElanHealthPage> {
  late final WebViewController _controller;
  late final String _url;

  @override
  void initState() {
    super.initState();

    _url =
        '${AppDefine.baseURL}elan/health?token=${AppManager.settings['api_token']}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('flutterApp',
          onMessageReceived: (msg) => debugPrint(msg.message))
      ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => setState(() {})))
      ..loadRequest(Uri.parse(_url));
  }

  void reload() => _controller.loadRequest(Uri.parse(_url));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            WidgetUtil.smallAppBar('', backgroundColor: WidgetUtil.primaryBG),
        body: SafeArea(child: WebViewWidget(controller: _controller)),
      );
}
