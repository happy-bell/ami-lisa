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
  static dynamic appsettings = {"AUTO_RECEIVE": "0", "SLEEP_MODE": "0", "SLEEP_CLOCK": "0", "SLEEPMODEBRIGHTNESS": "0", "SENSOR0": "0", "SENSOR1": "0", "SENSOR2": "0", "SENSOR3": "0", "SENSOR4": "0", "SENSOR5": "0", "SENSOR8": "0", "SENSOR9": "0", "RINGTONE": "0", "CALLSCREENIMAGE": "0", "CALLSCREENIMAGEL": "0", "VOLUME_CALL": "0", "CLOCKDISP": "0", "DISPLAYNUM": "3", "CALLSTATUSDISP": "0", "TV_CALL_WAITING": "0"};
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

  /// ホーム画面: tcl=TCLアミ / pi=ラズパイ移植版。アカウントごとに保存する。
  /// TCLアミ完成版とスタッフ画面は、この値が pi のとき以外は変更しない。
  static const tvLayoutTcl = 'tcl';
  static const tvLayoutPi = 'pi';

  static String get tvLayout {
    final server = (settings['TVLAYOUT'] ?? settings['tvlayout'] ?? '')
        .toString()
        .toLowerCase();
    if (server == 'pi' || server == 'raspi' || server == '3') {
      return tvLayoutPi;
    }
    if (server == 'tcl' || server == '4') {
      return tvLayoutTcl;
    }
    final local = appsettings['TV_LAYOUT']?.toString();
    if (local == tvLayoutPi || local == tvLayoutTcl) return local!;
    return tvLayoutTcl;
  }

  static bool get isPiTvLayout => tvLayout == tvLayoutPi;

  static String tvLayoutLabel() =>
      isPiTvLayout ? 'ラズパイ版' : 'TCLアミ';

  static String _accountTvLayoutKey() =>
      'tv_layout_${delegatorCode}_$myId';

  static Future<void> loadAccountTvLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_accountTvLayoutKey());
    if (v == tvLayoutPi || v == tvLayoutTcl) {
      appsettings['TV_LAYOUT'] = v;
    }
  }

  static Future<void> saveTvLayout(String layout) async {
    await saveAppSetting('TV_LAYOUT', layout);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountTvLayoutKey(), layout);
  }

  /// ラズパイ版の気象庁地域コード。TCLアミでは使わない。
  static const defaultWeatherAreas = [
    ['011000', '宗谷地方'],
    ['012000', '上川・留萌地方'],
    ['013000', '網走・北見・紋別地方'],
    ['014030', '十勝地方'],
    ['014100', '釧路・根室地方'],
    ['015000', '胆振・日高地方'],
    ['016000', '石狩・空知・後志地方'],
    ['017000', '渡島・檜山地方'],
    ['020000', '青森県'],
    ['030000', '岩手県'],
    ['040000', '宮城県'],
    ['050000', '秋田県'],
    ['060000', '山形県'],
    ['070000', '福島県'],
    ['080000', '茨城県'],
    ['090000', '栃木県'],
    ['100000', '群馬県'],
    ['110000', '埼玉県'],
    ['120000', '千葉県'],
    ['130000', '東京都'],
    ['140000', '神奈川県'],
    ['150000', '新潟県'],
    ['160000', '富山県'],
    ['170000', '石川県'],
    ['180000', '福井県'],
    ['190000', '山梨県'],
    ['200000', '長野県'],
    ['210000', '岐阜県'],
    ['220000', '静岡県'],
    ['230000', '愛知県'],
    ['240000', '三重県'],
    ['250000', '滋賀県'],
    ['260000', '京都府'],
    ['270000', '大阪府'],
    ['280000', '兵庫県'],
    ['290000', '奈良県'],
    ['300000', '和歌山県'],
    ['310000', '鳥取県'],
    ['320000', '島根県'],
    ['330000', '岡山県'],
    ['340000', '広島県'],
    ['350000', '山口県'],
    ['360000', '徳島県'],
    ['370000', '香川県'],
    ['380000', '愛媛県'],
    ['390000', '高知県'],
    ['400000', '福岡県'],
    ['410000', '佐賀県'],
    ['420000', '長崎県'],
    ['430000', '熊本県'],
    ['440000', '大分県'],
    ['450000', '宮崎県'],
    ['460100', '鹿児島県'],
    ['471000', '沖縄本島地方'],
    ['473000', '宮古島地方'],
    ['474000', '八重山地方'],
  ];

  static String get weatherArea {
    final server =
        (settings['WEATHERAREA'] ?? settings['weatherarea'] ?? '').toString();
    if (server.isNotEmpty && server != 'null') return server;
    final local = appsettings['WEATHER_AREA']?.toString() ?? '';
    if (local.isNotEmpty && local != 'null') return local;
    return '';
  }

  static String weatherAreaLabel() {
    final area = weatherArea;
    if (area.isEmpty) return '未設定';
    for (final item in weatherAreas.isEmpty ? defaultWeatherAreas : weatherAreas) {
      if (item[0] == area) return item[1];
    }
    return area;
  }

  static String _accountWeatherKey() =>
      'weather_area_${delegatorCode}_$myId';

  static Future<void> loadAccountWeatherArea() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_accountWeatherKey());
    if (v != null && v.isNotEmpty) {
      appsettings['WEATHER_AREA'] = v;
    }
  }

  static Future<void> saveWeatherArea(String area) async {
    await saveAppSetting('WEATHER_AREA', area);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountWeatherKey(), area);
  }

  /// ログイン時に入力したユーザーID（例: Doc00007 / tv000003）。
  /// ドクター判定はこれで行う。myId（fBNWB6s1_TV007）では判定できない。
  static String storedLoginId = '';

  static const amiModeDoctor = 'doctor';
  static const amiModePatient = 'patient';
  static String _amiMode = amiModeDoctor;

  static String get loginId {
    if (storedLoginId.isNotEmpty) return storedLoginId;
    final my = (settings['myId'] ?? myId).toString();
    if (my.contains('_')) return my.split('_').last;
    return my;
  }

  /// ログインIDが Doc 始まり（大小区別）ならドクターアカウント。
  static bool get isDoctorAccount => loginId.startsWith('Doc');

  /// 実効モード。患者アカウントは常に patient。
  static String get amiMode {
    if (!isDoctorAccount) return amiModePatient;
    return _amiMode == amiModePatient ? amiModePatient : amiModeDoctor;
  }

  /// ラズパイ版かつドクターモードのときだけ true。TCLアミでは使わない。
  static bool get isDoctorMode => isPiTvLayout && amiMode == amiModeDoctor;

  static String amiModeLabel() =>
      amiMode == amiModeDoctor ? 'ドクターモード' : '患者モード';

  static String _accountAmiModeKey() => 'ami_mode_${delegatorCode}_$myId';

  static Future<void> loadAccountAmiMode() async {
    final prefs = await SharedPreferences.getInstance();
    storedLoginId = prefs.getString('login_id') ?? '';
    final v = prefs.getString(_accountAmiModeKey());
    if (v == amiModePatient || v == amiModeDoctor) {
      _amiMode = v!;
    } else {
      _amiMode = amiModeDoctor;
    }
  }

  static Future<void> saveAmiMode(String mode) async {
    _amiMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountAmiModeKey(), mode);
  }

  static String talkId1 = '';
  static String talkId2 = '';
  static String holdId = '';
  static String holdedId = '';
  static String threewayId = '';
  static String safetyCheckId = '';
  static String autoReceiveId = '';
  /// TVオーバーレイ「はい」／電源オフ自動応答で、通話画面の再確認を飛ばす
  static bool tvForceAccept = false;
  /// 設定の再生から居室へ戻り、お知らせ動画を再生する
  static bool pendingPlayInfoVideo = false;
  static String pendingPlayInfoVideoPath = '';

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
    return {"AUTO_RECEIVE": "0", "SLEEP_MODE": "0", "SLEEP_CLOCK": "0", "SLEEPMODEBRIGHTNESS": "0", "SENSOR0": "0", "SENSOR1": "0", "SENSOR2": "0", "SENSOR3": "0", "SENSOR4": "0", "SENSOR5": "0", "SENSOR8": "0", "SENSOR9": "0", "RINGTONE": "0", "CALLSCREENIMAGE": "0", "CALLSCREENIMAGEL": "0", "VOLUME_CALL": "0", "CLOCKDISP": "0", "DISPLAYNUM": "3", "CALLSTATUSDISP": "0", "CALL_DELAY": "0"};
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
      for (final key in ['AUTO_RECEIVE', 'TV_CALL_WAITING']) {
        final v = AppManager.appsettings[key]?.toString();
        if (v != null) {
          await sharedPreferences.setString('tv_$key', v);
        }
      }
    }

    String? fcmtokenString = sharedPreferences.getString('fcmtoken');
    if (fcmtokenString != null) {
      AppManager.fcmtoken = fcmtokenString;
    }
    AppManager.myId = settings['myId'];
    AppManager.delegatorCode = settings['delegatorcode'];
    await loadAccountTvLayout();
    await loadAccountWeatherArea();
    await loadAccountAmiMode();
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
    if (key == 'AUTO_RECEIVE' || key == 'TV_CALL_WAITING') {
      await sharedPreferences.setString('tv_$key', val);
    }
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
      for (var value in autoreceiveJson) {
        AppManager.autoreceives[value[0].toString()] = value[1].toString();
      }
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

  static String callDelayText() {
    var delay = AppManager.appsettings["CALL_DELAY"] ?? '0';
    if (delay == '0') {
      return '即座に応答';
    } else {
      return '${delay}秒後';
    }
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
    var formatter = DateFormat(format, "ja_JP");
    var formatted = formatter.format(datetime); // DateからString
    return formatted;
  }
}