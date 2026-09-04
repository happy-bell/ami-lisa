import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/pages/room/room_talk_page.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
import 'package:amiapp/pages/singin/signin_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/address_sync.dart';
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
import '../../widgets/and_vital_result_popup.dart';
import '../../services/tv_health_notify.dart';
import '../../services/tv_info_notify.dart';
import '../../services/tv_message_schedule.dart';
import '../../services/tv_pi_vitals.dart';
import '../../services/tv_vital_serial.dart';
import '../../services/tv_weather.dart';
import '../../widgets/no_camera_banner.dart';
import '../../widgets/tv_pi_address_list.dart';
import '../../widgets/tv_weather_panel.dart';
import '../../widgets/tv_pi_spo2_popup.dart';
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
  Timer? _vitalsTimer;
  Timer? _piStatusTimer;
  TvHealthState _healthState = TvHealthState();
  String _healthDismissedSig = '';
  TvWeatherState? _weatherState;
  TvPiVitalValues _piVitals = TvPiVitalValues();
  final ValueNotifier<bool> _piClientsStatusReady = ValueNotifier(false);
  final FocusNode _piHomeFocus = FocusNode();
  final FocusNode _piVideoCloseFocus = FocusNode();
  /// Ring/Checkme はラベルが「停止」に変わるとウィジェットが作り直されるため、
  /// FocusNode を保持してフォーカスが別ボタンへ飛ばないようにする。
  final FocusNode _piRingFocus = FocusNode();
  final FocusNode _piCheckmeFocus = FocusNode();
  final FocusNode _lisaHomeFocus = FocusNode();
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
  /// お知らせ自動配信の多重起動防止。
  bool _infoPageOpening = false;
  bool _infoVideoStarting = false;
  List<String> _imageFiles = [];
  int _imageFileIndex = -1;
  double _imageOpacity = 0.0;

  final _safetyCheckIds = [];
  bool _safetyRestoreStandby = false;
  bool _watching = false;
  bool _receivingCall = false;
  bool _incomingConnecting = false;
  bool _incomingAborted = false;
  String? _ringingCallerId;
  String? _cancelledCallerId;
  DateTime? _cancelledAt;
  Timer? _incomingOverlayTimer;
  bool _hasUsbCamera = true;
  Timer? _cameraCheckTimer;

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

    // Ring / Checkme はホームのボタンで有効化する（通話していないときも測定する）。
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
      if (playPending && AppManager.isPiTvLayout) {
        AppManager.pendingPlayInfoVideo = false;
        _infoVideoPlaying = true;
        if (AppManager.pendingPlayInfoVideoPath.isNotEmpty) {
          _infoVideo = AppManager.pendingPlayInfoVideoPath;
        }
        AppManager.pendingPlayInfoVideoPath = '';
        if (_infoVideo.isNotEmpty) {
          _startMovie();
          _piFocusVideoClose();
        }
      } else if (playPending) {
        AppManager.pendingPlayInfoVideo = false;
        AppManager.pendingPlayInfoVideoPath = '';
      }

      if (TvUtil.isTelevision && !AppManager.isPiTvLayout) {
        print('isSleep lisa default clock');
        setState(() {
          _isSleep = true;
        });
      } else if (!playPending &&
          !TvUtil.isTelevision &&
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
      if (TvUtil.isTelevision) {
        Peer.warmupTvCamera();
        unawaited(TvVitalSerial.instance.bindOnLogin());
        _startCameraCheck();
      }
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
      _startHealthTimerIfPi();
      unawaited(_refreshUsbCamera());
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

  void _startCameraCheck() {
    if (!TvUtil.isTelevision) return;
    _cameraCheckTimer?.cancel();
    unawaited(_refreshUsbCamera());
    _cameraCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshUsbCamera());
    });
  }

  Future<void> _refreshUsbCamera() async {
    if (!TvUtil.isTelevision || !mounted) return;
    final has = await TvUtil.hasUsbCamera();
    if (!mounted || has == _hasUsbCamera) return;
    setState(() => _hasUsbCamera = has);
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
      if (_receivingCall) return;
      // スマホ切断と「はい」が重なったときのズレを吸収する。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (_wasJustCancelled(callerId) || await TvUtil.wasIncomingCancelled(callerId)) {
        print('[DEBUG PRINT] accept dropped: caller cancelled $callerId');
        await _restoreAfterIncomingGone(callerId);
        return;
      }
      _incomingOverlayTimer?.cancel();
      _incomingOverlayTimer = null;
      _ringingCallerId = null;
      await TvUtil.dismissIncomingCallOverlay();
      if (!mounted) return;
      await _receiveWhenResumed(callerId);
    } else if (action == 'reject') {
      _incomingOverlayTimer?.cancel();
      _ringingCallerId = null;
      await TvUtil.dismissIncomingCallOverlay();
      try {
        socketservice.io.emit("call_reject", [callerId]);
      } catch (_) {}
    } else if (action == 'cancel') {
      await _onIncomingCancelled(callerId);
    }
  }

  void _markIncomingCancelled(String callerId) {
    _cancelledCallerId = callerId;
    _cancelledAt = DateTime.now();
    if (_ringingCallerId == callerId) {
      _incomingAborted = true;
      _ringingCallerId = null;
    }
    _incomingOverlayTimer?.cancel();
    _incomingOverlayTimer = null;
  }

  bool _wasJustCancelled(String callerId) {
    if (_cancelledCallerId != callerId) return false;
    final at = _cancelledAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 8);
  }

  void _armIncomingOverlayTimeout(String callerId) {
    _incomingOverlayTimer?.cancel();
    _incomingOverlayTimer = Timer(const Duration(seconds: 29), () {
      if (_ringingCallerId != callerId) return;
      unawaited(_onIncomingOverlayTimeout(callerId));
    });
  }

  Future<void> _onIncomingOverlayTimeout(String callerId) async {
    if (callerId.isEmpty) return;
    _markIncomingCancelled(callerId);
    await TvUtil.timeoutIncomingCallOverlay(callerId: callerId);
  }

  Future<void> _onIncomingCancelled(String callerId) async {
    if (callerId.isEmpty) return;
    _markIncomingCancelled(callerId);
    await TvUtil.cancelIncomingCallOverlay(callerId: callerId);
  }

  Future<void> _restoreAfterIncomingGone(String callerId) async {
    await TvUtil.dismissIncomingCallOverlay();
    if (!TvUtil.isTelevision) return;
    try {
      final wasOff = await TvUtil.wasScreenOffAtCall();
      if (wasOff) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
        await TvUtil.lockScreenForStandby();
        return;
      }
      await TvUtil.returnToPreviousApp();
    } catch (_) {}
  }

  String? _callerIdFromAppMessage(dynamic data) {
    if (data is! Map) return null;
    final direct = data['udid']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final info = data['info'];
    if (info is Map) {
      final id = info['udid']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// 他アプリ／電源オフ／はい のあと、全面化してから通話開始する。
  Future<void> _receiveWhenResumed(String callerId) async {
    if (_incomingConnecting || _receivingCall) return;
    if (_wasJustCancelled(callerId) || await TvUtil.wasIncomingCancelled(callerId)) {
      await _restoreAfterIncomingGone(callerId);
      return;
    }
    _incomingConnecting = true;
    _incomingAborted = false;
    AppManager.tvForceAccept = true;
    _active = true;
    try {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;
          if (_incomingAborted || _wasJustCancelled(callerId)) {
            await _restoreAfterIncomingGone(callerId);
            return;
          }
          if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (!mounted) return;
      if (_incomingAborted ||
          _wasJustCancelled(callerId) ||
          await TvUtil.wasIncomingCancelled(callerId)) {
        await _restoreAfterIncomingGone(callerId);
        return;
      }
      await _receive(callerId);
    } finally {
      _incomingConnecting = false;
    }
  }

  @override
  void dispose() {
    print('room dispose');
    // socketservice.delegate = null;
    CheckmeRingService.instance.removeListener(_onRingChanged);
    CheckmeProService.instance.removeListener(_onRingChanged);
    AndVitalService.instance.removeListener(_onRingChanged);
    _cameraCheckTimer?.cancel();
    _incomingOverlayTimer?.cancel();
    _healthTimer?.cancel();
    _weatherTimer?.cancel();
    _vitalsTimer?.cancel();
    _piStatusTimer?.cancel();
    _piClientsStatusReady.dispose();
    _piHomeFocus.dispose();
    _piVideoCloseFocus.dispose();
    _piRingFocus.dispose();
    _piCheckmeFocus.dispose();
    _lisaHomeFocus.dispose();
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

  /// 保存済みの一覧を画面に載せたあと、サーバーから取り直す。
  ///
  /// まず手元のものを出すのは、通信を待たせないため。取り直せたら
  /// 差し替える。設定を触らなくても最新の相手が出るようにする。
  void _loadAddress() {
    _loadStoredAddress();
    AddressSync.fetch().then((list) {
      if (list == null || !mounted) return;
      context.read<AddressStore>().setAddressList(list);
    });
  }

  void _loadStoredAddress() {
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
    // ami-EX: 設定ボタンではなくホームを「戻る先」にする。
    // こうしないと ←設定 のあとサイドバーの「設定」を経由する。
    if (AppManager.isPiTvLayout) {
      TvUtil.muteNavSound();
      _piHomeFocus.requestFocus();
    } else if (TvUtil.isTelevision) {
      TvUtil.muteNavSound();
      _lisaHomeFocus.requestFocus();
    }
    _pauseInfoPlayback();
    _stopGetInfoTimer();
    _disconnect();
    context.read<AddressStore>().clear();
    _active = false;
    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }
    if (AppManager.isPiTvLayout) {
      _piHomeFocus.requestFocus();
      TvUtil.unmuteNavSound();
    } else if (TvUtil.isTelevision) {
      _lisaHomeFocus.requestFocus();
      TvUtil.unmuteNavSound();
    }
    await Navigator.of(context, rootNavigator: true).push(
      TvInstantRoute(builder: (_) => const SettingPage()),
    );
    if (!mounted) return;
    TvUtil.muteNavSound();
    if (AppManager.isPiTvLayout) {
      _piHomeFocus.requestFocus();
    } else if (TvUtil.isTelevision) {
      _lisaHomeFocus.requestFocus();
    }
    _active = true;
    socketservice.reconnect = true;
    socketservice.delegate = this;
    socketservice.startConnectTimer();
    _loadAddress();
    if (AppManager.isPiTvLayout) {
      _piClientsStatusReady.value = false;
    }
    setState(() {});
    _startGetInfoTimer(isGet: true);
    _startHealthTimerIfPi();
    _syncCheckmeProForLayout();
    if (_isSleep && AppManager.isPiTvLayout) {
      _hideSleep(requestHomeFocus: false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        TvUtil.unmuteNavSound();
        return;
      }
      if (AppManager.isPiTvLayout) {
        _piHomeFocus.requestFocus();
      } else if (TvUtil.isTelevision) {
        _lisaHomeFocus.requestFocus();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TvUtil.unmuteNavSound();
      });
    });
  }

  void _piFocusHome() {
    if (AppManager.isPiTvLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _piHomeFocus.requestFocus();
      });
      return;
    }
    if (TvUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lisaHomeFocus.requestFocus();
      });
    }
  }

  void _piFocusVideoClose() {
    if (!AppManager.isPiTvLayout) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _infoVideoPlaying) {
        _piVideoCloseFocus.requestFocus();
      }
    });
  }

  void _piGoHome() {
    if (_infoVideoPlaying) {
      _stopInfoVideo();
    }
    if (_isSleep) {
      _hideSleep();
      return;
    }
    _piFocusHome();
  }

  void _syncCheckmeProForLayout() {
    CheckmeProService.instance.start();
    AndVitalService.instance.start();
  }

  void _startHealthTimerIfPi() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _weatherTimer?.cancel();
    _weatherTimer = null;
    _vitalsTimer?.cancel();
    _vitalsTimer = null;
    _piStatusTimer?.cancel();
    _piStatusTimer = null;
    if (!AppManager.isPiTvLayout) return;
    _pollHealthNotify();
    _pollWeather();
    _pollPiVitals();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollHealthNotify();
    });
    // 気象庁の発表は1日3回（05/11/17時）。1分毎は取り過ぎなので10分毎にする。
    // 日付が変わったときの切り替わりも10分以内に反映される。
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _pollWeather();
    });
    _vitalsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _pollPiVitals();
    });
    _piStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_active || _talking || !socketservice.isConnect()) return;
      socketservice.io
          .emit("clients_status", [AppManager.settings['addressGroup']]);
    });
  }

  Future<void> _pollPiVitals() async {
    if (!AppManager.isPiTvLayout || !_active || _talking) return;
    // 46amip4: ドクターモードは自分のバイタル表を出さない。
    if (AppManager.isDoctorMode) {
      if (mounted) {
        setState(() => _piVitals = TvPiVitalValues());
      }
      return;
    }
    final values = await TvPiVitals.instance.fetch();
    values.applyLiveAndKeep(_piVitals);
    if (!mounted) return;
    setState(() => _piVitals = values);
  }

  Future<void> _pollWeather() async {
    if (!AppManager.isPiTvLayout || !_active || _talking) return;
    final state = await TvWeatherService.instance.fetch();
    if (!mounted) return;
    setState(() => _weatherState = state);
  }

  Future<void> _maybeWakeForHealth(TvHealthState state) async {
    if (!TvUtil.isTelevision || !AppManager.isPiTvLayout) return;
    final shouldShow =
        state.hasAny && state.signature != _healthDismissedSig;
    if (!shouldShow) return;
    final life = WidgetsBinding.instance.lifecycleState;
    var screenOn = true;
    try {
      screenOn = await TvUtil.isScreenOn();
    } catch (_) {}
    if (!screenOn || life != AppLifecycleState.resumed) {
      await TvUtil.wakeScreen();
      await TvUtil.bringToFront();
    }
  }

  Future<void> _pollHealthNotify() async {
    if (!AppManager.isPiTvLayout || _talking) return;
    if (!_active && !TvUtil.isTelevision) return;
    final state = await TvHealthNotify.instance.fetch();
    if (!mounted) return;
    await _maybeWakeForHealth(state);
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
      if (TvUtil.isTelevision && mounted) {
        setState(() {});
      }
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

      // 管理画面で配信オフ（video 空）なら必ずクリア。空のとき古い path を残すと
      // メニュー「ビデオ」が消えず、再生も止まらない。
      _infoVideo = nextVideo;
      _isVideoLoop = data['video_loop']?.toString() == '1';

      if (_infoVideo.isEmpty) {
        if (_infoVideoPlaying || currentVideo.isNotEmpty) {
          final wasPlaying = _infoVideoPlaying;
          _infoVideoPlaying = false;
          _stopMovie();
          if (wasPlaying) {
            _piFocusHome();
          }
        }
      } else if (_infoVideoPlaying &&
          !_infoVideoStarting &&
          (currentVideo != _infoVideo || currentVideoLoop != _isVideoLoop) &&
          (_infoVideoController == null ||
              !_infoVideoController!.value.isInitialized)) {
        _startMovie();
      }

      if (AppManager.isPiTvLayout) {
        _healthState = await TvHealthNotify.instance.applyResponse(data);
        await _maybeWakeForHealth(_healthState);
        // お知らせの自動配信。infoTime の時刻になったら電源を入れて
        // お知らせ画面（広報・ハザードマップ）を表示する。
        await _maybeDeliverInfo(_asInfoString(data['infoTime']));
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('getInfo error $e');
    }
  }

  /// お知らせの自動配信。お薬管理と同じく、指定時刻を過ぎたら1日1回だけ
  /// 電源を入れて（画面オフなら）お知らせ画面を前面に出す。
  Future<void> _maybeDeliverInfo(String infoTime) async {
    // 診断用: 受け取った infoTime と前提条件を必ず出す。
    print('[TvInfoNotify] check infoTime="$infoTime" '
        'tv=${TvUtil.isTelevision} pi=${AppManager.isPiTvLayout} '
        'talking=$_talking opening=$_infoPageOpening');
    if (!TvUtil.isTelevision || !AppManager.isPiTvLayout) return;
    if (_talking || _infoPageOpening) return;
    final should = await TvInfoNotify.instance.shouldDeliver(infoTime);
    print('[TvInfoNotify] shouldDeliver=$should');
    if (!should) return;
    if (!mounted) return;

    _infoPageOpening = true;
    try {
      print('[TvInfoNotify] delivering info page infoTime=$infoTime');
      // 画面オフ／他アプリ視聴中でも表示する（お薬管理と同じ流儀）。
      var screenOn = true;
      try {
        screenOn = await TvUtil.isScreenOn();
      } catch (_) {}
      final life = WidgetsBinding.instance.lifecycleState;
      if (!screenOn || life != AppLifecycleState.resumed) {
        await TvUtil.wakeScreen();
        await TvUtil.bringToFront();
        // 前面化が反映されるまで少し待つ。
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      if (!mounted) {
        _infoPageOpening = false;
        return;
      }
      await TvInfoNotify.instance.markDelivered(infoTime);
      await _openInfoPage();
    } catch (e) {
      print('[TvInfoNotify] deliver error $e');
    } finally {
      _infoPageOpening = false;
    }
  }

  void _startImageAnimation() {
    if (TvUtil.isTelevision && !AppManager.isPiTvLayout) {
      return;
    }
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
    if (TvUtil.isTelevision && !AppManager.isPiTvLayout) {
      return;
    }
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
    if (TvUtil.isTelevision && !AppManager.isPiTvLayout) {
      return;
    }
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
      _piFocusVideoClose();
      return;
    }
    _startMovie();
    _piFocusVideoClose();
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
    _piFocusHome();
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
    _piFocusHome();
  }

  Future<void> _piCallAddress(Address user) async {
    if (!AppManager.isPiTvLayout) return;
    if (!socketservice.isConnect()) {
      AppManager.toast("接続されていません。", bgColor: Colors.blue);
      return;
    }
    if (_tapping) return;
    _tapping = true;
    _active = false;
    _pauseInfoPlayback();
    _stopGetInfoTimer();
    AppManager.selectUser = user;
    AppManager.status = AppStatus.Call;

    if (_sleeptimer != null) {
      _sleeptimer!.cancel();
    }

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        pageBuilder: (BuildContext context, Animation<double> animation1,
            Animation<double> animation2) {
          return RoomTalkPage();
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    audio.stopCall();
    audio.stopRingtone();
    _active = true;
    socketservice.delegate = this;
    _tapping = false;
    _startGetInfoTimer(isGet: true);
    _startHealthTimerIfPi();
    _resumeInfoPlayback();
    _piFocusHome();
  }

  Future<void> _piOpenAddressList() async {
    if (!AppManager.isPiTvLayout) return;
    if (!socketservice.isConnect()) {
      AppManager.toast("接続されていません。", bgColor: Colors.blue);
      return;
    }
    try {
      socketservice.io
          .emit("clients_status", [AppManager.settings['addressGroup']]);
    } catch (_) {}
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final familyName = prefs.getString('family_name') ?? '';
    if (!mounted) return;
    final selected = await showGeneralDialog<Address>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '閉じる',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return TvPiAddressListDialog(
          statusReady: _piClientsStatusReady,
          familyName: familyName,
        );
      },
    );
    if (selected == null || !mounted) {
      _piFocusHome();
      return;
    }
    await _piCallAddress(selected);
    if (mounted) _piFocusHome();
  }

  Future<void> _piGroupCall() async {
    if (!AppManager.isPiTvLayout) return;
    final code = AppManager.delegatorCode.isNotEmpty
        ? AppManager.delegatorCode
        : (AppManager.settings['DELEGATORCODE'] ?? '').toString();
    await _piCallAddress(Address(
      id: '@${code}_STAFF',
      name: '一斉呼出し',
      code: code,
      type: 'staff',
      status: 0,
      call: 0,
      called: 0,
      userType: 'S',
      photo: '',
    ));
  }

  void _applyPiClientsStatus(dynamic statuses, {bool markReady = true}) {
    if (!AppManager.isPiTvLayout || statuses is! Map) return;
    if (markReady && !_piClientsStatusReady.value) {
      _piClientsStatusReady.value = true;
    }
    if (!mounted) return;
    final store = context.read<AddressStore>();
    statuses.forEach((udid, value) {
      dynamic status;
      if (value is Map) {
        status = value['status'];
      } else {
        status = value;
      }
      if (status == null) return;
      try {
        store.setAddressStatus(udid.toString(), status.toString());
      } catch (e) {
        print('[PiStatus] $udid $e');
      }
    });
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

  void _hideSleep({bool requestHomeFocus = true}) {
    if (_isChangeBrightness) {
      _setBrightness(_currentBrightness);
    }
    setState(() {
      _isSleep = false;
    });
    // ami-LiSA: 時計を閉じたら見守りも終了（従来どおり）。
    // ami-EX: ホームでも見守りするため、ここでは切らない。
    if (!AppManager.isPiTvLayout && _safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_stop", []);
      _safetyCheckIds.clear();
      peer.close();
    }

    _sleeptimer?.cancel();
    _sleeptimer = null;
    // TV（ami-LiSA / ami-EX）の時計は手動入退出のみ。ホームに戻ったあと
    // 10秒で再入場しない。
    if (!TvUtil.isTelevision) {
      _sleeptimer =
          Timer.periodic(const Duration(milliseconds: 10000), (Timer timer) {
        if (AppManager.status == AppStatus.None) {
          _showSleep();
        }
      });
    }
    _resumeInfoPlayback();
    if (requestHomeFocus) {
      _piFocusHome();
    }
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
      await TvUtil.captureForegroundApp();
      final life = WidgetsBinding.instance.lifecycleState;
      var screenOn = true;
      try {
        screenOn = await TvUtil.isScreenOn();
      } catch (_) {}
      var standby = false;
      try {
        standby = await TvUtil.isTvStandby();
      } catch (_) {}
      // 着信ごとに、その時点の画面オフ状態を正確に記録(wake前)。
      // 電源オフ着信のみ通話終了後に電源オフへ戻し、電源オン着信では戻さない。
      // Android 12(TV007)は電源オフでも stayawake のため isScreenOn だけでは
      // 足りない。TCLスクリーンレス判定(standby)を OR で見る。
      await TvUtil.setScreenOffAtCall(!screenOn || standby);
      final auto = AppManager.appsettings['AUTO_RECEIVE'] == '1';
      final waiting = TvUtil.isCallWaitingEnabled;
      final screenOff = !screenOn || standby;
      final watching = waiting && life != AppLifecycleState.resumed;
      print(
          'incoming call life=$life screenOn=$screenOn standby=$standby auto=$auto waiting=$waiting udid=$udid');

      // 自動応答オフ: 地デジ／他アプリ／電源オフ／ホームでもはい・いいえ。
      if (!auto) {
        _incomingAborted = false;
        _ringingCallerId = udid;
        _armIncomingOverlayTimeout(udid);
        await TvUtil.showIncomingCallOverlay(
          callerId: udid,
          callerName: '着信中',
        );
        return;
      }

      // 自動応答オン: 電源オフ／視聴中は確認なし。ホームは従来どおり接続。
      if (screenOff || watching) {
        if (AppManager.isPiTvLayout) {
          await TvUtil.wakeScreen();
          await TvUtil.bringToFront();
          await _receiveWhenResumed(udid);
          return;
        }
        await TvUtil.acceptIncomingCall(
          callerId: udid,
          callerName: '着信中',
        );
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
    if (_isSleep && (AppManager.isPiTvLayout || !TvUtil.isTelevision)) {
      _setBrightness(0.8);
    }
    _safetyCheckEnd(restoreTv: false);
    if (AppManager.isPiTvLayout) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
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
    if (_isSleep && (AppManager.isPiTvLayout || !TvUtil.isTelevision)) {
      _setBrightness(TvUtil.isTelevision ? 0.2 : 0.5);
    }
    if (TvUtil.isTelevision) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      // 着信時にTV電源オフ(画面オフ)だった場合は、直前アプリ(地デジ/Netflix等)への
      // 復帰より「電源オフに戻す」を優先する。地デジ等へ戻してしまうと要件と逆になる。
      final wasOff = await TvUtil.wasScreenOffAtCall();
      if (wasOff) {
        // 地デジ→電源オフ→着信→通話。終了後は地デジへ戻さず電源オフ。
        try {
          await WakelockPlus.disable();
        } catch (_) {}
        final locked = await TvUtil.lockScreenForStandby();
        print('[DEBUG PRINT] standby wasOff=true locked=$locked');
        return;
      }
      // 地デジ→着信→通話。終了後は地デジへ戻す。
      final restored = await TvUtil.returnToPreviousApp();
      print('[DEBUG PRINT] returnToPreviousApp=$restored');
      if (!restored) {
        _resumeInfoPlayback();
        if (AppManager.isPiTvLayout) _piFocusHome();
      }
    } else {
      _resumeInfoPlayback();
    }
  }

  void _receiveSafetyCheck(String udid) {
    if (_safetyCheckIds.isNotEmpty) {
      socketservice.io.emit("safety_check_error", [udid]);
      return;
    }
    // 非TVは従来どおり（安眠モードONかつ時計画面）。
    // TV（ami-LiSA / ami-EX）は電源オフ・地デジ・Netflix/YouTube 中でも受ける。
    if (!TvUtil.isTelevision && !AppManager.isPiTvLayout) {
      if (AppManager.appsettings['SLEEP_MODE'] != '1' || !_isSleep) {
        socketservice.io.emit("safety_check_error", [udid]);
        return;
      }
    }
    _safetyCheckIds.add(udid);
    unawaited(_beginSafetyCheck(udid));
  }

  Future<void> _beginSafetyCheck(String udid) async {
    if (TvUtil.isTelevision) {
      var screenOn = true;
      var standby = false;
      try {
        screenOn = await TvUtil.isScreenOn();
      } catch (_) {}
      try {
        standby = await TvUtil.isTvStandby();
      } catch (_) {}
      _safetyRestoreStandby = !screenOn || standby;
      if (!_safetyRestoreStandby) {
        try {
          await TvUtil.captureForegroundApp();
        } catch (_) {}
      }
      try {
        await TvUtil.wakeScreen();
        await TvUtil.bringToFront();
        for (final delay in const [300, 800, 1600, 2800]) {
          await Future<void>.delayed(Duration(milliseconds: delay));
          if (!_safetyCheckIds.contains(udid)) return;
          await TvUtil.bringToFront();
        }
      } catch (e) {
        debugPrint('safety check wake: $e');
      }
      if (mounted) setState(() {});
    }
    if (!_safetyCheckIds.contains(udid)) return;
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

  void _safetyCheckEnd({bool restoreTv = true}) {
    final had = _safetyCheckIds.isNotEmpty;
    final restoreStandby = _safetyRestoreStandby;
    if (had) {
      socketservice.io.emit("safety_check_stop", []);
    }
    _safetyCheckIds.clear();
    _safetyRestoreStandby = false;
    _disposePeer();
    if (AppManager.isPiTvLayout && _watching) {
      _watching = false;
    }
    if (mounted) setState(() {});
    _initPeer();
    if (had && restoreTv && TvUtil.isTelevision) {
      unawaited(_restoreAfterSafety(restoreStandby));
    }
  }

  Future<void> _restoreAfterSafety(bool toPowerOff) async {
    try {
      await TvUtil.restoreAfterSafety(toPowerOff: toPowerOff);
    } catch (e) {
      debugPrint('restore after safety: $e');
    }
  }

  Future<void> _onCallButton() async {
    _safetyCheckEnd(restoreTv: false);
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
    final piDisplayName = () {
      final name = (AppManager.settings['MCSNAME'] ?? '').toString().trim();
      return name.isEmpty ? connectMyId : name;
    }();
    final piSidebarW = size.width * 0.15;
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
    Color messageColor = const Color.fromARGB(255, 180, 220, 140);
    var messageAllowed = true;
    TvMessageSlot? clockSlot;
    if (TvUtil.isTelevision) {
      final slot = TvMessageSchedule.activeAt(DateTime.now());
      messageAllowed = slot != null;
      if (slot != null) {
        messageColor = slot.color;
      }
      clockSlot = TvMessageSchedule.activeAt(
        DateTime.now(),
        key: TvMessageSchedule.clockKey,
      );
      // EX 時計モードのメッセージは、時計と同じ緑の明るさにする。
      if (AppManager.isPiTvLayout && _isSleep) {
        if (clockSlot != null) {
          messageColor = clockSlot.color;
        } else if (slot != null) {
          messageColor = TvMessageSchedule.colorAt(
            slot.colorIndex,
            key: TvMessageSchedule.clockKey,
          );
        }
      }
    }
    final piMessageVisible = AppManager.isPiTvLayout &&
        _infoMessage.isNotEmpty &&
        messageAllowed &&
        !hideMessageForMeasure &&
        (!_infoVideoPlaying || _isSleep);
    final piFooterH = piMessageVisible ? messageHeight : 0.0;
    final overlayingMedia = !_isSleep &&
        ((_infoVideo.isNotEmpty &&
                _infoVideoController != null &&
                _infoVideoController!.value.isInitialized) ||
            (_imageFiles.length > _imageFileIndex && _imageFileIndex > -1));
    final lisaClockHome =
        TvUtil.isTelevision && !AppManager.isPiTvLayout && !_talking;
    final barTextColor =
        (overlayingMedia || lisaClockHome) ? Colors.white : Colors.black;
    print(MediaQuery.of(context).padding.left);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const Material(color: Colors.white),
                if (!_talking &&
                    TvUtil.isTelevision &&
                    !AppManager.isPiTvLayout)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black,
                        child: (clockSlot == null &&
                                _safetyCheckIds.isEmpty)
                            ? const SizedBox.shrink()
                            : ClockWidget(
                                color: clockSlot?.color,
                                watching: _safetyCheckIds.isNotEmpty,
                              ),
                      ),
                    ),
                  )
                else if (!_talking)
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
                    _imageFileIndex > -1 &&
                    AppManager.isPiTvLayout) ...[
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
                if (_infoVideoPlaying && !_isSleep && AppManager.isPiTvLayout)
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
                    !AppManager.isPiTvLayout)
                  Positioned(
                    top: 8,
                    right: 8,
                    width: size.width * 0.15,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tclSideButton(
                          label: 'ホーム',
                          autofocus: true,
                          focusNode: _lisaHomeFocus,
                          onPressed: () {
                            _lisaHomeFocus.requestFocus();
                          },
                        ),
                        _tclSideButton(
                          label: '通話する',
                          onPressed: _tap,
                        ),
                        _tclSideButton(
                          label: '設定',
                          onPressed: _toSetting,
                        ),
                        if (!_hasUsbCamera)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: NoCameraBanner(compact: true),
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
                if (_watching &&
                    !AppManager.isPiTvLayout &&
                    !TvUtil.isTelevision)
                  Positioned(
                    top: 8,
                    left: 8,
                    height: 80,
                    child: Image.asset('assets/images/status/watching.png'),
                  ),
                if (AppManager.isPiTvLayout &&
                    AppManager.isDoctorMode &&
                    !_isSleep &&
                    !_talking)
                  Positioned(
                    left: 8,
                    bottom: piFooterH,
                    height: iconSize,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.translate(
                          offset: const Offset(0, 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Doc',
                                style: TextStyle(
                                  color: Color(0x99000000),
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Transform.translate(
                                offset: const Offset(10, -5),
                                child: Text(
                                  AppManager.loginId,
                                  style: const TextStyle(
                                    color: Color(0x99000000),
                                    fontSize: 42 * 0.8 * 0.8,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!AppManager.isPiTvLayout)
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
                                style: TextStyle(
                                  fontSize: 16,
                                  color: barTextColor,
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
                                style: TextStyle(
                                  fontSize: 16,
                                  color: barTextColor,
                                ),
                              ),
                            ),
                            if (!TvUtil.isTelevision)
                              GestureDetector(
                                child: Image.asset(
                                  'assets/images/spana2.png',
                                  width: spanaSize.width,
                                  height: spanaSize.height,
                                ),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSleep &&
                    (AppManager.isPiTvLayout || !TvUtil.isTelevision))
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
                          child: !TvUtil.isTelevision
                              ? const ClockWidget()
                              : (clockSlot == null
                                  ? const SizedBox.shrink()
                                  : ClockWidget(color: clockSlot.color)),
                        ),
                      ),
                    ),
                  ),
                if (_watching && AppManager.isPiTvLayout)
                  Positioned(
                    top: 8,
                    left: 8,
                    height: 80,
                    child: IgnorePointer(
                      child: Image.asset('assets/images/status/watching.png'),
                    ),
                  ),
                if (_infoMessage.isNotEmpty &&
                    messageAllowed &&
                    !hideMessageForMeasure &&
                    (!_infoVideoPlaying ||
                        (AppManager.isPiTvLayout && _isSleep)))
                  Positioned(
                    bottom: AppManager.isPiTvLayout ? 0 : iconSize + 8,
                    left: 0,
                    right: AppManager.isPiTvLayout ? 0 : 0,
                    height: messageHeight,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: const Color(0x99000000),
                        child: Marquee(
                          text: message.isEmpty ? '　' : message,
                          blankSpace: 80,
                          velocity: 40,
                          style: TextStyle(
                            color: messageColor,
                            fontSize: messageFontSize,
                            fontWeight: FontWeight.bold,
                          ),
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
                    bottom: 8,
                    width: piSidebarW,
                    child: ExcludeFocus(
                      excluding: _piHealthFullscreen,
                      child: TvRoomSidebar(
                      displayName: piDisplayName,
                      hasVideo: _infoVideo.isNotEmpty,
                      videoPlaying: _infoVideoPlaying,
                      onHome: _piGoHome,
                      onCall: _piOpenAddressList,
                      onGroupCall: _piGroupCall,
                      onVideo: _infoVideoPlaying
                          ? _stopInfoVideo
                          : _playInfoVideo,
                      onHealth: _openHealthPage,
                      onInfo: () => _openInfoPage(autoPlayAudio: false),
                      onClock: _showSleep,
                      onSetting: _toSetting,
                      showNoCamera: !_hasUsbCamera,
                      homeFocusNode: _piHomeFocus,
                      videoFocusNode: _piVideoCloseFocus,
                      ringFocusNode: _piRingFocus,
                      checkmeFocusNode: _piCheckmeFocus,
                      onRing: () {
                        BleExclusive.toggleRing();
                      },
                      onCheckme: () {
                        BleExclusive.togglePro();
                      },
                      showVitals: !AppManager.isDoctorMode,
                      bpHigh: _piVitals.bp1,
                      bpLow: _piVitals.bp2,
                      bpPulse: _piVitals.bp4,
                      temp: _piVitals.bt1,
                      weight: _piVitals.bw1,
                      roomTemp: _piVitals.temp,
                      roomHum: _piVitals.pressure,
                      spo2: _piVitals.spo2,
                      pr: _piVitals.spo2Pr,
                      hr: _piVitals.hr,
                      pi: _piVitals.pi,
                    ),
                    ),
                  ),
                if (AppManager.isPiTvLayout &&
                    !_isSleep &&
                    !_talking &&
                    !_infoVideoPlaying &&
                    !_piHealthFullscreen &&
                    AppManager.weatherArea.isNotEmpty)
                  Positioned(
                    left: 10,
                    top: 10,
                    width: size.width * 0.22,
                    child: TvWeatherPanel(state: _weatherState),
                  ),
                if (!_talking &&
                    TvUtil.isTelevision &&
                    !_isSleep &&
                    CheckmeProService.instance.userEnabled &&
                    !_piHealthFullscreen)
                  Positioned(
                    left: 5,
                    bottom: AppManager.isPiTvLayout ? 5 + piFooterH : 5,
                    width: size.width * 0.43 * 5 / 4,
                    height: size.width * 0.43 * 9 / 16,
                    child: const IgnorePointer(child: CheckmeMonitorPanel()),
                  ),
                if (AppManager.isPiTvLayout &&
                    !_talking &&
                    !_isSleep &&
                    !_piHealthFullscreen &&
                    (CheckmeRingService.instance.userEnabled ||
                        CheckmeRingService.instance.popupVisible))
                  Positioned(
                    right: TvPiSpo2Popup.rightInset(piSidebarW),
                    bottom: TvPiSpo2Popup.bottomInset(
                        messageHeight: messageHeight),
                    child: IgnorePointer(
                      child: TvPiSpo2Popup(
                        spo2: CheckmeRingService.instance.spo2?.toString() ?? '-',
                        pr: CheckmeRingService.instance.pulse?.toString() ?? '-',
                      ),
                    ),
                  )
                else if (AppManager.isPiTvLayout &&
                    !_talking &&
                    !_isSleep &&
                    !_piHealthFullscreen &&
                    AndVitalService.instance.popupVisible)
                  Positioned(
                    right: TvPiSpo2Popup.rightInset(piSidebarW),
                    top: size.height * 0.22,
                    child: const IgnorePointer(child: AndVitalResultPopup()),
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
                if (_piHealthFullscreen)
                  Positioned.fill(
                    child: _healthOverlay(),
                  ),
              ],
            );
          }
      ),
    );
  }

  bool get _piHealthFullscreen {
    if (!AppManager.isPiTvLayout || _talking) return false;
    if (!_healthState.hasAny) return false;
    return _healthState.signature != _healthDismissedSig;
  }

  Widget _healthOverlay() {
    return Material(
      color: const Color(0xFFF5F5F0),
      child: SafeArea(
        // 健康管理中は裏のホームメニューへフォーカスが逃げない
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: true,
          child: TvHealthQuestions(
            state: _healthState,
            compact: true,
            title: '健康管理・お薬管理・デイサービス',
            onBack: () {
              setState(() {
                _healthDismissedSig = _healthState.signature;
              });
              _piFocusHome();
            },
            onSend: (type, time, value) async {
              await TvHealthNotify.instance.send(type, time, value);
              if (!mounted) return;
              // デイサービス「確認した」→ メッセージ消去＆全画面を閉じる
              if (type == 'dayservice') {
                setState(() {
                  _healthState.showDayService = false;
                  _healthState.showDayServiceCheck = false;
                  _healthState.dayServiceText = '';
                  _healthDismissedSig = _healthState.signature;
                });
                _piFocusHome();
                await _pollHealthNotify();
                if (!mounted) return;
                // ポーリング後のシグネチャでも閉じたままにする
                setState(() {
                  _healthDismissedSig = _healthState.signature;
                });
                return;
              }
              await _pollHealthNotify();
              if (!mounted) return;
              if (!_healthState.hasAny) {
                setState(() {
                  _healthDismissedSig = _healthState.signature;
                });
                _piFocusHome();
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openHealthPage() async {
    if (!AppManager.isPiTvLayout) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const TvHealthPage()),
    );
    if (mounted) _pollHealthNotify();
    _piFocusHome();
  }

  /// 広報配信ページを開く。[autoPlayAudio] は音声のみのお知らせの自動再生可否。
  /// 時間指定の自動配信は true、ホームの「広報配信」ボタンからは false。
  Future<void> _openInfoPage({bool autoPlayAudio = true}) async {
    if (!AppManager.isPiTvLayout) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TvInfoPage(autoPlayAudio: autoPlayAudio),
      ),
    );
    _piFocusHome();
  }

  Widget _tclSideButton({
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
    bool enabled = true,
    Color color = Colors.black,
    double textDy = 0,
    double fontSize = 22,
    double radius = 10,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: 6),
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _LisaHomeMenuButton(
        label: label,
        onPressed: onPressed,
        autofocus: autofocus,
        enabled: enabled,
        color: color,
        textDy: textDy,
        fontSize: fontSize,
        radius: radius,
        padding: padding,
        focusNode: focusNode,
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
      _applyPiClientsStatus(statuses);
      if (statuses is Map && statuses.containsKey(AppManager.myId)) {
        final mine = statuses[AppManager.myId];
        try {
          final sc = mine['safetyCheck'];
          if (sc is List && sc.isNotEmpty) {
            setState(() { _watching = true; });
          } else if (AppManager.isPiTvLayout &&
              (_watching || _safetyCheckIds.isNotEmpty)) {
            _safetyCheckEnd();
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
    else if (message == 'call_cancel') {
      final udid = _callerIdFromAppMessage(data);
      if (udid == null) return;
      unawaited(_onIncomingCancelled(udid));
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
        if (AppManager.isPiTvLayout) {
          _safetyCheckEnd();
        } else {
          setState(() { _watching = false; });
        }
      }
    }
    else if (AppManager.isPiTvLayout && message == 'login') {
      final client = data['info']?['client'];
      if (client is Map && client['udid'] != null) {
        _applyPiClientsStatus({client['udid']: client}, markReady: false);
      }
    }
    else if (AppManager.isPiTvLayout && message == 'status_change') {
      final info = data['info'];
      if (info is Map && info['MYID'] != null && info['STATUS'] != null) {
        _applyPiClientsStatus(
          {info['MYID']: {'status': info['STATUS']}},
          markReady: false,
        );
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

/// ami-LiSA ホーム右メニュー。背景はホームと同じ黒、透過 60%。
/// フォーカス時の塗りは RGB(80,82,147)。EX のサイドバーは変えない。
class _LisaHomeMenuButton extends StatefulWidget {
  const _LisaHomeMenuButton({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.enabled = true,
    this.color = Colors.black,
    this.textDy = 0,
    this.fontSize = 22,
    this.radius = 10,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
    this.focusNode,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool enabled;
  final Color color;
  final double textDy;
  final double fontSize;
  final double radius;
  final EdgeInsets padding;
  final FocusNode? focusNode;

  @override
  State<_LisaHomeMenuButton> createState() => _LisaHomeMenuButtonState();
}

class _LisaHomeMenuButtonState extends State<_LisaHomeMenuButton> {
  bool _focused = false;
  FocusNode? _externalNode;
  static const _focusColor = Color.fromARGB(255, 80, 82, 147);

  @override
  void initState() {
    super.initState();
    _listen(widget.focusNode);
  }

  @override
  void didUpdateWidget(_LisaHomeMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _listen(widget.focusNode);
    }
    final has = widget.focusNode?.hasFocus;
    if (has != null && has != _focused) {
      _focused = has;
    }
  }

  @override
  void dispose() {
    _externalNode?.removeListener(_onExternalFocus);
    super.dispose();
  }

  void _listen(FocusNode? node) {
    _externalNode?.removeListener(_onExternalFocus);
    _externalNode = node;
    _externalNode?.addListener(_onExternalFocus);
    final has = node?.hasFocus;
    if (has != null) {
      _focused = has;
    }
  }

  void _onExternalFocus() {
    final has = _externalNode?.hasFocus ?? false;
    if (!mounted || has == _focused) return;
    setState(() => _focused = has);
  }

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: widget.padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (_focused ? _focusColor : widget.color).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: Transform.translate(
        offset: Offset(0, widget.textDy),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (!TvUtil.isTelevision) {
      return GestureDetector(onTap: widget.onPressed, child: child);
    }

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onFocusChange: (hasFocus) {
        if (_focused != hasFocus) {
          setState(() => _focused = hasFocus);
        }
      },
      onKeyEvent: (node, event) {
        if (!widget.enabled) return KeyEventResult.ignored;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(onTap: widget.onPressed, child: child),
    );
  }
}
