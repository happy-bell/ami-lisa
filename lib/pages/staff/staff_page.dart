import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:amiapp/helpers/staff_util.dart';
import 'package:amiapp/pages/staff/staff_web_page.dart';
import 'package:amiapp/widgets/biosilver_popup_widget.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:real_volume/real_volume.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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

import '../../helpers/widget_util.dart';
import '../../services/sensor.dart';
import '../common/webview_page.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});

  @override
  _StaffPageState createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with WidgetsBindingObserver, SocketIOServiceDelegate, SensorServiceDelegate {
  bool _init = true;
  String _version = '1.0';
  SocketIOService socketservice = SocketIOService();
  AudioService audio = AudioService();
  SensorService sensorService = SensorService();
  bool _isconnect = false;
  List<Address> addressList = [];
  final List<dynamic> _callStatuses = [];
  bool _islist = false;
  bool _isActive = false;
  Widget? biosilverPopup;
  Timer? _buttonCallTimer;
  Timer? _checkAccountTimer;

  @override
  void initState() {
    super.initState();
    print('[DEBUG PRINT] staff initState');

    WidgetsBinding.instance.addObserver(this);

    socketservice.delegate = this;
    sensorService.delegate = this;
    AppManager.setStatusBarHidden(true);
    // initPlatformState();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

    if (_init) {
      print('staff didChangeDependencies');
      _init = false;
      _isActive = true;

      var load = await AppManager.loadSetting();
      if (!load) {
        _logout();
      }

      _requestPermission();
      _loadAddress();
      socketservice.startConnectTimer();
      _startButtonCallTimer();
      // _startCheckAccountTimer();

      if (socketservice.connected) {
        _isconnect = true;
        Future(() {
          socketservice.io.emit("clients_status", [AppManager.settings['addressGroup']]);
        });
      }

      _version = await AppManager.appVersion();

      if (AppManager.appsettings['SENSOR1'] == '1' || AppManager.appsettings['SENSOR2'] == '1' || AppManager.appsettings['SENSOR3'] == '1' || AppManager.appsettings['SENSOR5'] == '1') {
        sensorService.startWatch();
      }

      setState(() {

      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // print(state);
    // setState(() {
    //   _notification = state;
    // });
    if (state == AppLifecycleState.resumed) {
      print('resumed');
      if (AppManager.appsettings['SENSOR1'] == '1' || AppManager.appsettings['SENSOR2'] == '1' || AppManager.appsettings['SENSOR3'] == '1') {
        sensorService.startWatch();
      }

      socketservice.reconnect = true;
      socketservice.startConnectTimer();
      _startButtonCallTimer();
    } else if (state == AppLifecycleState.paused) {
      _stopButtonCallTimer();
      sensorService.stopWatch();

      socketservice.reconnect = false;
      socketservice.stopTimer();
      socketservice.disconnect();
      print('paused');
      setState(() {
        _isconnect = false;
      });
    }
  }

  @override
  void dispose() {
    print('staff dispose');
    // socketservice.delegate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _stopCheckAccountTimer() {
    print('stop check account timer');
    if (_checkAccountTimer != null) {
      print('stop check account timer');
      _checkAccountTimer!.cancel();
    }
  }

  void _startCheckAccountTimer() {
    _stopCheckAccountTimer();

    _checkAccountTimer = Timer.periodic(const Duration(seconds: 10), (Timer timer) {
      _checkAccount();
    });
  }

  Future<void> _checkAccount() async {
    var prefs = await SharedPreferences.getInstance();
    String? loginAt = prefs.getString('login_at');

    if (!mounted) {
      return;
    }

    if (loginAt == null) {
      return;
    }

    final url = '${AppDefine.baseURL}app/check_account';

    final dio = Dio();
    final data = await dio.post(
        url,
        data: FormData.fromMap({'code': AppManager.delegatorCode, 'user_id': AppManager.myId, 'type': AppManager.settings['MCSTYPE'], 'loginAt': loginAt, 'manager': AppManager.isManager ? '1' : '0'})
    ).then((response) {

      if (response.data['status'] == '1') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    // if (data == null) {
    //   _stopCheckAccountTimer();
    //
    //   await showDialog(
    //     context: context,
    //     barrierDismissible: false,
    //     builder: (BuildContext context) {
    //       return AlertDialog(
    //         title: const Text('確認'),
    //         content: Text('ログイン情報が更新されました。再度ログインをお願いします。'),
    //         actions: <Widget>[
    //           TextButton(
    //             child: const Text('OK'),
    //             onPressed: () {
    //               Navigator.of(context).pop();
    //             },
    //           ),
    //         ],
    //       );
    //     },
    //   );
    //   _logout();
    // }
    }

  Future<void> _logout() async {
    _disconnect();
    context.read<AddressStore>().clear();
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    Navigator.of(context, rootNavigator: true)
        .pushReplacement(MaterialPageRoute(builder: (context) => SignInPage()));
  }

  Future<void> initPlatformState() async {
    // RingerMode rMode = (await RealVolume.getRingerMode()) ?? RingerMode.NORMAL;
    // setState(() {
    //   ringerMode = rMode;
    // });
    // RealVolume.onRingerModeChanged.listen((event) async {
    //   setState(() {
    //     ringerMode = event;
    //   });
    //   if (Platform.isAndroid) {
    //     if (selectedStreamType == StreamType.NOTIFICATION ||
    //         selectedStreamType == StreamType.RING) {
    //       double curVol =
    //           (await RealVolume.getCurrentVol(selectedStreamType)) ?? 0;
    //       setState(() {
    //         currentVolume = curVol;
    //       });
    //     }
    //   }
    // });
    RealVolume.onVolumeChanged.listen((event) {
      onStreamTypeChanged(event.streamType);
    });
    // onStreamTypeChanged(selectedStreamType);
    if (!mounted) return;
  }

  Future<void> onStreamTypeChanged(StreamType? streamType) async {
    int minVol = (await RealVolume.getMinVol(streamType)) ?? 0;
    int maxVol = (await RealVolume.getMaxVol(streamType)) ?? 10;
    double currentVol = (await RealVolume.getCurrentVol(streamType)) ?? 0;
    // print(minVol.toString() + " " + maxVol.toString() + " " + currentVol.toString());
    if (currentVol >= 1.0) {
      await RealVolume.setVolume(currentVol - 0.05);
    }
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      // SimplePermissions.requestPermission(Permission.WriteExternalStorage);
      // var status = await Permission.storage.request();
      // print(status);
    } else if (Platform.isIOS) {
      // SimplePermissions.requestPermission(Permission.PhotoLibrary);
      // var status = await Permission.camera.request();
      // print(status);
    }
  }

  void _loadAddress() {
    SharedPreferences.getInstance().then((prefs) {
      String? addressString = prefs.getString('address');
      // print(addressString);
      if (addressString != null) {
        var addressJson = json.decode(addressString);
        context.read<AddressStore>().setAddressList(addressJson);
        // var storedAddressList = Address.fromJsonList(addressJson);

        // setState(() {
        //   addressList = storedAddressList;
        // });
      }
    });
  }

  void _stopButtonCallTimer() {
    print('stop button call timer');
    if (_buttonCallTimer != null) {
      print('stop button call timer');
      _buttonCallTimer!.cancel();
    }
  }

  void _startButtonCallTimer() {
    _stopButtonCallTimer();

    _buttonCallTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _checkButtonCall();
    });
  }

  Future<void> _checkButtonCall() async {
    var prefs = await SharedPreferences.getInstance();
    String? targetId = prefs.getString('bcId');

    if (!mounted) {
      return;
    }

    if (targetId != null) {
      prefs.remove('bcId');

      print('check button call: $targetId');
      var addressStore = context.read<AddressStore>();
      final index = addressStore.findAddress(targetId);
      if (index < 0) {
        print('check button call: $targetId not exist');
        return;
      }
      var address = addressStore.find(targetId)!;
      if (!AppManager.isAuthReceive(address)) {
        print('check button call: $targetId not auth');
        return;
      }
      if (address.call == 1) {
        print('check button call: $targetId is calling');
        return;
      }
      if (AppManager.status == AppStatus.Call ||
          AppManager.status == AppStatus.Talk ||
          AppManager.status == AppStatus.Multi ||
          AppManager.status == AppStatus.MultiToTalk) {
      } else {
        audio.stopRingtone();
        audio.buttonCall();
      }

      addressStore.setCalled(targetId, 1);
      // Ensure CALL STATUS popup reflects button-call events as well
      _openCallStatusPopup();
    }
  }

  Widget _addressCell(Address address) {
    // print("addressCell " + address.name);
    // print(address.status);

    if (_islist) {
      return _addressListCell(address);
    }

    String liveText = '';
    Uint8List bytes = Uint8List(0);
    var imageName = 'assets/images/status/dummy.png';
    if (address.call == 1) {
      imageName = 'assets/images/status/addr_call.png';
    } else if (address.called == 1) {
      imageName = 'assets/images/status/addr_called.png';
    } else if (address.supported == 1) {
      imageName = 'assets/images/status/addr_supported.png';
    }
    else if (address.status == 0 || address.status == 1) {
      imageName = 'assets/images/status/addr.png';
      if (address.userType == 'S') {
        imageName = 'assets/images/status/addr_staff.png';
      }
      if (address.sensors.isNotEmpty) {
        print("biosliv image");
        var sensorImage = SensorService.biosilverImageName(address.sensors);
        if (sensorImage.isNotEmpty) {
          imageName = sensorImage;
        }
      } else if (address.sensor.isNotEmpty) {
        // var sensorImage = SensorService.imageName(address.sensor);
        // if (sensorImage.length > 0) {
        //   imageName = sensorImage;
        // }
      } else if (address.photo.isNotEmpty) {
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
    else if (address.status == 9) {
      liveText = 'LIVE';
      if (address.liveimage.isNotEmpty) {
        bytes = base64Decode(address.liveimage);
      }
    }
    else if (address.status == -1) {
      if (address.sensors.isNotEmpty) {
        print("biosliv image");
        var sensorImage = SensorService.biosilverImageName(address.sensors);
        if (sensorImage.isNotEmpty) {
          imageName = sensorImage;
        }
      } else if (address.sensor.isNotEmpty) {
        // var sensorImage = SensorService.imageName(address.sensor);
        // if (sensorImage.length > 0) {
        //   imageName = sensorImage;
        // }
      }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color.fromARGB(255, 80, 80, 80),
          height: 29,//21 ユーザーリストの高さ 20250510
          child: Text(
            address.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,//16 ユーザーリスト名の大きさ20250510
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              _selectAddress(address);
            },
            child: Container(
              color: const Color.fromARGB(255, 30, 30, 30),
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
    );
  }

  Widget _addressListCell(Address address) {
    final Size size = MediaQuery.of(context).size;
    var textSize = 14.0;
    var textWidth = 120.0;
    var buttonHeight = 72.0;
    var buttonMinWidth = 80.0;

    if (size.width < 600) {
      textSize = 13.0;
      textWidth = 80.0;
      buttonHeight = 36.0;
      buttonMinWidth = 40.0;
    }

    var buttonWidth = buttonHeight / 3 * 4;

    var issensor1 = false;
    var issensor2 = false;
    var issensor3 = false;
    var issensor4 = false;
    if (address.userType != '5') {
      if (AppManager.appsettings['SENSOR1'] == '1') {
        issensor1 = true;
      }
      if (AppManager.appsettings['SENSOR2'] == '1') {
        issensor2 = true;
      }
      if (AppManager.appsettings['SENSOR3'] == '1') {
        issensor3 = true;
      }
      if (AppManager.appsettings['SENSOR4'] == '1') {
        issensor4 = true;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color.fromARGB(255, 30, 30, 30),
        border: Border(
          bottom: BorderSide(color: Color.fromARGB(255, 80, 80, 80)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            width: textWidth,
            child: Text(
              address.name,
              style: TextStyle(
                fontSize: textSize,
                color: Colors.white,
              ),
            ),
          ),
          Center(
            child: ButtonTheme(
              minWidth: buttonMinWidth,
              height: 30.0,
              child: ElevatedButton(
                child: Text("履歴"),
                // color: Colors.grey,
                // textColor: Colors.white,
                onPressed: () async {
                  _talkHistoryButton(address);
                },
              ),
            ),
          ),
          Container(width: 5.0),
          Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_video.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  _selectAddress(address);
                },
              )),
          Container(width: 5.0),
          issensor2
              ? Center(
            child: GestureDetector(
              child: Image.asset(
                'assets/images/service/sc_pir.png',
                width: buttonWidth,
                height: buttonHeight,
              ),
              onTap: () {
                _graphButton(address, "2");
              },
            ),
          )
              : Container(width: buttonWidth),
          Container(width: 5.0),
          issensor1
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_alert_H.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  _graphButton(address, "1");
                },
              ))
              : Container(width: buttonWidth),
          Container(width: 5.0),
          issensor3
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_flame.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  _graphButton(address, "3");
                },
              ))
              : Container(width: buttonWidth),
          issensor4
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_co2.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  _graphButton(address, "4");
                },
              ))
              : Container(width: buttonWidth),
        ],
      ),
    );
  }

  Widget _managerAddressCell(Address address) {
    final Size size = MediaQuery.of(context).size;
    if (_islist) {
      return StaffUtil.managerAddressListCell(size, address, _selectManagerAddress, _talkHistoryButton, _graphButton);
    }

    return StaffUtil.managerAddressCell(address, _selectManagerAddress);
  }

  Future<void> _selectManagerAddress(Address address) async {
    print('===============================================================${address.id}');
    if (address.userType == 'S') {
      AppManager.selectUser = address;
      await Navigator.of(context, rootNavigator: true)
          .push(
          PageRouteBuilder(
            pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
              return StaffTalkViewPage();
            },
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            fullscreenDialog: true,
          )
      );
      return;
    }

    AppManager.selectCode = address.code;
    setState(() {

    });
  }

  Widget _callStatusPopupListItem(int index) {
    var item = _callStatuses[index];
    Address address = item['address'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () {
          _selectAddress(address);
          setState(() {
            _callStatuses.clear();
          });
        },
        child: Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color.fromARGB(255, 80, 80, 80), width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(right: 10),
                width: 120,
                child: Image.asset(
                  'assets/images/status/addr_call.png',
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WidgetUtil.basicText(item['managerName'], fontSize: 18),
                    WidgetUtil.basicText(address.name, fontSize: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setAddressStatus(udid, status) {
    // print('set address status');
    if (mounted) {
      // print('set ok');
      context.read<AddressStore>().setLiveImage(udid, '');
      context.read<AddressStore>().setAddressStatus(udid, status);
    }
  }

  String _getTalkHistoryURL() {
    if (AppDefine.amiApp) {
      return "${AppDefine.baseURL}talk_history";
    }
    return "${AppDefine.baseURL}talk_history.php";
  }

  void _talkHistoryButton(Address address) {
    var cd = AppManager.delegatorCode;
    var id1 = AppManager.myId;
    var id2 = address.id;
    var name = address.name;
    var url = "${_getTalkHistoryURL()}?cd=$cd&id1=$id1&id2=$id2&na=$name";
    print(url);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return WebviewPage(title: '通話履歴', url: url);
        },
      ),
    );
  }

  void _openCallStatusPopup() {
    if (AppManager.appsettings['CALLSTATUSDISP'] != '1') {
      return;
    }
    _callStatuses.clear();
    var addressStore = context.read<AddressStore>();

    for (var i = 0; i < addressStore.addressList.length; i++) {
      var address = addressStore.addressList[i];
      // print(address);
      if (address.type == 'manager') {
        continue;
      }
      if (address.sensors.isNotEmpty) {
        var sensorImage = SensorService.biosilverImageName(address.sensors);
        if (sensorImage == 'sensor_alert_spo2.png') {
          _callStatuses.add({'address': address, 'status': 'spo2'});
          continue;
        }
      }
      // Show popup when ringing or when a button-call is active
      if (address.call == 1 || address.called == 1) {
        final managerName = addressStore.managerName(address.code);
        _callStatuses.add({'address': address, 'status': 'call', 'managerName': managerName});
      }
    }
    // print(_callStatuses);
    setState(() {

    });
  }

  Future<void> _graphButton(Address address, String sensorType) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return StaffWebPage(
            title: 'センサー',
            sensorType: sensorType,
            targetId: address.id,
            targetName: address.name,
          );
        },
      ),
    );
  }

  Future<void> _biosilverOnClose() async {
    print('_biosilverOnClose, ${AppManager.selectUser!.id}');
    var addressStore = context.read<AddressStore>();
    addressStore.setSensors(AppManager.selectUser!.id, []);
    sensorService.biosilverAlerts.remove(AppManager.selectUser!.id);
    sensorService.resetBiosilver(AppManager.selectUser!.id);

    AppManager.selectUser = null;
    biosilverPopup = null;
    setState(() {

    });
  }

  Future<void> _selectAddress(Address address) async {
    AppManager.selectUser = address;
    audio.stopButtonCall();
    _stopCheckAccountTimer();

    if (address.sensors.isNotEmpty) {
      setState(() {
        biosilverPopup = BiosilverPopupWidget(udid: address.id, alerts: address.sensors, onClose: () => {_biosilverOnClose()},);
      });
      return;
    }

    if (address.status == 9) {
      _isActive = false;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => StaffLiveViewPage()));
      _isActive = true;
      return;
    }

    await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return StaffTalkViewPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          fullscreenDialog: true,
        )
    );

    _startCheckAccountTimer();

    // TODO: implement sensorService
    sensorService.clearAlert(address.id);
    if (mounted) {
      context.read<AddressStore>().setSensor(address.id, '');
      context.read<AddressStore>().setCalled(address.id, 0);
    }
  }

  void _disconnect() {
    socketservice.stopTimer();
    socketservice.reconnect = false;
    socketservice.delegate = null;
    socketservice.disconnect();
    // print('_disconnect');
    setState(() {
      _isconnect = false;
    });
  }

  Future<void> _toSetting() async {
    _disconnect();
    context.read<AddressStore>().clear();
    _stopCheckAccountTimer();
    await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return SettingPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
    _startCheckAccountTimer();
  }

  Future<void> _toMeet() async {
    var url = 'frinursemeet://';
    if (Platform.isAndroid) {
      url += 'meet/?room=';
    }
    url += AppManager.delegatorCode;
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<void> _checkFcm() async {
    var prefs = await SharedPreferences.getInstance();
    String? targetId = prefs.getString('fmId');
    // print(addressString);

    if (targetId != null) {
      prefs.remove('fmId');
      socketservice.io.emit("call?", [targetId]);
    }
  }

  Future<void> _calledCheck(targetId) async {
    if (mounted) {
      var addressStore = context.read<AddressStore>();
      final index = addressStore.findAddress(targetId);
      if (index < 0) {
        return;
      }
      var address = addressStore.find(targetId)!;
      if (address.called == 1) {
        context.read<AddressStore>().setCalled(targetId, 0);
        // Refresh CALL STATUS popup after clearing button-call state
        _openCallStatusPopup();
        context.read<AddressStore>().setSupported(targetId, 1);
        await audio.stopButtonCall();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarBrightness: Brightness.dark,
      // statusBarColor: Colors.blue, //or set color with: Color(0xFF0000FF)
    ));
    const iconSize = 50.0;
    var connectMyId = AppManager.myId;
    if (AppManager.settings["DELEGATORCODE"] != null) {
      connectMyId = AppManager.myId.replaceAll(AppManager.settings["DELEGATORCODE"] + "_", "");
    }
    var callStatusBoxMaxHeight = MediaQuery.of(context).size.height - 80;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppManager.selectCode.isNotEmpty ? WidgetUtil.appBar(AppManager.selectCode,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(onPressed: () {
          setState(() {
            AppManager.selectCode = '';
          });
        }, icon: Icon(Icons.close))
      ) : null,
      body: SafeArea(
        child: LayoutBuilder(
            builder: (context, constraints) {
              var spanaSize = Size(51, 36);
              const gridPadding = 4.0;
              var gridSpacing = 10.0;
              var cols = int.parse(AppManager.appsettings['DISPLAYNUM']);
              if (cols != 2 && cols != 3 && cols != 5) {
                cols = 3;
              }
              var maxWidth = constraints.maxWidth;
              if (maxWidth > 500) {
                spanaSize = Size(60, 45);
              }
              var colWidth =
                  (maxWidth - (gridSpacing * (cols - 1) + gridPadding * 2)) /
                      cols;
              var colHeight = (colWidth / 3 * 2) + 20;

              if (_islist) {
                cols = 1;
                colWidth = maxWidth;
                colHeight = 50;
                gridSpacing = 0.0;
                if (maxWidth > 500) {
                  colHeight = 80;
                }
              }

              var gridRatio = colWidth / colHeight;
              var isManagerList = AppManager.isManager && AppManager.selectCode.isEmpty;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Consumer<AddressStore>(
                    builder: (context, addressStore, _) {
                      return GridView.extent(
                        maxCrossAxisExtent: colWidth,
                        padding: const EdgeInsets.only(
                          left: gridPadding,
                          right: gridPadding,
                          bottom: iconSize,
                        ),
                        mainAxisSpacing: gridSpacing,
                        crossAxisSpacing: gridSpacing,
                        childAspectRatio: gridRatio,
                        children: isManagerList ?
                        addressStore.managerList()
                            .map((data) => _managerAddressCell(data))
                            .toList() :
                        addressStore.staffList()
                            .map((data) => _addressCell(data))
                            .toList(),
                      );
                    },
                  ),
                  Positioned(
                    top: constraints.maxHeight - iconSize,
                    left: 0,
                    width: constraints.maxWidth,
                    height: iconSize,
                    // right: constraints.maxWidth,
                    child: Container(
                      color: Colors.black,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 30,
                                child: Image.asset(_isconnect
                                    ? 'assets/images/led/ledG.png'
                                    : 'assets/images/led/led2.png'),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Text(
                                  '${_isconnect ? 'ON' : 'OFF'} LINE $connectMyId',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
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
                                    foregroundColor: Colors.white, backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text("Web会議",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                  onPressed: () async {
                                    _toMeet();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8,),
                              SizedBox(
                                width: 50.0,
                                height: iconSize - 20.0,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text("表示",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),),
                                  onPressed: () async {
                                    setState(() {
                                      _islist = !_islist;
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4.0, right: 4.0, top: 8.0),
                                child: Text(
                                  'Ver. $_version',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _toSetting();
                                },
                                child: Image.asset(
                                  'assets/images/spana2.png',
                                  width: spanaSize.width,
                                  height: spanaSize.height,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (biosilverPopup != null)
                    biosilverPopup!,
                  if (_callStatuses.isNotEmpty)
                    ... [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _callStatuses.clear();
                          });
                        },
                        child: Opacity(
                          opacity: 0.5,
                          child: Container(
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 400,
                          height: 100.0 * _callStatuses.length + 48,
                          color: Colors.white,
                          constraints: BoxConstraints(
                            maxHeight: callStatusBoxMaxHeight,
                          ),
                          child: ListView.builder(
                            itemBuilder: (BuildContext context, int index) {
                              if (index == 0) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey,
                                          width: 0.5,
                                        ),
                                      )
                                    ),
                                    child: Center(child: WidgetUtil.basicText('CALL STATUS')),
                                  ),
                                );
                              }
                              return _callStatusPopupListItem(index - 1);
                            },
                            itemCount: _callStatuses.length + 1,
                          ),
                        ),
                      ),
                    ],
                ],
              );
            }
        ),
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

    if (AppManager.isManager) {
      useType = 'S';
    }

    socketservice.delegatorLogin(useType);
  }

  @override
  void onDisConnect() {
    if (mounted) {
      context.read<AddressStore>().clear();
    }
    print('onDisConnect');
    setState(() {
      _isconnect = false;
    });
  }

  @override
  void onAppMessage(data) {
    if (!_isActive) {
      return;
    }
    // print(data);
    String message = data['message'];
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        // AppManager.toast("ログイン済のアカウントです。");
        // return;
        return;
      }
      setState(() {
        _isconnect = true;
      });
      socketservice.io.emit("clients_status", [AppManager.settings['addressGroup']]);
      _checkFcm();
      // TODO: implement _checkPushSensor
      // _checkPushSensor();
    }
    else if (message == 'clients_status') {
      var statuses = data['data'];
      statuses.forEach((udid, value) {
        _setAddressStatus(udid, value['status']);
      });
    }
    else if (message == 'login') {
      if (data['info']['client']['udid'] != null) {
        var udid = data['info']['client']['udid'];
        _setAddressStatus(udid, data['info']['client']['status']);
      }
    }
    else if (message == 'status_change') {
      if (data["info"]["MYID"] != null && data["info"]["STATUS"] != null) {
        if (!mounted) {
          return;
        }
        var addressStore = context.read<AddressStore>();
        var udid = data["info"]["MYID"];
        final address = addressStore.find(udid);
        if (address != null) {
          if (address.call == 1) {
            audio.stopRingtone();
            addressStore.setCall(udid, 0);
            _openCallStatusPopup();

            if (data["info"]["STATUS"].toString() == '2') {
              addressStore.setSupported(udid, 1);
            }
          }
        }
        _setAddressStatus(data["info"]["MYID"], data["info"]["STATUS"]);
      }
    }
    else if (message == 'viewcan_image') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["udid"] == null || data["info"]["data"] == null) {
        return;
      }
      if (!mounted) {
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
    }
    else if (message == 'call') {
      if (data["info"]["udid"] == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      var addressStore = context.read<AddressStore>();
      var udid = data["info"]["udid"];
      final index = addressStore.findAddress(udid);
      if (index < 0) {
        return;
      }
      var address = context.read<AddressStore>().find(udid)!;
      if (!AppManager.isAuthReceive(address)) {
        socketservice.io.emit("call_not_auth", [address.id]);
        AppManager.toast("${address.name}から着信がありました", bgColor: Colors.blue, sec: 5);
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
            AppManager.autoReceiveId = address.id;
            _selectAddress(address);
                    }
          return;
        }
        audio.ringtone();
      }
      _openCallStatusPopup();
    }
    else if (message == 'call_cancel') {
      if (data["udid"] == null) {
        return;
      }

      bool shouldPlayButtonCall = false;

      if (mounted) {
        final addressStore = context.read<AddressStore>();
        final address = addressStore.find(data["udid"]);

        if (address != null) {
          final bool wasCallRinging = address.call == 1;
          final bool alreadyCalled = address.called == 1;
          if (!wasCallRinging && !alreadyCalled) {
            if (AppManager.status != AppStatus.Call &&
                AppManager.status != AppStatus.Talk &&
                AppManager.status != AppStatus.Multi &&
                AppManager.status != AppStatus.MultiToTalk) {
              shouldPlayButtonCall = true;
            }
          }
        }

        addressStore.setCall(data["udid"], 0);
        addressStore.setCalled(data["udid"], 1);
      }

      audio.stopRingtone();
      if (shouldPlayButtonCall) {
        audio.buttonCall();
      }
      _openCallStatusPopup();
    }
    else if (message == 'called_check') {
      if (data["TO"] == null) {
        return;
      }
      _calledCheck(data["TO"].toString());
    }
  }

  @override
  void onMessage(data) {
  }

  @override
  void onTalkMessage(data) {
  }

  @override
  void onSensorAlertsChange() {
    var addressStore = context.read<AddressStore>();
    sensorService.alerts.forEach((key, value) {
      addressStore.setSensor(key, value);
    });
    sensorService.biosilverAlerts.forEach((key, value) {
      addressStore.setSensors(key, value);
    });
  }
}
