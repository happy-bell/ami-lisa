import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

class SettingInfoMessagePage extends StatefulWidget {
  const SettingInfoMessagePage({super.key});

  @override
  SettingInfoMessagePageState createState() => SettingInfoMessagePageState();
}

class SettingInfoMessagePageState extends State<SettingInfoMessagePage> {
  bool _loading = true;
  var _init = true;
  final TextEditingController _textController = TextEditingController();
  String? _err;

  String get _code {
    if (AppManager.isManager && AppManager.selectCode.isNotEmpty) {
      return AppManager.selectCode;
    }
    if (AppManager.delegatorCode.isNotEmpty) {
      return AppManager.delegatorCode;
    }
    return (AppManager.settings['DELEGATORCODE'] ??
            AppManager.settings['delegatorcode'] ??
            '')
        .toString();
  }

  @override
  void didChangeDependencies() {
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
    var url =
        '${AppDefine.baseURL}elan/api/info_text?code=$_code&token=${AppManager.settings['api_token']}';
    print(url);
    var data = await dio.get(url).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    if (data == null || data is! Map) {
      return;
    }

    print(data);

    var text = (data['text'] ?? '').toString();
    if (text == 'null') {
      text = '';
    }
    setState(() {
      _textController.text = text;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    _err = null;

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
        'code': _code,
        'text': _textController.text
      }),
    ).then((response) {
      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['status'] == 'ok') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    if (data == null) {
      setState(() {
        _err = '登録できませんでした。';
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tv = TvUtil.isTelevision;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: WidgetUtil.appBar(
        'メッセージ配信',
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
                    child: WidgetUtil.basicText(
                      'メッセージ入力（50文字まで入力可）',
                      fontSize: tv ? 22 : 14,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 20.0),
                    child: WidgetUtil.basicTextField2(
                      _textController,
                      _err,
                      fontSize: tv ? 22 : 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TvFocusable(
                    autofocus: tv,
                    onPressed: _post,
                    child: ExcludeFocus(
                      child: WidgetUtil.basicButton('登録', _post),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
