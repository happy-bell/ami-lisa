import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:amiapp/notifiers/app_notifier.dart';
import 'package:amiapp/pages/elan/elan_call_page.dart';
import 'package:amiapp/pages/elan/elan_tab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent-tab-view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/pages/staff/staff_live_view_page.dart';
import 'package:amiapp/pages/staff/staff_talk_page.dart';
import 'package:amiapp/pages/setting/setting_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:real_volume/real_volume.dart';

import '../../helpers/widget_util.dart';

class ElanPhonePage extends StatefulWidget {
final ElanTabPageState tabPageState;
ElanPhonePage({Key? key, required this.tabPageState}) : super(key: key);

  @override
  ElanPhonePageState createState() => ElanPhonePageState();
}

class ElanPhonePageState extends State<ElanPhonePage>
    with WidgetsBindingObserver, SocketIOServiceDelegate {
  bool _init = true;
  String _version = '1.0';
  SocketIOService socketservice = SocketIOService();
  AudioService audio = AudioService();
  bool _isconnect = false;
  List<Address> addressList = [];
  bool _islist = false;

  @override
  void initState() {
    super.initState();
    print('[DEBUG PRINT] elan phone initState');

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      var addressStore = context.read<AddressStore>();
      if (addressStore.selectUser != null) {
        selectAddress(addressStore.selectUser!);
      }
    });

    // socketservice.delegate = this;
    // sensorService.delegate = this;
    // AppManager.setStatusBarHidden(true);
    // initPlatformState();
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    print('elan phone didChangeDependencies');

    if (_init) {
      print('plan phone init');
      _init = false;
      _version = await AppManager.appVersion();
      // final AppStore appStore = Provider.of<AppStore>(context);
      // if (appStore.selectUser != null) {
      //   selectAddress(appStore.selectUser!);
      // }
    }
  }

  Widget _gridItem(Address address) {
    String liveText = '';
    Uint8List bytes = Uint8List(0);
    var imageName = 'assets/images/status/dummy.png';
    if (address.call == 1) {
      imageName = 'assets/images/status/addr_call.png';
    }
    else if (address.called == 1) {
      imageName = 'assets/images/status/addr_called.png';
    }
    else if (address.status == 0 || address.status == 1) {
      imageName = 'assets/images/status/addr.png';
      if (address.photo.isNotEmpty) {
        var photo = address.photo;
        var base64Pos = photo.indexOf('base64,');
        if (base64Pos >= 0) {
          photo = photo.substring(base64Pos + 'base64,'.length);
          bytes = base64Decode(photo);
        }
      }
    }
    else if (address.status == 2 ||
        address.status == 3 ||
        address.status == 4 ||
        address.status == 5) {
      imageName = 'assets/images/status/addr_talk.png';
    }

    var imageWidget = Image.asset(
      imageName,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
    if (bytes.isNotEmpty) {
      imageWidget = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(left: 8,),
              decoration: const BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              height: 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  address.name,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  selectAddress(address);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border.all(color: Colors.grey),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageWidget,
                      Positioned(
                          top: 0,
                          left: 2.0,
                          child: Text(
                            liveText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // if (address.status == 0 || address.status == 1)
        //   Positioned(
        //     top: 20,
        //     height: 20,
        //     child: WidgetUtil.basicText('ON LINE', color: Colors.red,),
        //   ),
      ],
    );
  }

  void _setAddressStatus(udid, status) {
    context.read<AddressStore>().setAddressStatus(udid, status);
  }

  Future<void> selectAddress(Address address) async {
    print('select address: ${address.id}');
    var addressStore = context.read<AddressStore>();
    addressStore.setSelectUser(null);
    AppManager.selectUser = address;
    audio.stopButtonCall();

    // await Navigator.of(context, rootNavigator: true)
    //     .push(MaterialPageRoute(builder: (context) => ElanCallPage(tabPageState: widget.tabPageState), fullscreenDialog: true,));
    final toHome = await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return ElanCallPage(tabPageState: widget.tabPageState);
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );

    // TODO: implement sensorService
    // sensorService.clearAlert(address.id);
    context.read<AddressStore>().setSensor(address.id, '');
    context.read<AddressStore>().setCalled(address.id, 0);

    if (toHome) {
      widget.tabPageState.selectTabIndex(0);
    }
  }

  void _disconnect() {
    socketservice.delegate = null;
    socketservice.disconnect();
    setState(() {
      _isconnect = false;
    });
  }

  void _toSetting() async {
    // _disconnect();
    context.read<AddressStore>().clear();
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => SettingPage()));
  }

  int _colNum(double maxWidth, double maxHeight) {
    var cols = 2;
    var orientation = (maxWidth > maxHeight ? 'L' : 'P');
    bool isTablet = (max(maxWidth, maxHeight) > 800);
    var dispNum = AppManager.appsettings['DISPLAYNUM'];
    if (dispNum == '0') {
      // 表示数15
      if (!isTablet) {
        // スマホ
        if (orientation == 'L') {
          //　横向き
          cols = 4;
        }
      } else {
        // タブレット
        cols = (orientation == 'L' ? 4 : 3);
      }
    } else {
      // 表示数100
      if (!isTablet) {
        // スマホ
        cols = (orientation == 'L' ? 7 : 3);
      } else {
        // タブレット
        cols = (orientation == 'L' ? 7 : 5);
      }
    }
    return cols;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarBrightness: Brightness.dark,
      // statusBarColor: Colors.blue, //or set color with: Color(0xFF0000FF)
    ));
    const iconSize = 50.0;
    var connectMyId = AppManager.myId;
    if (AppDefine.amiApp) {
      connectMyId = AppManager.myId.replaceAll(AppManager.settings["DELEGATORCODE"] + "_", "");
    }

    final AppStore appStore = Provider.of<AppStore>(context);

    return Scaffold(
      appBar: WidgetUtil.appBar('相手を選んでください',
        foregroundColor: Colors.black,
        leading: TextButton(
          child: const Text(
            '< 戻る',
            style: TextStyle(
              color: Colors.blueAccent,  //文字の色を白にする
              fontWeight: FontWeight.bold,  //文字を太字する
              fontSize: 16.0,  //文字のサイズを調整する
            ),
          ),
          onPressed: () {
            widget.tabPageState.closePhonePage();
          },
        ),
        leadingWidth: 64,
        backgroundColor: WidgetUtil.phoneAppBar,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gridPadding = 4.0;
                var gridSpacing = 10.0;
                var cols = _colNum(constraints.maxWidth, constraints.maxHeight);
                var colWidth = (constraints.maxWidth - (gridSpacing * (cols - 1) + gridPadding * 2)) / cols;
                var colHeight = (colWidth / 3 * 2) + 24;
                var gridRatio = colWidth / colHeight;
                return Consumer<AddressStore>(builder: (BuildContext context,
                    AddressStore addressStore, Widget? child) {
                  return GridView.extent(
                    maxCrossAxisExtent: colWidth,
                    padding: const EdgeInsets.fromLTRB(gridPadding, 10, gridPadding, 60),
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: gridRatio,
                    children: addressStore.staffList()
                        .map((data) => _gridItem(data))
                        .toList(),
                  );
                });
              },
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              color: WidgetUtil.primaryBG,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 8,),
                        Image.asset(appStore.connect
                            ? 'assets/images/led/ledG.png'
                            : 'assets/images/led/led2.png'),
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            '${appStore.connect ? 'ON' : 'OFF'} LINE $connectMyId',
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 64.0,
                          height: iconSize - 20.0,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: const Text("WebMeet",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                            onPressed: () async {
                              // _toMeet();
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 8.0, right: 4.0, top: 8.0),
                          child: Text(
                            'Ver. $_version',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        // GestureDetector(
                        //   child: Image.asset(
                        //     'assets/images/spana.png',
                        //     width: 30,
                        //     height: 30,
                        //   ),
                        //   onLongPress: () {
                        //     _toSetting();
                        //   },
                        // ),
                        const SizedBox(width: 8,),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// socket service
  ///
  @override
  void onConnect() {
    var useType = "0";
    if (AppManager.settings["DISPTYPE"] == '2') {
      useType = '1';
    }

    socketservice.delegatorLogin(useType);
  }

  @override
  void onDisConnect() {
    setState(() {
      _isconnect = false;
    });
  }

  @override
  void onAppMessage(data) {
    String message = data['message'];
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        _isconnect = true;
      });
      socketservice.io.emit("clients_status", [AppManager.settings['addressGroup']]);
      // TODO: implement _checkFcm
      // _checkFcm();
      // TODO: implement _checkPushSensor
      // _checkPushSensor();
    } else if (message == 'clients_status') {
      var statuses = data['data'];
      statuses.forEach((udid, value) {
        _setAddressStatus(udid, value['status']);
      });
    } else if (message == 'login') {
      if (data['info']['client']['udid'] != null) {
        var udid = data['info']['client']['udid'];
        _setAddressStatus(udid, data['info']['client']['status']);
      }
    } else if (message == 'status_change') {
      if (data["info"]["MYID"] != null && data["info"]["STATUS"] != null) {
        var addressStore = context.read<AddressStore>();
        var udid = data["info"]["MYID"];
        final address = addressStore.find(udid);
        if (address != null) {
          if (address.call == 1) {
            // audio.stopRingtone();
            addressStore.setCall(udid, 0);
          }
        }
        _setAddressStatus(data["info"]["MYID"], data["info"]["STATUS"]);
      }
    } else if (message == 'viewcan_image') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["udid"] == null || data["info"]["data"] == null) {
        return;
      }
      var addressStore = context.read<AddressStore>();
      var udid = data["info"]["udid"];
      final index = addressStore.findAddress(udid);
      if (index < 0) {
        return;
      }
      String image = data["info"]["data"];
      var base64Pos = image.indexOf('base64,');
      if (base64Pos >= 0) {
        image = image.substring(base64Pos + 'base64,'.length);
      }
      var image64 = image.replaceAll("\r\n", "");
      // print(image64);
      addressStore.setLiveImage(udid, image64);
    } else if (message == 'call') {
      if (data["info"]["udid"] == null) {
        return;
      }
      var addressStore = context.read<AddressStore>();
      var udid = data["info"]["udid"];
      final index = addressStore.findAddress(udid);
      if (index < 0) {
        return;
      }
      addressStore.setCall(udid, 1);
      if (AppManager.status == AppStatus.Call ||
          AppManager.status == AppStatus.Talk ||
          AppManager.status == AppStatus.Multi ||
          AppManager.status == AppStatus.MultiToTalk) {
      } else {
        if (AppManager.appsettings["AUTO_RECEIVE"] == '1') {
          if (AppManager.selectUser == null) {
            var address = context.read<AddressStore>().find(data["info"]["udid"]);
            if (address != null) {
              AppManager.autoReceiveId = address.id;
              selectAddress(address);
            }
          }
          return;
        }
        audio.ringtone();
      }
    } else if (message == 'call_cancel') {
      if (data["udid"] == null) {
        return;
      }
      context.read<AddressStore>().setCall(data["udid"], 0);
      context.read<AddressStore>().setCalled(data["udid"], 1);
      audio.stopRingtone();
    }
  }

  @override
  void onMessage(data) {
    // TODO: implement onMessage
  }

  @override
  void onTalkMessage(data) {
    // TODO: implement onTalkMessage
  }
}