import 'dart:convert';
import "package:intl/intl.dart";
import 'package:intl/date_symbol_data_local.dart';

class AppDefine {
  // static final baseURL = 'https://mcs-a.com/frinurse/';
  static const amiURL = 'https://fun-talk.net/amiapp/';
  static final mcsaURL = 'https://mcs-a.com/frinurse/';
  static String get baseURL => _amiApp ? amiURL : mcsaURL;
  static const appLabel = 'テレビ電話アミ';
  static const elanApp = false;
  static const _amiApp = true;
  static bool get amiApp => _amiApp;

  static const kiyakuURL = 'https://happybell.biz/terms/index.html';
  static const policyURL = 'https://happybell.biz/privacy/index.html';
  static const signUpURL = 'https://happybell.biz/sign_up/index.html';
  static const companyURL = 'https://happybell.biz/service/index.html';
  static const licenseURL = 'https://happybell.biz/license/index.html';

  // 呼び出し未応答の自動切断(ミリ秒)
  static const absenceSec1 = 30 * 1000;
  static const absenceSec2 = 10 * 1000;

  static getRMSToken() {
    initializeDateFormatting("ja_JP");
    final now = DateTime.now();
    var formatter = DateFormat('yyyyMMddHHmmss', "ja_JP");
    var formatted = formatter.format(now);
    final str = "telnurseapptoken$formatted";
    List<int> bytes = utf8.encode(str);
    return base64.encode(bytes);
  }

  static getDelegatorToken() {
    return 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ';
  }
}

class ImageName {
  static const connecting = 'assets/images/talk/connecting.png';
  static const rusu = 'assets/images/talk/rusu.png';
  static const addrCall = 'assets/images/status/addr_call.png';
}
