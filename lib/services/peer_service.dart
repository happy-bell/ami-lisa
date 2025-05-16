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

typedef void SignalingStateCallback(String id, RTCSignalingState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void RemoteStreamStateCallback(String id, MediaStream stream);
typedef void IceCandidateCallback(String id, dynamic event);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Peer {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  var _remoteCandidates = {};
  // var _turnCredential;

  MediaStream? _localStream;
  set localStream(value) => _localStream = value;
  List<MediaStream> _remoteStreams = [];
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
  Map<String, RTCPeerConnection> _peerConnections = {};

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


    print('***************      Turn on speaker phone(${stream.getAudioTracks()[0].muted})       ******************************');
    // final session = await AudioSession.instance;
    // await session.configure(AudioSessionConfiguration.music());
    try {
      stream.getAudioTracks()[0].enableSpeakerphone(true);
    } catch (e) {
      print(e.toString());
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
        pc.onTrack = (RTCTrackEvent event) {
          print('onTrack: ' + id);
          if (event.track.kind == 'video') {
            if (onAddRemoteStream != null) onAddRemoteStream!(id, event.streams[0]);
            _remoteStreams.add(event.streams[0]);
          }
        };
        pc.onAddTrack = (MediaStream stream, MediaStreamTrack track) {
          if (track.kind == 'video') {
            if (onAddRemoteStream != null) onAddRemoteStream!(id, stream);
            _remoteStreams.add(stream);
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

  Future<void> _createOffer(String id, RTCPeerConnection pc, String media) async {
    print('_createOffer');
    try {
      RTCSessionDescription s = await pc.createOffer(media == 'video' || media == 'recvonly' ? _constraints : _dcConstraints);
      await pc.setLocalDescription(s);
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
      pc.setLocalDescription(s);

      if (onAnswer != null) onAnswer!({'sdp': s.sdp, 'id': id});
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
}