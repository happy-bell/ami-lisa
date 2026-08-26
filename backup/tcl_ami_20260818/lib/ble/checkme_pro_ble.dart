import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'checkme_pro_protocol.dart';

class CheckmeProScanDevice {
  CheckmeProScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isPro,
    required this.device,
  });

  final String id;
  String name;
  int rssi;
  bool isPro;
  final BluetoothDevice device;
}

/// 設定の BLEテスト用。自動サービスとは別に、画面の間だけ使う。
class CheckmeProBle {
  final Map<String, CheckmeProScanDevice> devices = {};
  final List<String> logs = [];

  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  String status = '未接続';
  String? connectedName;
  CheckmeProRealtime? lastRealtime;
  int packets = 0;
  String lastHex = '';

  void Function()? onChanged;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  final List<int> _buffer = [];
  bool _writeWithoutResponse = false;

  void _notify() => onChanged?.call();

  void _log(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.insert(0, '$stamp  $line');
    if (logs.length > 40) logs.removeLast();
    print('[CheckmePro] $line');
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
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
    if (await FlutterBluePlus.isSupported == false) {
      _log('BLE非対応');
      return false;
    }
    return true;
  }

  Future<void> startScan() async {
    if (!await ensureReady()) return;
    devices.clear();
    scanning = true;
    status = 'スキャン中... 本体でチェックモニターを起動してください';
    _log('スキャン開始');
    _notify();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = _deviceName(r);
        final id = r.device.remoteId.str;
        final isPro = CheckmeProProtocol.isProName(name);
        final existing = devices[id];
        if (existing == null) {
          devices[id] = CheckmeProScanDevice(
            id: id,
            name: name.isEmpty ? '(no name)' : name,
            rssi: r.rssi,
            isPro: isPro,
            device: r.device,
          );
        } else {
          existing.rssi = r.rssi;
          if (name.isNotEmpty) existing.name = name;
          existing.isPro = existing.isPro || isPro;
        }
      }
      _notify();
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      _log('スキャン失敗: $e');
    }
    scanning = false;
    status = connected ? status : 'スキャン終了';
    _notify();
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    scanning = false;
    _notify();
  }

  Future<void> connect(CheckmeProScanDevice target) async {
    if (connecting || connected) {
      await disconnect();
    }
    if (!await ensureReady()) return;

    connecting = true;
    connected = false;
    lastRealtime = null;
    packets = 0;
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
          connected = false;
          connecting = false;
          status = '切断されました';
          _notify();
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
      BluetoothCharacteristic? statusChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == CheckmeProProtocol.readUuid) readChar = c;
          if (uuid == CheckmeProProtocol.writeUuid) writeChar = c;
          if (uuid == CheckmeProProtocol.statusUuid) statusChar = c;
        }
      }
      if (readChar == null || writeChar == null) {
        throw StateError('Checkme Pro のGATT特性が見つかりません');
      }
      _writeChar = writeChar;
      _writeWithoutResponse =
          writeChar.properties.writeWithoutResponse && !writeChar.properties.write;

      await readChar.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = readChar.onValueReceived.listen(_onNotify);
      if (statusChar != null) {
        try {
          await statusChar.setNotifyValue(true);
        } catch (_) {}
      }

      connected = true;
      connecting = false;
      status = '接続済み ${target.name}';
      _log('接続成功。配信開始コマンド送信');
      _notify();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _writeChar!.write(
        CheckmeProProtocol.monitorStartCommand,
        withoutResponse: _writeWithoutResponse,
      );
      _log('0x01 送信。本体でチェックモニターを実行してください');
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
    if (status.startsWith('接続')) status = '切断';
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
    return r.device.platformName.trim();
  }

  void _onNotify(List<int> data) {
    lastHex = CheckmeProProtocol.bytesToHex(data);
    _buffer.addAll(data);
    while (true) {
      final packet = CheckmeProProtocol.popPacket(_buffer);
      if (packet == null) break;
      packets++;
      final parsed = CheckmeProProtocol.parsePacket(packet);
      if (parsed == null) continue;
      lastRealtime = (lastRealtime ?? parsed).merge(parsed);
      final r = lastRealtime!;
      if (packets % 25 == 1) {
        _log(
          'HR ${r.hr ?? "-"}  SpO2 ${r.spo2 ?? "-"}  PR ${r.pr ?? "-"}  '
          'PI ${r.pi ?? "-"}  pkt=$packets'
          '${r.isValid ? "  有効" : ""}',
        );
      }
    }
    _notify();
  }

  List<CheckmeProScanDevice> get sortedDevices {
    final list = devices.values.toList();
    list.sort((a, b) {
      if (a.isPro != b.isPro) return a.isPro ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }
}
