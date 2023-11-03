import 'dart:convert';
import 'dart:io';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/elan/elan_signin_page.dart';
import 'package:amiapp/pages/elan/setting/elan_setting_info_message_page.dart';
import 'package:amiapp/pages/elan/setting/elan_setting_info_photo_page.dart';
import 'package:amiapp/pages/elan/setting/elan_setting_info_video_page.dart';
import 'package:amiapp/pages/elan/setting/elan_user_list_page.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/setting/setting_about_page.dart';
import 'package:amiapp/pages/setting/setting_input_page.dart';
import 'package:amiapp/pages/setting/setting_select_page.dart';
import 'package:amiapp/pages/setting/setting_multi_select_page.dart';
import 'package:amiapp/pages/setting/setting_user_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';

import '../../../notifiers/address_notifier.dart';
import 'elan_setting_select_page.dart';

class ElanSettingPage extends StatefulWidget {
  ElanSettingPage({Key? key}) : super(key: key);

  @override
  ElanSettingPageState createState() => ElanSettingPageState();
}

class ElanSettingPageState extends State<ElanSettingPage> {
  bool _load = false;
  bool _savedSwitch = false;

  final TextStyle _titleTextStyle1 = const TextStyle(
    fontSize: 14,
  );
  final TextStyle _titleTextStyle2 = const TextStyle(fontSize: 14, color: Colors.blue);

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('[DEBUG PRINT] elan setting initState');
    AppManager.status = AppStatus.None;
    AppManager.talkId1 = '';
    AppManager.talkId2 = '';
    AppManager.holdId = '';
    AppManager.holdedId = '';

