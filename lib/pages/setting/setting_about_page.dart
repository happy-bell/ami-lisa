import 'package:flutter/material.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/common/webview_page.dart';

import '../../helpers/widget_util.dart';

class SettingAboutPage extends StatefulWidget {
  const SettingAboutPage({super.key});

  @override
  _SettingAboutPageState createState() => _SettingAboutPageState();
}

class _SettingAboutPageState extends State<SettingAboutPage> {
  var title = '';

  final _listHeight = 44.0;
  final TextStyle _titleTextStyle1 = const TextStyle(
    fontSize: 14,
  );

  Widget separator() {
    return Container(
      color: Color.fromARGB(255, 240, 240, 240),
      padding: EdgeInsets.all(10.0),
    );
  }

  Widget nextListContainer(String title, String subtitle, Function ontap) {
    return InkWell(
      onTap: () {
        ontap();
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: _listHeight,
        // margin: const EdgeInsets.all(0.0),
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: _titleTextStyle1,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  subtitle,
                  style: _titleTextStyle1,
                ),
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
              nextListContainer('利用規約', '', () {_toWebView('利用規約', AppDefine.kiyakuURL);}),
              nextListContainer('プライバシーポリシー', '', () {_toWebView('プライバシーポリシー', AppDefine.policyURL);}),
              nextListContainer('運営会社', '', () {_toWebView('運営会社', AppDefine.companyURL);}),
            ],
          ),
        ],
      ),
    );
  }
}
