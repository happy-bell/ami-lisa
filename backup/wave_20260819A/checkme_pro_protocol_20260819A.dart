/// Checkme Pro / Advance（CheckADV）チェックモニター配信プロトコル。
/// Ported from Ring-Checkme-A&D/x-amibl789/checkmepro_monitor.py
/// Ring のコマンド枠とは別。配信開始後は A5 5A の 47バイト連続パケット。
class CheckmeProProtocol {
  static const serviceUuid = '14839ac4-7d7e-415c-9a42-167340cf2339';
  static const readUuid = '0734594a-a8e7-4b1a-a6b1-cd5243059a57';
  static const writeUuid = '8b00ace7-eb0b-49b0-bbe9-9aee0a26e1a3';
  static const statusUuid = 'e06d5efb-4f4a-45c0-9eb1-371ae5a14ad4';

  static const packetLen = 47;
  static const sync0 = 0xA5;
  static const sync1 = 0x5A;

  /// 配信開始 0xAA 0x01 0xFE 00 00 00 00 0x0A（実機確認済み）
  static const monitorStartCommand = <int>[
    0xAA,
    0x01,
    0xFE,
    0x00,
    0x00,
    0x00,
    0x00,
    0x0A,
  ];

  static const deviceNameKeys = <String>[
    'checkadv',
    'checkme pro',
    'checkmepro',
  ];

  static bool isProName(String name) {
    final lower = name.toLowerCase();
    return deviceNameKeys.any(lower.contains);
  }

  static String bytesToHex(List<int> data) {
    return data
        .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  static int? _u16(int lo, int hi, int min, int max) {
    final v = (lo & 0xFF) | ((hi & 0xFF) << 8);
    if (v == 0xFF || v == 0xFFFF) return null;
    if (v < min || v > max) return null;
    return v;
  }

  static int? _u8(int v, int min, int max) {
    final n = v & 0xFF;
    if (n == 0xFF) return null;
    if (n < min || n > max) return null;
    return n;
  }

  /// バッファから 47バイトパケットを切り出す。足りなければ null。
  static List<int>? popPacket(List<int> buffer) {
    while (true) {
      var i = 0;
      while (i < buffer.length - 1 &&
          !(buffer[i] == sync0 && buffer[i + 1] == sync1)) {
        i++;
      }
      if (i > 0) {
        buffer.removeRange(0, i);
      }
      if (buffer.length < 2 ||
          buffer[0] != sync0 ||
          buffer[1] != sync1) {
        if (buffer.length > 1) {
          buffer.removeRange(0, buffer.length - 1);
        }
        return null;
      }
      if (buffer.length < packetLen) return null;
      final packet = List<int>.from(buffer.sublist(0, packetLen));
      buffer.removeRange(0, packetLen);
      return packet;
    }
  }

  static int _s16le(int lo, int hi) {
    var v = (lo & 0xFF) | ((hi & 0xFF) << 8);
    if (v >= 0x8000) v -= 0x10000;
    return v;
  }

  static List<int> _s16x5(List<int> p, int offset) {
    return List<int>.generate(5, (i) {
      final o = offset + i * 2;
      return _s16le(p[o], p[o + 1]);
    });
  }

  static CheckmeProRealtime? parsePacket(List<int> p) {
    if (p.length < packetLen) return null;
    if (p[0] != sync0 || p[1] != sync1) return null;
    return CheckmeProRealtime(
      hr: _u16(p[14], p[15], 20, 250),
      pr: _u16(p[35], p[36], 20, 250),
      spo2: _u8(p[37], 50, 100),
      pi: (p[38] & 0xFF) == 0xFF ? null : (p[38] & 0xFF) / 10.0,
      seq: p[45] & 0xFF,
      ecgSamples: _s16x5(p, 4),
      plethSamples: _s16x5(p, 25),
    );
  }
}

class CheckmeProRealtime {
  const CheckmeProRealtime({
    this.hr,
    this.pr,
    this.spo2,
    this.pi,
    this.seq = 0,
    this.ecgSamples = const [],
    this.plethSamples = const [],
  });

  final int? hr;
  final int? pr;
  final int? spo2;
  final double? pi;
  final int seq;
  final List<int> ecgSamples;
  final List<int> plethSamples;

  bool get isValid =>
      spo2 != null && hr != null && pr != null;

  CheckmeProRealtime merge(CheckmeProRealtime next) {
    return CheckmeProRealtime(
      hr: next.hr ?? hr,
      pr: next.pr ?? pr,
      spo2: next.spo2 ?? spo2,
      pi: next.pi ?? pi,
      seq: next.seq,
      ecgSamples: next.ecgSamples.isNotEmpty ? next.ecgSamples : ecgSamples,
      plethSamples:
          next.plethSamples.isNotEmpty ? next.plethSamples : plethSamples,
    );
  }
}
