import 'dart:convert';
import 'dart:io';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/setting/setting_info_photo_page.dart';
import 'package:amiapp/pages/staff/manager_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/pages/setting/setting_about_page.dart';
import 'package:amiapp/pages/setting/setting_input_page.dart';
import 'package:amiapp/pages/setting/setting_message_page.dart';
import 'package:amiapp/pages/setting/setting_select_page.dart';
import 'package:amiapp/services/tv_message_schedule.dart';
import 'package:amiapp/pages/setting/setting_multi_select_page.dart';
import 'package:amiapp/pages/staff/staff_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';

import '../../helpers/widget_util.dart';
import '../../widgets/and_vital_pair_dialog.dart';
import '../../widgets/tv_focusable.dart';
import '../elan/setting/elan_setting_info_video_page.dart';
import '../live/live_page.dart';
import '../room/room_page.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _load = false;
  bool _savedSwitch = false;
  String _androidId = '';

  final _listHeight = 44.0;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('[DEBUG PRINT] setting initState');
    AppManager.status = AppStatus.None;
    AppManager.talkId1 = '';
    AppManager.talkId2 = '';
    AppManager.holdId = '';
    AppManager.holdedId = '';
    if (Platform.isAndroid) {
      TvUtil.getAndroidId().then((id) {
        if (mounted) setState(() => _androidId = id);
      });
    }
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    print('[DEBUG PRINT] setting didChangeDependencies');
    AppManager.setStatusBarHidden(true);
  }

  Future<void> _logout() async {
    var value = await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('ログアウトしますか？'),
        actions: <Widget>[
          TvDialogAction(
            autofocus: TvUtil.isTelevision,
            label: 'はい',
            onPressed: () => Navigator.pop(context, "1"),
          ),
          TvDialogAction(
            label: 'いいえ',
            onPressed: () => Navigator.pop(context, "0"),
          ),
        ],
      ),
    );
    switch (value) {
      case "1":
        var prefs = await SharedPreferences.getInstance();
        await prefs.setBool('login', false);
        await prefs.setBool('manager', false);
        await prefs.remove('codes');

        if (mounted) {
          Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
            pageBuilder: (BuildContext context, Animation<double> animation1,
                Animation<double> animation2) {
              return SignInPage();
            },
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ));
        }
        break;
      case "0":
        break;
    }
  }

  Future<void> _getAddress() async {
    var response = await _requestAddress();
    var prefs = await SharedPreferences.getInstance();
    var addressKey = "ADDRESS";
    if (AppDefine.amiApp) {
      addressKey = "address";
    }
    await prefs.setString('address', json.encode(response[addressKey]));
    _showDialog(1);
  }

  String _getAddressURL() {
    if (AppDefine.amiApp) {
      if (AppManager.isManager) {
        return "${AppDefine.baseURL}app/staff_address_list?code=${AppManager.settings['DELEGATORCODE']}&token=${AppManager.settings['api_token']}";
      }
      var mstId = AppManager.settings['MYID']
          .replaceAll(AppManager.settings['DELEGATORCODE'] + "_", "");
      return "${AppDefine.baseURL}app/address_list?code=${AppManager.settings['DELEGATORCODE']}&mst_id=$mstId&token=${AppManager.settings['api_token']}";
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
    var url = _getAddressURL();
    print(url);

    final dio = Dio();
    var data = await dio
        .get(
      url,
    )
        .then((response) {
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
      AppManager.ringtones.add(
          [ringtones[i]['id'].toString(), ringtones[i]['name'].toString()]);
    }
    var result = await Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => SettingSelectPage(
            keyName: 'RINGTONE', value: AppManager.appsettings['RINGTONE'])));
    AppManager.appsettings['RINGTONE'] = result;
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  String _ringtoneURL() {
    if (AppDefine.amiApp) {
      return '${AppDefine.baseURL}app/ringtone_list?code=${AppManager.settings["DELEGATORCODE"]}&token=${AppManager.settings["api_token"]}';
    }
    var token = AppDefine.getRMSToken();
    var url =
        'https://${AppManager.settings['MCSURL']}/json/appringtonelist?gcd=${AppManager.settings['MCSGROUPCODE']}&ccd=${AppManager.settings['MCSCLINICCODE']}&token=$token';
    return url;
  }

  Future<dynamic> _requestRingtone() async {
    setState(() {
      _load = true;
    });
    var url = _ringtoneURL();
    print(url);

    final dio = Dio();
    var data = await dio
        .get(
      url,
    )
        .then((response) {
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

  Future<void> _toInfoVideoPage() async {
    var result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ElanSettingInfoVideoPage()));
    if (result == 'play' && mounted) {
      _leaveToHome();
      return;
    }
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  void _leaveToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1,
            Animation<double> animation2) {
          return RoomPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  Future<void> _toInfoPhotoPage() async {
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => SettingInfoPhotoPage()));
    setState(() {
      _savedSwitch = !_savedSwitch;
    });
  }

  List<Widget> _listContainers() {
    var mode = 'user';
    if (AppManager.isManager) {
      if (AppManager.selectCode.isEmpty) {
        mode = 'staff1';
      } else {
        mode = 'staff2';
      }
    }

    var label = "医療機関";
    if (AppDefine.amiApp) {
      label = "契約者名";
    }
    List<Widget> listContainers = [
      _separator(),
      dispListContainer(label, AppManager.settings['MCSCLINICNAME']),
      tapListContainer('ログアウト', () {
        print('logout');
        _logout();
      }, autofocus: TvUtil.isTelevision),
    ];

    if (AppManager.settings['MCSTYPE'] == '4') {
      listContainers.addAll([_separator(), abountListContainer()]);
      return listContainers;
    }

    if (AppDefine.amiApp) {
      listContainers.addAll([
        _separator(),
        dispListContainer('自分のID', AppManager.settings['myId']),
        if (TvUtil.isTelevision && _androidId.isNotEmpty)
          dispListContainer('テレビシリアル', _androidId),
        tapListContainer('リスト更新', () {
          _getAddress();
        }),
      ]);
    } else {
      listContainers.addAll([
        _separator(),
        dispListContainer('自分のID', AppManager.settings['myId']),
        nextListContainer('グループ', AppManager.settings['group'], () async {
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingInputPage(
                  keyName: 'group', value: AppManager.settings['group'])));
          if (result != null) {
            AppManager.settings['group'] = result;
          }
          setState(() {
            _savedSwitch = !_savedSwitch;
          });
        }),
        nextListContainer('住所録グループ', AppManager.settings['addressGroup'],
            () async {
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingInputPage(
                  keyName: 'addressGroup',
                  value: AppManager.settings['addressGroup'])));
          if (result != null) {
            AppManager.settings['addressGroup'] = result;
          }
          setState(() {
            _savedSwitch = !_savedSwitch;
          });
        }),
        tapListContainer('住所録取得', () {
          _getAddress();
        }),
      ]);
    }

    var dispType = AppManager.settings['DISPTYPE'];
    var anminModeFlg = AppManager.settings['ANMINMODEFLG'];
    // TCLアミ: 表示は居室固定。項目は残すがTVでは出さない（復活用）。
    if (TvUtil.isTelevision && dispType != '1') {
      dispType = '1';
      AppManager.settings['DISPTYPE'] = '1';
      AppManager.saveSetting('DISPTYPE', '1');
    }
    listContainers.addAll([
      _separator(),
      if (!TvUtil.isTelevision)
        nextListContainer('表示', AppManager.dispType(dispType), () async {
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingSelectPage(
                  keyName: 'DISPTYPE', value: AppManager.settings['DISPTYPE'])));
          AppManager.settings['DISPTYPE'] = result;
          setState(() {
            _savedSwitch = !_savedSwitch;
          });
        }),
      if (!TvUtil.isTelevision)
        nextListContainer(
            '表示数', AppManager.displyNumber(AppManager.appsettings['DISPLAYNUM']),
            () async {
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingSelectPage(
                  keyName: 'DISPLAYNUM',
                  value: AppManager.appsettings['DISPLAYNUM'])));
          AppManager.appsettings['DISPLAYNUM'] = result;
          setState(() {
            _savedSwitch = !_savedSwitch;
          });
        }),
      switchListContainer(
          TvUtil.isTelevision ? '自動応答（視聴中も確認なし）' : '自動応答',
          'AUTO_RECEIVE'),
      if (dispType == '1')
        nextListContainer('通話開始時間', AppManager.callDelayText(), () async {
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingSelectPage(
                  keyName: 'CALL_DELAY',
                  value: AppManager.appsettings['CALL_DELAY'] ?? '0')));
          AppManager.appsettings['CALL_DELAY'] = result;
          setState(() {
            _savedSwitch = !_savedSwitch;
          });
        }),
    ]);

    if (mode == 'staff2') {
      listContainers.add(switchListContainer('通話権限', 'AUTH_RECEIVE'));
    }

    if (dispType == '1' && anminModeFlg == '1') {
      listContainers.add(
        switchListContainer('安眠モード', 'SLEEP_MODE'),
      );
    }

    if (dispType == '1' && !TvUtil.isTelevision) {
      listContainers.add(
          nextListContainer('明るさ', AppManager.sleepModeBrightness(), () async {
        var result = await Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => SettingSelectPage(
                keyName: 'SLEEPMODEBRIGHTNESS',
                value: AppManager.appsettings['SLEEPMODEBRIGHTNESS'])));
        AppManager.appsettings['SLEEPMODEBRIGHTNESS'] = result;
        setState(() {
          _savedSwitch = !_savedSwitch;
        });
      }));
    }
    // EX の時計は下の「時計」（時間帯＋デジタル／デジタル日付）に統合する。
    if ((dispType == '1' || dispType == '2') &&
        !(TvUtil.isTelevision && AppManager.isPiTvLayout)) {
      listContainers
          .add(nextListContainer('時計', AppManager.clockMode(), () async {
        var result = await Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => SettingSelectPage(
                keyName: 'SLEEP_CLOCK',
                value: AppManager.appsettings['SLEEP_CLOCK'])));
        AppManager.appsettings['SLEEP_CLOCK'] = result;
        setState(() {
          _savedSwitch = !_savedSwitch;
        });
      }));
    }

    if (dispType == '0') {
      listContainers.addAll([
        // nextListContainer('自動応答個別設定', '', () async {
        //   await Navigator.of(context)
        //       .push(MaterialPageRoute(builder: (context) => SettingUserPage()));
        // }),
        // _separator,
        nextListContainer('センサー', '', () async {
          // final args = SettingArguments();
          // args.key = 'SENSOR';
          // args.value = '';
          var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingMultiSelectPage(
                  keyName: 'SENSOR', value: AppManager.settings['DISPTYPE'])));
          // await Navigator.of(context)
          //     .pushNamed('/settingmultiselect', arguments: args);
          // AppManager.settings['DISPTYPE'] = result;
          // setState(() {_savedSwitch = !_savedSwitch;});
        }),
      ]);
    }

    if (Platform.isIOS && dispType == '1') {
      listContainers.addAll([
        switchListContainer('ボリューム呼び出し', 'VOLUME_CALL'),
      ]);
    }

    if (mode != 'staff1') {
      listContainers.addAll([
        _separator(),
        nextListContainer('着信音', '', () {
          _getRingtone();
        }),
        _separator(),
      ]);
    } else {
      listContainers.add(_separator());
    }
    if (dispType == '1' && !TvUtil.isTelevision) {
      listContainers.add(
        switchListContainer('ホーム画面の時計', 'CLOCKDISP'),
      );
    }

    if (AppDefine.amiApp) {
      if (!TvUtil.isTelevision) {
        listContainers.add(switchListContainer('表示設定', 'CALLSTATUSDISP'));
      }
      if (mode == 'user' &&
          !(TvUtil.isTelevision && !AppManager.isPiTvLayout)) {
        listContainers.addAll([
          nextListContainer(
            TvUtil.isTelevision ? 'ビデオ' : 'お知らせ動画',
            '',
            _toInfoVideoPage,
          ),
          nextListContainer('スライドショー', '', _toInfoPhotoPage),
        ]);
      }
      if (TvUtil.isTelevision && mode == 'user') {
        listContainers.add(
          nextListContainer('ホーム画面', AppManager.tvLayoutLabel(), () async {
            var result = await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SettingSelectPage(
                keyName: 'TV_LAYOUT',
                value: AppManager.tvLayout,
              ),
            ));
            if (result != null) {
              await AppManager.saveTvLayout(result);
              if (mounted) {
                TvUtil.markRouteFocusSettle();
                Navigator.of(context).pop();
                return;
              }
            }
            setState(() {
              _savedSwitch = !_savedSwitch;
            });
          }),
        );
        listContainers.add(
          nextListContainer('メッセージ', TvMessageSchedule.summaryLabel(), () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SettingMessagePage(),
            ));
            setState(() {
              _savedSwitch = !_savedSwitch;
            });
          }),
        );
        listContainers.add(
          nextListContainer(
            '時計',
            TvMessageSchedule.summaryLabel(key: TvMessageSchedule.clockKey),
            () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingMessagePage(
                  title: '時計',
                  settingKey: TvMessageSchedule.clockKey,
                  colorTitle: '日付の明るさ',
                ),
              ));
              setState(() {
                _savedSwitch = !_savedSwitch;
              });
            },
          ),
        );
        if (AppManager.isPiTvLayout) {
          listContainers.add(
            nextListContainer('天気予報', AppManager.weatherAreaLabel(), () async {
              if (AppManager.weatherAreas.isEmpty) {
                AppManager.weatherAreas =
                    List<List<String>>.from(AppManager.defaultWeatherAreas);
              }
              var result = await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => SettingSelectPage(
                  keyName: 'WEATHER_AREA',
                  value: AppManager.weatherArea,
                ),
              ));
              if (result != null) {
                await AppManager.saveWeatherArea(result);
              }
              setState(() {
                _savedSwitch = !_savedSwitch;
              });
            }),
          );
        }
        if (AppManager.isPiTvLayout && AppManager.isDoctorAccount) {
          listContainers.add(
            nextListContainer('Doc/Pat', AppManager.amiModeLabel(), () async {
              var result = await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => SettingSelectPage(
                  keyName: 'AMI_MODE',
                  value: AppManager.amiMode,
                ),
              ));
              if (result != null) {
                await AppManager.saveAmiMode(result);
              }
              setState(() {
                _savedSwitch = !_savedSwitch;
              });
            }),
          );
        }
        listContainers.add(
          nextListContainer('BLE ペアリング', '', () {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const AndVitalPairDialog(),
            );
          }),
        );
      }
    }

    listContainers.addAll([_separator(), abountListContainer()]);

    return listContainers;
  }

  @override
  Widget build(BuildContext context) {
    var listContainers = _listContainers();

    return WillPopScope(
      onWillPop: () async {
        // TVの設定はホームから push されているので、そのまま pop する。
        // 新しい RoomPage を積み直すとフォーカスが二重になり移動音が2回鳴る。
        if (TvUtil.isTelevision &&
            AppManager.settings['DISPTYPE'] == '1') {
          TvUtil.markRouteFocusSettle();
          return true;
        }
        if (AppManager.settings['MCSTYPE'] == '4') {
          AppManager.setStatusBarHidden(false);
          return Future.value(true);
        }

        var nextpage = '/staff';
        if (AppManager.settings['DISPTYPE'] == '1') {
          nextpage = '/room';
          _leaveToHome();
        } else if (AppManager.settings['DISPTYPE'] == '2') {
          nextpage = '/live';
          // live
          // Navigator.pushAndRemoveUntil(
          //   context,
          //   MaterialPageRoute(builder: (context) => LivePage(),),
          //       (route) => false,
          // );
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (BuildContext context, Animation<double> animation1,
                  Animation<double> animation2) {
                return LivePage();
              },
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        } else if (AppManager.settings['MCSTYPE'] == 'SSSS') {
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (BuildContext context, Animation<double> animation1,
                  Animation<double> animation2) {
                return ManagerPage();
              },
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        } else {
          // Navigator.pushAndRemoveUntil(
          //   context,
          //   MaterialPageRoute(builder: (context) => StaffPage(),),
          //       (route) => false,
          // );
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (BuildContext context, Animation<double> animation1,
                  Animation<double> animation2) {
                return StaffPage();
              },
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        }
        // Navigator.of(context).pushNamedAndRemoveUntil(nextpage, (route) => false);

        return Future.value(false);
      },
      child: Scaffold(
        appBar: WidgetUtil.appBar(
          '設定',
          backgroundColor: WidgetUtil.iosNavbarBG,
          foregroundColor: Colors.black,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(
              color: const Color.fromARGB(255, 240, 240, 240),
              child: FocusTraversalGroup(
                child: ListView(
                  children: listContainers,
                ),
              ),
            ),
            if (_load)
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
      ),
    );
  }

  Widget _separator() => const SizedBox(height: 20);

  double get _rowHeight => TvUtil.isTelevision ? 64.0 : _listHeight;

  TextStyle get _rowTitleStyle => TextStyle(
        fontSize: TvUtil.isTelevision ? 22 : 14,
      );

  TextStyle get _rowLinkStyle => TextStyle(
        fontSize: TvUtil.isTelevision ? 22 : 14,
        color: Colors.blue,
      );

  Widget _tvFocusWrap({
    required Widget child,
    required VoidCallback onActivate,
    bool autofocus = false,
  }) {
    return TvSettingFocus(
      autofocus: autofocus,
      onActivate: onActivate,
      child: child,
    );
  }

  Widget dispListContainer(String title, String subtitle) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
        ),
      ),
      height: _rowHeight,
      padding: const EdgeInsets.all(10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: _rowTitleStyle),
          Text(subtitle, style: _rowTitleStyle),
        ],
      ),
    );
  }

  Widget tapListContainer(String title, Function ontap, {bool autofocus = false}) {
    return _tvFocusWrap(
      autofocus: autofocus,
      onActivate: () => ontap(),
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.all(10.0),
        alignment: Alignment.centerLeft,
        child: Text(title, style: _rowLinkStyle),
      ),
    );
  }

  Widget nextListContainer(String title, String subtitle, Function ontap,
      {bool autofocus = false}) {
    return _tvFocusWrap(
      autofocus: autofocus,
      onActivate: () => ontap(),
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: _rowTitleStyle),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(subtitle, style: _rowTitleStyle),
                const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 18.0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget switchListContainer(String title, String key) {
    var isSwtich = false;
    if (key == 'AUTO_RECEIVE' ||
        key == 'VOLUME_CALL' ||
        key == 'CLOCKDISP') {
      if (AppManager.appsettings[key] == '1') {
        isSwtich = true;
      }
    } else if (key == 'SLEEP_MODE' || key == 'CALLSTATUSDISP') {
      if (AppManager.appsettings[key] == '1') {
        isSwtich = true;
      }
    } else if (key == 'AUTH_RECEIVE') {
      if (AppManager.authReceives.keys.contains(AppManager.selectCode)) {
        if (AppManager.authReceives[AppManager.selectCode] == '1') {
          isSwtich = true;
        }
      }
    }

    Future<void> toggle([bool? value]) async {
      final next = value ?? !isSwtich;
      final val = next ? '1' : '0';
      if (key == 'AUTO_RECEIVE' ||
          key == 'VOLUME_CALL' ||
          key == 'CLOCKDISP') {
        await AppManager.saveAppSetting(key, val);
      } else if (key == 'SLEEP_MODE' || key == 'CALLSTATUSDISP') {
        await AppManager.saveAppSetting(key, val);
      } else if (key == 'AUTH_RECEIVE') {
        AppManager.saveAuthReceives(val);
      }

      setState(() {
        _savedSwitch = !_savedSwitch;
      });
    }

    return _tvFocusWrap(
      onActivate: () => toggle(),
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(title, style: _rowTitleStyle)),
            ExcludeFocus(
              child: CupertinoSwitch(
                value: isSwtich,
                onChanged: (value) => toggle(value),
                activeTrackColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget abountListContainer() {
    return nextListContainer("このアプリについて", '', () async {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => SettingAboutPage()));
    });
  }

  Future _showDialog(type) async {
    var message = 'ログイン情報を確認してください。';
    if (type == 1) {
      message = '住所録を取得しました。';
    } else if (type == 2) {
      message = '着信音情報を取得できません。';
    }
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認'),
          content: Text(message),
          actions: <Widget>[
            TvDialogAction(
              autofocus: TvUtil.isTelevision,
              label: 'OK',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}
