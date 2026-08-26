import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amiapp/helpers/tv_util.dart';

import '../../helpers/widget_util.dart';

class WebviewPage extends StatefulWidget {
  final String title;
  final String url;
  const WebviewPage({super.key, required this.title, required this.url});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) {
          if (TvUtil.isTelevision) {
            _controller.runJavaScript('''
              document.documentElement.style.overflow = 'auto';
              document.body.style.overflow = 'auto';
              document.body.style.height = 'auto';
            ''');
          }
          if (mounted) setState(() {});
        }),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _scrollBy(int direction) async {
    await _controller.runJavaScript(
      'window.scrollBy(0, $direction * Math.max(160, Math.floor(window.innerHeight * 0.7)));',
    );
  }

  @override
  Widget build(BuildContext context) {
    final webView = WebViewWidget(controller: _controller);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: TvUtil.isTelevision
          ? Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.pageDown) {
                  _scrollBy(1);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.pageUp) {
                  _scrollBy(-1);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: webView,
            )
          : webView,
    );
  }
}
