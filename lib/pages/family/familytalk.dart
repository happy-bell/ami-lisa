import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../appdefine.dart';
import '../../services/appmanager.dart';
import '../../services/audio_service.dart';
import '../../services/peer_service.dart';
import '../../services/socket_io_service.dart';

class FamilyTalkPage extends StatefulWidget {
  @override
  _FamilyTalkPageState createState() => _FamilyTalkPageState();
}

class _FamilyTalkPageState extends State<FamilyTalkPage> with SocketIOServiceDelegate {
  bool _init = true;
  Peer peer = Peer();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  SocketIOService socketservice = SocketIOService();
  AudioService audio = AudioService();

  String _statusImage = '';
  bool _talking = false;

  bool isconnect = true;
  bool isrecording = false;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('familytalk initState');
    socketservice.delegate2 = this;
    peer.onStateChange = _onStateChange;
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;
    initRenderers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('family didChangeDependencies');

    if (_init) {
      _init = false;
      AppManager.setStatusBarHidden(false);

      print('発信中 ' + AppManager.selectUser!.id);
      _call();
    }
  }

  @override
  void deactivate() {
    print('family deactivate');
    // WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    print('family dispose');
    // WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _call() async {
    _statusImage = ImageName.connecting;
    _setAppStatus(AppStatus.Call);
    await audio.call();
    socketservice.io.emit("call", [AppManager.selectUser!.id]);
  }

  void _startTalk() {
    _statusImage = '';
    _setAppStatus(AppStatus.Talk);
    audio.stopCall();
  }

  void _notConnect(String connectStatus) {
    _statusImage = '';
    _setAppStatus(AppStatus.None);
    if (connectStatus == '1') {
      AppManager.toast("呼び出し先が不在です", bgColor: Colors.blue);
    } else {
      AppManager.toast("通話中です", bgColor: Colors.blue);
    }
    audio.stopCall();
    _close();
  }

  void _callRejected() {
    _statusImage = '';
    _setAppStatus(AppStatus.None);
    AppManager.toast("切断されました", bgColor: Colors.blue);
    audio.stopCall();
    _close();
  }

  void _receiveHangup(String from) {
    AppStatus newStatus = AppStatus.None;

    if (AppManager.talkId1 == from) {
      AppManager.talkId1 = "";
      _setAppStatus(newStatus);
      _endTalk();
    }

  }

  void _callEndButton() {
    if (!socketservice.connected) {
      audio.stopCall();
      audio.stopRingtone();
      _close();
      return;
    }

    if (AppManager.status == AppStatus.Call) {
      _cancelcall();
    } else {
      if (AppManager.status == AppStatus.Multi) {
        var sendData = {
          "id2": "threewayToCall",
          "from": AppManager.talkId1,
          "to": AppManager.talkId2
        };
        socketservice.io.emit("talk", [sendData]);
      }
      _hangup();
    }
  }

  void _cancelcall() {
    _setAppStatus(AppStatus.None);
    socketservice.io.emit("call_cancel", [AppManager.selectUser!.id]);
    audio.stopCall();
    _close();
  }

  void _endTalk() {
    // recording 終了

    peer.close();
    _close();
  }

  void _close() {
    AppManager.selectUser = null;
    Navigator.of(context).pop();
  }

  void _hangup() {
    if (AppManager.holdId == AppManager.selectUser!.id) {
      // 保留中は通話終了
      AppManager.holdId = '';
      socketservice.io.emit("hold_end", [AppManager.selectUser!.id]);
    } else if (AppManager.holdedId == AppManager.talkId1) {
      // 保留中は通話終了
      AppManager.holdedId = '';
      socketservice.io.emit("holded_end", [AppManager.talkId1]);
    } else if (_talking) {
      // 通話中は通話終了
      socketservice.io.emit("hangup", []);
    }

    AppManager.talkId1 = '';
    AppManager.talkId2 = '';

    var newStatus = AppStatus.None;
    _setAppStatus(newStatus);

    _endTalk();
  }

  void _changeCamera() {
    peer.switchCamera();
  }

  void _setAppStatus(newstatus) {
    AppManager.status = newstatus;

    bool talking = false;

    if (newstatus == AppStatus.Talk ||
        newstatus == AppStatus.Multi ||
        newstatus == AppStatus.MultiToTalk) {
      talking = true;
    }

    setState(() {
      _talking = talking;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    var smallButtonSize = 32.0;
    var button1Width = 110.0;
    if (size.width <= 320) {
      button1Width = 80;
    }
    var button1Height = button1Width / 335 * 182;
    var statusImageSize = min(size.width / 2, 300.0);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Material(color: Colors.black),
          Positioned(
            top: 0,
            left: 0,
            height: size.height,
            width: size.width,
            child: RTCVideoView(_remoteRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
          ),
          Positioned(
            bottom: 20,
            right: 0,
            height: size.height / 4,
            width: size.height / 4 / 3 * 2,
            child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
          ),
          (_talking
              ? Positioned(
            top: 40,
            left: 0,
            width: size.width,
            height: 60,
            // right: constraints.maxWidth,
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      _changeCamera();
                    },
                    child: SizedBox(
                      width: smallButtonSize,
                      height: smallButtonSize,
                      child: Image.asset("assets/images/talk/btn-change_my_camera.png"),
                    ),
                  ),
                ],
              ),
            ),
          )
              : Container()),
          Positioned(
            bottom: 16.0,
            left: 0,
            width: size.width,
            child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
              GestureDetector(
                onTap: () {
                  _callEndButton();
                },
                child: SizedBox(
                  width: button1Width,
                  height: button1Height,
                  child: Image.asset("assets/images/talk/btn-callend.png"),
                ),
              ),
            ]),
          ),
          (_statusImage == ''
              ? Container()
              : Positioned(
            top: size.height / 2 - (statusImageSize / 2),
            left: size.width / 2 - (statusImageSize / 2),
            height: statusImageSize,
            width: statusImageSize,
            child: Image.asset(_statusImage),
          )),
        ],
      ),
    );
  }

  @override
  void onAppMessage(data) {
    String message = data['message'];
    print('familytalk app message $message');
    if (message == 'call_accept') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"] == AppManager.selectUser!.id) {}
    } else if (message == 'not_connect') {
      if (data["info"] == null) {
        return;
      }
      _notConnect(data["info"]);
    } else if (message == 'call_reject') {
      if (data["udid"] == null) {
        return;
      }
      _callRejected();
    } else if (message == 'talk_end') {
      if (data["udid"] == null) {
        return;
      }
      _receiveHangup(data["udid"]);
    }
  }

  @override
  void onTalkMessage(data) {

  }

  @override
  void onMessage(data) {
    var id = data['id'];
    if (id == 'callResponse') {
      var response = (data["response"] == null ? '' : data["response"]);
      if (response != 'accepted') {
        return;
      }
      var to = (data["to"] == null ? '' : data["to"]);
      var sdp = (data["sdpOffer"] == null ? '' : data["sdpOffer"]);
      print('callresponse $to');
      _onCallResponse(to, sdp);
    } else if (id == 'startCommunication') {
      var sdp = (data["sdpAnswer"] == null ? '' : data["sdpAnswer"]);
      var to = (data["to"] == null ? '' : data["to"]);
      _onStartCommunication(to, sdp);
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
    if (to != AppManager.safetyCheckId) {
      AppManager.talkId1 = AppManager.selectUser!.id;
    }
    peer.receiveOffer(to, sdp);
  }

  @override
  void onStartCommunication(to, sdp) {
    peer.receiveAnswer(to, sdp);

    _startTalk();
  }

  @override
  void onMessageIceCandidate(from, candidate) {
    print('iceCandidate $from');
    peer.receiveIceCandidate(from, candidate);
  }

  void _onCallResponse(to, sdp) {
    AppManager.talkId1 = to;
    peer.receiveOffer(to, sdp);
  }

  void _onStartCommunication(to, sdp) {
    peer.receiveAnswer(to, sdp);
    _startTalk();
  }

  @override
  void onConnect() {
    setState(() => isconnect = true);
  }

  @override
  void onDisConnect() {
    setState(() => isconnect = false);
  }

  void _onStateChange(id, state) {
    if (id == AppManager.recordConnectId && state == RTCSignalingState.RTCSignalingStateStable) {
      // recsocket.send({"id": "startRecording"});
    }
  }

  void _onLocalStream(stream) {
    print('onlocal stream');
    _localRenderer.srcObject = stream;
  }

  void _onAddRemoteStream(id, stream) {
    print('onremote stream $id ' + AppManager.talkId1 + ', ' + AppManager.talkId2);
    if (id == AppManager.talkId1) {
      _remoteRenderer.srcObject = stream;
    }
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
    _startTalk();
  }

  void _onIceCandidate(id, candidate) {
    final args = {
      "id": "onIceCandidate",
      "to": id,
      "name": id,
      "candidate": candidate
    };
    socketservice.io.emit("message", [args]);
  }
}
