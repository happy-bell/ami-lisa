import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:amiapp/pages/room/room_talk_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
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

import '../../services/peer_service.dart';
import '../../widgets/clock_widget.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({super.key});

  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage>
    with WidgetsBindingObserver, SocketIOServiceDelegate {
  bool _init = true;
  bool _active = true;
  bool _tapping = false;
  String _version = '1.0';
  Timer? _sleeptimer;
  Timer? _toSettingTimer;
  SocketIOService socketservice = SocketIOService();
  AudioService audio = AudioService();
  bool _isconnect = false;
  List<Address> addressList = [];
  final bool _talking = false;
  bool _isSleep = false;
  bool _isChangeBrightness = false;
  double _currentBrightness = 1.0;
  double _sleepBrightness = 0.5;
  final String _statusImage = '';
  Peer peer = Peer();
  late VideoPlayerController _videoController;
  bool _isVideoPlay = false;

  final _safetyCheckIds = [];
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    print('[DEBUG PRINT] room initState');

    AppManager.setStatusBarHidden(false);
    WidgetsBinding.instance.addObserver(this);
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;

    socketservice.delegate = this;

    Future(() {
      _videoController = VideoPlayerController.asset('assets/videos/sensor4.mp4');
      _videoController.addListener(_checkVideo);
      _brightnessSetting();
    });
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    print('room didChangeDependencies');

    if (_init) {
      _init = false;

      var load = await AppManager.loadSetting();
      if (!load) {
        _logout();
      }

      _loadAddress();
      AppManager.loadAutoReceive();

      if (AppManager.appsettings['VOLUME_CALL'] == '1') {
        _initPlatformState();
      }

      AppManager.requestPermission();
      socketservice.startConnectTimer();
      _version = await AppManager.appVersion();
    }

    if (AppManager.appsettings['SLEEP_MODE'] == '1' || AppManager.appsettings['CLOCKDISP'] == '1') {
      print('isSleep');
      setState(() {
        _isSleep = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("room life cycle state -> $state");
    // setState(() {
    //   _notification = state;
    // });
    if (state == AppLifecycleState.resumed) {
      print('resumed');
      socketservice.reconnect = true;
      socketservice.startConnectTimer();
    } else if (state == AppLifecycleState.paused) {
      // sensorService.stopWatch();
      _active = false;
      if (_sleeptimer != null) {
        _sleeptimer!.cancel();
      }

      socketservice.reconnect = false;
      socketservice.stopTimer();
      socketservice.disconnect();
      setState(() {
        _isconnect = false;
      });
    }
  }

  @override
  void dispose() {
    print('room dispose');
    // socketservice.delegate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initPeer() {
    peer = Peer();
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;
  }

  void _disposePeer() {
    peer.close();
    peer.onLocalStream = null;
    peer.onOffer = null;
    peer.onAnswer = null;
    peer.onAddRemoteStream = null;
    peer.onIceCandidate = null;
  }

  Future<void> _logout() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    Navigator.of(context, rootNavigator: true)
        .pushReplacement(MaterialPageRoute(builder: (context) => SignInPage()));
  }

  Future<void> _initPlatformState() async {
    RealVolume.onVolumeChanged.listen((event) {
      onStreamTypeChanged(event.streamType);
    });
  }

  Future<void> onStreamTypeChanged(StreamType? streamType) async {
    int minVol = (await RealVolume.getMinVol(streamType)) ?? 0;
    int maxVol = (await RealVolume.getMaxVol(streamType)) ?? 10;
    double currentVol = (await RealVolume.getCurrentVol(streamType)) ?? 0;
    print("$minVol $maxVol $currentVol");
    if (currentVol >= 1.0) {
      await RealVolume.setVolume(currentVol - 0.05);
    }
    _tap();
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

  void _disconnect() {
    socketservice.stopTimer();
    socketservice.delegate = null;
    socketservice.reconnect = false;
    socketservice.disconnect();
    setState(() {
      _isconnect = false;
    });
  }

  Future<void> _toSetting() async {
    _disconnect();
    context.read<AddressStore>().clear();
    _active = false;
    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }
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
  }

  Future<void> _tap() async {
    if (!socketservice.isConnect()) {
      AppManager.toast("接続されていません。", bgColor: Colors.blue);
      return;
    }
    if (_tapping) {
      return;
    }
    _tapping = true;
    _active = false;
    var list = context.read<AddressStore>().addressList;
    AppManager.selectUser = list[0];
    AppManager.status = AppStatus.Call;

    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }

    final talkResult = await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return RoomTalkPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
    print('[DEBUG PRINT] from roomtalk');
    audio.stopCall();
    audio.stopRingtone();
    _active = true;
    socketservice.delegate = this;
    _tapping = false;
  }

  void _showSleep() {
    _getBrightness();
    setState(() {
      _isSleep = true;
    });
    _setBrightness(_sleepBrightness);
    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }
  }

  void _hideSleep() {
    if (_isChangeBrightness) {
      _setBrightness(_currentBrightness);
    }
    setState(() {
      _isSleep = false;
    });
    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_stop", []);
      _safetyCheckIds.clear();
      peer.close();
    }

    _sleeptimer = Timer.periodic(const Duration(milliseconds: 5000), (Timer timer) {
      if (AppManager.status == AppStatus.None) {
        _showSleep();
      }
    });
  }

  Future<void> _stopVideo() async {
    if (!_isVideoPlay) {
      return;
    }
    setState(() {
      _isVideoPlay = false;
    });
    await _videoController.pause();
  }

  void _checkVideo() {
    print('checkvideo');
    if (_videoController.value.position == const Duration(seconds: 0, minutes: 0, hours: 0)) {
      print('video Started');
    }

    if (_videoController.value.position == _videoController.value.duration) {
      print('video Ended');
      _stopVideo();
    }
  }

  void _brightnessSetting() {
    _isChangeBrightness = false;
    _sleepBrightness = 0.5;
    if (AppManager.appsettings['SLEEPMODEBRIGHTNESS'] != '0') {
      _isChangeBrightness = true;
      if (AppManager.appsettings['SLEEPMODEBRIGHTNESS'] == '2') {
        _sleepBrightness = 0.2;
      }
    }
    _setBrightness(_sleepBrightness);
  }

  Future<void> _getBrightness() async {
    try {
      _currentBrightness = await ScreenBrightness().current;
    } catch (e) {
      debugPrint(e.toString());
      throw 'Failed to get brightness';
    }
  }

  Future<void> _setBrightness(double brightness) async {
    print('set brightness $brightness');
    if (!_isChangeBrightness) {
      return;
    }
    try {
      await ScreenBrightness().setScreenBrightness(brightness);
    } catch (e) {
      debugPrint(e.toString());
      throw 'Failed to set brightness';
    }
  }

  Future<void> _receive(String udid) async {
    print(DateTime.now());
    print('[DEBUG PRINT] room receive $udid');
    if (_isSleep) {
      _setBrightness(0.8);
    }
    _safetyCheckEnd();
    AppManager.selectUser = Address.fromJson({
      "id": udid,
      "name": '',
      "status": "0",
      "call": "1",
      "called": "0",
      "userType": "0",
      "photo": ""
    });
    _active = false;
    final talkResult = await Navigator.of(context, rootNavigator: true)
        .push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return RoomTalkPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );

    print('[DEBUG PRINT] from roomtalk');
    _tapping = false;
    _active = true;
    if (_isSleep) {
      _setBrightness(0.5);
    }
  }

  void _receiveSafetyCheck(String udid) {
    if (AppManager.appsettings['SLEEP_MODE'] != '1') {
      socketservice.io.emit("safety_check_error", [udid]);
      return;
    }
    if (!_isSleep) {
      socketservice.io.emit("safety_check_error", [udid]);
      return;
    }

    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_error", [udid]);
      return;
    }
    _safetyCheckIds.add(udid);
    peer.invite(udid, 'sendonly', true);
  }

  Future<void> _onAutoReceives() async {
    var response = await _requestAutoReceives();
    if (response == null) {
      return;
    }
    if (response['status'] != 'ok') {
      return;
    }
    var values = response['values'];
    var prefs = await SharedPreferences.getInstance();
    await prefs.setString('autoreceive', json.encode(values));
    AppManager.loadAutoReceive();
  }

  Future<dynamic> _requestAutoReceives() async {
    var token = AppDefine.getRMSToken();
    var url = '${AppDefine.baseURL}app/v4/auto_receives.php?delegatorCode=${AppManager.delegatorCode}&userID=${AppManager.myId}&token=' +
        token;
    print(url);
    var response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      var jsonResponse = json.decode(response.body);
      return jsonResponse;
    }
    return null;
  }

  void _receiveSafetyCheckEnd(String udid) {
    _safetyCheckEnd();
  }

  void _safetyCheckEnd() {
    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_stop", []);
    }
    _safetyCheckIds.clear();
    _disposePeer();
    _initPeer();
  }

  Future<void> _onCallButton() async {
    _safetyCheckEnd();
    _tap();
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 50.0;
    final Size size = MediaQuery.of(context).size;
    final statusImageSize = min(size.width / 2, 300.0);
    var callImageSize = min(size.width / 2, 400.0);
    var connectMyId = AppManager.myId;
    if (AppManager.settings["DELEGATORCODE"] != null) {
      connectMyId = AppManager.myId.replaceAll(AppManager.settings["DELEGATORCODE"] + "_", "");
    }
    var spanaSize = Size(45, 30);
    if (size.shortestSide > 500) {
      spanaSize = Size(60, 45);
    }
    if (size.width > size.height) {
      callImageSize = min(size.height * 0.7, 500.0);
    }
    print(MediaQuery.of(context).padding.left);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const Material(color: Colors.white),
                if (!_talking)
                  InkWell(
                    onTap: () {
                      _tap();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(AppManager.roomImageName(size)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                if (_statusImage.isNotEmpty)
                  Positioned(
                    top: size.height / 2 - (statusImageSize / 2),
                    left: size.width / 2 - (statusImageSize / 2),
                    height: statusImageSize,
                    width: statusImageSize,
                    child: Image.asset(_statusImage),
                  ),
                if (_watching)
                  Positioned(
                    top: 8,
                    left: 8,
                    height: 80,
                    child: Image.asset('assets/images/status/watching.png'),
                  ),
                Positioned(
                  top: constraints.maxHeight - MediaQuery.of(context).padding.bottom - iconSize,
                  left: 8,
                  right: max(MediaQuery.of(context).padding.right, 8),
                  height: iconSize,
                  // right: constraints.maxWidth,
                  child: Container(
                    color: Colors.transparent,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Image.asset(_isconnect
                                ? 'assets/images/led/ledG.png'
                                : 'assets/images/led/led2.png'),
                            Padding(
                              padding: const EdgeInsets.only(left: 12.0),
                              child: Text(
                                '${_isconnect ? 'ON' : 'OFF'} LINE $connectMyId',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 10.0, top: 8.0),
                              child: Text(
                                'Ver. $_version',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            GestureDetector(
                                child: Image.asset(
                                  'assets/images/spana2.png',
                                  width: spanaSize.width,
                                  height: spanaSize.height,
                                ),
                                // onPanCancel: () => _toSettingTimer?.cancel(),
                                // onPanDown: (_) => {
                                //   _toSettingTimer = Timer(Duration(seconds: 3), () {
                                //     print('pandown');
                                //     _toSetting();
                                //   })
                                // },
                                onLongPressStart: (_) {
                                  print('on long press start');
                                  _toSettingTimer = Timer(Duration(seconds: 2), () {
                                    _toSetting();
                                  });
                                },
                                onLongPressEnd: (_) {
                                  print('on long press end');
                                  _toSettingTimer?.cancel();
                                }
                              // onLongPress: () {
                              //   _toSetting();
                              // },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSleep)
                  InkWell(
                    onTap: () {
                      _hideSleep();
                    },
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: ClockWidget(),
                      ),
                    ),
                  ),
                if (_isVideoPlay)
                  InkWell(
                    onTap: () {
                      _stopVideo();
                    },
                    child: Container(
                      color: Colors.black,
                      child: VideoPlayer(_videoController),
                    ),
                  ),
              ],
            );
          }
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
      //   AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        _isconnect = true;
      });
      // ステータスと見守り状態の初期同期
      socketservice.io.emit("clients_status", [AppManager.settings['addressGroup']]);
    }
    else if (message == 'clients_status') {
      var statuses = data['data'];
      if (statuses is Map && statuses.containsKey(AppManager.myId)) {
        final mine = statuses[AppManager.myId];
        try {
          final sc = mine['safetyCheck'];
          if (sc is List && sc.isNotEmpty) {
            setState(() { _watching = true; });
          } else {
            setState(() { _watching = false; });
          }
        } catch (_) {}
      }
    }
    else if (message == 'call') {
      if (data["info"]["udid"] == null) {
        return;
      }
      final udid = data["info"]["udid"];
      _receive(udid);
    }
    else if (message == 'auto_receives') {
      _onAutoReceives();
    }
    else if (message == 'safety_check') {
      if (data["udid"] == null) {
        return;
      }
      _receiveSafetyCheck(data["udid"].toString());
    }
    else if (message == 'safety_check_end') {
      if (data["udid"] == null) {
        return;
      }
      _receiveSafetyCheckEnd(data["udid"]);
    }
    else if (message == 'watching') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"].toString() == AppManager.myId) {
        setState(() { _watching = true; });
      }
    }
    else if (message == 'watching_end') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"].toString() == AppManager.myId) {
        setState(() { _watching = false; });
      }
    }
    else if (message == 'call_button') {
      _onCallButton();
    }
  }

  @override
  void onMessage(data) {
    if (!_active) {
      return;
    }
    var id = data['id'];
    if (id == 'callResponse') {
      var response = (data["response"] ?? '');
      if (response != 'accepted') {
        return;
      }
      var to = (data["to"] ?? '');
      var sdp = (data["sdpOffer"] ?? '');
      print('callresponse $to');
      peer.receiveOffer(to, sdp);
    } else if (id == 'startCommunication') {
      var sdp = (data["sdpAnswer"] ?? '');
      var to = (data["to"] ?? '');
      peer.receiveAnswer(to, sdp);
    } else if (id == 'iceCandidate') {
      var from = data["from"];
      var candidate = data["candidate"];
      if (from == null || candidate == null) {
        return;
      }
      print('iceCandidate $from');
      peer.receiveIceCandidate(from, candidate);
    }
  }

  @override
  void onCallResponse(to, sdp) {
    if (!_active) {
      return;
    }
    peer.receiveOffer(to, sdp, 'sendonly');
  }

  @override
  void onStartCommunication(to, sdp) {
    if (!_active) {
      return;
    }
    peer.receiveAnswer(to, sdp);
  }

  @override
  void onMessageIceCandidate(from, candidate) {
    if (!_active) {
      return;
    }
    peer.receiveIceCandidate(from, candidate);
  }

  @override
  void onTalkMessage(data) {
    // TODO: implement onTalkMessage
  }

  void _onLocalStream(stream) {
    print('onlocal stream');
    peer.setAudioEnabled(false);
  }

  void _onAddRemoteStream(id, stream) {
    print('onremote stream $id');
  }

  void _onOffer(data) {
    print('onoffer');
    // print(data);

    final args = {
      "id": "incomingCallResponse",
      "callResponse": "accept",
      "sdpOffer": data['sdp'],
      "from": data['id']
    };
    socketservice.io.emit("message", [args]);
  }

  void _onAnswer(data) {
    print('onanswer');
    final args = {
      "id": "answerResponse",
      "callResponse": "accept",
      "sdpAnswer": data['sdp'],
      "from": data['id']
    };
    socketservice.io.emit("message", [args]);
  }

  void _onIceCandidate(id, candidate) {
    final args = {
      "id": "onIceCandidate",
      "to": id,
      "name": id,
      "sender": id,
      "candidate": candidate
    };
    socketservice.io.emit("message", [args]);
  }
}
