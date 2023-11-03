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

class ElanSettingSelectPage extends StatefulWidget {
  final String keyName;
  final String value;

  ElanSettingSelectPage({required this.keyName, required this.value});

  @override
  ElanSettingSelectPageState createState() => ElanSettingSelectPageState();
}

class ElanSettingSelectPageState extends State<ElanSettingSelectPage> {
  bool _load = false;
  bool _playing = false;
  var title = '';
  var _key = '';
  var _value = '';
  var _init = true;
  List<List<String>> data = [];
  AudioService audio = AudioService();

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('setting select  initState');

    _key = widget.keyName;
    _value = widget.value;
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('setting select didChangeDependencies');

    if (_init) {
      _init = false;

      if (_key == 'DISPTYPE') {
        title = '表示';
        data = [
          ['0', '標準'],
          ['1', '居室'],
          // ['2', 'カメラ']
        ];
      } else if (_key == 'DISPLAYNUM') {
        title = '表示数';
        data = [
          ['0', '15'],
          ['1', '100'],
        ];
      } else if (_key == 'SLEEP_CLOCK') {
        title = '時計';
        data = [
          ['0', 'デジタル'],
          ['1', 'デジタル(日付あり)'],
          // ['2', 'アナログ']
        ];
      } else if (_key == 'RINGTONE') {
        title = '着信音';
        data = AppManager.ringtones;
        data.insert(0, ['0', '標準']);
      } else if (_key == 'WEATHER_AREA') {
        title = '天気予報コード';
        data = AppManager.weatherAreas;
      } else if (_key == 'CALLSCREENIMAGE') {
        title = '背景画像';
        data = AppManager.callScreenImages;
        data.insert(0, ['0', '標準']);
      } else if (_key == 'CALLSCREENIMAGEL') {
        title = '背景画像(横)';
        data = AppManager.callScreenImages;
        data.insert(0, ['0', '標準']);
      }
    }

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

  void _downloadCallScreenImage(String id) async {
    setState(() {
      _load = true;
    });
    final filename = _key == 'CALLSCREENIMAGE' ? 'dlimage.jpg' : 'dlimagel.jpg';
    final url = "${AppDefine.baseURL}app/call_screen_image_dl/$id?token=" + AppManager.settings["api_token"];
    print(url);

    try {
      Directory appDocDir = await getApplicationDocumentsDirectory();
      String path = appDocDir.path;
      var res = await get(Uri.parse(url));
      final imagePath = '$path/$filename';
      //comment out the next three lines to prevent the image from being saved
      //to the device to show that it's coming from the internet
      File file2 = File(imagePath);
      file2.writeAsBytesSync(res.bodyBytes);

      // final dio = Dio();
      // Response response = await dio.get(
      //   url,
      //   // onReceiveProgress: showDownloadProgress,
      //   //Received data with List<int>
      //   options: Options(
      //     responseType: ResponseType.bytes,
      //     followRedirects: false,
      //     // validateStatus: (status) {
      //     //   return status < 500;
      //     // }
      //   ),
      // );
      // print(response.headers);
      // String dir = (await getApplicationDocumentsDirectory()).path;
      // File file = File('$dir/$filename');
      // var raf = file.openSync(mode: FileMode.write);
      // // response.data is List<int> type
      // raf.writeFromSync(response.data);
      // await raf.close();
      print('download success');
    } catch (e) {
      print('download error');
      print(e);
    }
    setState(() {
      _load = false;
      _value = id;
    });
  }

  Future<void> _postWeatherArea(String id) async {

    setState(() {
      _load = true;
    });
    final dio = Dio();
    var url = '${AppDefine.baseURL}app/set_weather_area';
    final data = await dio.post(
      url,
      data: FormData.fromMap({
        "token": AppManager.settings["api_token"],
        "value": id,
      }),
    ).then((response) {
      print(response.data);
      if (response.data['status'].toString() == 'ng') {
        return null;
      }
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });
    if (data != null) {
      setState(() {
        _value = id;
      });
    }
    setState(() {
      _load = false;
    });
  }

  Widget _listContainer(String title, String val) {
    return GestureDetector(
      onTap: () {
        if (_key == 'RINGTONE') {
          if (_playing) {
            _playRingtone();
          }
          _downloadRingtone(val);
          return;
        }
        if (_key == 'WEATHER_AREA') {
          _postWeatherArea(val);
        }
        if (_key == 'CALLSCREENIMAGE' || _key == 'CALLSCREENIMAGEL') {
          _downloadCallScreenImage(val);
          return;
        }
        setState(() {
          _value = val;
        });
      },
      child: WidgetUtil.listItem(Container(
        height: WidgetUtil.listHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: WidgetUtil.titleTextStyle1,
            ),
            if (_value == val)
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
        if (_key == 'DISPTYPE') {
          AppManager.saveSetting(_key, _value);
        } else if (_key == 'DISPLAYNUM') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'SLEEP_CLOCK') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'RINGTONE') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'CALLSCREENIMAGE') {
          AppManager.saveAppSetting(_key, _value);
        } else if (_key == 'CALLSCREENIMAGEL') {
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
            ListView.builder(
              itemBuilder: (BuildContext context, int index) {
                return _listContainer(data[index][1], data[index][0]);
              },
              itemCount: data.length,
            ),
            if (_load)
              WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
