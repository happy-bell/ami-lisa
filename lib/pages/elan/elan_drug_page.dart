import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import '../../services/appmanager.dart';
import 'elan_tab_page.dart';

class ElanDrugPage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  ElanDrugPage({Key? key, required this.tabPageState}) : super(key: key);

  @override
  State<ElanDrugPage> createState() => ElanDrugPageState();
}

class ElanDrugPageState extends State<ElanDrugPage> {
  var _url = "";
  final Completer<WebViewController> _controller = Completer<WebViewController>();

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      WebView.platform = SurfaceAndroidWebView();
    }
    _url = '${AppDefine.baseURL}elan/drug?token=${AppManager.settings['api_token']}';
  }

  void reload() {
    _controller.future.then((controller) async {
      // print(await controller.currentUrl());
      controller.loadUrl(_url);
      // controller.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: WidgetUtil.smallAppBar('',
          backgroundColor: WidgetUtil.primaryBG,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_url.isNotEmpty)
                WebView(
                  initialUrl: _url,
                  onWebViewCreated: (WebViewController webViewController) async {
                    await webViewController.clearCache();
                    _controller.complete(webViewController);
                  },
                  onPageFinished:(value) {
                    setState(() {
                      // print("====your page is load");
                    });
                  },
                  javascriptMode: JavascriptMode.unrestricted,
                  javascriptChannels: {
                    JavascriptChannel(
                      name: 'flutterApp',
                      onMessageReceived: (result) async {
                        print(result.message);
                      },
                    )
                  },
                ),
            ],
          ),
        )
    );
  }
}