import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';

class ElanInputUserNamePage extends StatefulWidget {
  final dynamic item;
  const ElanInputUserNamePage({Key? key, required this.item}) : super(key: key);

  @override
  ElanInputUserNamePageState createState() => ElanInputUserNamePageState();
}

class ElanInputUserNamePageState extends State<ElanInputUserNamePage> {
  bool _loading = false;
  var title = '';
  final _init = true;
  final List<dynamic> _data = [];
  final TextEditingController _textController = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    print('input user name initState');
    _textController.text = widget.item['name'].toString();
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

    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url =
        '${AppDefine.baseURL}elan/api/change_user_name?token=${AppManager.settings['api_token']}';

    var data = await dio
        .post(
      url,
      data: FormData.fromMap({
        'name': _textController.text,
        'code': widget.item['code'].toString(),
        'mst_id': widget.item['mst_id'].toString()
      }),
    )
        .then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

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
      appBar: WidgetUtil.appBar(
        '利用者名変更',
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: WidgetUtil.basicTextField2(_textController, _err),
                  ),
                  const SizedBox(height: 40),
                  WidgetUtil.basicButton('登録', _post),
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
