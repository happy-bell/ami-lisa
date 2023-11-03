import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amiapp/appdefine.dart';
import '../../helpers/widget_util.dart';
import '../../services/appmanager.dart';
import 'elan_tab_page.dart';

class ElanDayServicePage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  ElanDayServicePage({Key? key, required this.tabPageState}) : super(key: key);

  @override
  State<ElanDayServicePage> createState() => ElanDayServicePageState();
}

class ElanDayServicePageState extends State<ElanDayServicePage> {
  var _url = "";
  final Completer<WebViewController> _controller = Completer<WebViewController>();

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      WebView.platform = SurfaceAndroidWebView();
    }
    _url = '${AppDefine.baseURL}elan/day_service?token=${AppManager.settings['api_token']}';
  }

  void reload() {
    _controller.future.then((controller) async {
      controller.loadUrl(_url);
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