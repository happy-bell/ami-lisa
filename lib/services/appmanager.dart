import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:intl/intl.dart";
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/services/socket_io_service.dart';

enum AppStatus {
  None,
  Call,
  Talk,
  Hold,
  Holded,
  Response,
  Multi,
  Check,
  Receive,
  MultiToTalk,
}

class AppManager {
  static var settings = {};
  static bool isManager = false;
  static dynamic appsettings = {"AUTO_RECEIVE": "0", "SLEEP_MODE": "0", "SLEEP_CLOCK": "0", "SLEEPMODEBRIGHTNESS": "0", "SENSOR0": "0", "SENSOR1": "0", "SENSOR2": "0", "SENSOR3": "0", "SENSOR4": "0", "SENSOR5": "0", "SENSOR8": "0", "SENSOR9": "0", "RINGTONE": "0", "CALLSCREENIMAGE": "0", "CALLSCREENIMAGEL": "0", "VOLUME_CALL": "0", "CLOCKDISP": "0", "DISPLAYNUM": "3", "CALLSTATUSDISP": "0"};
  static var autoreceives = {};
  static var authReceives = {};
  static List<List<String>> ringtones = [];
  static List<List<String>> weatherAreas = [];
  static List<List<String>> callScreenImages = [];
  static String? fcmtoken;
  static AppStatus status = AppStatus.None;
  static String selectCode = '';
  static Address? selectUser;
  static String myId = '';
  static String delegatorCode = '';

  static String talkId1 = '';
  static String talkId2 = '';
  static String holdId = '';
  static String holdedId = '';
  static String threewayId = '';
  static String safetyCheckId = '';
  static String autoReceiveId = '';

  static String recordId = '';
  static String recordConnectId = '';
  static bool isRecording = false;

  static bool isMute = false;
  static bool isVideoMute = false;

  static String toPage = '';

  static String statusValue() {
    if (AppManager.status == AppStatus.None) { return "0"; }
    if (AppManager.status == AppStatus.Call) { return "1"; }
    if (AppManager.status == AppStatus.Talk) { return "2"; }
    if (AppManager.status == AppStatus.Response) { return "2"; }
    if (AppManager.status == AppStatus.Hold) { return "3"; }
    if (AppManager.status == AppStatus.Holded) { return "4"; }
    if (AppManager.status == AppStatus.Multi) { return "5"; }
    if (AppManager.status == AppStatus.MultiToTalk) { return "5"; }
    if (AppManager.settings['DISPTYPE'] == '2') { return "9"; }

    // Check,
    // Receive,

    return "0";
  }

  static Future<String> appVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    // String appName = packageInfo.appName;
    // String packageName = packageInfo.packageName;
    // String buildNumber = packageInfo.buildNumber;

