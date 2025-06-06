import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WidgetUtil {
  static const double listHeight = 52.0;
  static const double buttonWidth = 280;
  static const double buttonHeight = 40;

  static Widget get loadingIndicator => Align(
    alignment: FractionalOffset.center,
    child: Container(
      color: Colors.grey.withOpacity(0.3),
      child: const Padding(
        padding: EdgeInsets.all(5.0),
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );

  static Color get primaryBG => const Color.fromARGB(255, 252, 241, 217);//0xfffcf1d9

  static Color get iosNavbarBG => const Color.fromARGB(255, 242, 242, 247);

  static Color get homeAppBarBg => const Color.fromARGB(255, 116, 196, 165);// Color(0xff74c4a5);

  static Color get phoneAppBar => const Color(0xffddeede);

  static TextStyle get titleTextStyle1 => const TextStyle(
    fontSize: 14,
  );

  static TextStyle get titleTextStyle2 => const TextStyle(fontSize: 14, color: Colors.blue);

  static Color get textBorderGray => const Color(0xFFCCCCCC);

  static ButtonStyle get basicButtonStyle => ElevatedButton.styleFrom(
    foregroundColor: Colors.white, backgroundColor: const Color.fromARGB(255, 85, 146, 246),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
  );

  static Widget get listForwardIcon => const SizedBox(
    width: 30,
    child: Icon(
      Icons.arrow_forward_ios,
      color: Color(0xFFCCCCCC),
    ),
  );

  static Widget get listCheckIcon => const SizedBox(
    width: 30,
    child: Icon(
      Icons.check,
      color: Colors.grey,
      size: 18.0,
    ),
  );

  static Widget get dismissBackground => Container(
    padding: const EdgeInsets.only(right: 10,),
    alignment: AlignmentDirectional.centerEnd,
    color: Colors.red,
    child: const Icon(
      Icons.delete,
      color: Colors.white,
    ),
  );

  static PreferredSizeWidget homeAppBar(String name, String date, Function onTap, {Color? backgroundColor, Widget? leading, double? leadingWidth, List<Widget>? actions}) {
    final appbar = AppBar(
      backgroundColor: WidgetUtil.homeAppBarBg,
      foregroundColor: Colors.black,
      centerTitle: false,
      title: GestureDetector(
        onTap: () {
          onTap();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WidgetUtil.basicText(name, color: Colors.white, fontSize: 24,),
            WidgetUtil.basicText(date, color: Colors.white, fontSize: 16,),
          ],
        ),
      ),
      elevation: 0,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
    );
    if (Platform.isIOS) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(70.0),
        child: appbar,
      );
    }

    return appbar;
  }

  static PreferredSizeWidget appBar(String title, {Color? backgroundColor, Color? foregroundColor, Widget? leading, double? leadingWidth, List<Widget>? actions, double borderBottomWidth = 0.5}) {
    final appbar = AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      shape: Border(
        bottom: BorderSide(color: Colors.grey, width: borderBottomWidth),
      ),
      title: Text(title),
      elevation: 0,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
    );
    if (Platform.isIOS) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(43.0),
        child: appbar,
      );
    }

    return appbar;
  }

  static PreferredSizeWidget smallAppBar(String title, {Color? backgroundColor, Color? foregroundColor, Widget? leading, double? leadingWidth, List<Widget>? actions, double borderBottomWidth = 0.5}) {
    final appbar = AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      title: Text(title),
      elevation: 0,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
    );
    if (Platform.isIOS) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: appbar,
      );
    }

    return appbar;
  }

  static Text basicText(String text, {Color color = const Color(0xFF1d1d1d), TextAlign? textAlign = TextAlign.start, double? fontSize = 14, FontWeight? fontWeight = FontWeight.normal}) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        decoration: TextDecoration.none,
      ),
    );
  }

  static Widget basicTextField2(TextEditingController controller, String? errText, {String? hintText, int maxLines = 1, TextInputType? keyboardType, bool obscureText = false, Widget? suffixIcon, Function(String)? onSubmitted}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        fillColor: const Color.fromARGB(255, 255, 255, 255),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
          borderSide: BorderSide.none,
        ),
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFFcccccc),
        ),
        isDense: true,
        errorText: errText,
        suffixIcon: suffixIcon,
      ),
    );
  }

  static Widget basicButton(String text, Function onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Center(
        child: SizedBox(
          width: WidgetUtil.buttonWidth,
          height: WidgetUtil.buttonHeight,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white, backgroundColor: const Color(0xFF108f10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () async {
              onPressed();
            },
            child: Text(text),
          ),
        ),
      ),
    );
  }

  static Widget menuButton(String text, Function onPressed) {
    return Center(
      child: SizedBox(
        width: 200,
        child: ElevatedButton(
          style: WidgetUtil.basicButtonStyle,
          onPressed: () async {
            onPressed();
          },
          child: Text(text),
        ),
      ),
    );
  }

  static Widget normalButton(String text, Function onPressed, {double width = 160, double height = 48, Color? primaryColor = const Color(0xFF009389), Color? foregroundColor = Colors.white, BorderSide? side, double borderRadius = 8, double fontSize = 14}) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          side: side,
        ),
        onPressed: () async {
          onPressed();
        },
        child: Text(text,
          style: TextStyle(
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  static Widget listItem(Widget contents) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10.0,),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color.fromARGB(255, 220, 220, 220),//Colors.grey,
              width: 0.5,
            ),
          ),
        ),
        child: contents,
      ),
    );
  }

  static Widget selectBox(String text, double width) {
    return Container(
      width: width,
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: WidgetUtil.textBorderGray),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Text(text
      ),
    );
  }

  static void showSimpleDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  static Future<void> showAutoDisposeDialog(BuildContext context, String message) async {
    const displayTime = Duration(seconds: 2);

    try {
      await showDialog(
          context: context,
          barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('確認'),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      )
          .timeout(displayTime);

    } on TimeoutException {
      Navigator.of(context).pop();
    }
  }

  static Future<bool> showSimpleConfirmDialog(BuildContext context, String message, {String title = '確認'}) async {
    return await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            SimpleDialogOption(
              child: const Text('はい'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
            SimpleDialogOption(
              child: const Text('いいえ'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
          ],
        );
      },
    );
  }

  // static Widget loadingIndicator(bool loading, BuildContext context) {
  //   if (!loading) {
  //     return Container();
  //   }
  //   return Container(
  //     color: Colors.grey.withOpacity(0.3),
  //     width: MediaQuery.of(context).size.width, //70.0,
  //     height: MediaQuery.of(context).size.height, //70.0,
  //     child: const Padding(
  //       padding: EdgeInsets.all(5.0),
  //       child: Center(child: CircularProgressIndicator()),
  //     ),
  //   );
  // }

  static String numberFormat(num) {
    final formatter = NumberFormat('#,##0', 'ja_JP');
    return formatter.format(num);
  }

  static String dateFormat(datetime, format) {
    var formatter = DateFormat(format, "ja_JP");
    var formatted = formatter.format(datetime);
    return formatted;
  }
}