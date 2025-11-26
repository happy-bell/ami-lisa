import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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

typedef SignalingStateCallback = void Function(
    String id, RTCSignalingState state);
typedef StreamStateCallback = void Function(MediaStream stream);
typedef RemoteStreamStateCallback = void Function(
    String id, MediaStream stream);
typedef IceCandidateCallback = void Function(String id, dynamic event);
typedef OtherEventCallback = void Function(dynamic event);
typedef DataChannelMessageCallback = void Function(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef DataChannelCallback = void Function(RTCDataChannel dc);

class Peer {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  final _remoteCandidates = {};
  // var _turnCredential;

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
    ],
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

  void close() {
    if (_localStream != null) {
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream!.dispose();
      _localStream = null;
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

    // if (this.onStateChange != null) {
    //   this.onStateChange(SignalingState.CallStateBye);
    // }
    _remoteCandidates.clear();
  }

  void closeOne(String id) {
    print('peer closeOne $id');
    if (_peerConnections[id] != null) {
      _peerConnections[id]!.close();
      _peerConnections[id]!.dispose();
      _peerConnections.remove(id);
    }
  }

  void enableSpeaker(bool val) {
    if (_localStream != null) {
      _localStream!.getAudioTracks()[0].enableSpeakerphone(val);
      print(_localStream!.getAudioTracks()[0].muted);
    }
  }

  void switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!
          .getVideoTracks()
          .firstWhere((track) => track.kind == 'video');
      await Helper.switchCamera(videoTrack);
    }
  }

  void setLocalStream(MediaStream stream) {
    _localStream = stream;
    _peerConnections.forEach((_, pc) {
      stream.getTracks().forEach((t) => pc.addTrack(t, stream));
    });
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

  void receiveIceCandidate(
      String peerId, Map<String, dynamic> candidateMap) async {
    var pc = _peerConnections[peerId];

    print("receive ice $peerId");
    print(candidateMap);

    RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
        candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
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
    _createPeerConnection(peerId, media, useScreen, isHost: true).then((pc) {
      _peerConnections[peerId] = pc;
      _createOffer(peerId, pc, media);
    });
  }

  Future<MediaStream> createStream(media, userScreen) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '360',
          'minFrameRate': '15',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    // MediaStream stream = userScreen
    //     ? await MediaDevices.getUserMedia(
    //     mediaConstraints) //navigator.getDisplayMedia(mediaConstraints)
    //     : await MediaDevices.getUserMedia(mediaConstraints);

    var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (onLocalStream != null) onLocalStream!(stream);

    print(
        '***************      Turn on speaker phone(${stream.getAudioTracks()[0].muted})       ******************************');
    // final session = await AudioSession.instance;
    // await session.configure(AudioSessionConfiguration.music());
    try {
      stream.getAudioTracks()[0].enableSpeakerphone(true);
    } catch (e) {
      print('enableSpeakerphone failed: $e');
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

  void setAudioEnabled(bool value) {
    if (_localStream != null) {
      _localStream!.getAudioTracks()[0].enabled = value;
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

  Future<RTCPeerConnection> _createPeerConnection(id, media, userScreen,
      {isHost = false}) async {
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
        {'url': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': sdpSemantics
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
          // リモートの音声トラック追加時に念のためスピーカーを再度有効化
          if (event.track.kind == 'audio') {
            try {
              _localStream?.getAudioTracks().first.enableSpeakerphone(true);
            } catch (e) {
              print('re-enableSpeakerphone on onTrack failed: $e');
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
              _localStream?.getAudioTracks().first.enableSpeakerphone(true);
            } catch (e) {
              print('re-enableSpeakerphone on onAddTrack failed: $e');
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
    }
    pc.onIceCandidate = (candidate) {
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
      // print('onIceConnectionState $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateClosed ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        // bye();
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

  Future<void> _createOffer(
      String id, RTCPeerConnection pc, String media) async {
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

  Future<void> _receiveOffer(
      String id, RTCPeerConnection pc, String sdp) async {
    print('peer _receiveOffer');
    RTCSessionDescription description =
        RTCSessionDescription(sdp, 'offer'); // {'sdp': sdp, 'type': 'offer'};

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
      return lines.join('\n');
    } catch (e) {
      print('SDP munging failed: $e');
      return sdp;
    }
  }
}
