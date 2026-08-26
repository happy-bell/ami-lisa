import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/pages/setting/setting_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/peer_service.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:amiapp/widgets/clock_widget.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  _LivePageState createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with WidgetsBindingObserver, SocketIOServiceDelegate {
  bool _init = true;
  final List<String> _safetyCheckIds = [];
  String _version = '1.0';
  Peer peer = Peer();
  SocketIOService socketservice = SocketIOService();
  bool _isconnect = false;
  Timer? _timer;
  bool _capturing = false;

  final _localRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    print('live initState');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addObserver(this);
    peer.onStateChange = _onStateChange;
    peer.onLocalStream = _onLocalStream;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onAnswer = _onAnswer;
    peer.onOffer = _onOffer;
    peer.onIceCandidate = _onIceCandidate;
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('live didChangeDependencies');
    if (_init) {
      await _localRenderer.initialize();
      _init = false;
      _version = await AppManager.appVersion();
      socketservice.delegate = this;
      socketservice.delegate2 = this;
      
      var load = await AppManager.loadSetting();
      if (!load) {
        _logout();
        return;
      }
    }
    socketservice.connect();
    _open();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
  }

  void _logout() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    Navigator.of(context, rootNavigator: true)
        .pushReplacement(MaterialPageRoute(builder: (context) => SignInPage()));
  }

  void _disconnect() {
    socketservice.disconnect();
    setState(() {
      _isconnect = false;
    });
  }

  void _open() async {
    peer.localStream = await peer.createStream('sendonly', true);
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (Timer timer) {
      _capture();
    });
  }

  void _close() {
    // TODO: implement recsocket
    // if (_isrecording) {
    //   _stopRecord();
    //   _isrecording = false;
    // }
    if (_timer != null) {
      _timer!.cancel();
    }

    peer.close();
    AppManager.recordId = '';
    AppManager.recordConnectId = '';
  }

  void _capture() async {
    if (_capturing) {
      return;
    }
    _capturing = true;

    try {
      var track = peer.getVideoTrack();
      if (track != null) {
        var captured = await track.captureFrame();
        var image64 = base64Encode(captured.asUint8List());
        socketservice.io.emit("viewcan_image", [image64]);
      }
    } catch (e) {
      print(e);
    } finally {
      _capturing = false;
    }
  }

  void _toSetting() async {
    _close();
    _disconnect();
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => SettingPage()));
  }
  
  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    var smallButtonSize = 32.0;
    const iconSize = 50.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () {
                _toSetting();
              },
              child: Container(
                color: Colors.transparent,
                child: ClockWidget(),
              ),
            ),
            // _localRenderer.srcObject != null ? Positioned(
            //   bottom: 20,
            //   right: 0,
            //   height: size.height / 4,
            //   width: size.height / 4 / 3 * 2,
            //   child: RTCVideoView(
            //     _localRenderer,
            //     mirror: true,
            //     objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            //   ),
            // ) : Container(),
            Positioned(
              bottom: 0,
              left: 0,
              width: size.width,
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
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            '${_isconnect ? 'ON' : 'OFF'} LINE ${AppManager.myId}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding:
                          const EdgeInsets.only(left: 4.0, right: 4.0, top: 8.0),
                          child: Text(
                            'Ver. $_version',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /*
  socket service
   */
  void _delegatorLogin() {
    var useType = "1";

    socketservice.io.emit("login", [
      {
        "DELEGATOR": AppManager.delegatorCode,
        "MYID": AppManager.myId,
        "GROUP": AppManager.settings['group'],
        "USETYPE": useType,
        "MARKER": "0",
        "DISPSIZE": "1",
        "FIRTOKEN": '',
      }
    ]);
  }

  void _receiveSafetyCheck(String udid) {
    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_error", [udid]);
      return;
    }
    _safetyCheckIds.add(udid);
    peer.invite(udid, 'sendonly', true);
  }

  void _receiveSafetyCheckEnd(String udid) {
    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_stop", []);
      peer.closeOne(_safetyCheckIds[0]);
    }
    _safetyCheckIds.clear();
  }

  @override
  void onConnect() {
    _delegatorLogin();
  }

  @override
  void onAppMessage(data) {
    String message = data['message'];
    print('live app message $message');
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        _isconnect = true;
      });
    }
    else if (message == 'live_check') {
      if (data["udid"] == null) {
        return;
      }
      _receiveSafetyCheck(data["udid"].toString());
    }
    else if (message == 'live_check_end') {
      if (data["udid"] == null) {
        return;
      }
      var udid = data["udid"];
      _receiveSafetyCheckEnd(udid);
    }
  }

  @override
  void onDisConnect() {
    setState(() {
      _isconnect = false;
    });
  }

  // @override
  void _onMessage(data) {
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
  void onMessage(data) {
    var id = data['id'];
  }

  @override
  void onCallResponse(to, sdp) {
    peer.receiveOffer(to, sdp, 'sendonly');
  }

  @override
  void onStartCommunication(to, sdp) {
    peer.receiveAnswer(to, sdp);
  }

  @override
  void onMessageIceCandidate(from, candidate) {
    peer.receiveIceCandidate(from, candidate);
  }

  @override
  void onTalkMessage(data) {
    // TODO: implement onTalkMessage
  }

  /*
  peer service
   */

  void _onStateChange(id, state) {
    // if (id == AppManager.recordConnectId &&
    //     state == RTCSignalingState.RTCSignalingStateStable) {
    //   recsocket.send({"id": "startRecording", "cd": AppManager.delegatorCode, "myid": AppManager.myId, "filename": AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss")});
    // }
  }

  void _onLocalStream(stream) {
    print('onlocal stream');
    peer.setAudioEnabled(false);
    setState(() {
      _localRenderer.srcObject = stream;
    });
  }

  void _onAddRemoteStream(id, stream) {
    print('onremote stream $id');
  }

  void _onOffer(data) {
    print('onoffer');
    print(data['id']);
    if (data['id'] == AppManager.recordConnectId) {
      final sendData = {
        "id": "receiveVideoFrom",
        "sdpOffer": data['sdp'],
        "sender": data['id']
      };
      // TODO: implement recsocket
      // recsocket.send(sendData);
      return;
    }

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
    if (id == AppManager.recordConnectId) {
      print('rec icecandidate');
      // TODO: implement recsocket
      // recsocket.send(args);
      return;
    }
    socketservice.io.emit("message", [args]);
  }
}