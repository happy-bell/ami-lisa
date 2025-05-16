import 'dart:convert';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/family/family.dart';
import 'package:amiapp/pages/room/room_page.dart';
import 'package:amiapp/pages/staff/manager_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/pages/live/live_page.dart';

class SignInPage extends StatefulWidget {
  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  var _loginMode = 'user';
  var _loading = false;

  @override
  void initState() {
    super.initState();

    Future(() async {

      if (await Permission.camera.status == PermissionStatus.denied) {
        await Permission.camera.request();
      }
      if (await Permission.microphone.status == PermissionStatus.denied) {
        await Permission.microphone.request();
      }

      final prefs = await SharedPreferences.getInstance();
      String? loginCode = prefs.getString('login_code');
      if (loginCode != null) {
        _codeController.text = loginCode;
      }
    });

  }

  String _loginURL() {
    if (AppDefine.amiApp) {
      return '${AppDefine.baseURL}app/login';
    }
    return '${AppDefine.baseURL}app/v4/loginv6.php';
  }

  Future<void> _login() async {
    if (primaryFocus != null) {
      primaryFocus?.unfocus();
    }
    setState(() {
      _loading = true;
    });

    final url = _loginURL();
    print(url);

    final code = _codeController.text;
    final id = _idController.text;
    final password = _passController.text;

    if (code.isEmpty || id.isEmpty || password.isEmpty) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("確認"),
            content: const Text("ログイン情報を入力してください。"),
            actions: <Widget>[
              SimpleDialogOption(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
      return;
    }

    final dio = Dio();
    final data = await dio.post(
      url,
      data: FormData.fromMap({'delegatorCode': code, 'userID': id, 'password': password, 'code': code, 'user_id': id})
    ).then((response) {
      print(response.data);

      if (response.data['cnt'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });


    setState(() {
      _loading = false;
    });

    if (data == null) {
      WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
      return;
    }

    var isMaspro = false;

    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', true);
    await prefs.setString('login_code', code);
    await prefs.setString('address', json.encode(data['address']));
    await prefs.setString('autoreceive', json.encode(data['autoreceive']));
    await prefs.setString('login_at', WidgetUtil.dateFormat(DateTime.now(), 'yyyyMMddHHmmss'));

    Map<String, dynamic> settings = data['settings'];

    bool isAnminMode = false;
    for (var k in settings.keys) {
      if (k == 'ANMINMODEFLG' && settings[k] != '0') {
        isAnminMode = true;
      }
    }
    if (isAnminMode) {
      settings["SLEEPMODE"] = "0";
    }
    var mcsType = settings['MCSTYPE'];
    if (mcsType == '3') {
      settings['DISPTYPE'] = '1';
    }

    await prefs.setString('settings', json.encode(settings));
    AppManager.saveAppSetting("ANMINMODEFLG", isAnminMode ? "1" : "0");
    // if (settings['MASPROSENSOR'] == "1") {
    //   isMaspro = true;
    //   Navigator.of(context).pushReplacementNamed("/sensorweb");
    //   return;
    // }
    if (mcsType == '5') {
      if (!mounted) return;
      Navigator.of(context)
          .pushAndRemoveUntil(PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
          return StaffPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ), (_) => false);
    } else if (mcsType == '4') {
      if (!mounted) return;
      Navigator.of(context)
          .pushAndRemoveUntil(PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
          return FamilyPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ), (_) => false);
    } else if (mcsType == '3') {
      if (!mounted) return;
      Navigator.of(context)
          .pushAndRemoveUntil(PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
          return RoomPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ), (_) => false);
    } else {
      WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
    }

    return;
  }

