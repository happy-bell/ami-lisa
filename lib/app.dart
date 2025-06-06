import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/elan/elan_tutorial_page.dart';
import 'package:amiapp/pages/family/family.dart';
import 'package:amiapp/pages/family/familytalk.dart';
import 'package:amiapp/pages/room/room_page.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:amiapp/pages/elan/elan_tab_page.dart';
import 'package:amiapp/pages/elan/elan_signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/pages/live/live_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:amiapp/pages/tutorial/tutorial_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ami',
      theme: ThemeData(
        primaryColor: const Color.fromARGB(255, 246, 246, 246),
        textTheme: GoogleFonts.notoSansJavaneseTextTheme(
          Theme.of(context).textTheme,
        ),
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      locale: const Locale("ja", "JP"),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale("ja", "JP"),
      ],
      routes: <String, WidgetBuilder>{
        '/staff': (BuildContext context) => StaffPage(),
        '/room': (BuildContext context) => RoomPage(),
        '/live': (BuildContext context) => LivePage(),
        '/familytalk': (BuildContext context) => FamilyTalkPage(),
      },
      home: GestureDetector(
        onTap: () => primaryFocus?.unfocus(),
        child: AppPage(),
      ),
    );
  }
}

class AppPage extends StatefulWidget {
  const AppPage({super.key});

  @override
  State createState() => AppState();
}

class AppState extends State<AppPage> {
  AudioService audio = AudioService();

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();

