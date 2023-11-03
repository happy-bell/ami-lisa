import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/common/webview_page.dart';

import '../../helpers/widget_util.dart';
import 'elan_signin_page.dart';

class ElanTutorialPage extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const double fontSize = 14;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bgImage = constraints.maxWidth > 500 ? 'assets/images/tutorial/first_iPad.png' : 'assets/images/tutorial/first_iPhone.png';
          final douiImage = constraints.maxWidth > 500 ? 'assets/images/tutorial/doui_Pad.png' : 'assets/images/tutorial/doui_iPhone.png';
          final douiWidth = constraints.maxWidth > 600 ? 300.0 : 190.0;
          final douiHeight = douiWidth / 88 * 29;

          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(bgImage),
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              Positioned(
                top: constraints.maxHeight / 2 -20,
                left: 20,
                width: constraints.maxWidth - 40,
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        child: Image.asset(
                          douiImage,
                          width: douiWidth,
                          height: douiHeight,
                        ),
                        onTap: () async {
                          var prefs = await SharedPreferences.getInstance();
                          await prefs.setBool("isInitialized", true);
                          Navigator.of(context)
                              .pushReplacement(MaterialPageRoute(builder: (context) => ElanSignInPage()));
                        }
                      ),
                      const SizedBox(height: 60),
                      Center(child: WidgetUtil.basicText('サービス事業者より申し込みを行ってください。'))
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}