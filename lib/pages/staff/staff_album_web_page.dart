import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../appdefine.dart';
import '../../services/appmanager.dart';

class StaffAlbumWebPage extends StatefulWidget {
  final String title;
  final String targetId;
  final String targetName;
  const StaffAlbumWebPage({
    super.key,
    required this.title,
    required this.targetId,
    required this.targetName,
  });

  @override
  State<StaffAlbumWebPage> createState() => _StaffAlbumWebPageState();
}

class _StaffAlbumWebPageState extends State<StaffAlbumWebPage> {
  late WebViewController _controller;
  String _url = '';
  final bool _isTitleBar = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final cd = AppManager.selectCode.isNotEmpty
        ? AppManager.selectCode
        : AppManager.delegatorCode;
    _url =
        "${AppDefine.baseURL}app/album/?code=$cd&mst_id=${widget.targetId}&ua=fl";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'flutterApp',
        onMessageReceived: (_) => Navigator.of(context).pop(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => setState(() {})),
      )
      ..loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _isTitleBar ? AppBar(title: Text(widget.title)) : null,
        body: _url.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(child: WebViewWidget(controller: _controller)),
      );
}