    // Run code required to handle interacted messages in an async function
    // as initState() must not be async
    setNotificationListener();
    // setupInteractedMessage();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
  }

  Future<void> setupInteractedMessage() async {
    // Get any messages which caused the application to open from
    // a terminated state.
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    // If the message also contains a data property with a "type" of "chat",
    // navigate to a chat screen
    if (initialMessage != null) {
      print('initial message !!!!!!!!!!!!!!!!!');
      _handleMessage(initialMessage);
    }

    // Also handle any interaction when the app is in the background via a
    // Stream listener
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  String _targetIdFromRemoteMessage(RemoteMessage message) {
    print('Message data: ${message.data}');
    var data = message.data;
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = notification?.android;
    AppleNotification? ios = notification?.apple;
    print('Message notification: ${message.notification}');
    print('Message android: $android');
    print('Message ios: $ios');
    if (notification != null) {
      final title = notification.title ?? '';
      final body = notification.body ?? '';
      print('Message title: $title');
      print('Message body: $body');

      if (title.length > 5) {
        var messageId = title.substring(1, 5);
        if (messageId == 'M001') {
          return _targetIdFromMessage(body);
        }
      }
    }

    if (ios != null) {
      // iOS用の処理はこちらで行います。AppleNotificationクラスにはbadgeなどが含まれます。
    }
    if (android != null) {
      // Android用の処理はこちらで行います。
    }
    // 共通のデータペイロードです。パラメータ処理はここから行います。
    // 辞書型でデータを取り出せます。
    var value = data["key"];
      return '';
  }

  void _onMessage(RemoteMessage message) {
    final targetId = _targetIdFromRemoteMessage(message);
    if (targetId.isEmpty) {
      return;
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('bcId', targetId);
    });
  }

  void _onMessageOpendApp(RemoteMessage message) {
    final targetId = _targetIdFromRemoteMessage(message);
    print('_onMessageOpendApp: $targetId');
    if (targetId.isEmpty) {
      return;
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('fmId', targetId);
    });
  }

  void setNotificationListener() {
    // 1.フォアグラウンドで受信した場合
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _onMessage(message);
    });
    // 2.アプリがオンメモリの状態で通知から起動した場合
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('onMessageOpenedApp Message data: $message');
      _onMessageOpendApp(message);
    });

    // 3.アプリが完全に終了している状態で通知から起動した場合
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      print('getInitialMessage Message data: $message');
      if (message != null) {
        _onMessageOpendApp(message);
      }
    });
  }

  String _targetIdFromMessage(String message) {
    var pos1 = message.indexOf('[');
    var pos2 = message.indexOf(']');
    if (pos1 >= 0 && pos2 > pos1) {
    } else {
      pos1 = message.indexOf('【');
      pos2 = message.indexOf('】');
    }
    if (pos1 >= 0 && pos2 > pos1) {
      var targetId = message.substring(pos1 + 1, pos2);
      return targetId;
    }
    return '';
  }

  void _handleMessage(RemoteMessage message) {
    print(message.data);
    //{title: [M001]:緊急呼び出し, body: 緊急呼び出し [cfs8DILS_TV001]TVアカウント12 2023/09/08 12:40, click_action: FLUTTER_NOTIFICATION_CLICK}

    var data = message.data;
    var title = data['title'].toString();
    var messageId = title.substring(1, 5);
    print("messageId $messageId");
    if (messageId == 'M001') {
      _handleCallMessage(title, data['body'].toString());
    }
  }

  void _handleCallMessage(String title, String message) {
    var pos1 = message.indexOf('[');
    var pos2 = message.indexOf(']');
    if (pos1 >= 0 && pos2 > pos1) {
    } else {
      pos1 = message.indexOf('【');
      pos2 = message.indexOf('】');
    }
    if (pos1 >= 0 && pos2 > pos1) {
      var targetId = message.substring(pos1 + 1, pos2);
      print('targetId, $targetId');
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('fmId', targetId);
      });
    }
  }

  Future<int> _getElanLaunchType() async {
    int status = 10;
    final prefs = await SharedPreferences.getInstance();

    bool isInitialized = prefs.getBool("isInitialized") ?? false;
    if (!isInitialized) {
      return status;
    }

    status += 1;
    bool login = prefs.getBool("login") ?? false;
    if (!login) {
      return status;
    }
    status += 1;

    return status;
  }

  Future<int> _getLaunchType() async {
    if (AppDefine.elanApp) {
      return _getElanLaunchType();
    }
    int status = 0;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    String appName = packageInfo.appName;
    String packageName = packageInfo.packageName;
    String version = packageInfo.version;
    String buildNumber = packageInfo.buildNumber;

    print('$appName, $packageName, $version, $buildNumber');

    final prefs = await SharedPreferences.getInstance();
    bool isInitialized = prefs.getBool("isInitialized") ?? false;
    if (!isInitialized) {
      return status;
    }
    status = 1;
    bool login = prefs.getBool("login") ?? false;
    if (!login) {
      return status;
    }

    status = 2;
    var load = await AppManager.loadSetting();
    if (load) {
      if (AppManager.settings['MCSTYPE'] == '4') {
        status = 5;
      } else if (AppManager.settings['DISPTYPE'] == '1') {
        status = 3;
      } else if (AppManager.settings['DISPTYPE'] == '2') {
        status = 4;
        // }
        // if (AppManager.settings['MASPROSENSOR'] == "1") {
        //   status = 10;
      }
      if (AppManager.isManager) {
        status = 9;
      }
    }

    return status;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _getLaunchType(),
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          final hasData = snapshot.hasData;
          if (!hasData) {
            return const CircularProgressIndicator();
          }

          final launchType = snapshot.data;
          print("launchType: $launchType");
          if (launchType == 10) {
            return ElanTutorialPage();
          } else if (launchType == 11) {
            return ElanSignInPage();
          } else if (launchType == 12) {
            return ElanTabPage();
          }
          if (launchType == 0) {
            return TutorialPage();
          } else if (launchType == 1) {
            return SignInPage();
          } else if (launchType == 3) {
            return RoomPage();
          } else if (launchType == 4) {
            return LivePage();
          } else if (launchType == 5) {
            return FamilyPage();
          } else if (launchType == 9) {
            return StaffPage();
          }

          return StaffPage();
        });
  }
}