    if (AppManager.toPage == 'ElanUserListPage') {
      print('topage: elanuserlistpage');
      AppManager.toPage = '';
      Future(toUserListPage);
    }
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('[DEBUG PRINT] elan setting didChangeDependencies');
  }

  void _logout() async {
    var value = await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('ログアウトしますか？'),
        actions: <Widget>[
          SimpleDialogOption(
            child: const Text('はい'),
            onPressed: () {
              Navigator.pop(context, "1");
            },
          ),
          SimpleDialogOption(
            child: const Text('いいえ'),
            onPressed: () {
              Navigator.pop(context, "0");
            },
          ),
        ],
      ),
    );
    switch (value) {
      case "1":
        var prefs = await SharedPreferences.getInstance();
        await prefs.setBool('login', false);

        if (mounted) {
          Navigator.of(context, rootNavigator: true)
              .push(
              PageRouteBuilder(
                pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
                  return ElanSignInPage();
                },
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              )
          );
        }
        break;
      case "0":
        break;
    }
  }

  Future<void> _getAddress({bool showDialog = true}) async {
    var response = await _requestAddress();
    if (response == null) {
      return;
    }
    var prefs = await SharedPreferences.getInstance();
    var addressKey = "ADDRESS";
    if (AppDefine.amiApp) {
      addressKey = "address";
    }
    await prefs.setString('address', json.encode(response[addressKey]));
    context.read<AddressStore>().setAddressList(response[addressKey]);
    if (!showDialog) {
      return;
    }
    _showDialog(1);
  }

  String _getAddressURL() {
    if (AppDefine.amiApp) {
      var mstId = AppManager.settings['MYID'].replaceAll(AppManager.settings['DELEGATORCODE'] + "_", "");
      return AppDefine.baseURL + "app/address_list?code=" + AppManager.settings['DELEGATORCODE'] +
          "&mst_id=" + mstId +
          "&token=" + AppManager.settings['api_token'];
    }

    var token = AppDefine.getRMSToken();
    var url = 'https://' +
        AppManager.settings['MCSURL'] +
        '/json/appaddresslist?gcd=' +
        AppManager.settings['MCSGROUPCODE'] +
        '&ccd=' +
        AppManager.settings['MCSCLINICCODE'] +
        '&group=' +
        AppManager.settings['addressGroup'] +
        '&id=' +
        AppManager.settings['myId'] +
        '&token=' +
        token;
    return url;
  }

  Future<dynamic> _requestAddress() async {
    setState(() {
      _load = true;
    });
    final url = _getAddressURL();

    final dio = Dio();
    var data = await dio.get(
        url,
    ).then((response) {
      // print(response.data);
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _load = false;
    });
    return data;
  }

  Future<void> _getRingtone() async {
    var response = await _requestRingtone();
    print(response);
    if (response['status'] != 'OK') {
      _showDialog(2);
      return;
    }
    AppManager.ringtones = [];
    var ringtones = response['ringtones'];
    for (var i = 0; i < ringtones.length; i++) {
      AppManager.ringtones.add([ringtones[i]['id'].toString(), ringtones[i]['name'].toString()]);
    }
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanSettingSelectPage(keyName: 'RINGTONE', value: AppManager.appsettings['RINGTONE'])));
    if (result != null) {
      AppManager.appsettings['RINGTONE'] = result;
    }
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  String _ringtoneURL() {
    if (AppDefine.amiApp) {
      return '${AppDefine.baseURL}app/ringtone_list?code=${AppManager.settings["DELEGATORCODE"]}&token=${AppManager.settings["api_token"]}';
    }
    var token = AppDefine.getRMSToken();
    var url = 'https://${AppManager.settings['MCSURL']}/json/appringtonelist?gcd=${AppManager.settings['MCSGROUPCODE']}&ccd=${AppManager.settings['MCSCLINICCODE']}&token=${token}';
    return url;
  }

  Future<dynamic> _requestRingtone() async {
    setState(() {
      _load = true;
    });
    var url = _ringtoneURL();
    print(url);

    final dio = Dio();
    var data = await dio.get(
      url,
    ).then((response) {
      print(response.data);
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _load = false;
    });

    return data;
  }

  Future<void> _getWeatherArea() async {

    setState(() {
      _load = true;
    });
    final url = '${AppDefine.baseURL}app/weather_area?code=${AppManager.settings["DELEGATORCODE"]}&token=${AppManager.settings["api_token"]}';
    print(url);

    final dio = Dio();
    final data = await dio.get(
      url,
    ).then((response) {
      print(response.data);
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _load = false;
    });

    var area = '';
    if (data != null) {
      area = data['area'].toString();
      AppManager.weatherAreas = [];
      for (var i = 0; i < data['weatherArea'].length; i++) {
        AppManager.weatherAreas.add([data['weatherArea'][i][0].toString(), data['weatherArea'][i][1].toString()]);
      }
    }
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanSettingSelectPage(keyName: 'WEATHER_AREA', value: area)));

    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  Future<void> _getCallScreenImage(String keyName) async {
    var response = await _requestCallScreenImage();
    print(response);
    if (response['status'] != 'OK') {
      _showDialog(3);
      return;
    }
    AppManager.callScreenImages = [];
    var items = response['items'];
    for (var i = 0; i < items.length; i++) {
      AppManager.callScreenImages.add([items[i]['id'].toString(), items[i]['name'].toString()]);
    }
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanSettingSelectPage(keyName: keyName, value: AppManager.appsettings[keyName])));
    if (result != null) {
      AppManager.appsettings[keyName] = result;
    }
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  String _callScreenImageURL() {
    var shortestSide = MediaQuery.of(context).size.shortestSide;
    var type = shortestSide < 600 ? 'phone' : 'tablet';
    return '${AppDefine.baseURL}app/call_screen_image_list?code=${AppManager.settings["DELEGATORCODE"]}&type=$type&token=${AppManager.settings["api_token"]}';
  }

  Future<dynamic> _requestCallScreenImage() async {
    setState(() {
      _load = true;
    });
    var url = _callScreenImageURL();
    print(url);

    final dio = Dio();
    var data = await dio.get(
      url,
    ).then((response) {
      print(response.data);
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _load = false;
    });

    return data;
  }

  Future<void> toUserListPage() async {
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanUserListPage()));
    if (result != null && result) {
      _getAddress(showDialog: false);
    }
  }

  Future<void> _toInfoVideoPage() async {
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanSettingInfoVideoPage()));
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  Future<void> _toInfoPhotoPage() async {
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => ElanSettingInfoPhotoPage()));
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  List<Widget> _listContainers() {
    var _separator = separator();

    var label = "契約者名";

    var listContainers = [
      _separator,
      basicListContainer(label, AppManager.settings['MCSCLINICNAME']),
      tapListContainer('ログアウト', _logout),
    ];
    listContainers.addAll([
      _separator,
      basicListContainer('自分のID', AppManager.settings['myId']),
      tapListContainer('リスト更新', _getAddress),
    ]);

    var dispType = AppManager.settings['DISPTYPE'];
    var dispNum = AppManager.appsettings['DISPLAYNUM'];
    var anminModeFlg = AppManager.settings['ANMINMODEFLG'];
    listContainers.addAll([
      _separator,
      // nextListContainer('表示', AppManager.dispType(dispType), () async {
      //   var result = await Navigator.of(context)
      //       .push(MaterialPageRoute(builder: (context) => ElanSettingSelectPage(keyName: 'DISPTYPE', value: AppManager.settings['DISPTYPE'])));
      //   AppManager.settings['DISPTYPE'] = result;
      //   setState(() {
      //     _savedSwitch = !_savedSwitch;
      //   });
      // }),
      nextListContainer('表示数', AppManager.displyNumber(dispNum), () async {
        var result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => ElanSettingSelectPage(keyName: 'DISPLAYNUM', value: AppManager.appsettings['DISPLAYNUM'])));
        if (result != null) {
          AppManager.appsettings['DISPLAYNUM'] = result;
        }
        setState(() {
          _savedSwitch = !_savedSwitch;
        });
      }),
      switchListContainer('自動応答', 'AUTO_RECEIVE'),
      nextListContainer('着信音', '', _getRingtone),
      nextListContainer('背景画像', '', () {
        _getCallScreenImage('CALLSCREENIMAGE');
      }),
      nextListContainer('背景画像(横)', '', () {
        _getCallScreenImage('CALLSCREENIMAGEL');
      }),
      aboutListContainer()
    ]);

    listContainers.addAll([
      _separator,
      nextListContainer('利用者名・画像の変更', '', toUserListPage),
      nextListContainer('お知らせ動画', '', _toInfoVideoPage),
      nextListContainer('スライドショー', '', _toInfoPhotoPage),
      nextListContainer('メッセージ配信', '', () async {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (context) => ElanSettingInfoMessagePage()));
      }),
      nextListContainer('天気予報コード', '', _getWeatherArea),
      _separator,
    ]);

    return listContainers;
  }

  @override
  Widget build(BuildContext context) {
    var listContainers = _listContainers();

    return Scaffold(
      appBar: WidgetUtil.appBar('設定',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Container(
            color: const Color.fromARGB(255, 240, 240, 240),
            child: ListView(
              children: listContainers,
            ),
          ),
          if (_load)
            WidgetUtil.loadingIndicator,
        ],
      ),
    );
  }

  Widget separator() {
    return const SizedBox(height: 20,);
  }

  Widget basicListContainer(String title, String subtitle) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
        ),
      ),
      height: WidgetUtil.listHeight,
      // margin: const EdgeInsets.all(0.0),
      padding: const EdgeInsets.all(10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: _titleTextStyle1,
          ),
          Text(
            subtitle,
            style: _titleTextStyle1,
          ),
        ],
      ),
    );
  }

  Widget tapListContainer(String title, Function ontap) {
    return InkWell(
      onTap: () {
        ontap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: new BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: WidgetUtil.listHeight,
        padding: const EdgeInsets.all(10.0),
        child: Text(
          title,
          style: _titleTextStyle2,
        ),
      ),
    );
  }

  Widget nextListContainer(String title, String subtitle, Function ontap) {
    return InkWell(
      onTap: () {
        ontap();
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: WidgetUtil.listHeight,
        // margin: const EdgeInsets.all(0.0),
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: _titleTextStyle1,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  subtitle,
                  style: _titleTextStyle1,
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 18.0,
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget switchListContainer(String title, String key) {
    var isSwtich = false;
    if (key == 'AUTO_RECEIVE' || key == 'VOLUME_CALL' || key == 'CLOCKDISP') {
      if (AppManager.appsettings[key] == '1') {
        isSwtich = true;
      }
    } else if (key == 'SLEEP_MODE') {
      if (AppManager.appsettings[key] == '1') {
        isSwtich = true;
      }
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
        ),
      ),
      height: WidgetUtil.listHeight,
      padding: const EdgeInsets.all(10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: _titleTextStyle1,
          ),
          Switch(
            value: isSwtich,
            onChanged: (value) {
              print(value);
              String val = '0';
              if (value) {
                val = '1';
              }
              if (key == 'AUTO_RECEIVE' || key == 'VOLUME_CALL' || key == 'CLOCKDISP') {
                AppManager.saveAppSetting(key, val);
              } else if (key == 'SLEEP_MODE') {
                AppManager.saveAppSetting(key, val);
              }

              setState(() {
                _savedSwitch = !_savedSwitch;
              });
            },
            activeTrackColor: Colors.lightBlueAccent,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget aboutListContainer() {
    return nextListContainer("このアプリについて", '', () async {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => SettingAboutPage()));
    });
  }

  Future _showDialog(type) async {
    var message = 'ログイン情報を確認してください。';
    if (type == 1) {
      message = 'リストを取得しました。';
    } else if (type == 11) {
      message = 'リストを取得できませんでした。';
    } else if (type == 2) {
      message = '着信音情報を取得できません。';
    } else if (type == 3) {
      message = '背景画像情報を取得できません。';
    }
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認'),
          content: Text(message),
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
}