    String version = packageInfo.version;
    return version;
  }

  static Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      // SimplePermissions.requestPermission(Permission.WriteExternalStorage);
      var status = await Permission.storage.request();
      print(status);
    } else if (Platform.isIOS) {
      // SimplePermissions.requestPermission(Permission.PhotoLibrary);
    }
    var status = await Permission.camera.request();
    print(status);
    var status2 = await Permission.microphone.request();
    print(status2);
  }

  static dynamic initialAppSettings() {
    return {"AUTO_RECEIVE": "0", "SLEEP_MODE": "0", "SLEEP_CLOCK": "0", "SLEEPMODEBRIGHTNESS": "0", "SENSOR0": "0", "SENSOR1": "0", "SENSOR2": "0", "SENSOR3": "0", "SENSOR4": "0", "SENSOR5": "0", "SENSOR8": "0", "SENSOR9": "0", "RINGTONE": "0", "CALLSCREENIMAGE": "0", "CALLSCREENIMAGEL": "0", "VOLUME_CALL": "0", "CLOCKDISP": "0", "DISPLAYNUM": "3", "CALLSTATUSDISP": "0"};
  }

  static Future<bool> loadSetting() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    String? settingsString = sharedPreferences.getString('settings');
    if (settingsString == null) {
      AppManager.settings = {};
      return false;
    }
    AppManager.settings = json.decode(settingsString);
    // print(AppManager.settings);

    String? appString = sharedPreferences.getString('appsettings');
    if (appString == null) {
      // AppManager.appsettings = AppManager.initalAppSettings();
    } else {
      AppManager.appsettings = json.decode(appString);
      var initAppSetting = AppManager.initialAppSettings();
      initAppSetting.forEach((key, val) {
        if (!AppManager.appsettings.containsKey(key)) {
          AppManager.appsettings[key] = val;
        }
      });
    }

    String? fcmtokenString = sharedPreferences.getString('fcmtoken');
    if (fcmtokenString != null) {
      AppManager.fcmtoken = fcmtokenString;
    }
    AppManager.myId = settings['myId'];
    AppManager.delegatorCode = settings['delegatorcode'];
    var socketservice = SocketIOService();
    socketservice.url = settings['server'];

    bool isManager = sharedPreferences.getBool("manager") ?? false;
    AppManager.isManager = isManager;

    String? authReceivesString = sharedPreferences.getString('authreceives');
    if (authReceivesString != null) {
      AppManager.authReceives = json.decode(authReceivesString);
    }
    return true;
  }

  static saveSetting(String key, String val) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    String? settingsString = sharedPreferences.getString('settings');
    if (settingsString != null) {
      var storedSettings = json.decode(settingsString);
      storedSettings[key] = val;
      await sharedPreferences.setString('settings', json.encode(storedSettings));
    }
    AppManager.settings[key] = val;
    print("save $key " + AppManager.settings[key]);
  }

  static saveAppSetting(String key, String val) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    String? appString = sharedPreferences.getString('appsettings');
    var storedSettings = (appString == null ? AppManager.appsettings : json.decode(appString));
    storedSettings[key] = val;
    await sharedPreferences.setString('appsettings', json.encode(storedSettings));
    AppManager.appsettings = storedSettings;
  }

  static loadAutoReceive() async {
    AppManager.autoreceives = {};
    final sharedPreferences = await SharedPreferences.getInstance();
    String? autoreceive = sharedPreferences.getString('autoreceive');
    print(autoreceive);
    if (autoreceive == null) {
      return;
    }
    var autoreceiveJson = json.decode(autoreceive);
    if (autoreceiveJson is List) {
      autoreceiveJson.forEach((value) {
        AppManager.autoreceives[value[0].toString()] = value[1].toString();
      });
    }
  }

  static saveAuthReceives(String val) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    AppManager.authReceives[AppManager.selectCode] = val;
    await sharedPreferences.setString('authreceives', json.encode(AppManager.authReceives));
  }

  static bool isAuthReceive(Address address) {
    if (!AppManager.isManager) {
      return true;
    }
    if (address.userType == 'S') {
      return true;
    }
    final code = address.code;

    if (AppManager.authReceives.keys.contains(code)) {
      if (AppManager.authReceives[code] == '1') {
        return true;
      }
    }
    return false;
  }

  static String dispType(String type) {
    if (type == '0') {
      return '標準';
    }
    else if (type == '1') {
      return '居室';
    }
    else if (type == '2') {
      return 'カメラ';
    }
    return '';
  }

  static String displyNumber(String type) {
    if (type == '2' || type == '3' || type == '5') {
      return type;
    }
    return '3';
  }

  static String sleepModeBrightness() {
    var mode = AppManager.appsettings["SLEEPMODEBRIGHTNESS"];
    if (mode == '0') {
      return '変えない';
    } else if (mode == '1') {
      return '普通';
    } else if (mode == '2') {
      return '暗い';
    }
    return '';
  }

  static String clockMode() {
    var mode = AppManager.appsettings["SLEEP_CLOCK"];
    if (mode == '0') {
      return 'デジタル';
    } else if (mode == '1') {
      return 'デジタル(日付あり)';
    } else if (mode == '2') {
      return 'アナログ';
    }
    return '';
  }

  static String roomImageName(Size size) {
    if (size.shortestSide < 500) {
      if (size.width > size.height) {
        return "assets/images/room_bg_s_landscape.png";
      }
      return "assets/images/room_bg_s.png";
    }
    if (size.width > size.height) {
      return "assets/images/room_bg_landscape.png";
    }
    return "assets/images/room_bg.png";
  }

  static setStatusBarHidden(bool show) {
    if (show) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
    }
  }

  static Future<ui.Image> loadImage(List<int> img) async {
    String base64Image = base64Encode(img);
    Uint8List unit8 = base64Decode(base64Image);
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(unit8, (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  static void toast(String message, {Color bgColor = Colors.red, Color color = Colors.white, ToastGravity gravity = ToastGravity.BOTTOM, int sec = 3}) async {
    await Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: gravity,
        timeInSecForIosWeb: sec,
        backgroundColor: bgColor,
        textColor: color,
        fontSize: 16.0);
  }

  static Future dialog(String title, String content, BuildContext context) async {
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            SimpleDialogOption(
              child: Text('OK'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  static String dateFormat(DateTime datetime, String format) {
    initializeDateFormatting("ja_JP");
    var formatter = new DateFormat(format, "ja_JP");
    var formatted = formatter.format(datetime); // DateからString
    return formatted;
  }
}