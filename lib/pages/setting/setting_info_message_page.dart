import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' show get;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/setting/setting_args.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';

class SettingInfoMessagePage extends StatefulWidget {

  @override
  SettingInfoMessagePageState createState() => SettingInfoMessagePageState();
}

class SettingInfoMessagePageState extends State<SettingInfoMessagePage> {
  bool _loading = true;
  var _init = true;
  final TextEditingController _textController = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

    if (_init) {
      _init = false;
      _getData();
    }

  }

  Future<void> _getData() async {
    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url = '${AppDefine.baseURL}elan/api/info_text?code=${AppManager.settings['DELEGATORCODE']}&token=${AppManager.settings['api_token']}';
print(url);
    var data = await dio.get(
      url,
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _loading = false;
    });

    if (data == null) {
      return;
    }

    print(data);

    setState(() {
      _textController.text = data['text'].toString();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    _err = null;

    if (_textController.text.isEmpty) {
      setState(() {
        _err = '入力してください。';
      });
      return;
    }
    if (_textController.text.length > 50) {
      setState(() {
        _err = '50文字までで入力してください。';
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url = '${AppDefine.baseURL}elan/api/store_info_text';

    var data = await dio.post(
      url,
      data: FormData.fromMap({
        'token': AppManager.settings['api_token'],
        'code': AppManager.settings['delegatorcode'],
        'text': _textController.text
      }),
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    setState(() {
      _loading = false;
    });

    if (data == null) {
      setState(() {
        _err = '登録できませんでした。';
      });
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WidgetUtil.appBar('メッセージ配信',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: WidgetUtil.basicText('メッセージ入力（50文字まで入力可）'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20.0),
                    child: WidgetUtil.basicTextField2(_textController, _err),
                  ),
                  const SizedBox(height: 20),
                  WidgetUtil.basicButton('登録', _post),
                ],
              ),
            ),
            if (_loading)
              WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
