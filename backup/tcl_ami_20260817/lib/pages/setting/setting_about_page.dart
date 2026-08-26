import 'package:flutter/material.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/common/webview_page.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

import '../../helpers/widget_util.dart';

class SettingAboutPage extends StatefulWidget {
  const SettingAboutPage({super.key});

  @override
  _SettingAboutPageState createState() => _SettingAboutPageState();
}

class _SettingAboutPageState extends State<SettingAboutPage> {
  var title = '';

  final _listHeight = 44.0;

  Widget separator() {
    return Container(
      color: Color.fromARGB(255, 240, 240, 240),
      padding: EdgeInsets.all(10.0),
    );
  }

  Widget nextListContainer(String title, String subtitle, Function ontap,
      {bool autofocus = false}) {
    final height = TvUtil.isTelevision ? 64.0 : _listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);
    return TvSettingFocus(
      autofocus: autofocus,
      onActivate: () => ontap(),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: style),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(subtitle, style: style),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 18.0,
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toWebView(String title, String url) async {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(
        builder: (context) => WebviewPage(title: title, url: url),
        fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('このアプリについて'),
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ListView(
            children: [
              nextListContainer('利用規約', '', () {_toWebView('利用規約', AppDefine.kiyakuURL);}, autofocus: TvUtil.isTelevision),
              nextListContainer('プライバシーポリシー', '', () {_toWebView('プライバシーポリシー', AppDefine.policyURL);}),
              nextListContainer('運営会社', '', () {_toWebView('運営会社', AppDefine.companyURL);}),
            ],
          ),
        ],
      ),
    );
  }
}
