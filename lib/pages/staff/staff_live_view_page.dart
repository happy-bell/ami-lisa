import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:amiapp/services/peer_service.dart';

class StaffLiveViewPage extends StatefulWidget {
  const StaffLiveViewPage({super.key});

  @override
  _StaffLiveViewPageState createState() => _StaffLiveViewPageState();
}

class _StaffLiveViewPageState extends State<StaffLiveViewPage>
    with SocketIOServiceDelegate {
  bool _init = true;
  Peer peer = Peer();
  final _remoteRenderer = RTCVideoRenderer();
  SocketIOService socketservice = SocketIOService();

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('stafflive initState');
    socketservice.delegate2 = this;
    // socketservice.delegate2 = this;
    peer.onStateChange = _onStateChange;
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;
    initRenderers();

    AppManager.isMute = false;
    AppManager.isVideoMute = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('stafflive didChangeDependencies');

    if (_init) {
      _init = false;
      AppManager.setStatusBarHidden(false);

      // socketservice.connect();
      _liveCheckStart();
    }
  }

  @override
  void deactivate() {
    print('stafflive deactivate');
    // WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
    socketservice.delegate2 = null;
    // socketservice.delegate = null;
    AppManager.setStatusBarHidden(true);
  }

  @override
  void dispose() {
    print('stafflive dispose');
    // WidgetsBinding.instance.removeObserver(this);
    _remoteRenderer.dispose();
    super.dispose();
  }

  void initRenderers() async {
    await _remoteRenderer.initialize();
  }

  void _liveCheckStart() {
    socketservice.io.emit('live_check', [AppManager.selectUser!.id]);
  }

  void _liveCheckEnd() {
    socketservice.io.emit('live_check_end', [AppManager.selectUser!.id]);
  }

  void _close() {
    _liveCheckEnd();
    peer.close();
    AppManager.selectUser = null;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            height: size.height,
            width: size.width,
            child: RTCVideoView(
              _remoteRenderer,
              mirror: false,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          Positioned(
            top: 20.0,
            left: 20.0,
            height: 50.0,
            width: size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('LIVE', style: TextStyle(color: Colors.red,),),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MaterialButton(
                      onPressed: () {
                        _close();
                      },
                      color: Colors.red,
                      textColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                      shape: const CircleBorder(),
                      child: const Icon(
                        Icons.clear,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void onAppMessage(data) {
    // TODO: implement onAppMessage
    String message = data['message'];
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        // _isconnect = true;
      });
      _liveCheckStart();
    }
    else if (message == 'status_change') {
      if (data["info"]["MYID"] != null && data["info"]["STATUS"] != null) {
        if (data["info"]["MYID"] == AppManager.selectUser!.id) {
          _close();
        }
      }
    }
  }

  @override
  void onMessage(data) {
    var id = data['id'];
  }

  @override
  void onCallResponse(to, sdp) {
    peer.receiveOffer(to, sdp, 'recvonly');
  }

  @override
  void onStartCommunication(to, sdp) {
    peer.receiveAnswer(to, sdp);
  }

  @override
  void onMessageIceCandidate(from, candidate) {
    // print('iceCandidate $from');
    peer.receiveIceCandidate(from, candidate);
  }

  @override
  void onTalkMessage(data) {
    // TODO: implement onTalkMessage
  }

  @override
  void onConnect() {

  }

  @override
  void onDisConnect() {
    // TODO: implement onDisConnect
  }

  void _onStateChange(id, state) {}

  void _onLocalStream(stream) {
    print('onlocal stream');
  }

  void _onAddRemoteStream(id, stream) {
    print('onremote stream $id');
    if (id == AppManager.selectUser!.id) {
      print('remoterenderer stream set');
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
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
