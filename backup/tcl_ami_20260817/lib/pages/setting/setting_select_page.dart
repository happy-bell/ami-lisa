import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

class SettingSelectPage extends StatefulWidget {
  final String keyName;
  final String value;

  const SettingSelectPage({super.key, required this.keyName, required this.value});

  @override
  SettingSelectPageState createState() => SettingSelectPageState();
}

class SettingSelectPageState extends State<SettingSelectPage> {
  bool _load = false;
  bool _playing = false;
  var title = '';
  var _key = '';
  var _value = '';
  List<List<String>> data = [];
  AudioService audio = AudioService();

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('setting select  initState');

    _key = widget.keyName;
    _value = widget.value;

    if (_key == 'DISPTYPE') {
      title = '表示';
      data = [
        ['0', '標準'],
        ['1', '居室'],
        ['2', 'カメラ']
      ];
    } else if (_key == 'DISPLAYNUM') {
      title = '表示数';
      data = [
        ['2', '2'],
        ['3', '3'],
        ['5', '5']
      ];
    } else if (_key == 'SLEEP_CLOCK') {
      title = '時計';
      data = [
        ['0', 'デジタル'],
        ['1', 'デジタル(日付あり)'],
        // ['2', 'アナログ']
      ];
    } else if (_key == 'SLEEPMODEBRIGHTNESS') {
      title = '明るさ';
      data = [
        ['0', '変えない'],
        ['1', '普通'],
        ['2', '暗い']
      ];
    } else if (_key == 'CALL_DELAY') {
      title = '通話開始時間';
      data = [
        ['0', '即座に応答'],
        ['5', '5秒後'],
        ['10', '10秒後'],
        ['15', '15秒後'],
        ['20', '20秒後'],
        ['25', '25秒後'],
        ['30', '30秒後']
      ];
    } else if (_key == 'TV_LAYOUT') {
      title = 'ホーム画面';
      data = [
        ['tcl', 'TCLアミ'],
        ['pi', 'ラズパイ版'],
      ];
    } else if (_key == 'WEATHER_AREA') {
      title = '天気予報';
      final areas = AppManager.weatherAreas.isEmpty
          ? AppManager.defaultWeatherAreas
          : AppManager.weatherAreas;
      data = [
        ['', '表示しない'],
        ...areas,
      ];
    } else if (_key == 'RINGTONE') {
      title = '着信音';
      data = AppManager.ringtones;
      data.insert(0, ['0', '標準']);
    }
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    print('setting select didChangeDependencies');
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _playRingtone() {
    if (_playing) {
      audio.stopRingtone();
    } else {
      if (_value == '0') {
        audio.assetRingtone();
      } else {
        audio.dlRingtone();
      }
    }
    setState(() {
      _playing = !_playing;
    });
  }

  String _ringtoneURL(String id) {
    if (AppDefine.amiApp) {
      return "${AppDefine.baseURL}app/ringtone_dl/$id?token=" + AppManager.settings["api_token"];
    }
    var token = AppDefine.getRMSToken();
    var url = '${'https://' +
        AppManager.settings['MCSURL']}/json/appringtone?id=$id&token=' +
        token;
    return url;
  }

  void _downloadRingtone(String id) async {
    setState(() {
      _load = true;
    });
    var filename = 'dlringtone.mp3';
    var token = AppDefine.getRMSToken();
    var url = _ringtoneURL(id);
    print(url);

    try {
      final dio = Dio();
      Response response = await dio.get(
        url,
        // onReceiveProgress: showDownloadProgress,
        //Received data with List<int>
        options: Options(
            responseType: ResponseType.bytes,
            followRedirects: false,
            // validateStatus: (status) {
            //   return status < 500;
            // }
          ),
      );
      print(response.headers);
      String dir = (await getApplicationDocumentsDirectory()).path;
      File file = File('$dir/$filename');
      var raf = file.openSync(mode: FileMode.write);
      // response.data is List<int> type
      raf.writeFromSync(response.data);
      await raf.close();
    } catch (e) {
      print(e);
    }
    setState(() {
      _load = false;
      _value = id;
    });
  }

  Widget _listContainer(String title, String val, {bool autofocus = false}) {
    void activate() {
      if (_key == 'RINGTONE') {
        if (_playing) {
          _playRingtone();
        }
        _downloadRingtone(val);
        return;
      }
      setState(() {
        _value = val;
      });
    }

    final rowHeight = TvUtil.isTelevision ? 64.0 : WidgetUtil.listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);

    return TvSettingFocus(
      autofocus: autofocus,
      onActivate: activate,
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: style),
            if (_value == val) WidgetUtil.listCheckIcon,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return WillPopScope(
      onWillPop: () async {
        if (_key == 'DISPTYPE') {
          AppManager.saveSetting(_key, _value);
        } else if (_key == 'SLEEP_CLOCK' || _key == 'DISPLAYNUM') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'SLEEPMODEBRIGHTNESS') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'CALL_DELAY') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'RINGTONE') {
          AppManager.saveAppSetting(_key, _value);
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
            FocusTraversalGroup(
              child: ListView.builder(
                itemBuilder: (BuildContext context, int index) {
                  final selected = data[index][0] == _value;
                  return _listContainer(
                    data[index][1],
                    data[index][0],
                    autofocus: TvUtil.isTelevision && (selected || (index == 0 && _value.isEmpty)),
                  );
                },
                itemCount: data.length,
              ),
            ),
            if (_load)
              WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
