import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/common/webview_page.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  Future<void> _agree(BuildContext context) async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isInitialized", true);

    await Navigator.of(context, rootNavigator: true).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1,
            Animation<double> animation2) {
          return SignInPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double fontSize = TvUtil.isTelevision ? 24 : 20;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          var bgImage = constraints.maxWidth > 500
              ? 'assets/images/tutorial/first_iPad.png'
              : 'assets/images/tutorial/first_iPhone.png';
          var douiImage = constraints.maxWidth > 500
              ? 'assets/images/tutorial/doui_Pad.png'
              : 'assets/images/tutorial/doui_iPhone.png';
          var douiWidth = constraints.maxWidth > 600 ? 300.0 : 190.0;
          var douiHeight = douiWidth / 88 * 29;

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
                top: constraints.maxHeight / 2 - 20,
                left: 20,
                width: constraints.maxWidth - 40,
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TvFocusable(
                        autofocus: TvUtil.isTelevision,
                        onPressed: () => _agree(context),
                        child: GestureDetector(
                          child: Image.asset(
                            douiImage,
                            width: douiWidth,
                            height: douiHeight,
                          ),
                          onTap: () => _agree(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: constraints.maxHeight > 800 ? 310 : 200,
                left: 40,
                width: constraints.maxWidth - 80,
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: fontSize,
                      ),
                      children: [
                        const TextSpan(
                          text: 'ご利用には',
                        ),
                        TextSpan(
                          text: '利用規約',
                          style: const TextStyle(
                            color: Colors.teal,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (context) => WebviewPage(
                                          title: '利用規約',
                                          url: AppDefine.kiyakuURL),
                                      fullscreenDialog: true));
                            },
                        ),
                        const TextSpan(
                          text: 'および',
                        ),
                        TextSpan(
                          text: '個人情報保護方針',
                          style: const TextStyle(
                            color: Colors.teal,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (context) => WebviewPage(
                                          title: '個人情報保護方針',
                                          url: AppDefine.policyURL),
                                      fullscreenDialog: true));
                            },
                        ),
                        const TextSpan(
                          text: 'への同意が必要です。',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 200,
                left: 40,
                width: constraints.maxWidth - 80,
                child: Center(
                  child: Text(
                    'サービス事業者より申し込みを行ってください。',
                    style: TextStyle(fontSize: fontSize),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
