import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'appmanager.dart';

mixin SocketIOServiceDelegate {
  void onConnect();

  void onDisConnect();

  void onAppMessage(data);

  void onMessage(data);

  void onTalkMessage(data);

  void onCallResponse(to, sdp) => print('');

  void onStartCommunication(to, sdp) => print('');

  void onMessageIceCandidate(from, candidate) => print('');
}

class SocketIOService {
  static final SocketIOService _instance = SocketIOService._internal();

  String url = '';
  SocketIOServiceDelegate? delegate;
  SocketIOServiceDelegate? delegate2;

  IO.Socket? _socket;
  IO.Socket get io => _socket!;
  bool reconnect = true;
  bool connected = false;
  bool connecting = false;
  bool _ping = false;
  Timer? _timer;
  var _connectCount = 0;

  SocketIOService._internal();

  factory SocketIOService() {
    return _instance;
  }

  bool isConnect() {
    if (_socket != null) {
      return _socket!.connected;
    }
    return false;
  }

  void _setSocket() {
    print('setSocket $url');
    _socket = IO.io(url,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build()
    );
    _socket!.onConnect((_) {
      print('socket connect');
      delegate?.onConnect();
    });
    _socket!.onDisconnect((_) {
      print('socket disconnect');
      delegate?.onDisConnect();
      disconnect();

      if (reconnect) {
        startConnectTimer();
      }
    });

    _socket!.on("app", (data) {
      // print(data);
      String message = data['message'];
      print('socket app message $message');
      if (message == 'talk') {
        if (data["info"] == null) {
          return;
        }
        if (data["info"]["id2"] == null) {
          return;
        }
        delegate?.onTalkMessage(data["info"]);
        delegate2?.onTalkMessage(data["info"]);
        return;
      }

      if (message == 'from_server') {
        connected = true;
      }

      if (delegate == null) {
        print('socket no delegate');
      }
      if (delegate == null) {
        print('**********************************************');
        print('        delegate is null');
        print('**********************************************');
      }
      delegate?.onAppMessage(data);
      delegate2?.onAppMessage(data);
    });

    // カメラ映像要求
    _socket!.on("called_check", (data) {
      dynamic wrapped;
      if (data is Map) {
        try {
          wrapped = Map<String, dynamic>.from(data);
        } catch (_) {
          wrapped = {'data': data};
        }
      } else {
        wrapped = {'data': data};
      }
      wrapped['message'] = 'called_check';
      delegate?.onAppMessage(wrapped);
      delegate2?.onAppMessage(wrapped);
    });

    _socket!.on("from_server", (data) {

    });

    _socket!.on("message", (data) {
      // print(data);

      var id = data['id'];
      if (id == 'callResponse') {
        var response = (data["response"] ?? '');
        if (response != 'accepted') {
          return;
        }
        var to = (data["to"] ?? '');
        var sdp = (data["sdpOffer"] ?? '');
        print('**************************************');
        print('callresponse $to');
        print('**************************************');
        delegate?.onCallResponse(to, sdp);
        delegate2?.onCallResponse(to, sdp);
        return;
      } else if (id == 'startCommunication') {
        var sdp = (data["sdpAnswer"] ?? '');
        var to = (data["to"] ?? '');
        delegate?.onStartCommunication(to, sdp);
        delegate2?.onStartCommunication(to, sdp);
        return;
      } else if (id == 'iceCandidate') {
        var from = data["from"];
        var candidate = data["candidate"];
        if (from == null || candidate == null) {
          return;
        }
        print('iceCandidate $from');
        delegate?.onMessageIceCandidate(from, candidate);
        delegate2?.onMessageIceCandidate(from, candidate);
        return;
      }
      delegate?.onMessage(data);
      delegate2?.onMessage(data);
    });
  }

  Future<void> connect() async {
    if (isConnect()) {
      print('socket already connected');
      return;
    }
    // print('socket connect to ' + url);

    if (_socket == null) {
      _setSocket();
    }

    print('connect');
    _socket!.connect();
  }

  void _connect() {

    if (connected) {
      if (_ping) {
        _socket!.emit("my_status", [AppManager.statusValue()]);
      }
      _ping = !_ping;
      // print('connected');
      return;
    }

    print('_connect');
    if (connecting) {
      print('socket is connecting');
      return;
    }
    connecting = true;

    if (isConnect()) {
      _connectCount += 1;
      if (_connectCount > 5) {
        _connectCount = 0;
        disconnect();
      }
      connecting = false;
      return;
    }
    connect();
    connecting = false;
  }

  void stopTimer() {
    print('stop socket timer1');
    if (_timer != null) {
      print('stop socket timer');
      _timer!.cancel();
    }
  }

  void startConnectTimer() {
    stopTimer();

    _timer = Timer.periodic(const Duration(milliseconds: 2 * 1000), (Timer timer) {
      _connect();
    });
  }

  void disconnect() {
    if (_socket != null) {
      if (_socket!.connected) {
        _socket!.disconnect();
      }
      _socket?.offAny();
      _socket?.close();
      _socket?.dispose();
      // _socket!.dispose();
      _socket = null;
    }
    connecting = false;
    connected = false;
  }

  void delegatorLogin(useType) async {

    final sharedPreferences = await SharedPreferences.getInstance();
    var codes = [];
    String? codesString = sharedPreferences.getString('codes');
    if (AppManager.isManager && codesString != null) {
      var allCodes = json.decode(codesString);
      for (var i = 0; i < allCodes.length; i++) {
        codes.add(allCodes[i] + '_STAFF');
      }
    }

    _socket!.emit("login", [
      {
        "DELEGATOR": AppManager.delegatorCode,
        "MYID": AppManager.myId,
        "NAME": AppManager.settings['MCSNAME'],
        "GROUP": AppManager.settings['group'],
        "USETYPE": useType,
        "MARKER": "0",
        "DISPSIZE": "1",
        "FIRTOKEN": AppManager.fcmtoken,
        "CODES": codes
      }
    ]);
  }
}