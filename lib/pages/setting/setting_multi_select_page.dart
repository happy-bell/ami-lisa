import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/setting/setting_args.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';

import '../../appdefine.dart';

class SettingMultiSelectPage extends StatefulWidget {
  final String keyName;
  final String value;

  SettingMultiSelectPage({required this.keyName, required this.value});

  @override
  SettingMultiSelectPageState createState() => SettingMultiSelectPageState();
}

class SettingMultiSelectPageState extends State<SettingMultiSelectPage> {
  var title = '';
  var _key = '';
  var _value = '';
  var _init = true;
  List<List<String>> data = [];
  List<String> values = [];

  @override
  void initState() {
    super.initState();
    print('setting multi select  initState');

    _key = widget.keyName;
    _value = widget.value;
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('setting multi select didChangeDependencies');

    if (_init) {
      _init = false;
      if (_key == 'SENSOR') {
        title = 'センサー';
        data = [
          ['0', 'ギガテック', 'SENSOR0'],
          ['1', 'レガーメ', 'SENSOR1'],
          ['2', '人感センサー', 'SENSOR2'],
          ['3', '炎センサー', 'SENSOR3'],
          ['4', 'CO2センサー', 'SENSOR4'],
          ['5', 'バイオシルバー', 'SENSOR5'],
        ];
        values = [
          AppManager.appsettings['SENSOR0'],
          AppManager.appsettings['SENSOR1'],
          AppManager.appsettings['SENSOR2'],
          AppManager.appsettings['SENSOR3'],
          AppManager.appsettings['SENSOR4'],
          AppManager.appsettings['SENSOR5'],
        ];
        if (AppDefine.amiApp) {
          data.add(['8', '血圧計', 'SENSOR8']);
          values.add(AppManager.appsettings['SENSOR8']);
          data.add(['9', 'パルスオキシメーター', 'SENSOR9']);
          values.add(AppManager.appsettings['SENSOR9']);
        }
      }
    }

  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _listContainer(int index, String val) {
    return GestureDetector(
      onTap: () {
        setState(() {
          values[index] = (values[index] == '0' ? '1' : '0');
        });
      },
      child: WidgetUtil.listItem(Container(
        height: WidgetUtil.listHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              val,
              style: WidgetUtil.titleTextStyle1,
            ),
            if (values[index] == '1')
              WidgetUtil.listCheckIcon,
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return WillPopScope(
      onWillPop: () async {
        for (var i = 0; i < values.length; i++) {
          AppManager.saveAppSetting(data[i][2], values[i]);
        }
        Navigator.of(context).pop(_value);
        return Future.value(false);
      },
      child: Scaffold(
        appBar: WidgetUtil.appBar(title,
          backgroundColor: WidgetUtil.iosNavbarBG,
          foregroundColor: Colors.black,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            ListView.builder(
              itemBuilder: (BuildContext context, int index) {
                return _listContainer(index, data[index][1]);
              },
              itemCount: data.length,
            ),
          ],
        ),
      ),
    );
  }
}
