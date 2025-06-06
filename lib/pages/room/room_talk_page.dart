import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:amiapp/pages/staff/staff_album_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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

class RoomTalkPage extends StatefulWidget {
  const RoomTalkPage({super.key});

  @override
  RoomTalkPageState createState() => RoomTalkPageState();
}

class RoomTalkPageState extends State<RoomTalkPage>
    with WidgetsBindingObserver, SocketIOServiceDelegate, SocketServiceDelegate, PaintControllerDelegate {
  bool _init = true;
  bool _active = true;
  Peer peer = Peer();
  late Address _address;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _remote2Renderer = RTCVideoRenderer();
  bool _hasRemoteVideo = false;
  bool _hasRemote2Video = false;
  final double _remoteMargin = 0;
  SocketIOService socketservice = SocketIOService();
  SocketService? socketioservice;
  AudioService audio = AudioService();
  bool _talking = false;
  Timer? _rusuTimer;
  String _statusImage = '';
  bool _isrecording = false;

  bool _talked = false;
  final bool _showSubmenu = false;
  bool _callendIsEnabled = true;

  /// 通話中着信対応
  final String _callingId = '';
  final String _callingName = '';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print('roomtalk initState');
    // socketservice.delegate = this;
    socketservice.delegate2 = this;
    peer.onStateChange = _onStateChange;
    peer.onLocalStream = _onLocalStream;
    peer.onOffer = _onOffer;
    peer.onAnswer = _onAnswer;
    peer.onAddRemoteStream = _onAddRemoteStream;
    peer.onIceCandidate = _onIceCandidate;
    _controller.delegate = this;
    _initRenderers();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

    print('roomtalk didChangeDependencies $_init');

    if (_init) {
      _init = false;
      AppManager.setStatusBarHidden(false);

      if (AppManager.selectUser!.call == 1) {
        await audio.ringtone();
        print('[DEBUG PRINT]着信中 ${AppManager.selectUser!.id}');
        _statusImage = ImageName.addrCall;
        if (AppManager.appsettings["AUTO_RECEIVE"] == '1') {
          print(DateTime.now());
          print('[DEBUG PRINT]room talk 着信中 auto receive');
          sleep(Duration(milliseconds: 500));
          _response();
          return;
        } else {
          if (AppManager.autoreceives[AppManager.selectUser!.id] == '1') {
            _response();
            return;
          }
        }
      } else if (AppManager.status == AppStatus.Call) {
        print('発信中 ${AppManager.selectUser!.id}');
        _callendIsEnabled = false;
        _call();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("room talk life cycle state -> $state");
    // setState(() {
    //   _notification = state;
    // });
    if (state == AppLifecycleState.resumed) {

    } else if (state == AppLifecycleState.paused) {
      if (AppManager.status == AppStatus.Call) {
        _cancelCall();
      } else {
        _close();
      }
    }
  }

  @override
  void deactivate() {
    print('roomtalk deactivate');
    // WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
    _active = false;
    socketservice.delegate2 = null;
    // socketservice.delegate = null;
    AppManager.setStatusBarHidden(true);
  }

  @override
  void dispose() {
    print('roomtalk dispose');
    WidgetsBinding.instance.removeObserver(this);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _remote2Renderer.dispose();
    _stopRusuTimer();
    super.dispose();
  }

  Future<void> _initRenderers() async {
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
    _stopRusuTimer();
    audio.stopButtonCall();
    if (_isrecording) {
      // recording 終了
      _onRecordEnd('');
    }
    AppManager.selectUser = null;
    Navigator.of(context).pop();
  }

  /// *******************************************************************************************
  /// call talk button
  /// *******************************************************************************************

  void _callEndButton() {
    if (!socketservice.connected) {
      audio.stopCall();
      audio.stopRingtone();
      _close();
      return;
    }
    if (AppManager.status == AppStatus.Call) {
      _cancelCall();
    } else if (AppManager.selectUser!.call == 1) {
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
    _statusImage = ImageName.connecting;
    setAppStatus(AppStatus.Call);
    await audio.call();
    socketservice.io.emit("call", [AppManager.selectUser!.id]);

    _rusuTimer = Timer.periodic(const Duration(milliseconds: AppDefine.absenceSec1), (Timer timer) {
      if (!_active || AppManager.status == AppStatus.Talk) {
        print('[DEBUG PRINT]  rusu timer in talk');
        return;
      }
      _cancelCall(isClose: false);
      setState(() {
        _statusImage = ImageName.rusu;
      });

      _rusuTimer = Timer.periodic(Duration(milliseconds: AppDefine.absenceSec2), (Timer timer) {
        _close();
      });
    });
  }

  Future<void> _response() async {
    await audio.stopRingtone();
    // sleep(Duration(milliseconds: 300));
    AppManager.talkId1 = AppManager.selectUser!.id;
    peer.invite(AppManager.selectUser!.id, 'video', true);
  }

  void _stopRusuTimer() {
    if (_rusuTimer != null) {
      _rusuTimer!.cancel();
      _rusuTimer = null;
    }
  }

  void _startTalk() {
    _stopRusuTimer();
    // AppManager.talkId1 = AppManager.selectUser.id;
    AppManager.selectUser!.call = 0;
    _statusImage = '';
    _callendIsEnabled = true;
    setAppStatus(AppStatus.Talk);
    audio.stopCall();
  }

  void _cancelCall({bool isClose = true}) {
    if (socketservice.isConnect()) {
      socketservice.io.emit("call_cancel", [AppManager.selectUser!.id]);
    }
    audio.stopCall();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    if (isClose) {
      _close();
    }
  }

  void _rejectCall() {
    _statusImage = '';
    socketservice.io.emit("call_reject", [AppManager.selectUser!.id]);
    audio.stopRingtone();
    _close();
  }

  void _hangup() {
    setState(() {
      _talked = true;
    });
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

    if (AppManager.status == AppStatus.Multi) {
      if (socketioservice != null) {
        socketioservice!.disconnect();
      }
      // var sendData = {
      //   "id2": "threewayToCall",
      //   "from": AppManager.talkId1,
      //   "to": AppManager.talkId2
      // };
      // socketservice.io.emit("talk", [sendData]);
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

    peer.close();
    _close();
  }

  void _notConnect(String connectStatus) {
    audio.stopCall();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    if (connectStatus == '1') {
      AppManager.toast("呼び出し先が不在です", bgColor: Colors.blue);
    } else {
      AppManager.toast("通話中です", bgColor: Colors.blue);
    }
    _close();
  }

  void _callRejected() {
    audio.stopCall();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    AppManager.toast("切断されました", bgColor: Colors.blue);
    socketservice.io.emit("call_cancel", [AppManager.selectUser!.id]);
    _close();
  }

  Future<void> _callNotAuth() async {
    if (AppManager.selectUser != null) {
      if (AppManager.selectUser!.id.startsWith('@')) {
        print('call not auth is not show no call to @');
        return;
      }
    }
    audio.stopCall();
    _statusImage = '';
    setAppStatus(AppStatus.None);
    await WidgetUtil.showAutoDisposeDialog(context, '通話許可がありません　通知しました');
    _close();
  }

  void _receiveHangup(String from) {
    AppStatus newStatus = AppStatus.None;

    if (AppManager.holdId == from) {
      // 保留相手から切断
      AppManager.holdId = "";
      if (AppManager.selectUser!.id == from) {
        // 保留相手選択中は通話終了処理
        setState(() {
          _talked = true;
        });
        _endTalk();
        setAppStatus(newStatus);
        return;
      }
      if (AppManager.talkId1.isEmpty) {
        // 通話相手なし
      }
    } else if (AppManager.holdedId == from) {
      // 保留された相手から切断
      setState(() {
        _talked = true;
      });
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
        setState(() {
          _talked = true;
        });
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
        socketioservice?.disconnect();
      }
      AppManager.talkId2 = '';
      _hasRemote2Video = false;
      if (AppManager.myId == from) {
        print("_threewayToCall myId = from");
        AppManager.talkId1 = to;
        setAppStatus(AppStatus.MultiToTalk);
        await Future.delayed(Duration(seconds: 1));
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
    var result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => StaffAlbumPage()));
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
  /// record
  /// *******************************************************************************************
  Future<void> _requestedRecord(String udid, String recid) async {
    var value = await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('確認'),
        content: Text('録画を開始してもよろしいですか？'),
        actions: <Widget>[
          SimpleDialogOption(child: Text('はい'),onPressed: (){Navigator.pop(context, true);},),
          SimpleDialogOption(child: Text('いいえ'),onPressed: (){Navigator.pop(context, false);},),
        ],
      ),
    );
    if (value) {
      AppManager.recordId = recid;
      var sendData = {
        'recid': AppManager.recordId,
        'to': AppManager.talkId1
      };
      socketservice.io.emit("request_record_accept", [sendData]);
      AppManager.recordId = '${AppManager.recordId}_2';
      _startRecord();
    } else {
      socketservice.io.emit("request_record_reject", [AppManager.talkId1]);
    }
  }

  void _startRecord() {
    if (_isrecording) {
      return;
    }
    print('start record');
    //self.recordConnectId = "REC_" + Date().toString("yyyyMMddHHmmss") + "_" + appManager.delegatorCode + "_" + appManager.myId
    AppManager.recordConnectId = 'REC_${AppManager.dateFormat(DateTime.now(), "yyyyMMddHHmmss")}_${AppManager.delegatorCode}_${AppManager.myId}';
    setState(() {
      _isrecording = true;
    });

    var url = AppManager.settings['MEDIASERVER4'];
    print('connect rec:' + url);
    print(url.substring(0, 2));
    if (url.substring(0, 2) == 'ws') {
      AppManager.toast("録画開始できませんでした", gravity: ToastGravity.CENTER);
      socketservice.io.emit("request_record_reject", [AppManager.talkId1]);
    } else {
      socketioservice = SocketService();
      socketioservice!.url = url;
      socketioservice!.roomDelegate = this;
      socketioservice!.connect();
    }
  }

  void _onRecordEnd(message) {
    AppManager.recordConnectId = '';
    peer.closeOne(AppManager.recordConnectId);
    _onErrorStartRecord();
  }

  void _onErrorStartRecord() {
    setState(() {
      _isrecording = false;
    });
    socketioservice?.disconnect();
  }

  bool _tapping = false;
  Future<void> _tap() async {
    if (_tapping) {
      return;
    }
    _tapping = true;
    if (AppManager.status == AppStatus.Call) {
      _cancelCall();
    } else if (AppManager.selectUser?.call == 1) {
      _response();
    } else {
      _close();
    }
    await Future.delayed(const Duration(seconds: 1));
    _tapping = false;
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    var smallButtonSize = 32.0;
    var button1Width = size.shortestSide / 4;
    if (button1Width > 168) {
      button1Width = 168;
    }
    // if (size.width <= 350) {
    //   button1Width = 80;
    // } else if (size.width <= 600) {
    //   button1Width = 148;
    // }
    var button1Height = button1Width / 335 * 182;
    var button2Width = button1Height / 182 * 228;
    var button3Height = button2Width / 239 * 130;
    var button1FrameHeight = button1Height + button3Height + 8;
    var statusImageSize = min(size.width / 2, 300.0);
    var callImageSize = min(size.width / 2, 200.0);
    if (size.width > size.height) {
      callImageSize = min(size.height * 0.7, 500.0);
    }

    return Scaffold(
      body: _talked ? Container(color: Colors.black,) : LayoutBuilder(
        builder: (context, constraints) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          final viewPadding = MediaQuery.of(context).padding;
          final topOffset = viewInsets.top + viewPadding.top;
          final leftOffset = viewInsets.left + viewPadding.left + 12;
          final bottomOffset = viewInsets.bottom + viewPadding.bottom;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const Material(color: Colors.white),
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
                      ? constraints.maxHeight / 2
                      : constraints.maxHeight,
                  width: constraints.maxWidth,
                  child: RTCVideoView(_remoteRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
                ),
              if (_talking && AppManager.safetyCheckId.isEmpty)
                Positioned(
                  bottom: 20,
                  right: 0,
                  height: constraints.maxHeight / 4,
                  width: constraints.maxHeight / 4 / 3 * 2,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
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
              if (_talking)
                Positioned(
                  top: 40,
                  left: 0,
                  width: constraints.maxWidth,
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
                ),
              if (_callendIsEnabled)
                Positioned(
                  bottom: (_showSubmenu ? button1FrameHeight : 0.0) + 16.0,
                  left: 0,
                  width: constraints.maxWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      GestureDetector(
                        child: Image.asset(
                          'assets/images/talk/btn-callend.png',
                          width: button1Width,
                          height: button1Height,
                        ),
                        onTap: () {
                          _callEndButton();
                        },
                      ),
                    ],
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
    print('roomtalk app message $message');
    if (message == 'call') {

    }
    else if (message == 'call_cancel') {
      if (data["udid"] == null) {
        return;
      }
      if (data["udid"] == AppManager.selectUser!.id) {
        audio.stopRingtone();
        _close();
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
      _callRejected();
    }
    else if (message == 'call_not_auth') {
      if (data["udid"] == null) {
        return;
      }
      _callNotAuth();
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
    else if (message == 'request_record') {
      if (data['info'] == null) {
        return;
      }
      var info = data['info'];
      if (info['udid'] == null || info['recid'] == null) {
        return;
      }
      if (AppManager.status == AppStatus.Talk && AppManager.talkId1 == info['udid']) {
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
    // if (id == 'callResponse') {
    //   var response = (data["response"] ?? '');
    //   if (response != 'accepted') {
    //     return;
    //   }
    //   var to = (data["to"] ?? '');
    //   var sdp = (data["sdpOffer"] ?? '');
    //   print('callresponse $to');
    //   onCallResponse(to, sdp);
    // } else if (id == 'startCommunication') {
    //   var sdp = (data["sdpAnswer"] ?? '');
    //   var to = (data["to"] ?? '');
    //   onStartCommunication(to, sdp);
    // } else if (id == 'iceCandidate') {
    //   var from = data["from"];
    //   var candidate = data["candidate"];
    //   if (from == null || candidate == null) {
    //     return;
    //   }
    //   // print('iceCandidate $from');
    //   peer.receiveIceCandidate(from, candidate);
    // }
  }

  @override
  void onCallResponse(to, sdp) {
    AppManager.talkId1 = to;
    peer.receiveOffer(to, sdp);
  }

  @override
  void onStartCommunication(to, sdp) {
    print('=============       onStartCommunication($to)           =============');
    peer.receiveAnswer(to, sdp);

    if (AppManager.status == AppStatus.Holded) {
      AppManager.holdedId = '';
    }

    if (AppManager.status != AppStatus.MultiToTalk) {
      socketservice.io.emit("call_accept", [to]);
    }
    if (AppManager.status == AppStatus.Multi) {
      return;
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
  }

  /// *******************************************************************************************
  /// peer
  /// *******************************************************************************************
  void _onStateChange(id, state) {
    if (id == AppManager.recordConnectId && state == RTCSignalingState.RTCSignalingStateStable) {
      if (socketioservice != null) {
        socketioservice!.io.emit("message", [{"id": "startRecording"}]);
        return;
      }
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
    print('======================================= onremote stream $id ==============================================================================');
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
    print('onoffer');
    if (data['id'] == AppManager.recordConnectId) {
      final sendData = {
        "id": "receiveVideoFrom",
        "sdpOffer": data['sdp'],
        "sender": data['id']
      };
      socketioservice?.io.emit("message", [sendData]);
      return;
    }

    if (AppManager.status == AppStatus.Multi) {
      final sendData = {
        "id": "receiveVideoFrom",
        "sdpOffer": data['sdp'],
        "sender": data['id']
      };
      socketioservice?.io.emit("message", [sendData]);
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
    _startTalk();
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
      socketioservice?.io.emit("message", [args]);
      return;
    }
    if (AppManager.status == AppStatus.Multi) {
      socketioservice?.io.emit("message", [args]);
      return;
    }
    socketservice.io.emit("message", [args]);
  }

  String _imageName(size) {
    if (size.width > size.height) {
      return "assets/images/talk/call_bg_landscape.png";
    }
    if (size.width < 500) {
      return "assets/images/talk/call_bg_s.png";
    }
    return "assets/images/talk/call_bg.png";
  }

  @override
  void onIoConnect() {
    // print('onIoconnect');
    if (AppManager.recordConnectId.isNotEmpty) {
      return;
    }
    _joinRoom();
  }

  @override
  void onIoDisConnect() {

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
      // _onJoinRoomResponse(data);
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

    data.forEach((name) {
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
