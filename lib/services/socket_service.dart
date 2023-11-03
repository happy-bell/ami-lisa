import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'appmanager.dart';

mixin SocketServiceDelegate {
  void onIoConnect();

  void onIoDisConnect();

  void onIoMessage(data);
}

class SocketService {

  String url = '';
  SocketServiceDelegate? roomDelegate;

  int tag = 0;
  IO.Socket? _socket;
  IO.Socket get io => _socket!;
  bool connected = false;

  Future<void> connect() async {
    print('room socket connect to ' + url);
    if (_socket != null) {
      if (_socket!.connected) {
        print('room socket already connected');
        return;
      }
    }

    _socket = IO.io(url,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build()
    );

    _socket!.onConnect((_) {
      print('room socket connect');
      roomDelegate?.onIoConnect();
    });
    _socket!.onDisconnect((_) {
      print('room socket disconnect');
      connected = false;
      roomDelegate?.onIoDisConnect();
    });

    // _socket!.on("connect", (data) {
    //   print('room socket dddconnect');
    // });

    _socket!.on("from_server", (data) {
      roomDelegate?.onIoMessage(data);
    });

    _socket!.on("message", (data) {
      // print(data);

      // var id = data['id'];
      roomDelegate?.onIoMessage(data);
    });

    _socket!.connect();
  }

  void disconnect() {
    if (tag != 4) {
      var sendData = {
        "id": "leaveRoom"
      };
      // print("***************************   leaveRoom   ************************************");
      // _socket?.emit("message", [sendData]);
    }
    if (_socket != null) {
      if (_socket!.connected) {
        _socket?.disconnect();
      }
      _socket?.dispose();
      _socket = null;
    }
    connected = false;
  }
}