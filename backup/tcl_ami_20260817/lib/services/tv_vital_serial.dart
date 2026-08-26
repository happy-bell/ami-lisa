import 'package:amiapp/helpers/tv_util.dart';

/// TCL の測定は Android ID で送る。ラズパイのシリアルは使わない。
/// スタッフ画面に出すには ami_serial_nos へ
/// serial_no + code + mst_id の行が必要。
class TvVitalSerial {
  TvVitalSerial._();
  static final TvVitalSerial instance = TvVitalSerial._();

  String _androidId = '';

  String get androidId => _androidId;

  void _log(String line) {
    // ignore: avoid_print
    print('[TvVitalSerial] $line');
  }

  /// Android TV のシリアルだけを返す。
  Future<List<String>> resolvePostSerials() async {
    if (_androidId.isEmpty) {
      _androidId = await TvUtil.getAndroidId();
    }
    _log('post sn=$_androidId');
    if (_androidId.isEmpty) return const [];
    return <String>[_androidId];
  }
}
