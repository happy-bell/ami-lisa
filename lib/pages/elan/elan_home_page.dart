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

class ElanHomePage extends StatefulWidget {
  final ElanTabPageState tabPageState;
  ElanHomePage({Key? key, required this.tabPageState}) : super(key: key);

  @override
  State<ElanHomePage> createState() => ElanHomePageState();
}

class ElanHomePageState extends State<ElanHomePage> {
  var _url = "";
  dynamic _tv;
  String _myName = '';
  final Completer<WebViewController> _controller = Completer<WebViewController>();
  var _today = WidgetUtil.dateFormat(DateTime.now(), 'yyyy/M/d(EEE)');

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      WebView.platform = SurfaceAndroidWebView();
    }
    _url = '${AppDefine.baseURL}elan/home?token=${AppManager.settings['api_token']}';

    Future(() {
      _getData();
    });
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
  }

  Future<void> _getData() async {
    final dio = Dio();
    var url = '${AppDefine.baseURL}elan/api/tv_account?token=${AppManager.settings['api_token']}';
    // print(url);

    var data = await dio.get(
      url,
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    if (data == null) {
      return;
    }

    print(data);

    setState(() {
      _tv = data['user'];
      _myName = data['my_name'];
    });
  }

  void updateAppBar() {
    _controller.future.then((controller) async {
      // print(await controller.currentUrl());
      controller.loadUrl(_url);
      // controller.reload();
    });
    setState(() {
      _today = WidgetUtil.dateFormat(DateTime.now(), 'yyyy/M/d(EEE)');
    });
    _getData();
  }

  Future<void> _toSettingPage() async {
    _controller.future.then((controller) {
      final url = '${AppDefine.baseURL}elan/setting?token=${AppManager.settings['api_token']}';
      controller.loadUrl(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 48.0;
    return Scaffold(
        appBar: WidgetUtil.homeAppBar(_myName, _today, () {
          _toSettingPage();
        },
          actions: [
          GestureDetector(
            onTap: () {
              widget.tabPageState.toProfileImage();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              width: iconSize,
              height: iconSize,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(iconSize / 2),
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: Image.network(
                      "${AppDefine.baseURL}elan/api/profile_image?token=${AppManager.settings['api_token']}",
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
                        if (result.message == 'drug') {
                          widget.tabPageState.selectTabIndex(1);
                        }
                        if (result.message == 'health') {
                          widget.tabPageState.selectTabIndex(2);
                        }
                        if (result.message == 'dayService') {
                          widget.tabPageState.selectTabIndex(4);
                        }
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