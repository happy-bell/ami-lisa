/// Checkme Ring (Viatom / Checkme O2) BLE packet protocol.
/// Ported from Ring-Checkme-A&D/x-amibl789/ble_checkmering.py
class CheckmeRingProtocol {
  static const serviceUuid = '14839ac4-7d7e-415c-9a42-167340cf2339';
  static const readUuid = '0734594a-a8e7-4b1a-a6b1-cd5243059a57';
  static const writeUuid = '8b00ace7-eb0b-49b0-bbe9-9aee0a26e1a3';

  static const cmdGetRtData = 0x17;
  static const cmdParaSync = 0x16;

  static const deviceNamePrefixes = <String>[
    'Checkme O2',
    'O2',
    'O2Ring',
    'O2M',
    'BabyO2',
    'BabyO2N',
    'SleepO2',
    'O2BAND',
    'WearO2',
    'SleepU',
    'Oxylink',
    'KidsO2',
    'Oxyfit',
    'OxyRing',
    'OxySmart',
    'OxyU',
    'CMRing',
    'O2NCI',
  ];

  static const _crc8Table = <int>[
    0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15, 0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
    0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65, 0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
    0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5, 0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
    0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85, 0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
    0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2, 0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
    0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2, 0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
    0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32, 0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
    0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42, 0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
    0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C, 0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
    0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC, 0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
    0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C, 0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
    0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C, 0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
    0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B, 0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
    0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B, 0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
    0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB, 0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
    0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB, 0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3,
  ];

  static int crc8(List<int> data) {
    var ret = 0;
    for (final value in data) {
      ret = _crc8Table[ret ^ (value & 0xFF)];
    }
    return ret;
  }

  static String bytesToHex(List<int> data) {
    return data.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join(' ');
  }

  static bool isRingName(String name) {
    if (name.isEmpty) return false;
    return deviceNamePrefixes.any(name.startsWith);
  }

  static bool isRingServiceUuid(String uuid) {
    return uuid.toLowerCase() == serviceUuid;
  }

  static List<int> buildCommand(int cmd, {int pktNr = 0, List<int> data = const []}) {
    final body = <int>[
      0xAA,
      cmd & 0xFF,
      (~cmd) & 0xFF,
      pktNr & 0xFF,
      (pktNr >> 8) & 0xFF,
      data.length & 0xFF,
      (data.length >> 8) & 0xFF,
      ...data,
    ];
    body.add(crc8(body));
    return body;
  }

  static List<int> buildGetRtDataCommand() => buildCommand(cmdGetRtData);

  static List<int> buildSetTimeCommand() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)},${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final payload = '{"SetTIME":"$stamp"}'.codeUnits;
    return buildCommand(cmdParaSync, data: payload);
  }

  /// Returns a parsed packet, or null if more bytes are needed.
  /// Throws [FormatException] on CRC / device error. May drop a leading byte.
  static CheckmeRingPacket? popResponse(List<int> buffer) {
    while (buffer.isNotEmpty && buffer[0] != 0x55 && buffer[0] != 0xA5) {
      buffer.removeAt(0);
    }
    if (buffer.length < 8) return null;

    final header = buffer[0];
    if (buffer[2] != ((~buffer[1]) & 0xFF)) {
      buffer.removeAt(0);
      return null;
    }

    final dataSize = buffer[5] | (buffer[6] << 8);
    final packetSize = 7 + dataSize + 1;
    if (buffer.length < packetSize) return null;

    final packet = List<int>.from(buffer.sublist(0, packetSize));
    if (crc8(packet.sublist(0, packet.length - 1)) != packet.last) {
      buffer.removeRange(0, packetSize);
      throw const FormatException('Checkme Ring response CRC error');
    }
    buffer.removeRange(0, packetSize);

    final cmd = packet[1];
    final payload = packet.sublist(7, packet.length - 1);
    if (header == 0x55 && cmd != 0x00) {
      final errCode = payload.length >= 4
          ? payload[0] | (payload[1] << 8) | (payload[2] << 16) | (payload[3] << 24)
          : cmd;
      throw FormatException('Checkme Ring returned error: $errCode');
    }
    return CheckmeRingPacket(header: header, cmd: cmd, payload: payload);
  }

  static CheckmeRingRealtime parseRealtimeData(List<int> data) {
    if (data.length < 13) {
      throw const FormatException('Checkme Ring real-time data is too short');
    }
    return CheckmeRingRealtime(
      spo2: data[0],
      pulse: data[1] | (data[2] << 8),
      steps: data[3] | (data[4] << 8) | (data[5] << 16) | (data[6] << 24),
      battery: data[7],
      chargeState: data[8],
      motion: data[9],
      pi: data[10],
      wearState: data[11],
    );
  }
}

class CheckmeRingPacket {
  const CheckmeRingPacket({
    required this.header,
    required this.cmd,
    required this.payload,
  });

  final int header;
  final int cmd;
  final List<int> payload;
}

class CheckmeRingRealtime {
  const CheckmeRingRealtime({
    required this.spo2,
    required this.pulse,
    required this.steps,
    required this.battery,
    required this.chargeState,
    required this.motion,
    required this.pi,
    required this.wearState,
  });

  final int spo2;
  final int pulse;
  final int steps;
  final int battery;
  final int chargeState;
  final int motion;
  final int pi;
  final int wearState;

  bool get isWorn => wearState == 1;

  bool get isValid {
    if (!isWorn) return false;
    if (spo2 == 0 || spo2 == 0xFF) return false;
    if (pulse == 0 || pulse == 0xFFFF) return false;
    if (spo2 < 70 || spo2 > 100) return false;
    if (pulse < 30 || pulse > 250) return false;
    return true;
  }

  String get wearLabel {
    switch (wearState) {
      case 1:
        return '装着中';
      case 0:
        return '未装着';
      default:
        return '不明($wearState)';
    }
  }
}
