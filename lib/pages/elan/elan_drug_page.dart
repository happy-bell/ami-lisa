import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amiapp/appdefine.dart';
import '../../helpers/widget_util.dart';
import '../../services/appmanager.dart';
import 'elan_tab_page.dart';

class ElanDrugPage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  const ElanDrugPage({super.key, required this.tabPageState});

  @override
  State<ElanDrugPage> createState() => ElanDrugPageState();
}

class ElanDrugPageState extends State<ElanDrugPage> {
  late final WebViewController _controller;
  late final String _url;

  @override
  void initState() {
    super.initState();

    _url =
        '${AppDefine.baseURL}elan/drug?token=${AppManager.settings['api_token']}';

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
