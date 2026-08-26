import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';

enum SignalingState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

typedef SignalingStateCallback = void Function(String id, RTCSignalingState state);
typedef StreamStateCallback = void Function(MediaStream stream);
typedef RemoteStreamStateCallback = void Function(String id, MediaStream stream);
typedef IceCandidateCallback = void Function(String id, dynamic event);
typedef OtherEventCallback = void Function(dynamic event);
typedef DataChannelMessageCallback = void Function(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef DataChannelCallback = void Function(RTCDataChannel dc);

class Peer {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  final _remoteCandidates = {};
  final Map<String, bool> _iceStable = {};
  // var _turnCredential;

  bool _emeetCapture = false;
  bool _closed = false;
  MediaStream? _localStream;
  set localStream(value) => _localStream = value;
  // 互換用: 旧コードが peer.setLocalStream(stream) を呼ぶ場合に備える
  void setLocalStream(MediaStream stream) {
    _localStream = stream;
  }
  final List<MediaStream> _remoteStreams = [];
  SignalingStateCallback? onStateChange;
  StreamStateCallback? onLocalStream;
  RemoteStreamStateCallback? onAddRemoteStream;
  RemoteStreamStateCallback? onRemoveRemoteStream;
  OtherEventCallback? onAnswer;
  OtherEventCallback? onOffer;
  IceCandidateCallback? onIceCandidate;
  OtherEventCallback? onPeersUpdate;
  OtherEventCallback? onEventUpdate;
  DataChannelMessageCallback? onDataChannelMessage;
  DataChannelCallback? onDataChannel;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  static Future<void>? _tvWarmup;

  /// 起動直後の USB カメラ初回オープン失敗を避ける。
  /// TCL では映像を開きっぱなしにすると WebRTC ネイティブが落ちる／ANR になるため、
  /// 開いてすぐ閉じ、通話時に開き直す。
  static Future<void> warmupTvCamera() {
    _tvWarmup ??= _warmupTvCameraOnce();
    return _tvWarmup!;
  }

  static Future<void> _warmupTvCameraOnce() async {
    if (!TvUtil.isTelevision) return;
    try {
      print('[TV] camera warmup start');
      await navigator.mediaDevices.enumerateDevices();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': true,
      });
      for (final t in stream.getTracks()) {
        try {
          t.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
      print('[TV] camera warmup done');
    } catch (e) {
      print('[TV] camera warmup: $e');
    }
  }

  static Future<void> _waitForLocalVideoLive(MediaStream stream) async {
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return;
    final track = tracks.first;
    try {
      track.enabled = true;
    } catch (_) {}
    final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final settings = track.getSettings();
        final w = settings['width'];
        if (w is num && w.toDouble() > 0) {
          print('[TV] local video live ${w}x${settings['height']}');
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    print('[TV] local video live wait timed out (continue)');
  }

  String get sdpSemantics => 'unified-plan';
  // String get sdpSemantics => 'plan-b';
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
       */
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  /// close() で立てた旗を下ろし、また接続できるようにする。
  ///
  /// close() は通話が終わったあとに紛れ込む接続要求を弾くためのもので、
  /// テレビでUSBカメラが開きっぱなしになるのを防いでいる。
  /// ただし**保留は通話の終わりではない**。保留から戻るときや
  /// 三者通話へ移るときは、ここを通してから繋ぎ直す必要がある。
  void reopen() {
    if (!_closed) return;
    print('peer reopen');
    _closed = false;
  }

  void close() {
    _closed = true;
    if (TvUtil.isTelevision) {
      TvUtil.usbMicStop();
    }
    final stream = _localStream;
    _localStream = null;
    _emeetCapture = false;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.enabled = false;
        } catch (_) {}
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        stream.dispose();
      } catch (_) {}
    }

    if (peerConnection != null) {
      peerConnection!.close();
      peerConnection!.dispose();
    }

    _peerConnections.forEach((key, pc) {
      pc.close();
      pc.dispose();
    });

    _peerConnections.clear();
    _iceStable.clear();

    // if (this.onStateChange != null) {
    //   this.onStateChange(SignalingState.CallStateBye);
    // }
    _remoteCandidates.clear();
  }

  /// 張ってある接続をすべて閉じる。カメラとマイクは止めない。
  ///
  /// 三者通話から二者通話へ戻るときに使う。閉じずに残すと、
  /// ICEの状態が「確立済み」のまま居座り、次に繋ぎ直したときの
  /// 通信候補がすべて `ignore late ice` で捨てられて映像が固まる。
  void closeAllConnections() {
    print('peer closeAllConnections (${_peerConnections.length})');
    _peerConnections.forEach((key, pc) {
      try {
        pc.close();
        pc.dispose();
      } catch (_) {}
    });
    _peerConnections.clear();
    _iceStable.clear();
    _remoteCandidates.clear();
  }

  void closeOne(String id) {
    print('peer closeOne $id');
    if (_peerConnections[id] != null) {
      _peerConnections[id]!.close();
      _peerConnections[id]!.dispose();
      _peerConnections.remove(id);
    }
    _iceStable.remove(id);
  }

  void setAudioEnabled(bool value) {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks();
    if (tracks.isEmpty) {
      print('setAudioEnabled($value): no audio tracks');
      return;
    }
    for (final track in tracks) {
      track.enabled = value;
      print('setAudioEnabled($value) track=${track.id} enabled=${track.enabled}');
    }
  }

  void enableSpeaker(bool val) {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks();
    if (tracks.isEmpty) return;
    // TVではスピーカーフォン切替をスキップ（USBマイク送信に影響する場合がある）
    if (TvUtil.isTelevision) {
      print('enableSpeaker skipped on TV');
      return;
    }
    try {
      tracks[0].enableSpeakerphone(val);
      print(tracks[0].muted);
    } catch (e) {
      print('enableSpeaker failed: $e');
    }
  }

  void switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().firstWhere((track) => track.kind == 'video');
      await Helper.switchCamera(videoTrack);
    }
  }

  void receiveOffer(String peerId, String sdp, [String media = 'video']) {
    _createPeerConnection(peerId, media, true).then((pc) {
      print('**************************************************************');
      print('_createPeerConnectioned');
      print('**************************************************************');
      _peerConnections[peerId] = pc;
      _receiveOffer(peerId, pc, sdp);
    });
  }

  void receiveAnswer(String peerId, String sdp) {
    _receiveAnswer(peerId, sdp);
  }

  void receiveIceCandidate(String peerId, Map<String, dynamic> candidateMap) async {
    if (_iceStable[peerId] == true) {
      print('ignore late ice $peerId');
      return;
    }
    var pc = _peerConnections[peerId];

    print("receive ice $peerId");
    print(candidateMap);

    RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex']);
    if (pc != null) {
      await pc.addCandidate(candidate);
    } else {
      print('ice collect');
      if (_remoteCandidates[peerId] == null) {
        _remoteCandidates[peerId] = [];
      }
      _remoteCandidates[peerId].add(candidate);
    }
  }

  void invite(String peerId, String media, useScreen) {
    if (AppManager.isPiTvLayout && _closed) {
      print('peer invite skipped (closed)');
      return;
    }
    _createPeerConnection(peerId, media, useScreen, isHost: true).then((pc) {
      if (AppManager.isPiTvLayout && _closed) {
        try {
          pc.close();
          pc.dispose();
        } catch (_) {}
        return;
      }
      _peerConnections[peerId] = pc;
      _createOffer(peerId, pc, media);
    }).catchError((e) {
      print('peer invite failed: $e');
    });
  }

  Future<String?> _preferUsbAudioDeviceId() async {
    // flutter_webrtc の enumerateDevices は USB 入力を列挙しない。
    // ネイティブ AudioManager から USB を取る。
    final nativeId = await TvUtil.findUsbAudioDeviceId();
    if (nativeId != null && nativeId.isNotEmpty) {
      print('preferred audioinput (native USB): $nativeId');
      return nativeId;
    }
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      print('=== media devices (${devices.length}) ===');
      MediaDeviceInfo? anyAudio;
      for (final d in devices) {
        print('device kind=${d.kind} label=${d.label} id=${d.deviceId}');
        if (d.kind != 'audioinput') continue;
        anyAudio ??= d;
      }
      if (anyAudio != null) {
        print(
            'preferred audioinput (fallback): ${anyAudio.label} (${anyAudio.deviceId})');
        return anyAudio.deviceId;
      }
    } catch (e) {
      print('enumerateDevices failed: $e');
    }
    return null;
  }

  Future<void> _tuneEmeetSender(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind != 'video') continue;
        final params = sender.parameters;
        params.degradationPreference =
            RTCDegradationPreference.MAINTAIN_RESOLUTION;
        final encodings = params.encodings;
        if (encodings != null) {
          for (final enc in encodings) {
            enc.maxFramerate = 30;
            enc.maxBitrate = 3500000;
            enc.minBitrate = 800000;
            enc.scaleResolutionDownBy = 1.0;
          }
        }
        await sender.setParameters(params);
        print('EMEET sender tuned fps=30 maxBr=3500k maintainResolution');
      }
    } catch (e) {
      print('EMEET sender tune failed: $e');
    }
  }

  Future<void> _stopStream(MediaStream stream) async {
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Map<String, dynamic> _emeetVideoConstraints(int w, int h, int fps) {
    return {
      'width': w,
      'height': h,
      'frameRate': fps,
      'mandatory': {
        'minWidth': '$w',
        'minHeight': '$h',
        'minFrameRate': '$fps',
      },
      'optional': [],
    };
  }

  Future<MediaStream> _attachEmeetAudio(MediaStream video) async {
    try {
      final audio = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      for (final track in audio.getAudioTracks()) {
        await video.addTrack(track);
      }
      try {
        await audio.dispose();
      } catch (_) {}
    } catch (e) {
      print('EMEET audio attach failed: $e');
    }
    return video;
  }

  /// EMEET C960: ネイティブ 1080p30。640x360+PRIVATE は HAL ENOSYS。
  /// 波うちの主因は 50Hz 既定の電源周波数。先に UVC で 60Hz を指定する。
  /// 映像を先に開き、その後マイクを足して USB 同時ネゴを避ける。
  Future<MediaStream> _openEmeetStream() async {
    try {
      final af = await TvUtil.setUvcAntiFlicker60();
      print('EMEET uvc anti-flicker 60Hz: $af');
    } catch (e) {
      print('EMEET uvc anti-flicker failed: $e');
    }
    const attempts = <Map<String, int>>[
      {'w': 1920, 'h': 1080, 'fps': 30},
      {'w': 1280, 'h': 720, 'fps': 30},
      {'w': 960, 'h': 720, 'fps': 30},
      {'w': 800, 'h': 600, 'fps': 30},
    ];
    MediaStream? lastAudio;
    for (final a in attempts) {
      try {
        print('EMEET getUserMedia video-only ${a['w']}x${a['h']}@${a['fps']}');
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': _emeetVideoConstraints(a['w']!, a['h']!, a['fps']!),
        });
        if (stream.getVideoTracks().isNotEmpty) {
          print('EMEET video ok ${a['w']}x${a['h']}@${a['fps']}');
          if (lastAudio != null) await _stopStream(lastAudio);
          try {
            final af2 = await TvUtil.setUvcAntiFlicker60();
            print('EMEET uvc anti-flicker after open: $af2');
          } catch (_) {}
          return _attachEmeetAudio(stream);
        }
        lastAudio ??= stream;
      } catch (e) {
        print('EMEET getUserMedia ${a['w']}x${a['h']} failed: $e');
      }
    }
    if (lastAudio != null) return lastAudio;
    print('EMEET fallback audio-only');
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }

  Future<MediaStream> createStream(media, userScreen) async {
    if (AppManager.isPiTvLayout && _closed) {
      throw StateError('peer closed');
    }
    if (TvUtil.isTelevision) {
      try {
        await warmupTvCamera();
      } catch (_) {}
    }

    // マイク権限を確実に取得（USBカメラ内蔵マイク含む）
    try {
      final mic = await Permission.microphone.request();
      print('microphone permission: $mic');
    } catch (e) {
      print('microphone permission request failed: $e');
    }

    if (TvUtil.isTelevision) {
      try {
        const channel = MethodChannel('jp.amiplus.lisa/tv');
        final usbPerm = await channel.invokeMethod('ensureUsbAudioPermission');
        print('ensureUsbAudioPermission: $usbPerm');
        // 権限ダイアログを新規表示した場合のみ、付与を待つ
        final requested = usbPerm is Map && usbPerm['requested'] == true;
        if (requested) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
        final prepared =
            await channel.invokeMethod('prepareCommunicationAudio');
        print('prepareCommunicationAudio: $prepared');
      } catch (e) {
        print('prepareCommunicationAudio failed: $e');
      }
    }

    // Google TV + USBカメラでは facingMode を付けると失敗しやすい。
    // EMEET だけ専用経路。C270n / TZZ / その他は従来の 640x360@15。
    final cam = TvUtil.isTelevision ? await TvUtil.getUsbCameraProfile() : null;
    print('usb camera profile: $cam');
    final camId = cam?['id']?.toString() ?? '';

    String? audioDeviceId;
    if (TvUtil.isTelevision) {
      audioDeviceId = await _preferUsbAudioDeviceId();
      if (audioDeviceId != null && audioDeviceId.isNotEmpty) {
        try {
          await Helper.selectAudioInput(audioDeviceId);
          print('Helper.selectAudioInput($audioDeviceId) ok');
        } catch (e) {
          print('Helper.selectAudioInput failed: $e');
        }
      }
    }

    MediaStream stream;
    _emeetCapture = TvUtil.isTelevision && camId == 'emeet';
    if (_emeetCapture) {
      stream = await _openEmeetStream();
    } else {
      final Map<String, dynamic> videoConstraints = {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '360',
          'minFrameRate': '15',
        },
        'optional': [],
      };
      if (!TvUtil.isTelevision) {
        videoConstraints['facingMode'] = 'user';
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': videoConstraints,
        });
      } catch (e) {
        print('getUserMedia failed ($e), retry with simple constraints');
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': true,
        });
      }
      if (TvUtil.isTelevision && stream.getVideoTracks().isEmpty) {
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
          print('TV camera retry ${i + 1}');
          try {
            final retry = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': true,
            });
            if (retry.getVideoTracks().isNotEmpty) {
              await _stopStream(stream);
              stream = retry;
              break;
            }
            await _stopStream(retry);
          } catch (e) {
            print('TV camera retry failed: $e');
          }
        }
      }
    }

    if (stream.getVideoTracks().isEmpty && camId != 'emeet') {
      print('no video tracks; retry video-only getUserMedia');
      try {
        final videoOnly = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': true,
        });
        for (final track in videoOnly.getVideoTracks()) {
          await stream.addTrack(track);
        }
      } catch (e) {
        print('video-only getUserMedia failed: $e');
      }
    }

    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
      print(
          'local video track: id=${track.id} enabled=${track.enabled} muted=${track.muted} label=${track.label}');
    }

    // 映像は取れたが音声トラックが無い場合、音声だけ再取得して結合
    if (stream.getAudioTracks().isEmpty) {
      print('no audio tracks; retry audio-only getUserMedia');
      try {
        if (audioDeviceId != null && audioDeviceId.isNotEmpty) {
          try {
            await Helper.selectAudioInput(audioDeviceId);
          } catch (_) {}
        }
        final audioOnly = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        for (final track in audioOnly.getAudioTracks()) {
          await stream.addTrack(track);
        }
      } catch (e) {
        print('audio-only getUserMedia failed: $e');
      }
    }

    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
      print(
          'local audio track: id=${track.id} enabled=${track.enabled} muted=${track.muted} label=${track.label}');
      if (TvUtil.isTelevision) {
        try {
          // USBマイクはレベルが低いことがある
          await Helper.setVolume(5.0, track);
        } catch (e) {
          print('setVolume failed: $e');
        }
      }
      try {
        await Helper.setMicrophoneMute(false, track);
      } catch (_) {}
    }

    if (AppManager.isPiTvLayout) {
      if (_closed) {
        await _stopStream(stream);
        throw StateError('peer closed after getUserMedia');
      }
      await _waitForLocalVideoLive(stream);
      if (_closed) {
        await _stopStream(stream);
        throw StateError('peer closed after video wait');
      }
    }

    if (onLocalStream != null) onLocalStream!(stream);

    print(
        '***************      Turn on speaker phone(${stream.getAudioTracks().isNotEmpty ? stream.getAudioTracks()[0].muted : "no-audio"})       ******************************');
    if (!TvUtil.isTelevision) {
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (e) {
        print('setSpeakerphoneOn failed: $e');
      }
      try {
        if (stream.getAudioTracks().isNotEmpty) {
          stream.getAudioTracks()[0].enableSpeakerphone(true);
        }
      } catch (e) {
        print('enableSpeakerphone failed: $e');
      }
    } else if (audioDeviceId != null && audioDeviceId.isNotEmpty) {
      try {
        await Helper.selectAudioInput(audioDeviceId);
      } catch (_) {}
    }

    if (TvUtil.isTelevision) {
      // 送信開始前にUSBマイク注入を完了させる（非同期だと最初の数秒が途切れる）
      try {
        final res = await TvUtil.usbMicStart();
        print('usbMicStart: $res');
      } catch (e) {
        print('usbMicStart failed: $e');
      }
    }
    return stream;
  }

  MediaStreamTrack? getVideoTrack() {
    if (_localStream != null) {
      final videoTrack = _localStream!
          .getVideoTracks()
          .firstWhere((track) => track.kind == 'video');
      return videoTrack;
      // return _localStream!.getVideoTracks()[0];
    }
    return null;
  }

  void setVideoEnabled(bool value) {
    if (_localStream != null) {
      _localStream!.getVideoTracks()[0].enabled = value;
    }
  }

  /*
  peer connection
   */

  void _onTrack(RTCTrackEvent event) {
    print('onTrack');
    if (event.track.kind == 'video') {
      // _remoteRenderer.srcObject = event.streams[0];
    }
  }

  void _onAddTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      // _remoteRenderer.srcObject = stream;
    }
  }

  void _onRemoveTrack(MediaStream stream, MediaStreamTrack track) {
    if (track.kind == 'video') {
      // _remoteRenderer.srcObject = null;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(id, media, userScreen, {isHost = false}) async {
    if (media != 'data' && media != 'recvonly' && _localStream == null) {
      _localStream = await createStream(media, userScreen);

      if (AppManager.isMute) {
        setAudioEnabled(false);
      }
      print('**************************************************************');
      print('_createPeerConnection 1');
      print('**************************************************************');
    }

    print('**************************************************************');
    print('_createPeerConnection 2');
    print('**************************************************************');
    var configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': sdpSemantics,
      'iceCandidatePoolSize': 4,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'continualGatheringPolicy': 'gather_once',
    };
    RTCPeerConnection pc = await createPeerConnection(configuration, _config);
    if (media != 'data' && media != 'sendonly') {
      if (sdpSemantics == 'plan-b') {
        pc.onAddStream = (stream) {
          if (onAddRemoteStream != null) onAddRemoteStream!(id, stream);
          _remoteStreams.add(stream);
        };
        pc.onRemoveStream = (stream) {
          if (onRemoveRemoteStream != null) onRemoveRemoteStream!(id, stream);
          _remoteStreams.removeWhere((it) {
            return (it.id == stream.id);
          });
        };
        await pc.addStream(_localStream!);
      } else if (sdpSemantics == 'unified-plan') {
        pc.onTrack = (RTCTrackEvent event) async {
          print('onTrack: ' + id);
          if (event.track.kind == 'video') {
            try {
              if (event.streams.isNotEmpty) {
                if (onAddRemoteStream != null) onAddRemoteStream!(id, event.streams[0]);
                _remoteStreams.add(event.streams[0]);
              } else {
                // 一部の中華系SoCなどでstreamsが空のケースにフォールバック
                final tmp = await createLocalMediaStream('remote-$id');
                await tmp.addTrack(event.track);
                if (onAddRemoteStream != null) onAddRemoteStream!(id, tmp);
                _remoteStreams.add(tmp);
              }
            } catch (e) {
              print('onTrack(video) handling failed: $e');
            }
          }
          // リモートの音声トラック追加時にスピーカーを再度有効化（TV含む）
          if (event.track.kind == 'audio') {
            try {
              event.track.enabled = true;
            } catch (_) {}
            if (!TvUtil.isTelevision) {
              try {
                await Helper.setSpeakerphoneOn(true);
              } catch (e) {
                print('re-setSpeakerphoneOn on onTrack failed: $e');
              }
            }
          }
        };
        pc.onAddTrack = (MediaStream stream, MediaStreamTrack track) async {
          if (track.kind == 'video') {
            try {
              if (stream.id.isNotEmpty) {
                if (onAddRemoteStream != null) onAddRemoteStream!(id, stream);
                _remoteStreams.add(stream);
              } else {
                final tmp = await createLocalMediaStream('remote2-$id');
                await tmp.addTrack(track);
                if (onAddRemoteStream != null) onAddRemoteStream!(id, tmp);
                _remoteStreams.add(tmp);
              }
            } catch (e) {
              print('onAddTrack(video) handling failed: $e');
            }
          }
          if (track.kind == 'audio') {
            try {
              track.enabled = true;
            } catch (_) {}
            if (!TvUtil.isTelevision) {
              try {
                await Helper.setSpeakerphoneOn(true);
              } catch (e) {
                print('re-setSpeakerphoneOn on onAddTrack failed: $e');
              }
            }
          }
        };
        pc.onRemoveTrack = (MediaStream stream, MediaStreamTrack track) {
          if (track.kind == 'video') {
            if (onRemoveRemoteStream != null) onRemoveRemoteStream!(id, stream);
            _remoteStreams.removeWhere((it) {
              return (it.id == stream.id);
            });
          }
        };
      }
    }
    if (media != 'data' && media != 'recvonly') {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
      if (_emeetCapture) {
        await _tuneEmeetSender(pc);
      }
    }
    pc.onIceCandidate = (candidate) {
      if (_iceStable[id] == true) {
        return;
      }
      final iceCandidate = {
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'sdpMid': candidate.sdpMid,
        'candidate': candidate.candidate,
      };
      if (onIceCandidate != null) {
        onIceCandidate!(id, iceCandidate);
      }
    };

    pc.onIceConnectionState = (state) {
      print('onIceConnectionState $id $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceStable[id] = true;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _iceStable[id] = false;
      }
    };

    pc.onSignalingState = (state) {
      if (onStateChange != null) onStateChange!(id, state);
    };

    // pc.onAddStream = (stream) {
    //   if (onAddRemoteStream != null) onAddRemoteStream!(id, stream);
    //   _remoteStreams.add(stream);
    // };

    // pc.onRemoveStream = (stream) {
    //   if (onRemoveRemoteStream != null) onRemoveRemoteStream!(id, stream);
    //   _remoteStreams.removeWhere((it) {
    //     return (it.id == stream.id);
    //   });
    // };

    pc.onDataChannel = (channel) {
      _addDataChannel(id, channel);
    };

    return pc;
  }

  void _addDataChannel(id, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      if (onDataChannelMessage != null) onDataChannelMessage!(channel, data);
    };
    dataChannel = channel;

    if (onDataChannel != null) onDataChannel!(channel);
  }

  Future<void> _createOffer(String id, RTCPeerConnection pc, String media) async {
    print('_createOffer');
    try {
      RTCSessionDescription s = await pc.createOffer(media == 'video' || media == 'recvonly' ? _constraints : _dcConstraints);
      final munged = _mungeSdpForCompatibility(s.sdp ?? '');
      final local = RTCSessionDescription(munged, 'offer');
      await pc.setLocalDescription(local);
      var localDescription = await pc.getLocalDescription();
      if (onOffer != null) onOffer!({'sdp': localDescription!.sdp, 'id': id});
    } catch (e) {
      print('error !!!!!!!!!!!!!!!!!');
      print(e.toString());
    }
  }

  Future<void> _createAnswer(String id, RTCPeerConnection pc, media) async {
    try {
      RTCSessionDescription s = await pc.createAnswer(media == 'data' ? _dcConstraints : _constraints);
      final munged = _mungeSdpForCompatibility(s.sdp ?? '');
      final local = RTCSessionDescription(munged, 'answer');
      await pc.setLocalDescription(local);

      if (onAnswer != null) onAnswer!({'sdp': local.sdp, 'id': id});
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _receiveOffer(String id, RTCPeerConnection pc, String sdp) async {
    print('peer _receiveOffer');
    RTCSessionDescription description = RTCSessionDescription(sdp, 'offer');// {'sdp': sdp, 'type': 'offer'};

    await pc.setRemoteDescription(description);
    await _createAnswer(id, pc, 'video');

    if (_remoteCandidates.containsKey(id)) {
      _remoteCandidates[id].forEach((candidate) async {
        await pc.addCandidate(candidate);
      });
      _remoteCandidates.remove(id);
    }
  }

  Future<void> _receiveAnswer(String id, String sdp) async {
    var pc = _peerConnections[id];
    if (pc != null) {
      print('peer _receiveAnswer');
      // print(sdp);
      try {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      } catch (e) {
        print(e.toString());
      }
    }
  }

  /// 端末間互換性を高めるためのSDP加工
  /// - VP8を最優先
  /// - H264を使う場合はBaseline相当に調整（profile-level-id=42e01f, packetization-mode=1）
  String _mungeSdpForCompatibility(String sdp) {
    try {
      final lines = sdp.split('\n');
      // rtpmapマッピング: PT -> codec名
      final Map<String, String> ptCodec = {};
      final RegExp rtpmap = RegExp(r'^a=rtpmap:(\d+)\s+([^/]+)/', multiLine: false);
      for (final l in lines) {
        final m = rtpmap.firstMatch(l.trim());
        if (m != null) {
          ptCodec[m.group(1)!] = m.group(2)!.toUpperCase();
        }
      }

      int videoMLineIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('m=video')) {
          videoMLineIndex = i;
          break;
        }
      }

      if (videoMLineIndex >= 0) {
        final parts = lines[videoMLineIndex].trim().split(' ');
        if (parts.length > 3) {
          final header = parts.sublist(0, 3); // m=video <port> RTP/SAVPF
          final payloads = parts.sublist(3);

          final vp8 = <String>[];
          final h264 = <String>[];
          final others = <String>[];
          for (final pt in payloads) {
            final codec = ptCodec[pt] ?? '';
            if (codec == 'VP8') {
              vp8.add(pt);
            } else if (codec == 'H264') {
              h264.add(pt);
            } else {
              others.add(pt);
            }
          }
          // VP8優先 → H264 → その他
          final newPayloads = <String>[]..addAll(vp8)..addAll(h264)..addAll(others);
          lines[videoMLineIndex] = (header + newPayloads).join(' ');

          // H264のfmtpをBaseline相当に調整
          if (h264.isNotEmpty) {
            final h264Pts = Set<String>.from(h264);
            final RegExp fmtpRe = RegExp(r'^a=fmtp:(\d+)\s+(.+)+?$', multiLine: false);
            for (int i = 0; i < lines.length; i++) {
              final l = lines[i].trim();
              final m = fmtpRe.firstMatch(l);
              if (m != null && h264Pts.contains(m.group(1)!)) {
                // 既存パラメータを解析して安全側に上書き
                final params = m.group(2)!.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                final Map<String, String> kv = {};
                for (final p in params) {
                  final idx = p.indexOf('=');
                  if (idx > 0) {
                    kv[p.substring(0, idx)] = p.substring(idx + 1);
                  } else {
                    kv[p] = '';
                  }
                }
                kv['profile-level-id'] = '42e01f';
                kv['packetization-mode'] = '1';
                kv['level-asymmetry-allowed'] = '1';
                final rebuilt = kv.entries.map((e) => e.value.isEmpty ? e.key : '${e.key}=${e.value}').join(';');
                lines[i] = 'a=fmtp:${m.group(1)} ' + rebuilt;
              }
            }
          }
        }
      }

      // Opus: 開始直後の欠落に強くする（FEC ON / DTX OFF）
      final opusPts = ptCodec.entries
          .where((e) => e.value == 'OPUS')
          .map((e) => e.key)
          .toSet();
      if (opusPts.isNotEmpty) {
        final fmtpOpus = RegExp(r'^a=fmtp:(\d+)\s+(.*)$');
        final haveFmtp = <String>{};
        for (int i = 0; i < lines.length; i++) {
          final m = fmtpOpus.firstMatch(lines[i].trim());
          if (m == null || !opusPts.contains(m.group(1))) continue;
          haveFmtp.add(m.group(1)!);
          final params = m.group(2)!
              .split(';')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final kv = <String, String>{};
          for (final p in params) {
            final idx = p.indexOf('=');
            if (idx > 0) {
              kv[p.substring(0, idx)] = p.substring(idx + 1);
            } else {
              kv[p] = '';
            }
          }
          kv['minptime'] = '10';
          kv['useinbandfec'] = '1';
          kv['usedtx'] = '0';
          final rebuilt = kv.entries
              .map((e) => e.value.isEmpty ? e.key : '${e.key}=${e.value}')
              .join(';');
          lines[i] = 'a=fmtp:${m.group(1)} $rebuilt';
        }
        for (int i = 0; i < lines.length; i++) {
          final m = rtpmap.firstMatch(lines[i].trim());
          if (m == null) continue;
          final pt = m.group(1)!;
          if (opusPts.contains(pt) && !haveFmtp.contains(pt)) {
            lines.insert(
              i + 1,
              'a=fmtp:$pt minptime=10;useinbandfec=1;usedtx=0',
            );
            haveFmtp.add(pt);
          }
        }
      }

      // 映像の初期ビットレートを上げ、開始直後に音声が圧迫されないようにする
      final vp8Pts = ptCodec.entries
          .where((e) => e.value == 'VP8')
          .map((e) => e.key)
          .toSet();
      if (vp8Pts.isNotEmpty) {
        final fmtpVp8 = RegExp(r'^a=fmtp:(\d+)\s+(.*)$');
        final haveFmtp = <String>{};
        for (int i = 0; i < lines.length; i++) {
          final m = fmtpVp8.firstMatch(lines[i].trim());
          if (m == null || !vp8Pts.contains(m.group(1))) continue;
          haveFmtp.add(m.group(1)!);
          var rest = m.group(2)!;
          if (!rest.contains('x-google-start-bitrate')) {
            rest = _emeetCapture
                ? '$rest;x-google-min-bitrate=800;x-google-start-bitrate=1800;x-google-max-bitrate=3500'
                : '$rest;x-google-min-bitrate=150;x-google-start-bitrate=500;x-google-max-bitrate=1200';
          }
          lines[i] = 'a=fmtp:${m.group(1)} $rest';
        }
        for (int i = 0; i < lines.length; i++) {
          final m = rtpmap.firstMatch(lines[i].trim());
          if (m == null) continue;
          final pt = m.group(1)!;
          if (vp8Pts.contains(pt) && !haveFmtp.contains(pt)) {
            lines.insert(
              i + 1,
              _emeetCapture
                  ? 'a=fmtp:$pt x-google-min-bitrate=800;x-google-start-bitrate=1800;x-google-max-bitrate=3500'
                  : 'a=fmtp:$pt x-google-min-bitrate=150;x-google-start-bitrate=500;x-google-max-bitrate=1200',
            );
            haveFmtp.add(pt);
          }
        }
      }

      return lines.join('\n');
    } catch (e) {
      print('SDP munging failed: $e');
      return sdp;
    }
  }
}
