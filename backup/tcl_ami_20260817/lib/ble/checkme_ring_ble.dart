import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'checkme_ring_protocol.dart';

class CheckmeRingScanDevice {
  CheckmeRingScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isRing,
    required this.device,
  });

  final String id;
  String name;
  int rssi;
  bool isRing;
  final BluetoothDevice device;
}

class CheckmeRingBle {
  final Map<String, CheckmeRingScanDevice> devices = {};
  final List<String> logs = [];

  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  String status = '未接続';
  String? connectedName;
  CheckmeRingRealtime? lastRealtime;
  String lastHex = '';

  void Function()? onChanged;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  Timer? _pollTimer;
  final List<int> _buffer = [];
  bool _writeWithoutResponse = false;

  void _notify() => onChanged?.call();

  void _log(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, '$stamp  $line');
    if (logs.length > 40) {
      logs.removeLast();
    }
    print('[CheckmeRing] $line');
    _notify();
  }

  Future<bool> ensureReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _log('この端末ではBLEに未対応です');
      status = '未対応';
      _notify();
      return false;
    }

    if (Platform.isAndroid) {
      final req = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];
      final results = await req.request();
      for (final e in results.entries) {
        _log('権限 ${e.key}: ${e.value}');
      }
    }

    if (await FlutterBluePlus.isSupported == false) {
      _log('この端末はBluetooth LE非対応です');
      status = 'BLE非対応';
      _notify();
      return false;
    }

    var adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      _log('Bluetoothがオフです。オンにします');
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _log('Bluetoothオン失敗: $e');
      }
      adapter = await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => adapter,
          );
    }
    if (adapter != BluetoothAdapterState.on) {
      status = 'Bluetoothオフ';
      _log('Bluetoothをオンにしてから再試行してください');
      _notify();
      return false;
    }
    return true;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    if (scanning) return;
    if (!await ensureReady()) return;

    devices.clear();
    scanning = true;
    status = 'スキャン中...';
    _log('スキャン開始 (${timeout.inSeconds}秒)');
    _notify();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      var changed = false;
      for (final r in results) {
        final id = r.device.remoteId.str;
        final name = _deviceName(r);
        final uuids = r.advertisementData.serviceUuids
            .map((u) => u.str.toLowerCase())
            .toList();
        final isRing = (CheckmeRingProtocol.isRingName(name) ||
                uuids.any(CheckmeRingProtocol.isRingServiceUuid)) &&
            !name.toLowerCase().contains('checkadv') &&
            !name.toLowerCase().contains('checkme pro');
        final existing = devices[id];
        if (existing == null) {
          devices[id] = CheckmeRingScanDevice(
            id: id,
            name: name.isEmpty ? '(名前なし)' : name,
            rssi: r.rssi,
            isRing: isRing,
            device: r.device,
          );
          _log(
            '発見 ${isRing ? "[Ring] " : ""}${name.isEmpty ? id : name}  RSSI ${r.rssi}',
          );
          changed = true;
        } else {
          if (r.rssi != existing.rssi ||
              (name.isNotEmpty && name != existing.name)) {
            existing.rssi = r.rssi;
            if (name.isNotEmpty) existing.name = name;
            existing.isRing = existing.isRing || isRing;
            changed = true;
          }
        }
      }
      if (changed) _notify();
    }, onError: (e) {
      _log('スキャンエラー: $e');
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      await FlutterBluePlus.isScanning.where((v) => v == false).first.timeout(
            timeout + const Duration(seconds: 2),
          );
    } catch (e) {
      _log('スキャン失敗: $e');
    } finally {
      scanning = false;
      final ringCount = devices.values.where((d) => d.isRing).length;
      status = devices.isEmpty
          ? '機器なし'
          : 'スキャン完了  Ring $ringCount / 全体 ${devices.length}';
      _log(status);
      _notify();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    scanning = false;
    _notify();
  }

  Future<void> connect(CheckmeRingScanDevice target) async {
    if (connecting || connected) {
      await disconnect();
    }
    if (!await ensureReady()) return;

    connecting = true;
    connected = false;
    lastRealtime = null;
    lastHex = '';
    _buffer.clear();
    connectedName = target.name;
    status = '接続中... ${target.name}';
    _log('接続 ${target.name} ${target.id}');
    _notify();

    try {
      await stopScan();
      _device = target.device;
      await _connSub?.cancel();
      _connSub = _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && connected) {
          _log('切断されました');
          _onLost();
        }
      });

      await _device!.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );
      await _device!.connectionState
          .firstWhere((s) => s == BluetoothConnectionState.connected)
          .timeout(const Duration(seconds: 20));

      final services = await _device!.discoverServices();
      BluetoothCharacteristic? readChar;
      BluetoothCharacteristic? writeChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == CheckmeRingProtocol.readUuid) readChar = c;
          if (uuid == CheckmeRingProtocol.writeUuid) writeChar = c;
        }
      }
      if (readChar == null || writeChar == null) {
        throw StateError(
          'RingのGATT特性が見つかりません (read=${readChar != null} write=${writeChar != null})',
        );
      }
      _writeChar = writeChar;
      _writeWithoutResponse =
          writeChar.properties.writeWithoutResponse && !writeChar.properties.write;

      await readChar.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = readChar.onValueReceived.listen(_onNotify);

      connected = true;
      connecting = false;
      status = '接続済み ${target.name}';
      _log('接続成功。通知開始');
      _notify();

      try {
        await _write(CheckmeRingProtocol.buildSetTimeCommand());
        _log('時刻同期を送信');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _log('時刻同期スキップ: $e');
      }

      await _requestRealtime();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _requestRealtime();
      });
    } catch (e) {
      _log('接続失敗: $e');
      status = '接続失敗';
      connecting = false;
      connected = false;
      _notify();
      await disconnect();
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _writeChar = null;
    final device = _device;
    _device = null;
    connected = false;
    connecting = false;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    if (status.startsWith('接続')) {
      status = '切断';
    }
    _log('切断');
    _notify();
  }

  Future<void> dispose() async {
    onChanged = null;
    await stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    await disconnect();
  }

  String _deviceName(ScanResult r) {
    final adv = r.advertisementData.advName.trim();
    if (adv.isNotEmpty) return adv;
    final platform = r.device.platformName.trim();
    if (platform.isNotEmpty) return platform;
    return '';
  }

  void _onNotify(List<int> data) {
    lastHex = CheckmeRingProtocol.bytesToHex(data);
    _log('notify $lastHex');
    _buffer.addAll(data);
    while (true) {
      try {
        final packet = CheckmeRingProtocol.popResponse(_buffer);
        if (packet == null) break;
        if (packet.header == 0xA5 &&
            packet.cmd != CheckmeRingProtocol.cmdGetRtData) {
          _log('skip cmd ${packet.cmd}');
          continue;
        }
        try {
          lastRealtime = CheckmeRingProtocol.parseRealtimeData(packet.payload);
          final r = lastRealtime!;
          _log(
            'SpO2 ${r.spo2}  脈拍 ${r.pulse}  PI ${r.pi}  ${r.wearLabel}'
            '${r.isValid ? "  有効" : "  無効"}',
          );
        } catch (e) {
          _log('$e');
        }
      } catch (e) {
        _log('$e');
      }
    }
    _notify();
  }

  Future<void> _requestRealtime() async {
    if (!connected || _writeChar == null) return;
    try {
      await _write(CheckmeRingProtocol.buildGetRtDataCommand());
    } catch (e) {
      _log('リアルタイム要求失敗: $e');
    }
  }

  Future<void> _write(List<int> bytes) async {
    final c = _writeChar;
    if (c == null) return;
    await c.write(bytes, withoutResponse: _writeWithoutResponse);
  }

  void _onLost() {
    _pollTimer?.cancel();
    _pollTimer = null;
    connected = false;
    connecting = false;
    status = '切断されました';
    _notify();
  }

  List<CheckmeRingScanDevice> get sortedDevices {
    final list = devices.values.toList();
    list.sort((a, b) {
      if (a.isRing != b.isRing) return a.isRing ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }
}