  Future<void> _staffLogin() async {
    setState(() {
      _loading = true;
    });
    var url = '${AppDefine.baseURL}app/staff_login';

    var code = _codeController.text;
    var id = _idController.text;
    var password = _passController.text;

    if (code.isEmpty || id.isEmpty || password.isEmpty) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("確認"),
            content: const Text("ログイン情報を入力してください。"),
            actions: <Widget>[
              SimpleDialogOption(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
      return;
    }

    final dio = Dio();
    var data = await dio.post(
        url,
        data: FormData.fromMap({'delegatorCode': code, 'userID': id, 'password': password, 'code': code, 'user_id': id})
    ).then((response) {
      print(response.data);

      if (response.data['cnt'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _loading = false;
    });

    if (data == null) {
      WidgetUtil.showSimpleDialog(context, 'ログイン情報を確認してください。');
      return;
    }

    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', true);
    await prefs.setBool('manager', true);
    await prefs.setString('login_code', code);
    await prefs.setString('address', json.encode(data['address']));
    await prefs.setString('autoreceive', json.encode(data['autoreceive']));
    await prefs.setString('codes', json.encode(data['codes']));

    Map<String, dynamic> settings = data['settings'];

    var mcsType = settings['MCSTYPE'];
    if (mcsType == '3') {
      settings['DISPTYPE'] = '1';
    }

    await prefs.setString('settings', json.encode(settings));

    setState(() {
      _loading = false;
    });

    if (!mounted) return;
    Navigator.of(context)
        .pushAndRemoveUntil(PageRouteBuilder(
      pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
        return StaffPage();
      },
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ), (_) => false);

    return;
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    double verticalPadding = 150.0;
    double verticalPadding2 = 50.0;
    if (size.height < 700) {
      verticalPadding = 80.0;
      verticalPadding2 = 10.0;
    }
    double paddingX = 50;
    if (size.width > 700) {
      paddingX = 200;
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 238, 239, 243),
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: paddingX),
            child: Container(
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 247, 247, 247),
                borderRadius: BorderRadius.circular(8.0),
              ),
              padding: EdgeInsets.symmetric(vertical: verticalPadding2, horizontal: 22.0),
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('コード'),
                      const SizedBox(height: 4,),
                      TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          fillColor: Colors.white,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Color.fromARGB(255, 220, 220, 220),
                            ),
                          ),
                          hintText: '',
                          isDense: true,
                          // errorText: _passErr.isEmpty ? null : _passErr,
                        ),
                        // obscureText: true,
                      ),
                      const SizedBox(height: 12.0,),
                      const Text("ユーザーID"),
                      const SizedBox(height: 4,),
                      TextField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          fillColor: Colors.white,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Color.fromARGB(255, 220, 220, 220),
                            ),
                          ),
                          hintText: '',
                          isDense: true,
                          // errorText: _passErr.isEmpty ? null : _passErr,
                        ),
                        // obscureText: true,
                      ),
                      const SizedBox(height: 12.0,),
                      const Text("パスワード"),
                      const SizedBox(height: 4,),
                      TextField(
                        controller: _passController,
                        decoration: const InputDecoration(
                          fillColor: Colors.white,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Color.fromARGB(255, 220, 220, 220),
                            ),
                          ),
                          hintText: '',
                          isDense: true,
                          // errorText: _passErr.isEmpty ? null : _passErr,
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 50,),
                      Center(
                        child: SizedBox(
                          width: size.width - 60 > 200 ? 200 : size.width - 60,
                          height: 40,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: _loginMode == 'user' ? Color.fromARGB(255, 115, 176, 236) :  Color.fromARGB(255, 115, 206, 146),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () async {
                              if (_loginMode == 'staff') {
                                _staffLogin();
                                return;
                              }
                              _login();
                            },
                            child: const Text("ログイン"),
                          ),
                        ),
                      ),
                      if (1 == 1)
                        ... [
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 14),
                              ),
                              onPressed: () {
                                setState(() {
                                  _loginMode = _loginMode == 'user' ? 'staff' : 'user';
                                });
                              },
                              child: Text(_loginMode == 'user' ? 'スタッフはこちら' : 'ユーザーはこちら'),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            Align(
              alignment: FractionalOffset.center,
              child: Container(
                color: Colors.grey.withOpacity(0.3),
                child: const Padding(
                  padding: EdgeInsets.all(5.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}