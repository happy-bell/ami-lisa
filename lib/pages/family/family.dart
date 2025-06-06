import 'dart:async';
import 'dart:convert';
import 'package:amiapp/pageroutes/simplepageroute.dart';
import 'package:amiapp/pages/family/familytalk.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:amiapp/services/appmanager.dart';
import '../../appdefine.dart';
import '../../notifiers/address_notifier.dart';
import '../../services/socket_io_service.dart';
import '../setting/setting_page.dart';
import '../singin/signin_page.dart';

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  _FamilyPageState createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> with WidgetsBindingObserver, SocketIOServiceDelegate {

  SocketIOService socketservice = SocketIOService();
  bool _isconnect = false;
  bool _load = false;
  Timer? _checkAccountTimer;

  @override
  void initState() {
    super.initState();
    print('family initState');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('family didChangeDependencies');

    if (!_load) {
      _load = true;
      AppManager.requestPermission();
      socketservice.delegate = this;

      AppManager.setStatusBarHidden(false);

      var load = await AppManager.loadSetting();
      if (!load) {
        _logout();
      }
      _loadAddress();
      socketservice.connect();
      _startCheckAccountTimer();
    }
  }

  @override
  void dispose() {
    print('family dispose');
    // WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print(state);
    // setState(() {
    //   _notification = state;
    // });
    if (state == AppLifecycleState.resumed) {
      print('resumed');
      socketservice.connect();
    } else if (state == AppLifecycleState.paused) {
      socketservice.disconnect();
    }
  }

  void _stopCheckAccountTimer() {
    print('stop check account timer');
    if (_checkAccountTimer != null) {
      print('stop check account timer');
      _checkAccountTimer!.cancel();
    }
  }

  void _startCheckAccountTimer() {
    _stopCheckAccountTimer();

    _checkAccountTimer = Timer.periodic(const Duration(seconds: 10), (Timer timer) {
      _checkAccount();
    });
  }

  Future<void> _checkAccount() async {
    var prefs = await SharedPreferences.getInstance();
    String? loginAt = prefs.getString('login_at');

    if (!mounted) {
      return;
    }

    if (loginAt == null) {
      return;
    }

    print('check account: $loginAt');
    final url = '${AppDefine.baseURL}app/check_account';
    print({'code': AppManager.delegatorCode, 'user_id': AppManager.myId, 'type': AppManager.settings['MCSTYPE'], 'loginAt': loginAt, 'manager': AppManager.isManager ? '1' : '0'});

    final dio = Dio();
    final data = await dio.post(
        url,
        data: FormData.fromMap({'code': AppManager.delegatorCode, 'user_id': AppManager.myId, 'type': AppManager.settings['MCSTYPE'], 'loginAt': loginAt, 'manager': AppManager.isManager ? '1' : '0'})
    ).then((response) {
      print(response.data);

      if (response.data['status'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    if (data == null) {
      _stopCheckAccountTimer();

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('確認'),
            content: Text('ログイン情報が更新されました。再度ログインをお願いします。'),
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
      print('to logout');
      _logout();
    }
    }

  void _loadAddress() {
    SharedPreferences.getInstance().then((prefs) {
      String? addressString = prefs.getString('address');
      // print(addressString);
      if (addressString != null) {
        var addressJson = json.decode(addressString);
        context.read<AddressStore>().setAddressList(addressJson);
      }
    });
  }

  Future<void> _logout() async {
    socketservice.disconnect();
    context.read<AddressStore>().clear();
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    Navigator.of(context, rootNavigator: true)
        .pushReplacement(MaterialPageRoute(builder: (context) => SignInPage()));
  }

  void _toSetting() async {
    _stopCheckAccountTimer();
    socketservice.disconnect();

    await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return SettingPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
    print('from settings');
    socketservice.connect();
    _startCheckAccountTimer();
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 50.0;
    const spanaSize = Size(55, 40);
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Material(color: Color.fromARGB(255, 104, 104, 104)),
            Positioned(
              bottom: iconSize + 20,
              left: 20,
              width: constraints.maxWidth - 40,
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text("呼び出す"),
                      onPressed: () async {
                        if (_isconnect) {
                          _tap();
                        } else {
                          await _showDialog();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: size.height - iconSize,
              left: 0,
              width: size.width,
              height: iconSize,
              // right: constraints.maxWidth,
              child: Container(
                color: Colors.transparent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Image.asset(_isconnect
                            ? 'assets/images/led/ledG.png'
                            : 'assets/images/led/led2.png'),
                        Padding(
                          padding: EdgeInsets.only(left: 12.0),
                          child: Text(
                            '${_isconnect ? 'ON' : 'OFF'} LINE ',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: 10.0, top: 8.0),
                          child: Text(
                            'Ver. 1.0',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        GestureDetector(
                          child: Image.asset('assets/images/spana.png', width: spanaSize.width, height: spanaSize.height,),
                          onTap: () {
                            _toSetting();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tap() async {
    _stopCheckAccountTimer();
    var list = context.read<AddressStore>().addressList;
    AppManager.selectUser = list[0];
    AppManager.status = AppStatus.Call;

    await Navigator.of(context).push(
      SimplePageRoute(
        page: FamilyTalkPage(),
        settings: RouteSettings(
          name: '/familytalk',
        ),
      ),
    );
    socketservice.delegate = this;
    _startCheckAccountTimer();
  }

  void _login() {
    var useType = "0";

    socketservice.io.emit("login", [
      {
        "DELEGATOR": AppManager.delegatorCode,
        "MYID": AppManager.myId,
        "NAME": AppManager.settings['MCSNAME'],
        "GROUP": AppManager.settings['group'],
        "USETYPE": useType,
        "MARKER": "0",
        "DISPSIZE": "1",
        "FIRTOKEN": AppManager.fcmtoken,
      }
    ]);
  }

  @override
  void onAppMessage(data) {
    String message = data['message'];
    print('room app message $message');
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        _isconnect = true;
      });
    }
  }

  @override
  void onTalkMessage(data) {

  }

  @override
  void onMessage(data) {
    // TODO: implement onAppMessage
  }

  @override
  void onConnect() {
    _login();
  }

  @override
  void onDisConnect() {
    setState(() => _isconnect = false);
  }

  Future _showDialog() async {
    print('showdialog');
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('確認'),
          content: Text('通話できません\n（サーバー接続エラー）'),
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

  @override
  void onIoConnect() {
    // TODO: implement onIoConnect
  }

  @override
  void onIoDisConnect() {
    // TODO: implement onIoDisConnect
  }

  @override
  void onIoMessage(data) {
    // TODO: implement onIoMessage
  }
}
