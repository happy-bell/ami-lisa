/// RATOC RS-SCBTN2（Bluetooth Smart Button）の広告パケット。
///
/// Manufacturer Specific Data (AD Type 0xFF)
///   Offset 0-1: Manufacture ID 0x0B60（RATOC）
///   Offset 2  : ボタンステータス  00=未押し / 01=押下
///   Offset 3  : 電池残量（0-100）
///
/// ローカル名: SCBTN-XXXX（XXXX は MAC 下4桁）
class ScbtnProtocol {
  static const int manufacturerId = 0x0B60;
  static const String namePrefix = 'SCBTN-';

  static bool isScbtnName(String name) {
    final n = name.trim().toUpperCase();
    return n.startsWith(namePrefix);
  }

  /// 登録IDと広告を突き合わせる。
  /// 管理画面のボタンID、SCBTN-XXXX、XXXX、MAC下4桁のいずれでもよい。
  static bool matchesId(String registered, String name, String mac) {
    final want = _norm(registered);
    if (want.isEmpty) return false;
    final n = _norm(name);
    final m = _norm(mac);
    final tail = n.startsWith('SCBTN') ? n.substring(5) : n;
    final macTail = m.length >= 4 ? m.substring(m.length - 4) : m;
    return want == n ||
        want == tail ||
        want == m ||
        want == macTail ||
        n == 'SCBTN$want';
  }

  static String displayId(String name, String mac) {
    final n = name.trim();
    if (isScbtnName(n)) return n.toUpperCase();
    final m = _norm(mac);
    if (m.length >= 4) return '$namePrefix${m.substring(m.length - 4)}';
    return n.isNotEmpty ? n : mac;
  }

  static ScbtnAdvertisement? parse({
    required String name,
    required String mac,
    required Map<int, List<int>> manufacturerData,
  }) {
    List<int>? payload = manufacturerData[manufacturerId];
    payload ??= manufacturerData.values.cast<List<int>?>().firstWhere(
          (v) => v != null && _looksLikeScbtn(v),
          orElse: () => null,
        );
    if (payload == null) {
      if (!isScbtnName(name)) return null;
      return ScbtnAdvertisement(
        name: name,
        mac: mac,
        pressed: false,
        battery: null,
      );
    }
    final statusIndex = payload.length >= 4 ? 2 : 0;
    final battIndex = payload.length >= 4 ? 3 : 1;
    final status = payload.length > statusIndex ? payload[statusIndex] : 0;
    final battery = payload.length > battIndex ? payload[battIndex] : null;
    return ScbtnAdvertisement(
      name: name,
      mac: mac,
      pressed: status == 1,
      battery: battery,
    );
  }

  static bool _looksLikeScbtn(List<int> v) {
    if (v.length < 2) return false;
    if (v.length >= 4 && v[0] == 0x60 && v[1] == 0x0B) return true;
    return v.length == 2 && (v[0] == 0 || v[0] == 1);
  }

  static String _norm(String s) {
    return s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
  }
}

class ScbtnAdvertisement {
  const ScbtnAdvertisement({
    required this.name,
    required this.mac,
    required this.pressed,
    this.battery,
  });

  final String name;
  final String mac;
  final bool pressed;
  final int? battery;

  String get id => ScbtnProtocol.displayId(name, mac);
}
