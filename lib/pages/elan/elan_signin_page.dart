import 'dart:convert';
import 'package:amiapp/pages/elan/elan_tab_page.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/pages/live/live_page.dart';

class ElanSignInPage extends StatefulWidget {
  @override
  _ElanSignInPageState createState() => _ElanSignInPageState();
}

class _ElanSignInPageState extends State<ElanSignInPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('elan signin page initState');

    Future(() async {
      final prefs = await SharedPreferences.getInstance();
      String? loginCode = prefs.getString('login_code');
      if (loginCode != null) {
        _codeController.text = loginCode;
      }
    });
  }

  void _login() async {
    var url = '${AppDefine.baseURL}elan/api/login';

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

    if (data == null) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("確認"),
            content: const Text("ログイン情報を確認してください。"),
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

    var isMaspro = false;

    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', true);
    await prefs.setString('login_code', code);
    await prefs.setString('address', json.encode(data['address']));
    await prefs.setString('autoreceive', json.encode(data['autoreceive']));

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

    await prefs.setString('settings', json.encode(settings));
    AppManager.saveAppSetting("ANMINMODEFLG", isAnminMode ? "1" : "0");

    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (context) => ElanTabPage()));
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: const Color.fromARGB(255, 238, 239, 243),
            padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 50),
            child: Container(
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 247, 247, 247),
                borderRadius: BorderRadius.circular(8.0),
              ),
              padding: EdgeInsets.only(top: verticalPadding2, left: 12.0, right: 12.0),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        keyboardType: TextInputType.visiblePassword,
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
                              backgroundColor: const Color.fromARGB(255, 115, 176, 236),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () async {
                              _login();
                            },
                            child: const Text("ログイン"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}