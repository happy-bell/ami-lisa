/// A&D UA-651 / UT201 / UC-352 の測定値デコード。
/// x-amibl789/ble.py と同じ計算。
enum AndVitalKind { blood, temp, weight }

class AndVitalCodec {
  AndVitalCodec._();

  static const bpService = '00001810-0000-1000-8000-00805f9b34fb';
  static const tempService = '00001809-0000-1000-8000-00805f9b34fb';
  static const weightService = '0000181d-0000-1000-8000-00805f9b34fb';
  static const cccd = '00002902-0000-1000-8000-00805f9b34fb';

  static const namePatterns = ['UA-651', 'UT201', 'UC-352', 'A&D_'];

  static bool nameMatches(String name) {
    return namePatterns.any(name.contains);
  }

  static String normalizeUuid(String uuid) {
    final u = uuid.toLowerCase().replaceAll('urn:uuid:', '');
    if (u.length == 4) {
      return '0000$u-0000-1000-8000-00805f9b34fb';
    }
    if (u.length == 8) {
      return '$u-0000-1000-8000-00805f9b34fb';
    }
    return u;
  }

  static AndVitalKind? kindForService(String uuid) {
    final n = normalizeUuid(uuid);
    if (n == bpService) return AndVitalKind.blood;
    if (n == tempService) return AndVitalKind.temp;
    if (n == weightService) return AndVitalKind.weight;
    return null;
  }

  /// IEEE 11073 16-bit SFLOAT (ble.py to_float_from11073_16bit_float)
  static double sfloat16(List<int> data) {
    if (data.length < 2) return 0;
    final raw = data[0] | (data[1] << 8);
    var mantissa = raw & 0x0fff;
    final exponent = raw >> 12;
    if (mantissa >= 0x0800) {
      mantissa = mantissa - 0x1000;
    }
    return (mantissa * _pow10(exponent) * 10).round() / 10.0;
  }

  /// IEEE 11073 32-bit FLOAT (ble.py to_float_from11073_32bit_float)
  static double float32(List<int> data) {
    if (data.length < 4) return 0;
    var mantissa = data[0] | (data[1] << 8) | (data[2] << 16);
    if (mantissa & 0x800000 != 0) mantissa = mantissa - 0x1000000;
    var exponent = data[3];
    if (exponent & 0x80 != 0) exponent = exponent - 0x100;
    return (mantissa * _pow10(exponent) * 10).round() / 10.0;
  }

  static double _pow10(int exp) {
    var v = 1.0;
    if (exp >= 0) {
      for (var i = 0; i < exp; i++) {
        v *= 10;
      }
    } else {
      for (var i = 0; i < -exp; i++) {
        v /= 10;
      }
    }
    return v;
  }

  /// UA-651: エラーは収縮期 0x07FF
  static AndBpReading? parseBp(List<int> data) {
    if (data.length < 7) return null;
    if (data[1] == 0xFF && data[2] == 0x07) return null;
    final sys = sfloat16(data.sublist(1, 3));
    final dia = sfloat16(data.sublist(3, 5));
    final map = sfloat16(data.sublist(5, 7));
    final flags = data[0];
    final timeStamp = (flags & 0x02) != 0;
    double pulse = 0;
    if (!timeStamp && data.length >= 9) {
      pulse = sfloat16(data.sublist(7, 9));
    } else if (timeStamp && data.length >= 16) {
      pulse = sfloat16(data.sublist(14, 16));
    }
    return AndBpReading(
      systolic: sys,
      diastolic: dia,
      map: map,
      pulse: pulse,
      rawLen: data.length,
    );
  }

  /// UT-201: エラー NaN 0xFF,0xFF,0x7F
  static double? parseTemp(List<int> data) {
    if (data.length < 5) return null;
    if (data[1] == 0xFF && data[2] == 0xFF && data[3] == 0x7F) return null;
    return float32(data.sublist(1, 5));
  }

  /// UC-352: (b1 + b2*256)*0.005 kg。エラー 0xFFFF
  static double? parseWeight(List<int> data) {
    if (data.length < 3) return null;
    if (data[1] == 0xFF && data[2] == 0xFF) return null;
    return (data[1] + data[2] * 256) * 0.005;
  }
}

class AndBpReading {
  AndBpReading({
    required this.systolic,
    required this.diastolic,
    required this.map,
    required this.pulse,
    required this.rawLen,
  });

  final double systolic;
  final double diastolic;
  final double map;
  final double pulse;
  final int rawLen;
}
