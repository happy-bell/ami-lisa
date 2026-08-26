import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/room/room_talk_page.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marquee/marquee.dart';
import 'package:video_player/video_player.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/pages/staff/staff_live_view_page.dart';
import 'package:amiapp/pages/staff/staff_talk_page.dart';
import 'package:amiapp/pages/setting/setting_page.dart';
import 'package:amiapp/pages/setting/tv_pi_setting_page.dart';
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/audio_service.dart';
import 'package:amiapp/services/and_vital_service.dart';
import 'package:amiapp/services/ble_exclusive.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/services/socket_io_service.dart';
import 'package:real_volume/real_volume.dart';

import '../../services/peer_service.dart';
import '../../widgets/clock_widget.dart';
import '../../widgets/tv_room_sidebar.dart';
import '../../widgets/checkme_monitor_panel.dart';
import '../../widgets/and_vital_pair_dialog.dart';
import '../../widgets/and_vital_result_popup.dart';
import '../../services/tv_health_notify.dart';
import '../../services/tv_weather.dart';
import '../../widgets/tv_weather_panel.dart';
import 'tv_health_page.dart';
import 'tv_info_page.dart';

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
  Timer? _getInfoTimer;
  Timer? _slideShowTimer;
  Timer? _healthTimer;
  Timer? _weatherTimer;
  TvHealthState _healthState = TvHealthState();
  TvWeatherState? _weatherState;
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
  VideoPlayerController? _infoVideoController;
  bool _isVideoLoop = false;
  String _infoMessage = '';
  String _infoVideo = '';
  bool _infoVideoPlaying = false;
  bool _infoVideoStarting = false;
  List<String> _imageFiles = [];
  int _imageFileIndex = -1;
  double _imageOpacity = 0.0;

  final _safetyCheckIds = [];
  bool _watching = false;
  bool _receivingCall = false;

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
    _bindIncomingCallHandler();

    Future(() {
      _videoController = VideoPlayerController.asset('assets/videos/sensor4.mp4');
      _videoController.addListener(_checkVideo);
      _brightnessSetting();
    });

    // Ring / Checkme はホームのボタンで有効化する（TCL）。PiはRing自動。
    CheckmeRingService.instance.addListener(_onRingChanged);
    CheckmeRingService.instance.start();
    CheckmeProService.instance.addListener(_onRingChanged);
    AndVitalService.instance.addListener(_onRingChanged);
  }

  void _onRingChanged() {
    if (mounted) setState(() {});
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

      await TvUtil.ensureTclCallWaiting();
      await _handlePendingIncomingIfNeeded();

      final playPending = AppManager.pendingPlayInfoVideo;
      if (playPending) {
        AppManager.pendingPlayInfoVideo = false;
        _infoVideoPlaying = true;
        if (AppManager.pendingPlayInfoVideoPath.isNotEmpty) {
          _infoVideo = AppManager.pendingPlayInfoVideoPath;
        }
        AppManager.pendingPlayInfoVideoPath = '';
        if (_infoVideo.isNotEmpty) {
          _startMovie();
        }
      }

      if (!playPending &&
          (AppManager.appsettings['SLEEP_MODE'] == '1' ||
              AppManager.appsettings['CLOCKDISP'] == '1')) {
        print('isSleep');
        setState(() {
          _isSleep = true;
        });
      }

      _startGetInfoTimer(isGet: true);
      _startHealthTimerIfPi();
      _syncCheckmeProForLayout();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("room life cycle state -> $state");
    if (state == AppLifecycleState.resumed) {
      print('resumed');
      _active = true;
      socketservice.reconnect = true;
      socketservice.startConnectTimer();
      _handlePendingIncomingIfNeeded();
      _startGetInfoTimer(isGet: true);
    } else if (state == AppLifecycleState.paused) {
      if (_sleeptimer != null) {
        _sleeptimer!.cancel();
      }
      _pauseInfoPlayback();

      // TV着信待機中は Socket と処理を維持（視聴中・スクリーンレスでも着信を受ける）
      if (TvUtil.isCallWaitingEnabled) {
        socketservice.reconnect = true;
        print('TV_CALL_WAITING: keep socket on pause');
        return;
      }
      _active = false;

      socketservice.reconnect = false;
      socketservice.stopTimer();
      socketservice.disconnect();
      setState(() {
        _isconnect = false;
      });
    }
  }

  void _bindIncomingCallHandler() {
    if (!TvUtil.isTelevision) return;
    TvUtil.setIncomingCallHandler((data) async {
      final action = data['action']?.toString() ?? '';
      final callerId = data['callerId']?.toString() ?? '';
      await _applyIncomingAction(action, callerId);
    });
  }

  Future<void> _handlePendingIncomingIfNeeded() async {
    if (!TvUtil.isTelevision) return;
    final pending = await TvUtil.getPendingIncomingCall();
    if (pending == null) return;
    final action = pending['action']?.toString() ?? '';
    final callerId = pending['callerId']?.toString() ?? '';
    await _applyIncomingAction(action, callerId);
  }

  Future<void> _applyIncomingAction(String action, String callerId) async {
    if (callerId.isEmpty) return;
    if (action == 'accept') {
      await TvUtil.dismissIncomingCallOverlay();
      if (!mounted) return;
      AppManager.tvForceAccept = true;
      _active = true;
      await _receive(callerId);
    } else if (action == 'reject') {
      await TvUtil.dismissIncomingCallOverlay();
      try {
        socketservice.io.emit("call_reject", [callerId]);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    print('room dispose');
    // socketservice.delegate = null;
    CheckmeRingService.instance.removeListener(_onRingChanged);
    CheckmeProService.instance.removeListener(_onRingChanged);
    AndVitalService.instance.removeListener(_onRingChanged);
    _healthTimer?.cancel();
    _weatherTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _stopGetInfoTimer();
    _stopImageAnimation();
    _infoVideoController?.dispose();
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
    _pauseInfoPlayback();
    _stopGetInfoTimer();
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
            return AppManager.isPiTvLayout
                ? const TvPiSettingPage()
                : SettingPage();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
    );
    if (!mounted) return;
    _active = true;
    socketservice.reconnect = true;
    socketservice.delegate = this;
    socketservice.startConnectTimer();
    setState(() {});
    _startGetInfoTimer(isGet: true);
    _startHealthTimerIfPi();
    _syncCheckmeProForLayout();
  }

  void _syncCheckmeProForLayout() {
    if (AppManager.isPiTvLayout) {
      CheckmeProService.instance.stop();
    } else {
      CheckmeProService.instance.start();
      AndVitalService.instance.start();
    }
  }

  void _startHealthTimerIfPi() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _weatherTimer?.cancel();
    _weatherTimer = null;
    if (!AppManager.isPiTvLayout) return;
    _pollHealthNotify();
    _pollWeather();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollHealthNotify();
    });
    _weatherTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _pollWeather();
    });
  }

  Future<void> _pollWeather() async {
    if (!AppManager.isPiTvLayout || !_active || _talking) return;
    final state = await TvWeatherService.instance.fetch();
    if (!mounted) return;
    setState(() => _weatherState = state);
  }

  Future<void> _pollHealthNotify() async {
    if (!AppManager.isPiTvLayout || !_active || _talking) return;
    final state = await TvHealthNotify.instance.fetch();
    if (!mounted) return;
    setState(() => _healthState = state);
  }

  void _stopGetInfoTimer() {
    _getInfoTimer?.cancel();
    _getInfoTimer = null;
  }

  void _startGetInfoTimer({bool isGet = false}) {
    print('start get info timer $isGet');
    _stopGetInfoTimer();
    if (isGet) {
      _getInfo();
    }
    _getInfoTimer = Timer.periodic(const Duration(seconds: 30), (Timer timer) {
      _getInfo();
    });
  }

  String _asInfoString(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    if (text == 'null') return '';
    return text;
  }

  Future<void> _getInfo() async {
    final url =
        '${AppDefine.baseURL}api/info?code=${AppManager.delegatorCode}&mst_id=${AppManager.myId}';
    print(url);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return;
      }
      final data = json.decode(response.body);
      if (data is! Map) {
        return;
      }

      _infoMessage = _asInfoString(data['message']);

      final currentVideo = _infoVideo;
      final currentVideoLoop = _isVideoLoop;
      var nextVideo = _asInfoString(data['video']);

      final nextFiles = <String>[];
      final rawFiles = data['files'];
      if (rawFiles is List) {
        for (final file in rawFiles) {
          final path = _asInfoString(file);
          if (path.isNotEmpty) {
            nextFiles.add(path);
          }
        }
      }

      var fileChanged = nextFiles.length != _imageFiles.length;
      if (!fileChanged) {
        for (var i = 0; i < nextFiles.length; i++) {
          if (_imageFiles[i] != nextFiles[i]) {
            fileChanged = true;
            break;
          }
        }
      }
      if (fileChanged) {
        _imageFileIndex = -1;
        _imageFiles = nextFiles;
        if (!_infoVideoPlaying) {
          _startImageAnimation();
        }
      }

      if (nextVideo.isNotEmpty) {
        _infoVideo = nextVideo;
      }
      _isVideoLoop = data['video_loop']?.toString() == '1';

      if (_infoVideo.isEmpty) {
        _infoVideoPlaying = false;
        if (currentVideo.isNotEmpty) {
          _stopMovie();
        }
      } else if (_infoVideoPlaying &&
          !_infoVideoStarting &&
          (currentVideo != _infoVideo || currentVideoLoop != _isVideoLoop) &&
          (_infoVideoController == null ||
              !_infoVideoController!.value.isInitialized)) {
        _startMovie();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('getInfo error $e');
    }
  }

  void _startImageAnimation() {
    _stopImageAnimation();
    if (_imageFiles.isEmpty) {
      return;
    }
    _slideShow();
    _slideShowTimer = Timer.periodic(const Duration(seconds: 30), (Timer timer) {
      _slideShow();
    });
  }

  void _stopImageAnimation() {
    _slideShowTimer?.cancel();
    _slideShowTimer = null;
  }

  void _slideShow() {
    if (!mounted || _imageFiles.isEmpty) {
      return;
    }
    if (_imageFiles.length == 1) {
      setState(() {
        _imageFileIndex = 0;
        _imageOpacity = 1.0;
      });
      return;
    }
    setState(() {
      _imageOpacity = 0.0;
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted || _imageFiles.isEmpty) {
        return;
      }
      _imageFileIndex =
          (_imageFileIndex + 1) < _imageFiles.length ? _imageFileIndex + 1 : 0;
      setState(() {
        _imageOpacity = 1.0;
      });
    });
  }

  Uri _infoVideoUri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.parse('${AppDefine.baseURL}image').replace(
      queryParameters: {
        'path': path,
        'token': (AppManager.settings['api_token'] ?? '').toString(),
      },
    );
  }

  Future<VideoPlayerController> _openInfoVideo(String path) async {
    final uri = _infoVideoUri(path);
    print('info video uri $uri');
    final network = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: const {'Accept': '*/*'},
    );
    try {
      await network.initialize().timeout(const Duration(seconds: 12));
      return network;
    } catch (e) {
      print('info video network init failed $e');
      await network.dispose();
    }

    final tmp = File('${Directory.systemTemp.path}/ami_info_home.mp4');
    final response = await http.get(uri).timeout(const Duration(seconds: 90));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('video download ${response.statusCode}');
    }
    await tmp.writeAsBytes(response.bodyBytes, flush: true);
    final file = VideoPlayerController.file(tmp);
    await file.initialize().timeout(const Duration(seconds: 10));
    return file;
  }

  Future<void> _startMovie() async {
    if (_infoVideo.isEmpty || _infoVideoStarting) {
      return;
    }
    _infoVideoStarting = true;
    final old = _infoVideoController;
    _infoVideoController = null;
    await old?.dispose();
    if (mounted) {
      setState(() {});
    }
    try {
      final controller = await _openInfoVideo(_infoVideo);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _infoVideoController = controller;
      controller.setLooping(_isVideoLoop);
      if (_infoVideoPlaying && !_isSleep && !_talking) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('info video start error $e');
      _infoVideoPlaying = false;
      if (mounted) {
        AppManager.toast('動画を再生できませんでした');
        setState(() {});
      }
    } finally {
      _infoVideoStarting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _stopMovie() {
    _infoVideoController?.dispose();
    _infoVideoController = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _playInfoVideo() {
    if (_infoVideo.isEmpty) {
      return;
    }
    setState(() {
      _isSleep = false;
      _infoVideoPlaying = true;
    });
    final controller = _infoVideoController;
    if (controller != null && controller.value.isInitialized) {
      controller.play();
      setState(() {});
      return;
    }
    _startMovie();
  }

  void _stopInfoVideo() {
    _infoVideoPlaying = false;
    _infoVideoController?.pause();
    if (_imageFiles.isNotEmpty) {
      _startImageAnimation();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _pauseInfoPlayback() {
    _infoVideoController?.pause();
    _stopImageAnimation();
  }

  void _resumeInfoPlayback() {
    if (_imageFiles.isNotEmpty && !_infoVideoPlaying) {
      _startImageAnimation();
    }
    if (_infoVideoPlaying &&
        !_isSleep &&
        _infoVideo.isNotEmpty &&
        _infoVideoController != null &&
        _infoVideoController!.value.isInitialized) {
      _infoVideoController!.play();
    }
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
    _pauseInfoPlayback();
    _stopGetInfoTimer();
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
    _startGetInfoTimer(isGet: true);
    _resumeInfoPlayback();
  }

  Future<void> _showSleep() async {
    await _getBrightness();
    setState(() {
      _isSleep = true;
    });
    final target = TvUtil.isTelevision
        ? (_currentBrightness * 0.2).clamp(0.05, 0.2)
        : _sleepBrightness;
    await _setBrightness(target);
    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }
    _pauseInfoPlayback();
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

    _sleeptimer = Timer.periodic(const Duration(milliseconds: 10000), (Timer timer) {
      if (AppManager.status == AppStatus.None) {
        _showSleep();
      }
    });
    _resumeInfoPlayback();
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
    if (TvUtil.isTelevision) {
      // TCLアミ: 時計画面は通常の約20%。設定項目は非表示だが処理は使う。
      _isChangeBrightness = true;
      _sleepBrightness = 0.2;
      return;
    }
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
      debugPrint('get brightness failed: $e');
      _currentBrightness = 1.0;
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
      debugPrint('set brightness failed: $e');
    }
  }

  Future<void> _handleIncomingCall(String udid) async {
    if (TvUtil.isTelevision) {
      final life = WidgetsBinding.instance.lifecycleState;
      var screenOn = true;
      try {
        screenOn = await TvUtil.isScreenOn();
      } catch (_) {}
      final auto = AppManager.appsettings['AUTO_RECEIVE'] == '1';
      final waiting = TvUtil.isCallWaitingEnabled;
      final screenOff = !screenOn;
      final watching = waiting && life != AppLifecycleState.resumed;
      print(
          'incoming call life=$life screenOn=$screenOn auto=$auto waiting=$waiting udid=$udid');

      // テレビ電源オフ（スクリーンレス）: 自動応答の有無で分岐
      if (screenOff) {
        if (auto) {
          await TvUtil.acceptIncomingCall(
            callerId: udid,
            callerName: '着信',
          );
        } else {
          await TvUtil.showIncomingCallOverlay(
            callerId: udid,
            callerName: '着信',
          );
        }
        return;
      }

      // 視聴中（アプリが裏）: 着信待機ON時のみ
      if (watching) {
        if (auto) {
          await TvUtil.acceptIncomingCall(
            callerId: udid,
            callerName: '着信',
          );
        } else {
          await TvUtil.showIncomingCallOverlay(
            callerId: udid,
            callerName: '着信',
          );
        }
        return;
      }
    }
    await _receive(udid);
  }

  Future<void> _receive(String udid) async {
    if (_receivingCall) {
      print('[DEBUG PRINT] room receive skipped (already receiving) $udid');
      return;
    }
    _receivingCall = true;
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
    _pauseInfoPlayback();
    _stopGetInfoTimer();
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
    _receivingCall = false;
    _startGetInfoTimer(isGet: true);
    _resumeInfoPlayback();
    if (_isSleep) {
      _setBrightness(TvUtil.isTelevision ? 0.2 : 0.5);
    }
    if (TvUtil.isTelevision) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final restored = await TvUtil.returnToPreviousApp();
      print('[DEBUG PRINT] returnToPreviousApp=$restored');
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
    final messageHeight = TvUtil.isTelevision ? 62.0 : 78.0;
    final messageFontSize = TvUtil.isTelevision ? 39.0 : 39.0;
    final hideMessageForMeasure =
        CheckmeProService.instance.userEnabled ||
            CheckmeRingService.instance.measuring ||
            CheckmeRingService.instance.popupVisible;
    var message = _infoMessage;
    if (_infoMessage.isNotEmpty &&
        _infoMessage.length * messageFontSize < size.width) {
      final addChars =
          ((size.width - (_infoMessage.length * messageFontSize)) /
                  messageFontSize)
              .floor();
      message += List.filled(addChars, '　').join();
    }
    final overlayingMedia = !_isSleep &&
        ((_infoVideo.isNotEmpty &&
                _infoVideoController != null &&
                _infoVideoController!.value.isInitialized) ||
            (_imageFiles.length > _imageFileIndex && _imageFileIndex > -1));
    final barTextColor = overlayingMedia ? Colors.white : Colors.black;
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
                  TvUtil.isTelevision
                      ? Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage(
                                  AppManager.roomImageName(size)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : InkWell(
                          onTap: () {
                            _tap();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image:
                                    AssetImage(AppManager.roomImageName(size)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                if (!_isSleep &&
                    _imageFiles.length > _imageFileIndex &&
                    _imageFileIndex > -1) ...[
                  const IgnorePointer(
                    child: ColoredBox(color: Colors.black),
                  ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(seconds: 1),
                      opacity: _imageOpacity,
                      child: Image.network(
                        '${AppDefine.baseURL}image?path=${_imageFiles[_imageFileIndex]}',
                        width: size.width,
                        height: size.height,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                if (_infoVideoPlaying && !_isSleep)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: (_infoVideoController != null &&
                                _infoVideoController!.value.isInitialized)
                            ? AspectRatio(
                                aspectRatio: _infoVideoController!
                                            .value.aspectRatio ==
                                        0
                                    ? 16 / 9
                                    : _infoVideoController!.value.aspectRatio,
                                child: VideoPlayer(_infoVideoController!),
                              )
                            : const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 16),
                                  Text(
                                    '動画を読み込み中...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                if (!_talking &&
                    TvUtil.isTelevision &&
                    !_isSleep &&
                    AppManager.isPiTvLayout)
                  Positioned(
                    top: 8,
                    right: 8,
                    bottom: 4,
                    width: size.width * 0.18,
                    child: SingleChildScrollView(
                      child: TvRoomSidebar(
                        displayName: connectMyId,
                        hasVideo: _infoVideo.isNotEmpty,
                        videoPlaying: _infoVideoPlaying,
                        onHome: () {},
                        onCall: _tap,
                        onGroupCall: () {
                          AppManager.toast('一斉呼出しは次に移植します',
                              bgColor: Colors.blue);
                        },
                        onVideo: _infoVideoPlaying
                            ? _stopInfoVideo
                            : _playInfoVideo,
                        onHealth: _openHealthPage,
                        onInfo: _openInfoPage,
                        onClock: _showSleep,
                        onSetting: _toSetting,
                        onRing: () {
                          AppManager.toast(
                            CheckmeRingService.instance.measuring
                                ? 'Ring測定中'
                                : '指を入れると自動で測定します',
                            bgColor: Colors.blue,
                          );
                        },
                        onCheckme: () {
                          AppManager.toast('Checkmeは次に移植します',
                              bgColor: Colors.blue);
                        },
                      ),
                    ),
                  ),
                if (!_talking &&
                    TvUtil.isTelevision &&
                    !_isSleep &&
                    !AppManager.isPiTvLayout)
                  Positioned(
                    top: 10,
                    right: 10,
                    width: size.width * 0.15,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TvFocusable(
                          autofocus: !_infoVideoPlaying,
                          enabled: !_infoVideoPlaying,
                          borderRadius: 16,
                          onPressed: _tap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xE01166CC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              '通話する',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (_infoVideo.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _tclSideButton(
                            label: _infoVideoPlaying ? '停止' : '再生',
                            autofocus: _infoVideoPlaying,
                            onPressed: _infoVideoPlaying
                                ? _stopInfoVideo
                                : _playInfoVideo,
                          ),
                        ],
                        const SizedBox(height: 10),
                        _ringCheckmeButtons(),
                        if (CheckmeRingService.instance.popupVisible) ...[
                          const SizedBox(height: 10),
                          IgnorePointer(child: _spo2PopupBox()),
                        ] else if (AndVitalService.instance.popupVisible) ...[
                          const SizedBox(height: 10),
                          const IgnorePointer(child: AndVitalResultPopup()),
                        ],
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
                if (_watching)
                  Positioned(
                    top: 8,
                    left: 8,
                    height: 80,
                    child: Image.asset('assets/images/status/watching.png'),
                  ),
                if (AppManager.isDoctorMode && !_isSleep && !_talking)
                  Positioned(
                    left: 16,
                    bottom: iconSize + messageHeight + 8,
                    child: const IgnorePointer(
                      child: Text(
                        'DOC',
                        style: TextStyle(
                          color: Color(0x99000000),
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: constraints.maxHeight - MediaQuery.of(context).padding.bottom - iconSize,
                  left: 8,
                  right: AppManager.isPiTvLayout
                      ? size.width * 0.18 + 16
                      : max(MediaQuery.of(context).padding.right, 8),
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
                                style: TextStyle(
                                  fontSize: 16,
                                  color: barTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!AppManager.isPiTvLayout)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 10.0, top: 8.0),
                              child: Text(
                                'Ver. $_version',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: barTextColor,
                                ),
                              ),
                            ),
                            TvFocusable(
                              onPressed: () {
                                if (TvUtil.isTelevision) {
                                  _toSetting();
                                }
                              },
                              child: GestureDetector(
                                child: Image.asset(
                                  'assets/images/spana2.png',
                                  width: spanaSize.width,
                                  height: spanaSize.height,
                                ),
                                onTap: TvUtil.isTelevision
                                    ? () => _toSetting()
                                    : null,
                                onLongPressStart: (_) {
                                  print('on long press start');
                                  _toSettingTimer =
                                      Timer(Duration(seconds: 2), () {
                                    _toSetting();
                                  });
                                },
                                onLongPressEnd: (_) {
                                  print('on long press end');
                                  _toSettingTimer?.cancel();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSleep)
                  Focus(
                    autofocus: TvUtil.isTelevision,
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                        _hideSleep();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: InkWell(
                      onTap: () {
                        _hideSleep();
                      },
                      child: Container(
                        color: Colors.black,
                        child: Center(
                          child: Opacity(
                            opacity: TvUtil.isTelevision ? 0.2 : 1.0,
                            child: const ClockWidget(),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_infoMessage.isNotEmpty &&
                    !_infoVideoPlaying &&
                    !hideMessageForMeasure)
                  Positioned(
                    bottom: iconSize + 8,
                    left: 0,
                    right: AppManager.isPiTvLayout ? size.width * 0.18 + 16 : 0,
                    height: messageHeight,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: const Color(0x99000000),
                        child: Marquee(
                          text: message.isEmpty ? '　' : message,
                          blankSpace: 80,
                          velocity: 40,
                          style: TextStyle(
                            color: const Color.fromARGB(255, 180, 220, 140),
                            fontSize: messageFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (AppManager.isPiTvLayout &&
                    !_isSleep &&
                    !_talking &&
                    !_infoVideoPlaying &&
                    AppManager.weatherArea.isNotEmpty)
                  Positioned(
                    left: 10,
                    top: 10,
                    width: size.width * 0.22,
                    child: TvWeatherPanel(state: _weatherState),
                  ),
                if (AppManager.isPiTvLayout &&
                    !_isSleep &&
                    !_talking &&
                    _healthState.hasAny)
                  Positioned(
                    left: 16,
                    top: 16,
                    right: size.width * 0.18 + 24,
                    bottom: iconSize + messageHeight + 16,
                    child: _healthOverlay(),
                  ),
                if (!_talking &&
                    TvUtil.isTelevision &&
                    !_isSleep &&
                    !AppManager.isPiTvLayout &&
                    CheckmeProService.instance.userEnabled)
                  Positioned(
                    left: 5,
                    bottom: 5,
                    width: size.width * 0.43 * 5 / 4,
                    height: size.width * 0.43 * 9 / 16,
                    child: const IgnorePointer(child: CheckmeMonitorPanel()),
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

  Widget _healthOverlay() {
    return Material(
      color: const Color(0xF2F5F5F0),
      borderRadius: BorderRadius.circular(16),
      child: TvHealthQuestions(
        state: _healthState,
        compact: true,
        onSend: (type, time, value) async {
          await TvHealthNotify.instance.send(type, time, value);
          await _pollHealthNotify();
        },
      ),
    );
  }

  Future<void> _openHealthPage() async {
    if (!AppManager.isPiTvLayout) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const TvHealthPage()),
    );
    if (mounted) _pollHealthNotify();
  }

  Future<void> _openInfoPage() async {
    if (!AppManager.isPiTvLayout) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const TvInfoPage()),
    );
  }

  Widget _ringCheckmeButtons() {
    final ringOn = CheckmeRingService.instance.userEnabled;
    final proOn = CheckmeProService.instance.userEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tclSideButton(
          label: 'Ring',
          color: ringOn ? const Color(0xFFC97187) : const Color(0xCC111111),
          textDy: 4,
          onPressed: () {
            BleExclusive.toggleRing();
          },
        ),
        const SizedBox(height: 10),
        _tclSideButton(
          label: proOn ? '閉じる' : 'Checkme',
          textDy: 4,
          onPressed: () {
            BleExclusive.togglePro();
          },
        ),
        const SizedBox(height: 10),
        _tclSideButton(
          label: 'ペアリング',
          textDy: 4,
          onPressed: _openAndVitalPair,
        ),
      ],
    );
  }

  Widget _tclSideButton({
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
    Color color = const Color(0xCC111111),
    double textDy = 0,
  }) {
    return TvFocusable(
      autofocus: autofocus,
      borderRadius: 10,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Transform.translate(
          offset: Offset(0, textDy),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAndVitalPair() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AndVitalPairDialog(),
    );
  }

  Future<void> _openComingSoon(String title) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => TvComingSoonPage(title: title)),
    );
  }

  Widget _spo2PopupBox() {
    final ring = CheckmeRingService.instance;
    const labelSize = 20.0 * 0.8;
    const numSize = 36.0 * 0.85;

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: labelSize,
                color: Color(0xFF111111),
                height: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: numSize,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111111),
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('SpO2(%)', ring.spo2?.toString() ?? '-'),
          row('PRbpm', ring.pulse?.toString() ?? '-'),
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
      //   AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      setState(() {
        _isconnect = true;
      });
      // ステータスと見守り状態の初期同期
      socketservice.io.emit("clients_status", [AppManager.settings['addressGroup']]);
      if (TvUtil.isCallWaitingEnabled) {
        socketservice.flushPendingCall();
      }
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
      final udid = data["info"]["udid"].toString();
      _handleIncomingCall(udid);
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
