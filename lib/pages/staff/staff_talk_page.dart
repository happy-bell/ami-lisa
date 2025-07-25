import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:amiapp/pages/staff/staff_album_web_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:amiapp/pages/staff/staff_web_page.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:amiapp/services/peer_service.dart';
import 'package:amiapp/widgets/staff_talk_menu_widget.dart';

import '../../helpers/paint_helper.dart';
import '../../helpers/widget_util.dart';
import '../../services/socket_service.dart';
import '../../widgets/sensor_view_widget.dart';

class StaffTalkViewPage extends StatefulWidget {
  const StaffTalkViewPage({super.key});

  @override
  StaffTalkViewPageState createState() => StaffTalkViewPageState();
}

class StaffTalkViewPageState extends State<StaffTalkViewPage>
    with SocketIOServiceDelegate, SocketServiceDelegate, PaintControllerDelegate {
  bool _init = true;
  Peer peer = Peer();
  late Address _address;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _remote2Renderer = RTCVideoRenderer();
  bool _hasRemoteVideo = false;
  bool _hasRemote2Video = false;
  final double _remoteMargin = 0;
  bool _minimiseLocalRenderer = false;
  SocketIOService socketservice = SocketIOService();
  SocketService? socketioservice;
  AudioService audio = AudioService();
  bool _talking = false;
  Timer? _rusuTimer;
  String _statusImage = '';
  bool _isrecording = false;

  /// 通話中着信対応
  String _callingId = '';
  String _callingName = '';
  AnimationController? _blinkAnimationController;
  /// 画像共有
  ui.Image? _shareImage;
  bool _drawing = false;
  double _localCanvasWidth = 0;
  double _localCanvasHeight = 0;
  double _remoteCanvasWidth = 0;
  double _remoteCanvasHeight = 0;
  final PaintController _controller = PaintController();
  bool _drawClearMode = false;

  GlobalKey<StaffTalkMenuWidgetState> menuWidgetGlobalKey = GlobalKey();

  GlobalKey<SensorViewWidgetState> sensorWidgetGlobalKey = GlobalKey();
  bool _sensorViewIsHidden = true;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('stafftalk initState');
    // socketservice.delegate = this;
    socketservice.delegate2 = this;
    _controller.delegate = this;
    peer.onStateChange = _onStateChange;
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;
    _initRenderers();

    AppManager.isMute = false;
    AppManager.isVideoMute = false;

    Future(() async {
      var statusImage = '';
      var address = context.read<AddressStore>().find(AppManager.selectUser!.id);
      if (address != null) {
        _address = address;
        if (_address.id == AppManager.autoReceiveId) {
          AppManager.autoReceiveId = '';
          _response();
          return;
        }
        if (address.call == 1) {
          statusImage = 'assets/images/status/addr_call.png';
        } else if (address.called == 1) {
          statusImage = 'assets/images/status/addr_called.png';
          socketservice.io.emit("called_check", [AppManager.selectUser!.id]);
        } else if (address.supported == 1) {
          statusImage = 'assets/images/status/addr_supported.png';
        }
        if (statusImage.isNotEmpty) {
          setState(() {
            _statusImage = statusImage;
          });
        }
        context.read<AddressStore>().setSupported(AppManager.selectUser!.id, 0);

        // if (true) {
        //   // 3者通話テスト
        //   AppManager.threewayId = 'room22222';
        //   _statusImage = '';
        //   setAppStatus(AppStatus.Multi);
        //   await Future.delayed(const Duration(seconds: 1));
        //   _connectRoom();
        // }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('stafftalk didChangeDependencies');

    if (_init) {
      _init = false;
      AppManager.setStatusBarHidden(false);

      var address = context.read<AddressStore>().find(AppManager.selectUser!.id);
      if (address == null) {
        _close();
      }
    }
  }

  @override
  void deactivate() {
    print('stafftalk deactivate');
    // WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
    socketservice.delegate2 = null;
    // socketservice.delegate = null;
    AppManager.setStatusBarHidden(true);
  }

  @override
  void dispose() {
    print('stafftalk dispose');
    // WidgetsBinding.instance.removeObserver(this);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _remote2Renderer.dispose();
    _blinkAnimationController?.dispose();
    _stopRusuTimer();
    super.dispose();
  }

  void _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _remote2Renderer.initialize();
  }

  void setAppStatus(newstatus) {
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

    menuWidgetGlobalKey.currentState?.setState(() {});
  }

  void _close() {
    if (AppManager.status == AppStatus.Call ||
        AppManager.status == AppStatus.Talk ||
        AppManager.status == AppStatus.Multi ||
        AppManager.status == AppStatus.Holded ||
        AppManager.status == AppStatus.MultiToTalk) {
      return;
    }
    var selectUserId = '';
    if (AppManager.selectUser != null) {
      selectUserId = AppManager.selectUser!.id;
    }
    if (AppManager.safetyCheckId == selectUserId) {
      return;
    }
    audio.stopButtonCall();
    if (_isrecording) {
      if (socketioservice?.tag == 4) {
        socketioservice?.disconnect();
      }
      // recsocket.close();
    }

    context.read<AddressStore>().setSensor(selectUserId, '');
    context.read<AddressStore>().setCalled(selectUserId, 0);

    AppManager.selectUser = null;
    Navigator.of(context).pop();
  }

  /// *******************************************************************************************
  /// call talk button
  /// *******************************************************************************************
  void callButton() {
    var addressStore = context.read<AddressStore>();
    addressStore.setCalled(AppManager.selectUser!.id, 0);

    if (AppManager.holdId == AppManager.selectUser!.id) {
      return;
    }

    if (AppManager.status == AppStatus.Call ||
        AppManager.status == AppStatus.Talk ||
        AppManager.status == AppStatus.Multi ||
        AppManager.status == AppStatus.Holded ||
        AppManager.status == AppStatus.MultiToTalk) {
      return;
    }

    if (_address.call == 1) {
      _response();
    } else {
      _call();
    }
  }

  void callEndButton() {
    if (AppManager.status == AppStatus.Call) {
      _cancelcall();
    } else if (_address.call == 1) {
      _rejectCall();
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

  /// *******************************************************************************************
  /// call talk
  /// *******************************************************************************************
  Future<void> _call() async {
    _statusImage = 'assets/images/talk/connecting.png';
    setAppStatus(AppStatus.Call);
    await audio.call();
    socketservice.io.emit("call", [AppManager.selectUser!.id]);

    print("call to ${AppManager.selectUser!.id}");

    _rusuTimer = Timer.periodic(Duration(milliseconds: AppDefine.absenceSec1), (Timer timer) {
      _cancelcall();
      setState(() {
        _statusImage = ImageName.rusu;
      });

      _rusuTimer = Timer.periodic(Duration(milliseconds: AppDefine.absenceSec2), (Timer timer) {
        _close();
      });
    });
  }

  void _response() {
    audio.stopRingtone();
    _statusImage = '';
    setAppStatus(AppStatus.Response);
    AppManager.talkId1 = AppManager.selectUser!.id;
    peer.invite(AppManager.selectUser!.id, 'video', true); // => _onOffer
  }

  void _stopRusuTimer() {
    if (_rusuTimer != null) {
      _rusuTimer!.cancel();
    }
  }

  void _startTalk() {
    _stopRusuTimer();
    // AppManager.talkId1 = AppManager.selectUser.id;
    _statusImage = '';
    context.read<AddressStore>().setCall(AppManager.selectUser!.id, 0);
    context.read<AddressStore>().setCalled(AppManager.selectUser!.id, 0);
    setAppStatus(AppStatus.Talk);
    audio.stopCall();
    // 通話開始時に必ず着信音を停止（デフォルト着信音対応）
    audio.stopRingtone();
    // _onTalking();
  }

  void _cancelcall() {
    _stopRusuTimer();
    audio.stopCall();
    setState(() {
      _statusImage = '';
    });
    setAppStatus(AppStatus.None);
    socketservice.io.emit("call_cancel", [AppManager.selectUser!.id]);
  }

  void _rejectCall() {
    _statusImage = '';
    socketservice.io.emit("call_reject", [_address.id]);
    context.read<AddressStore>().setCall(_address.id, 0);
    setAppStatus(AppManager.status);
    audio.stopRingtone();
  }

  void _hangup() {
    if (AppManager.holdId == _address.id) {
      // 保留中は通話終了
      AppManager.holdId = '';
      socketservice.io.emit("hold_end", [_address.id]);
    } else if (AppManager.holdedId == _address.id) {
      // 保留中は通話終了
      AppManager.holdedId = '';
      socketservice.io.emit("holded_end", [_address.id]);
    } else if (_talking) {
      // 通話中は通話終了
      socketservice.io.emit("hangup", []);
    }

    if (AppManager.status == AppStatus.Multi) {
      if (socketioservice != null) {
        socketioservice!.roomDelegate = null;
        socketioservice!.disconnect();
      }
      // if (roomsocket != null) {
      //   roomsocket.close();
      // }
    }

    AppManager.talkId1 = '';
    AppManager.talkId2 = '';

    var newStatus = AppStatus.None;
    if (AppManager.holdId.isNotEmpty) {
      newStatus = AppStatus.Hold;
    }
    setAppStatus(newStatus);

    _endTalk();
  }

  void _endTalk() {
    setState(() {
      _hasRemoteVideo = false;
      _hasRemote2Video = false;
    });
    // recording 終了

    peer.close();
    _close();
  }

  void _notConnect(String connectStatus) {
    _statusImage = '';
    setAppStatus(AppStatus.None);
    if (connectStatus == '1') {
      AppManager.toast("呼び出し先が不在です", bgColor: Colors.blue);
    } else {
      AppManager.toast("通話中です", bgColor: Colors.blue);
    }
    _stopRusuTimer();
    audio.stopCall();
  }

  void _callRejected() {
    audio.stopCall();
    _stopRusuTimer();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    AppManager.toast("切断されました", bgColor: Colors.blue);
  }

  void _callNotAuth() {
    audio.stopCall();
    _stopRusuTimer();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    WidgetUtil.showAutoDisposeDialog(context, '通話許可がありません　通知しました');
  }

  void _receiveHangup(String from) {
    print("****************     receiveHangup: $from   talkId1 = ${AppManager.talkId1}   ********************************");
    AppStatus newStatus = AppStatus.None;

    if (AppManager.holdId == from) {
      // 保留相手から切断
      AppManager.holdId = "";
      if (AppManager.selectUser!.id == from) {
        // 保留相手選択中は通話終了処理
        _endTalk();
        setAppStatus(newStatus);
        return;
      }
      if (AppManager.talkId1.isEmpty) {
        // 通話相手なし
      }
    } else if (AppManager.holdedId == from) {
      // 保留された相手から切断
      AppManager.holdedId = "";
      AppManager.talkId1 = "";
      setAppStatus(newStatus);
      _endTalk();
      return;
    } else if (AppManager.talkId1 == from) {
      if (AppManager.talkId2.isNotEmpty) {
        // 三者通話中
      } else {
        // 通話終了
        AppManager.talkId1 = "";
        if (AppManager.holdId.isNotEmpty) {
          newStatus = AppStatus.Hold;
        }
        setAppStatus(newStatus);
        _endTalk();
        return;
      }
    } else if (AppManager.talkId2 == from) {
      // 三者通話中
    }
  }

  /// *******************************************************************************************
  /// record
  /// *******************************************************************************************
  Future<void> _recordButton() async {
    if (_isrecording) {
      _recordEnd();
      return;
    }

    var result = await WidgetUtil.showSimpleConfirmDialog(context, '録画を開始しますか？');
    if (result) {
      _requestRecord();
    }
  }

  Future<void> _recordEnd() async {
    var result = await WidgetUtil.showSimpleConfirmDialog(context, '録画を終了しますか？');
    if (result) {
      socketservice.io.emit("record_stop", [
        {"to": AppManager.talkId1, "recid": AppManager.recordId}
      ]);
      _onRecordEnd({});
    }
  }

  void _requestRecord() {
    var recId = '${AppManager.myId}_${AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss")}';
    var sendData = {'recid': recId, 'to': AppManager.talkId1};
    socketservice.io.emit("request_record", [sendData]);
    AppManager.recordId = '${recId}_1';
  }

  Future<void> _requestedRecord(String udid, String recid) async {
    var sendData = {'recid': recid, 'to': AppManager.talkId1};
    socketservice.io.emit("request_record_accept", [sendData]);
    AppManager.recordId = '${recid}_2';
    _startRecord();

    // var value = await showDialog(
    //   context: context,
    //   builder: (BuildContext context) => new AlertDialog(
    //     title: new Text('確認'),
    //     content: new Text('録画を開始してもよろしいですか？'),
    //     actions: <Widget>[
    //       new SimpleDialogOption(
    //         child: new Text('はい'),
    //         onPressed: () {
    //           Navigator.pop(context, Answers.YES);
    //         },
    //       ),
    //       new SimpleDialogOption(
    //         child: new Text('いいえ'),
    //         onPressed: () {
    //           Navigator.pop(context, Answers.NO);
    //         },
    //       ),
    //     ],
    //   ),
    // );
    // switch (value) {
    //   case Answers.YES:
    //     AppManager.recordId = recid;
    //     var sendData = {'recid': AppManager.recordId, 'to': AppManager.talkId1};
    //     socketservice.io.emit("request_record_accept", [sendData]);
    //     AppManager.recordId = AppManager.recordId + '_2';
    //     _startRecord();
    //     break;
    //   case Answers.NO:
    //     socketservice.io.emit("request_record_reject", [AppManager.talkId1]);
    //     break;
    // }
  }

  void _startRecord() {
    if (_isrecording) {
      return;
    }
    print('start record');
    if (AppManager.recordId.isEmpty) {
      var recId = '${AppManager.myId}_${AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss")}';
      AppManager.recordId = '${recId}_1';
    }
    //self.recordConnectId = "REC_" + Date().toString("yyyyMMddHHmmss") + "_" + appManager.delegatorCode + "_" + appManager.myId
    AppManager.recordConnectId = 'REC_${AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss")}_${AppManager.delegatorCode}_${AppManager.myId}';
    setState(() {
      _isrecording = true;
    });

    var url = AppManager.settings['MEDIASERVER4'];
    print(url.substring(0, 2));
    if (url.substring(0, 2) == 'ws') {
      // recsocket.type = 'record';
      // recsocket.delegate = this;
      // recsocket.connect(url);
    } else {
      _connectRecRoom();
    }

  }

  void _connectRecRoom() {
    print('connect rec:' + AppManager.settings['MEDIASERVER4']);
    // print(url.substring(0, 2));
    socketioservice = SocketService();
    socketioservice!.url = AppManager.settings['MEDIASERVER4'];
    socketioservice!.roomDelegate = this;
    socketioservice!.tag = 4;
    socketioservice!.connect();
  }

  void _joinRecRoom() {
    print('joinRecRoom');
    var sendData = {
      "id": "joinRoom",
      "room": AppManager.recordId,
      "name": AppManager.recordConnectId,
      "code": AppManager.delegatorCode,
      "baseurl": AppDefine.baseURL
    };
    if (socketioservice?.tag == 4) {
      socketioservice!.io.emit("message", [sendData]);
      return;
    }
    // recsocket.send(sendData);
  }

  void _onJoinRoomResponse(message) {
    var response = '';
    if (message["response"] != null) {
      response = message["response"];
    }
    if (response != "accepted") {
      AppManager.toast("録画を開始できませんでした", gravity: ToastGravity.CENTER);
      _onErrorStartRecord();
      return;
    }
    peer.invite(AppManager.recordConnectId, 'sendonly', true);
  }

  void _onRecordResponse(message) {
    var response = '';
    if (message["response"] != null) {
      response = message["response"];
    }
    if (message["name"] == null || message["sdpAnswer"] == null) {
      response = '';
    }

    if (response != "started") {
      AppManager.toast("録画を開始できませんでした", gravity: ToastGravity.CENTER);
      peer.closeOne(AppManager.recordConnectId);
      socketservice.io.emit("request_record_reject", [AppManager.talkId1]);
      socketservice.io.emit("record_stop", [
        {"to": AppManager.talkId1, "recid": AppManager.recordId}
      ]);
      _onErrorStartRecord();
      return;
    }
    peer.receiveAnswer(message["name"], message["sdpAnswer"]);
  }

  void _onRecordEnd(message) {
    peer.closeOne(AppManager.recordConnectId);
    _onErrorStartRecord();
  }

  void _onErrorStartRecord() {
    setState(() {
      _isrecording = false;
    });
    if (socketioservice?.tag == 4) {
      socketioservice?.disconnect();
      return;
    }
    // recsocket.close();
  }

  /// *******************************************************************************************
  /// threeway
  /// *******************************************************************************************
  void addCallButton() {
    if (AppManager.status == AppStatus.Hold) {
      _close();
    }
  }

  void threewayButton() {
    var isEnableThreeway = true;

    if (AppManager.status != AppStatus.Talk) {
      isEnableThreeway = false;
    }
    if (AppManager.holdId.isEmpty) {
      isEnableThreeway = false;
    }

    if (!isEnableThreeway) {
      AppManager.toast("三者通話できる相手がいません", gravity: ToastGravity.CENTER);
      return;
    }

    AppManager.talkId2 = AppManager.holdId;
    AppManager.holdId = '';

    AppManager.threewayId = AppManager.delegatorCode +
        AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss");
    socketservice.io.emit("threeway_call", [
      {
        "talkID1": AppManager.talkId1,
        "talkID2": AppManager.talkId2,
        "roomId": AppManager.threewayId
      }
    ]);
  }

  void _recvThreeway(String talkId1, String talkId2, String roomId) async {
    print('recv threeway $talkId1 , $talkId2 , $roomId');
    print(AppManager.talkId1);
    print(AppManager.holdedId);
    if (AppManager.status == AppStatus.Holded) {
      if (AppManager.holdedId == talkId1 || AppManager.holdedId == talkId2) {
        AppManager.talkId1 = talkId1;
        AppManager.talkId2 = talkId2;
        AppManager.holdedId = '';
        AppManager.threewayId = roomId;

        _statusImage = '';
        setAppStatus(AppStatus.Multi);
        _connectRoom();
      }
    } else if (AppManager.status == AppStatus.Talk) {
      if (AppManager.talkId1 == talkId1) {
        AppManager.talkId2 = talkId2;
      } else if (AppManager.talkId1 == talkId2) {
        AppManager.talkId2 = talkId1;
      }
      peer.closeOne(AppManager.talkId1);
      AppManager.threewayId = roomId;
      _statusImage = '';
      setAppStatus(AppStatus.Multi);
      await Future.delayed(const Duration(seconds: 1));
      _connectRoom();
    }
  }

  void _threewayToCall(String from, String to) async {
    print("_threewayToCall from:$from to:$to, status:${AppManager.status}");

    if (AppManager.status == AppStatus.Multi && (AppManager.myId == from || AppManager.myId == to)) {
      if (socketioservice != null) {
        socketioservice!.roomDelegate = null;
        socketioservice?.disconnect();
      }
      AppManager.talkId2 = '';
      _hasRemote2Video = false;
      if (AppManager.myId == from) {
        print("_threewayToCall myId = from");
        AppManager.talkId1 = to;
        setAppStatus(AppStatus.MultiToTalk);
        await Future.delayed(const Duration(milliseconds: 500));
        peer.invite(to, 'video', true);
      } else if (AppManager.myId == to) {
        print("_threewayToCall myId = to");
        AppManager.talkId1 = from;
        setAppStatus(AppStatus.Talk);
      }
      var address = context.read<AddressStore>().find(AppManager.talkId1);
      AppManager.selectUser = address;
    }
  }

  void _recvThreewayCallError() {
    AppManager.toast("三者通話できません", gravity: ToastGravity.CENTER);
    AppManager.holdId = AppManager.talkId2;
    AppManager.talkId2 = '';
    setAppStatus(AppStatus.Talk);
  }

  void _connectRoom() {
    // print(url.substring(0, 2));
    socketioservice = SocketService();
    socketioservice!.url = AppManager.settings['MEDIASERVER3'];
    socketioservice!.roomDelegate = this;
    socketioservice!.connect();
  }

  /// *******************************************************************************************
  /// hold
  /// *******************************************************************************************
  void holdButton() {
    if (AppManager.holdId.isNotEmpty) {
      if (AppManager.selectUser!.id == AppManager.holdId) {
        _clearHold();
      } else {
        AppManager.toast("保留中の通話があります", bgColor: Colors.blue);
      }
      return;
    }
    if (AppManager.status == AppStatus.Talk) {
      _hold();
    }
  }

  void _hold() {
    AppManager.holdId = AppManager.selectUser!.id;
    AppManager.talkId1 = '';
    _statusImage = 'assets/images/status/addr_hold.png';
    setAppStatus(AppStatus.Hold);
    socketservice.io.emit("hold", [AppManager.selectUser!.id]);
    peer.close();
    setState(() {
      _hasRemoteVideo = false;
    });
  }

  void _clearHold() {
    _statusImage = '';
    AppManager.holdId = '';
    AppManager.talkId1 = AppManager.selectUser!.id;
    setAppStatus(AppStatus.Talk);
    socketservice.io.emit("hold_clear", [AppManager.selectUser!.id]);
  }

  void _receiveHold(String from) {
    if (AppManager.talkId1 == from) {
      _talking = false;
      AppManager.holdedId = from;
      _statusImage = 'assets/images/status/addr_hold.png';
      setAppStatus(AppStatus.Holded);
      peer.close();
      setState(() {
        _hasRemoteVideo = false;
      });
    }
  }

  void _receiveClearHold(String from) {
    if (AppManager.status != AppStatus.Holded || AppManager.holdedId != from) {
      return;
    }
    AppManager.holdedId = '';
    _statusImage = '';
    peer.invite(from, 'video', true);
  }

  /// *******************************************************************************************
  /// photo and draw
  /// *******************************************************************************************
  void _requestPhoto() async {
    var confirm = await WidgetUtil.showSimpleConfirmDialog(context, '画像を取得しますか？');
    if (confirm) {
      _doRequestPhoto("2");
    }
  }

  void _doRequestPhoto(String type) {
    socketservice.io.emit("request_photo", [
      {'udid': AppManager.talkId1, 'type': type}
    ]);
  }

  Future<Uint8List?> _takeVideoFrame() async {
    var track = peer.getVideoTrack();
    if (track == null) {
      return null;
    }
    final frame = await track.captureFrame();
    return frame.asUint8List();
  }

  Future<void> _receiveRequestPhoto() async {
    print('_receiveRequestPhoto');

    var imageBytes = await _takeVideoFrame();
    if (imageBytes == null) {
      return;
    }
    var image64 = base64Encode(imageBytes);

    _shareImage = await AppManager.loadImage(imageBytes);
    if (_shareImage == null) {
      return;
    }

    final Size size = MediaQuery.of(context).size;
    double wratio = size.width / _shareImage!.width;
    double hratio = size.height / _shareImage!.height;

    if (wratio <= hratio) {
      _localCanvasWidth = size.width;
      _localCanvasHeight = _shareImage!.height * wratio;
    } else {
      _localCanvasWidth = _shareImage!.width * hratio;
      _localCanvasHeight = size.height;
    }

    // print("shareimage  $size");
    // print(wratio.toString() + "," + hratio.toString());
    // print("local w, h = ( $_localCanvasWidth  ,  $_localCanvasHeight )");
    // print("image w, h = ( " + _shareImage.width.toString() + "  ,  " + _shareImage.height.toString() + " )");

    var sendData = {
      "id2": "shareimage",
      "to": AppManager.talkId1,
      "image": image64,
      "frameW": _localCanvasWidth.toString(),
      "frameH": _localCanvasHeight.toString()
    };
    socketservice.io.emit("talk", [sendData]);
  }

  Future<void> _receiveShareImage(Uint8List image) async {
    print(image.length);
    _shareImage = await AppManager.loadImage(image);
    if (_shareImage == null) {
      return;
    }
    print('share image ');
    // print(_shareImage.width);
    // print(_shareImage.height);

    final shareImage = _shareImage!;
    final Size size = MediaQuery.of(context).size;
    var wratio = size.width / shareImage.width;
    var hratio = size.height / shareImage.height;

    if (wratio <= hratio) {
      _localCanvasWidth = size.width;
      _localCanvasHeight = shareImage.height * wratio;
    } else {
      _localCanvasWidth = shareImage.width * hratio;
      _localCanvasHeight = size.height;
    }

    print('localcanvas   $_localCanvasWidth $_localCanvasHeight');

    var sendData = {
      "id2": "shareRecv",
      "frameW": _localCanvasWidth.toString(),
      "frameH": _localCanvasHeight.toString()
    };
    socketservice.io.emit("talk", [sendData]);

    _controller.clear();
    _controller.clear2();
    _controller.setIsClear(false);
    _controller.setIsClear2(false);
    // _shareImageData = await _shareImage.toByteData();
    _drawClearMode = false;
    setState(() {
      _drawing = true;
    });
  }

  void _showDrawView() {
    _controller.setDrawColor(2);
    _controller.clear();
    _controller.clear2();
    _controller.setIsClear(false);
    _controller.setIsClear2(false);
    _drawClearMode = false;
    setState(() {
      _drawing = true;
    });
  }

  void _undoDraw() {
    _controller.undo();
    var sendData = {"id2": "shareUndo", "to": AppManager.talkId1};
    socketservice.io.emit("talk", [sendData]);
  }

  void _toggleDrawClearMode() {
    var newMode = true;
    if (_drawClearMode) {
      newMode = false;
    }
    setState(() {
      _drawClearMode = newMode;
    });
    _controller.setIsClear(newMode);

    var sendData = {
      "id2": "shareEraseMode",
      "to": AppManager.talkId1,
      "mode": newMode ? "1" : "0"
    };
    print(sendData);
    socketservice.io.emit("talk", [sendData]);
  }

  Future<void> _savePhoto() async {
    var confirm = await WidgetUtil.showSimpleConfirmDialog(context, '画像を保存しますか？');
    if (confirm) {
      Directory docDir = await getApplicationDocumentsDirectory();
      String directory = "${docDir.path}/album/${AppManager.talkId1}";
      Directory("$directory/").exists().then((isThere) {
        if (!isThere) {
          Directory("$directory/").create(recursive: true).then((value) {
            _savePhotoImage(directory);
          });
        } else {
          _savePhotoImage(directory);
        }
      });
    }
  }

  Future<void> _savePhotoImage(String directory) async {
    ui.Image image = await _controller.image(
        _shareImage!, Size(_localCanvasWidth, _localCanvasHeight));
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);

    var filepath = '$directory/${AppManager.dateFormat(DateTime.now(), 'yyyyMMddHHmmss')}.png';
    File imageFile = File(filepath);
    imageFile.writeAsBytesSync(pngBytes!.buffer.asInt8List());
    // AppManager.toast("保存しました", Colors.blue, Colors.white);
    _uploadPhotoImage(filepath);
  }

  String _uploadURL() {
    if (AppDefine.amiApp) {
      return '${AppDefine.baseURL}app/upload_photos';
    }
    return "${AppDefine.baseURL}app/upphototest.php";
  }

  void _uploadPhotoImage(filepath) async {
    String fileName = filepath.split('/').last;
    FormData formData = FormData.fromMap({
      "mcs": AppManager.settings["MCSURL"],
      "gcd": AppManager.settings["MCSGROUPCODE"],
      "ccd": AppManager.settings["MCSCLINICCODE"],
      "mid": AppManager.selectUser!.id,
      "code": AppManager.selectUser!.code,
      "mst_id": AppManager.selectUser!.id.replaceAll("${AppManager.selectUser!.code}_", ""),
      "files0": await MultipartFile.fromFile(filepath, filename: fileName),
    });
    var url = _uploadURL();
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
    } catch (e) {
    }
  }

  Future<void> _endShareButton() async {
    var confirm = await WidgetUtil.showSimpleConfirmDialog(context, '画像共有を終了しますか？');
    if (confirm) {
      setState(() {
        _drawing = false;
      });
      socketservice.io.emit("close_drawview", [AppManager.talkId1]);
    }
  }

  /// *******************************************************************************************
  /// other buttons
  /// *******************************************************************************************
  void _changeCamera() {
    peer.switchCamera();
  }

  void _requestChangeCamera() {
    if (AppManager.status == AppStatus.Talk) {
      socketservice.io.emit("change_camera", [AppManager.talkId1]);
    }
  }

  void muteButton() {
    AppManager.isMute = !AppManager.isMute;
    peer.setAudioEnabled(!AppManager.isMute);

    // menuWidgetGlobalKey.currentState.setState(() {});
  }

  void videoMuteButton() {
    AppManager.isVideoMute = !AppManager.isVideoMute;
    peer.setVideoEnabled(AppManager.isVideoMute);
  }

  Future<void> albumButton() async {
    await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return StaffAlbumWebPage(
              title: 'アルバム',
              targetId: AppManager.selectUser!.id,
              targetName: AppManager.selectUser!.name,
            );
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
  }

  /// *******************************************************************************************
  /// safety check
  /// *******************************************************************************************
  void safetyCheckButton() {
    AppManager.isMute = true;
    AppManager.safetyCheckId = AppManager.selectUser!.id;
    socketservice.io.emit("safety_check", [AppManager.selectUser!.id]);
    setState(() {});
  }

  void safetyCheckEndButton() {
    socketservice.io.emit("safety_check_end", [AppManager.safetyCheckId]);
    peer.close();
    _endSafetyCheck();
  }

  void _endSafetyCheck() {
    AppManager.safetyCheckId = '';
    AppManager.isMute = false;
    _close();
  }

  /// *******************************************************************************************
  /// sensor
  /// *******************************************************************************************
  void sensorButton() {
    setState(() {
      _sensorViewIsHidden = false;
    });
  }

  void hideSensorView() {
    print('hide sensor view');
    setState(() {
      _sensorViewIsHidden = true;
    });
  }

  Future<void> graphButton(String sensorType) async {
    print('sensorType$sensorType');
    await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (BuildContext context, Animation<double> animation1, Animation<double> animation2) {
            return StaffWebPage(
              title: 'センサー',
              sensorType: sensorType,
              targetId: AppManager.selectUser!.id,
              targetName: AppManager.selectUser!.name,
            );
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const smallButtonSize = 32.0;
    final statusImageSize = min(size.width / 2, 300.0);

    List<Widget> widgets = [];
    if (!_talking && AppManager.safetyCheckId.isEmpty && AppManager.status != AppStatus.Call) {
      widgets.add(InkWell(
        onTap: () {
          Navigator.of(context).pop();
        },
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(_imageName(size)),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ));
    }

    if (_drawing) {

    } else {
      if (_talking || AppManager.safetyCheckId.isNotEmpty) {
        widgets.add(Positioned(
          top: 0,
          left: 0,
          height: AppManager.status == AppStatus.Multi
              ? size.height / 2
              : size.height,
          width: size.width - _remoteMargin,
          child: RTCVideoView(_remoteRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
        ));
      }
      if (_talking) {
        widgets.add(Positioned(
          bottom: 20,
          right: 0,
          height: size.height / 4,
          width: size.height / 4 / 3 * 2,
          child: Opacity(
            opacity: AppManager.safetyCheckId.isNotEmpty ? 0.0 : 1.0,
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ));
      }
      widgets.add(StaffTalkMenuWidget(key: menuWidgetGlobalKey));

      if (_statusImage.isNotEmpty) {
        widgets.add(Positioned(
          top: size.height / 2 - (statusImageSize / 2),
          left: size.width / 2 - (statusImageSize / 2),
          height: statusImageSize,
          width: statusImageSize,
          child: Image.asset(_statusImage),
        ));
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
          builder: (context, constraints) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            final viewPadding = MediaQuery.of(context).padding;
            final topOffset = viewInsets.top + viewPadding.top;
            final leftOffset = viewInsets.left + viewPadding.left + 12;
            final bottomOffset = viewInsets.bottom + viewPadding.bottom;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (!_talking && !_hasRemoteVideo && AppManager.status != AppStatus.Response)
                  InkWell(
                    onTap: () {
                      _close();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(_imageName(size)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                if (_hasRemote2Video)
                  Positioned(
                    top: constraints.maxHeight / 2,
                    left: 0,
                    height: constraints.maxHeight / 2,
                    width: constraints.maxWidth,
                    child: RTCVideoView(
                      _remote2Renderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                if (_hasRemoteVideo)
                  Positioned(
                    top: 0,
                    left: 0,
                    height: AppManager.status == AppStatus.Multi
                        ? size.height / 2
                        : size.height,
                    width: size.width - _remoteMargin,
                    child: RTCVideoView(_remoteRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
                  ),
                if (_talking && AppManager.safetyCheckId.isEmpty)
                  Positioned(
                    bottom: 20,
                    right: _minimiseLocalRenderer ? 20 : 0,
                    height: _minimiseLocalRenderer ? 28 : size.height / 4,
                    width: _minimiseLocalRenderer ? 28 : size.height / 4 / 3 * 2,
                    child: GestureDetector(
                      onTap: () {
                        if (_minimiseLocalRenderer) {
                          setState(() {
                            _minimiseLocalRenderer = false;
                          });
                        }
                      },
                      onVerticalDragUpdate: (DragUpdateDetails details) {

                      },
                      onVerticalDragEnd: (details) {
                        if (details.primaryVelocity != null) {
                          print(details.primaryVelocity!);
                          if (details.primaryVelocity! >= 0 && !_minimiseLocalRenderer) {
                            // 下向き
                            setState(() {
                              _minimiseLocalRenderer = true;
                            });
                          } else if (details.primaryVelocity! < 0 && _minimiseLocalRenderer) {
                            // 上向き
                            setState(() {
                              _minimiseLocalRenderer = false;
                            });
                          }
                        }
                      },
                      child: _minimiseLocalRenderer ?
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                        height: 28,
                        width: 28,
                      ) : RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                if (_talking)
                  Positioned(
                    top: topOffset,
                    left: leftOffset,
                    width: constraints.maxWidth - (leftOffset * 2),
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _requestPhoto();
                                },
                                child: SizedBox(
                                  width: smallButtonSize,
                                  height: smallButtonSize,
                                  child: Image.asset("assets/images/talk/btn-photo_request.png"),
                                ),
                              ),
                              const SizedBox(width: 20,),
                              GestureDetector(
                                onTap: () {
                                  _recordButton();
                                },
                                child: _isrecording
                                    ? Image.asset(
                                  "assets/images/talk/btn-recordend.png",
                                  width: smallButtonSize,
                                  height: smallButtonSize,
                                )
                                    : Image.asset(
                                  "assets/images/talk/btn-record.png",
                                  width: smallButtonSize,
                                  height: smallButtonSize,
                                ),
                              ),
                              const SizedBox(width: 20,),
                              GestureDetector(
                                onTap: () {
                                  _requestChangeCamera();
                                },
                                child: SizedBox(
                                  width: smallButtonSize,
                                  height: smallButtonSize,
                                  child: Image.asset("assets/images/talk/btn-change_camera.png"),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                StaffTalkMenuWidget(key: menuWidgetGlobalKey),
                if (_statusImage.isNotEmpty)
                  Positioned(
                    top: size.height / 2 - (statusImageSize / 2),
                    left: size.width / 2 - (statusImageSize / 2),
                    height: statusImageSize,
                    width: statusImageSize,
                    child: Image.asset(_statusImage),
                  ),
                if (_drawing)
                  ... [
                    Container(
                      color: Colors.black,
                    ),
                    Positioned(
                      top: (constraints.maxHeight - _localCanvasHeight) / 2,
                      left: (constraints.maxWidth - _localCanvasWidth) / 2,
                      width: _localCanvasWidth,
                      height: _localCanvasHeight,
                      child: Container(
                        color: Colors.black,
                        child: Painter(
                          paintController: _controller,
                          image: _shareImage!,
                          width: _localCanvasWidth,
                          height: _localCanvasHeight,
                        ),
                      ),
                    ),
                    Positioned(
                      top: topOffset,
                      left: leftOffset,
                      height: 40.0,
                      width: constraints.maxWidth - 32.0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          WidgetUtil.normalButton('保存', _savePhoto, primaryColor: const Color.fromARGB(255, 179, 182, 186), foregroundColor: Colors.white,),
                          WidgetUtil.normalButton('共有終了', _endShareButton, primaryColor: const Color.fromARGB(255, 238, 85, 104), foregroundColor: Colors.white,),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: bottomOffset,
                      left: leftOffset,
                      height: 40.0,
                      width: constraints.maxWidth - 32.0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: SizedBox(
                              width: smallButtonSize,
                              height: smallButtonSize,
                              child: GestureDetector(
                                onTap: () {
                                  _undoDraw();
                                },
                                child: Image.asset("assets/images/talk/icon_undo.png"),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _toggleDrawClearMode();
                            },
                            child: _drawClearMode
                                ? Image.asset(
                              "assets/images/talk/icon_eraser_on.png",
                              width: smallButtonSize,
                              height: smallButtonSize,
                            )
                                : Image.asset(
                              "assets/images/talk/icon_eraser_off.png",
                              width: smallButtonSize,
                              height: smallButtonSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                if (!_sensorViewIsHidden)
                  InkWell(
                    onTap: () {
                      hideSensorView();
                    },
                    child: SensorViewWidget(key: sensorWidgetGlobalKey),
                  ),
              ],
            );
          },
      ),
    );
  }

  /// *******************************************************************************************
  /// socket io
  /// *******************************************************************************************
  @override
  void onAppMessage(data) {
    String message = data['message'];
    print('stafftalk app message $message');
    if (message == 'call') {
      if (data["info"]["udid"] == null) {
        return;
      }

      if (AppManager.appsettings["AUTO_RECEIVE"] == '1') {
        // 自動応答
        if (AppManager.status == AppStatus.Call ||
            AppManager.status == AppStatus.Talk ||
            AppManager.status == AppStatus.Multi ||
            AppManager.status == AppStatus.MultiToTalk) {
        } else {
          // 応答する
          if (AppManager.selectUser!.id != data["info"]["udid"]) {
            var address = context.read<AddressStore>().find(data["info"]["udid"])!;
            AppManager.selectUser = address;
            _address = address;
          }
          _response();
          return;
        }
      }

      if (data["info"]["udid"] == AppManager.selectUser!.id) {
        _statusImage = 'assets/images/status/addr_call.png';
        setAppStatus(AppManager.status);
      } else if (AppManager.status == AppStatus.Talk) {
        var address = context.read<AddressStore>().find(data["info"]["udid"]);
        if (address != null) {
          setState(() {
            _callingId = address.id;
            _callingName = address.name;
          });
        }
      }
    }
    else if (message == 'call_cancel') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"] == AppManager.selectUser!.id) {
        _statusImage = 'assets/images/status/addr_called.png';
        setAppStatus(AppManager.status);
      }
      if (_callingId == data["udid"]) {
        setState(() {
          _callingId = '';
          _callingName = '';
        });
      }
    }
    else if (message == 'call_accept') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"] == AppManager.selectUser!.id) {}
    }
    else if (message == 'not_connect') {
      if (data["info"] == null) {
        return;
      }
      _notConnect(data["info"]);
    }
    else if (message == 'call_reject') {
      if (data["udid"] == null) {
        return;
      }
      if (AppManager.selectUser!.id == data["udid"]) {
        _callRejected();
      }
    }
    else if (message == 'call_not_auth') {
      if (data["udid"] == null) {
        return;
      }
      if (AppManager.selectUser!.id == data["udid"]) {
        _callNotAuth();
      }
    }
    else if (message == 'talk_end') {
      if (data["udid"] == null) {
        return;
      }
      _receiveHangup(data["udid"]);
    }
    else if (message == 'hold') {
      print(data["udid"]);
      if (data["udid"] == null) {
        return;
      }
      _receiveHold(data["udid"]);
    }
    else if (message == 'hold_clear') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["udid"] == null) {
        return;
      }
      _receiveClearHold(data["info"]["udid"]);
    }
    else if (message == 'change_camera') {
      if (data["udid"] == null) {
        return;
      }
      if (AppManager.status == AppStatus.Talk && AppManager.talkId1 == data["udid"]) {
        _changeCamera();
      }
    }
    else if (message == 'threeway') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["talkID1"] == null ||
          data["info"]["talkID2"] == null ||
          data["info"]["roomID"] == null) {
        return;
      }
      _recvThreeway(data["info"]["talkID1"], data["info"]["talkID2"], data["info"]["roomID"]);
    }
    else if (message == 'threeway_response') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["talkID1"] == null ||
          data["info"]["talkID2"] == null ||
          data["info"]["roomID"] == null) {
        return;
      }
      _recvThreeway(data["info"]["talkID1"], data["info"]["talkID2"], data["info"]["roomID"]);
    }
    else if (message == 'request_photo') {
      if (data["info"] == null) {
        return;
      }
      if (data["info"]["udid"] == null) {
        return;
      }
      if (AppManager.status == AppStatus.Talk &&
          AppManager.talkId1 == data["info"]["udid"]) {
        _receiveRequestPhoto();
      }
    }
    else if (message == 'photo_request_error') {
      AppManager.toast("画像取得に失敗しました。", gravity: ToastGravity.CENTER);
    }
    else if (message == 'close_drawview') {
      setState(() {
        _drawing = false;
      });
    }
    else if (message == 'safety_check_stop') {
      peer.close();
      _endSafetyCheck();
      AppManager.toast("操作されました。安全/安静目視を終了します");
    }
    else if (message == 'safety_check_error') {
      peer.close();
      _endSafetyCheck();
      AppManager.toast("アプリが起動していないか操作中です。");
    }
    else if (message == 'request_record') {
      if (data['info'] == null) {
        return;
      }
      var info = data['info'];
      if (info['udid'] == null || info['recid'] == null) {
        return;
      }
      if (AppManager.status == AppStatus.Talk &&
          AppManager.talkId1 == info['udid']) {
        _requestedRecord(info['udid'], info['recid']);
      }
    }
    else if (message == 'request_record_error') {
      AppManager.toast("録画開始できませんでした", gravity: ToastGravity.CENTER);
    }
    else if (message == 'request_record_reject') {
      AppManager.toast("録画開始されませんでした", gravity: ToastGravity.CENTER);
    }
    else if (message == 'request_record_accept') {
      if (AppManager.recordId.isNotEmpty) {
        _startRecord();
      }
    }
    else if (message == 'request_record_accept_error') {
    }
    else if (message == 'record_stop') {
      _onRecordEnd(message);
    }
  }

  @override
  void onMessage(data) {
    var id = data['id'];
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

    if (AppManager.status != AppStatus.MultiToTalk) {
      socketservice.io.emit("call_accept", [to]);
    }
    _startTalk();
  }

  @override
  void onMessageIceCandidate(from, candidate) {
    print('iceCandidate $from');
    peer.receiveIceCandidate(from, candidate);
  }

  @override
  void onTalkMessage(data) {
    String id2 = data['id2'];
    print('talk message $id2');
    if (id2 == 'shareimage') {
      String frameW = data['frameW'];
      String frameH = data['frameH'];
      String image = data['image'];

      _remoteCanvasWidth = double.parse(frameW);
      _remoteCanvasHeight = double.parse(frameH);

      print('shareimage 1');
      print(_remoteCanvasWidth);
      print(_remoteCanvasHeight);

      _controller.setDrawColor(1);
      print('shareimage 2');

      var base64Pos = image.indexOf('base64,');
      if (base64Pos >= 0) {
        image = image.substring(base64Pos + 'base64,'.length);
      }
      try {
        var image64 = image.replaceAll("\r\n", "");
        print('shareimage 3 $image64');
        // final UriData imageData = Uri.parse(image).data;
        // print('shareimage 4');
        // print(imageData.isBase64);
        var bytes = base64Decode(image64);
        print('image length');
        print(bytes.length);
        _receiveShareImage(bytes);
      } catch (e) {
        print(e);
        var sendData = {
          "id2": "shareRecvError",
        };
        socketservice.io.emit("talk", [sendData]);
      }
    }
    else if (id2 == 'shareRecv') {
      if (data['frameW'] == null || data['frameH'] == null) {
        return;
      }

      String frameW = data['frameW'];
      String frameH = data['frameH'];

      _remoteCanvasWidth = double.parse(frameW);
      _remoteCanvasHeight = double.parse(frameH);

      _showDrawView();
    }
    else if (id2 == 'draw') {
      if (data['event'] == null || data['x'] == null || data['y'] == null) {
        return;
      }
      double x =
          double.parse(data['x']) * _localCanvasWidth / _remoteCanvasWidth;
      double y =
          double.parse(data['y']) * _localCanvasHeight / _remoteCanvasHeight;
      _controller.receiveDraw(data['event'], x, y);
    }
    else if (id2 == 'shareUndo') {
      _controller.receiveDraw('undo', 0.0, 0.0);
    }
    else if (id2 == 'shareEraseMode') {
      if (data['mode'] == null) {
        return;
      }
      if (data['mode'] == '1') {
        _controller.setIsClear2(true);
      } else {
        _controller.setIsClear2(false);
      }
    }
    else if (id2 == 'threewayToCall') {
      if (data['from'] == null || data['to'] == null) {
        return;
      }
      _threewayToCall(data['from'], data['to']);
    }
  }

  @override
  void onConnect() {

  }

  @override
  void onDisConnect() {
    // TODO: implement onDisConnect
  }

  /// *******************************************************************************************
  /// peer
  /// *******************************************************************************************
  void _onStateChange(id, state) {
    if (id == AppManager.recordConnectId &&
        state == RTCSignalingState.RTCSignalingStateStable) {
      if (socketioservice?.tag == 4) {
        socketioservice!.io.emit("message", [{"id": "startRecording"}]);
        return;
      }
      // recsocket.send({"id": "startRecording"});
    }
  }

  void _onLocalStream(stream) {
    print('onlocal stream');
    _setLocalStream(stream);
  }

  Future<void> _setLocalStream(stream) async {
    // if (_localRenderer == null) {
    //   _localRenderer = RTCVideoRenderer();
    //   await _localRenderer!.initialize();
    // }
    _localRenderer.srcObject = stream;
  }

  void _onAddRemoteStream(id, stream) {
    print('onremote stream $id');
    if (id == AppManager.talkId1) {
      _setRemoteStream(stream);
    } else if (id == AppManager.talkId2) {
      _setRemote2Stream(stream);
    } else if (id == AppManager.safetyCheckId) {
      _setRemoteStream(stream);
    }
  }

  Future<void> _setRemoteStream(stream) async {
    // if (_remoteRenderer == null) {
    //   _remoteRenderer = RTCVideoRenderer();
    //   await _remoteRenderer!.initialize();
    // }
    _remoteRenderer.srcObject = stream;

    setState(() {
      _hasRemoteVideo = true;
    });
  }

  Future<void> _setRemote2Stream(stream) async {
    // if (_remote2Renderer == null) {
    //   _remote2Renderer = RTCVideoRenderer();
    //   await _remote2Renderer!.initialize();
    // }
    _remote2Renderer.srcObject = stream;

    setState(() {
      _hasRemote2Video = true;
    });
  }

  void _onOffer(data) {
    if (data['id'] == AppManager.recordConnectId) {
      print('onoffer rec');
      final sendData = {
        "id": "receiveVideoFrom",
        "sdpOffer": data['sdp'],
        "sender": data['id']
      };
      if (socketioservice?.tag == 4) {
        socketioservice!.io.emit("message", [sendData]);
        return;
      }
      // recsocket.send(sendData);
      return;
    }

    if (AppManager.status == AppStatus.Multi) {
      print('onoffer multi');
      final sendData = {
        "id": "receiveVideoFrom",
        "sdpOffer": data['sdp'],
        "sender": data['id']
      };
      socketioservice!.io.emit("message", [sendData]);
      return;
    }

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
    if (data['id'] != AppManager.safetyCheckId) {
      _startTalk();
    }
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
      if (socketioservice?.tag == 4) {
        socketioservice!.io.emit("message", [args]);
        return;
      }
      // recsocket.send(args);
      return;
    }

    if (AppManager.status == AppStatus.Multi) {
      socketioservice!.io.emit("message", [args]);
      return;
    }

    socketservice.io.emit("message", [args]);
  }

  String _imageName(size) {
    if (size.width > size.height) {
      if (size.width < 500) {
        return "assets/images/talk/call_bg_s_landscape.png";
      }
      return "assets/images/talk/call_bg_s_landscape.png";
    }
    if (size.width < 500) {
      return "assets/images/talk/call_bg_s.png";
    }
    return "assets/images/talk/call_bg.png";
  }

  @override
  void onIoConnect() {
    print('onIoconnect');

    if (socketioservice!.tag == 4) {
      _joinRecRoom();
      return;
    }
    _joinRoom();
  }

  @override
  void onIoDisConnect() {
    print('onIoDisConnect');
    AppManager.toast("三者通話を開始できませんでした。", bgColor: Colors.blue);
    _hangup();
  }

  @override
  void onIoMessage(data) {
    var messageId = data['id'];
    print("onIoMessage, $messageId");

    if (messageId == 'existingParticipants') {
      _onExistingParticipants(data);
    }
    else if (messageId == 'newParticipantArrived') {
      _onNewParticipant(data);
    }
    else if (messageId == 'participantLeft') {
      _onParticipantLeft(data);
    }
    else if (messageId == 'receiveVideoAnswer') {
      _onReceiveVideoAnswer(data);
    }
    else if (messageId == 'joinRoomResponse') {
      _onJoinRoomResponse(data);
    }
    else if (messageId == 'recordResponse') {
      _onRecordResponse(data);
    }
    else if (messageId == 'recordEnd') {
      _onRecordEnd(data);
    }
    else if (messageId == 'iceCandidate') {
      // print(data);
      if (data["name"] == null || data["candidate"] == null) {
        return;
      }
      peer.receiveIceCandidate(data["name"], data["candidate"]);
    }
  }

  void _joinRoom() {
    var sendData = {
      "id": "joinRoom",
      "room": AppManager.threewayId,
      "roomName": AppManager.threewayId,
      "name": AppManager.myId,
    };
    // print('socketio joinRoom');
    // print(sendData);
    socketioservice!.io.emit("message", [sendData]);
  }

  void _onExistingParticipants(message) {
    print(message);
    peer.invite(AppManager.myId, 'sendonly', true);

    if (message['data'] == null || message['data'] == 'Null') {
      return;
    }

    var data = message['data'];

    data.forEach((name) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _onParticipant(name.toString());
    });
  }

  void _onNewParticipant(message) {
    if (message['name'] == null) {
      return;
    }
    _onParticipant(message['name']);
  }

  void _onParticipant(String name) {
    print('on participant $name');
    peer.invite(name, 'recvonly', true);
  }

  void _onParticipantLeft(message) {}

  void _onReceiveVideoAnswer(message) {
    if (message['name'] == null || message['sdpAnswer'] == null) {
      return;
    }
    peer.receiveAnswer(message["name"], message["sdpAnswer"]);
    // _onTalking();
  }

  @override
  void onPaint(data) {
    var event = data['event'];
    var x = data['x'];
    var y = data['y'];

    var sendData = {"id2": "draw", "event": event, "x": x, "y": y};
    socketservice.io.emit("talk", [sendData]);
  }
}
