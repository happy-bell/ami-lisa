import 'package:flutter/material.dart';
import 'package:amiapp/services/appmanager.dart';

import '../../helpers/widget_util.dart';

class SettingInputPage extends StatefulWidget {
  final String keyName;
  final String value;

  const SettingInputPage({super.key, required this.keyName, required this.value});

  @override
  SettingInputPageState createState() => SettingInputPageState();
}

class SettingInputPageState extends State<SettingInputPage> {
  var title = '';
  var _key = '';
  var _value = '';
  var _init = true;

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('settinginput  initState');

    _key = widget.keyName;
    _value = widget.value;
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('settinginput didChangeDependencies');

    if (_init) {
      _init = false;

      if (_key == 'group') {
        title = 'グループ';
      } else if (_key == 'addressGroup') {
        title = '住所録グループ';
      }

      _controller.text = _value;
    }

  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() async {
    print(_controller.text);
    if (_controller.text.isEmpty) {
      await AppManager.dialog('確認', '入力してください。', context);
    }

    AppManager.saveSetting(_key, _controller.text);
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: WidgetUtil.appBar(title,
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: Container(
        height: size.height,
        color: const Color.fromARGB(255, 240, 240, 240),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(left: 24.0, right: 24.0),
          children: [
            const SizedBox(height: 48.0),
            Container(
              color: Colors.white,

              child: TextFormField(
                autofocus: true,
                controller: _controller,
                // initialValue: value,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.fromLTRB(20.0, 10.0, 20.0, 10.0),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _controller.clear();
                    },
                    icon: const Icon(Icons.clear),
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 96),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white, backgroundColor: Colors.lightBlueAccent,
                  // shape: RoundedRectangleBorder(
                  //   borderRadius: BorderRadius.circular(10),
                  // ),
                ),
                onPressed: () async {
                  _save();
                },
                child: const Text("保存"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
