import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/lisa_watchdog.dart';
import 'package:amiapp/widgets/lisa_splash_overlay.dart';
import 'package:amiapp/pages/elan/elan_tutorial_page.dart';
import 'package:amiapp/pages/family/family.dart';
import 'package:amiapp/pages/family/familytalk.dart';
import 'package:amiapp/pages/room/room_page.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:amiapp/pages/elan/elan_tab_page.dart';
import 'package:amiapp/pages/elan/elan_signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/pages/live/live_page.dart';
import 'package:amiapp/pages/lisa/lisa_activation_page.dart';
import 'package:amiapp/pages/lisa/lisa_splash_page.dart';
import 'package:amiapp/pages/lisa/lisa_terms_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:amiapp/pages/tutorial/tutorial_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final home = TvUtil.isTelevision
        ? const AppPage()
        : GestureDetector(
            onTap: () => primaryFocus?.unfocus(),
            child: const AppPage(),
          );

    return MaterialApp(
      // 解除を検知したとき、どの画面からでも登録画面へ戻せるようにする。
      navigatorKey: LisaWatchdog.navigatorKey,
      // 前面に戻ったときのロゴは、画面を差し替えずにここへ重ねる。
      // 差し替えると居室画面が作り直され、着信の受け口ごと壊れる。
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          if (TvUtil.isTelevision) const LisaSplashOverlay(),
        ],
      ),
      debugShowCheckedModeBanner: false,
      title: 'テレビ電話ａｍｉシリーズ LiSA',
      theme: ThemeData(
        primaryColor: const Color.fromARGB(255, 246, 246, 246),
        textTheme: GoogleFonts.notoSansJavaneseTextTheme(
          Theme.of(context).textTheme,
        ),
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        focusColor: const Color(0xFF4FC3F7),
        highlightColor: const Color(0x334FC3F7),
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
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
        const SingleActivator(LogicalKeyboardKey.goBack): const DismissIntent(),
      },
      routes: <String, WidgetBuilder>{
        '/staff': (BuildContext context) => StaffPage(),
        '/room': (BuildContext context) => RoomPage(),
        '/live': (BuildContext context) => LivePage(),
        '/familytalk': (BuildContext context) => FamilyTalkPage(),
      },
      home: home,
    );
  }
}

class AppPage extends StatefulWidget {
  const AppPage({super.key});

  @override
  State createState() => AppState();
}

class AppState extends State<AppPage> with WidgetsBindingObserver {
  AudioService audio = AudioService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    if (TvUtil.isTelevision) {
      TvUtil.startCallWaiting();
    }
    _checkIncomingAtLaunch();

    // Run code required to handle interacted messages in an async function
    // as initState() must not be async
    setNotificationListener();
    // setupInteractedMessage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 前面に戻ったときのロゴ。最後に出した時刻。
  DateTime? _lastOverlayAt;

  /// 前面に戻ったらロゴを2秒だけ重ねる。
  ///
  /// 画面は差し替えないので、裏では接続も着信待ちもそのまま進む。
  /// 通話中は出さない。相手の顔が隠れてしまう。
  void _showLogoOnResume() {
    if (!TvUtil.isTelevision) return;
    if (!_splashDone) return;                     // 起動時のロゴが先
    if (AppManager.status != AppStatus.None) return;   // 通話中は出さない

    // 画面が一瞬切り替わっただけで何度も流れないようにする。
    final last = _lastOverlayAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastOverlayAt = DateTime.now();
    LisaSplashOverlay.show();
  }

  /// 着信で起こされた起動かどうかを調べる。
  /// そうであればロゴを飛ばし、すぐに通話の画面へ進める。
  ///
  /// ロゴを出している数秒のあいだに着信が来ることもある。その間は
  /// 着信を受ける画面がまだ無いので、こまめに確かめて、来ていたら
  /// すぐロゴを切り上げる。**着信を取り逃すほうがずっと困る。**
  Future<void> _checkIncomingAtLaunch() async {
    if (!TvUtil.isTelevision) return;
    for (var i = 0; i < 14; i++) {
      if (!mounted || _splashDone) return;
      try {
        final pending = await TvUtil.getPendingIncomingCall();
        if (pending != null) {
          // ignore: avoid_print
          print('[Splash] 着信を検知したためロゴを切り上げる');
          if (!mounted) return;
          setState(() {
            _incomingAtLaunch = true;
            _splashDone = true;
          });
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!TvUtil.isTelevision) return;
    // 表示中だけ画面を維持し、電源オフ／他アプリ中は外す。
    // 画面ロックを持ったままだと、電源オフ時に本体がアプリを落とす機種がある。
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
      _showLogoOnResume();
    } else {
      WakelockPlus.disable();
    }
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
      final udid = message.data['udid']?.toString() ??
          message.data['callerId']?.toString() ??
          '';
      if (udid.isNotEmpty) {
        _handleTvRemoteIncoming(udid, '着信');
      }
      return;
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('bcId', targetId);
    });
    _handleTvRemoteIncoming(targetId, '着信中');
  }

  void _handleTvRemoteIncoming(String callerId, String callerName) {
    if (!TvUtil.isTelevision) return;
    TvUtil.isScreenOn().then((screenOn) {
      final life = WidgetsBinding.instance.lifecycleState;
      final waiting = TvUtil.isCallWaitingEnabled;
      if (!screenOn) {
        TvUtil.handleWatchingIncoming(
          callerId: callerId,
          callerName: callerName,
        );
        return;
      }
      if (waiting && life != AppLifecycleState.resumed) {
        TvUtil.handleWatchingIncoming(
          callerId: callerId,
          callerName: callerName,
        );
      }
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

  /// スプラッシュを出し終えたか。アプリを立ち上げ直すと false に戻る。
  ///
  /// **前面に戻ったときは出さない。** 画面全体を差し替えるため、
  /// 着信で復帰したときに着信を受ける画面ごと壊してしまう。
  bool _splashDone = false;

  /// 着信で立ち上がったか。この場合はロゴを飛ばして通話へ急ぐ。
  bool _incomingAtLaunch = false;

  @override
  Widget build(BuildContext context) {
    // テレビは起動のたびにロゴを見せる。どのアプリが立ち上がったのか、
    // 高齢の利用者にも分かるようにするため。
    // 着信で立ち上がったときはロゴを出さない。
    // 5秒待たせると、その間に相手が切ってしまう。
    if (TvUtil.isTelevision && !_splashDone && !_incomingAtLaunch) {
      return LisaSplashPage(
        onFinished: () {
          if (!mounted) return;
          setState(() => _splashDone = true);
        },
      );
    }

    return FutureBuilder(
        future: _getLaunchType(),
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          final hasData = snapshot.hasData;
          if (!hasData) {
            if (TvUtil.isTelevision) {
              return const ColoredBox(
                color: Color(0xFFF5F5F0),
                child: SizedBox.expand(),
              );
            }
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
            // 初回起動。スプラッシュはこの手前で終えているので規約から。
            if (TvUtil.isTelevision) {
              return const LisaTermsPage();
            }
            return TutorialPage();
          } else if (launchType == 1) {
            // テレビはリモコンで英数字を打たせない。6桁の番号で登録する画面を出す。
            // 番号で登録できない場合は、その画面から従来のログインへ進める。
            if (TvUtil.isTelevision) {
              return const LisaActivationPage();
            }
            return SignInPage();
          } else if (launchType == 3) {
            // ログイン済みのテレビは登録画面を通らずここへ来る。
            // 見張りを始めるのを忘れると、解除しても止まらなくなる。
            if (TvUtil.isTelevision) {
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => LisaWatchdog.instance.start());
            }
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
