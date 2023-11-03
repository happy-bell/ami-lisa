import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../helpers/widget_util.dart';

class WebviewPage extends StatefulWidget {
  final String title;
  final String url;
  WebviewPage({required this.title, required this.url});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  var _title = "";
  var _url = "";
  bool _load = true;

  @override
  void initState() {
    super.initState();

    _title = widget.title;
    _url = widget.url;
    if (Platform.isAndroid) {
      WebView.platform = SurfaceAndroidWebView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: WebView(
        initialUrl: widget.url,
        onPageFinished:(value) {
          setState(() {
            // print("====your page is load");
          });
        },
      )
    );
  }
}