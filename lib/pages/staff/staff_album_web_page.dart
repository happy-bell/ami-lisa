import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../appdefine.dart';
import '../../services/appmanager.dart';

class StaffAlbumWebPage extends StatefulWidget {
  final String title;
  final String targetId;
  final String targetName;
  StaffAlbumWebPage({required this.title, required this.targetId, required this.targetName});

  @override
  _StaffAlbumWebPageState createState() => _StaffAlbumWebPageState();
}

class _StaffAlbumWebPageState extends State<StaffAlbumWebPage> {
  late WebViewController _controller;
  var _isTitleBar = true;
  var _url = '';

  @override
  void initState() {
    super.initState();
    print('staffalbumweb initState');
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('staffalbumweb didChangeDependencies');

    var cd = AppManager.delegatorCode;
    if (AppManager.selectCode.isNotEmpty) {
      cd = AppManager.selectCode;
    }
    var id = widget.targetId;
    setState(() {
      _url = AppDefine.baseURL + "app/album/?code=$cd&mst_id=$id&ua=fl";;
      print(_url);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [];

    return Scaffold(
      appBar: _isTitleBar ? AppBar(
        title: Text(widget.title),
        actions: actions,
      ) : null,
      body: Builder(builder: (BuildContext context) {
        return _url == ''
            ? Container(
          color: Colors.grey.withOpacity(0.3),
          width: MediaQuery.of(context).size.width, //70.0,
          height: MediaQuery.of(context).size.height, //70.0,
          child: const Padding(
              padding: EdgeInsets.all(5.0),
              child: Center(child: CircularProgressIndicator())),
        )
            : SafeArea(
              child: Stack(
          children: [
              WebView(
                initialUrl: _url,
                javascriptMode: JavascriptMode.unrestricted,
                javascriptChannels: {
                  JavascriptChannel(
                    name: 'flutterApp', // 任意の文字列（JS側の呼び出し名になる）
                    onMessageReceived: (result) async {
                      print('flutterApp');

                      Navigator.of(context).pop();
                    },
                  )
                },
                onWebViewCreated: (WebViewController webViewController) {
                  _controller = webViewController;
                },
                onPageFinished: (value) {
                  setState(() {
                    print("====your page is load");
                  });
                },
              ),
          ],
        ),
            );
      }),
    );
  }
}
