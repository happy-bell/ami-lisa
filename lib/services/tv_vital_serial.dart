import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';

/// Google TV の Android ID を ami_serial_nos の serial_no として使う。
/// ログイン後に code / mst_id をサーバーへ送り、管理画面で先に登録した行を更新する。
class TvVitalSerial {
  TvVitalSerial._();
  static final TvVitalSerial instance = TvVitalSerial._();

  String _androidId = '';
  bool _bindStarted = false;

  String get androidId => _androidId;

  void _log(String line) {
    // ignore: avoid_print
    print('[TvVitalSerial] $line');
  }

  String _mstId() {
    final my = AppManager.myId;
    final code = AppManager.delegatorCode;
    if (code.isNotEmpty && my.startsWith('${code}_')) {
      return my.substring(code.length + 1);
    }
    final i = my.lastIndexOf('_');
    if (i >= 0 && i < my.length - 1) {
      return my.substring(i + 1);
    }
    return my;
  }

  /// ログイン後・ホーム起動時。シリアル照合して code / mst_id を保存する。
  Future<void> bindOnLogin() async {
    if (!TvUtil.isTelevision) return;
    if ((AppManager.settings['MCSTYPE'] ?? '').toString() == '5') return;
    if (_bindStarted) return;
    _bindStarted = true;
    try {
      await _bindOnce();
    } catch (e) {
      _bindStarted = false;
      _log('bind error $e');
    }
  }

  Future<void> _bindOnce() async {
    if (_androidId.isEmpty) {
      _androidId = await TvUtil.getAndroidId();
    }
    final sn = _androidId;
    final code = AppManager.delegatorCode;
    final mstId = _mstId();
    if (sn.isEmpty || code.isEmpty || mstId.isEmpty) {
      _log('bind skipped sn=$sn code=$code mst_id=$mstId');
      _bindStarted = false;
      return;
    }

    final body = {
      'sn': sn,
      'code': code,
      'mst_id': mstId,
      'token': AppDefine.getDelegatorToken(),
    };
    final urls = <String>[
      '${AppDefine.mcsaURL}newhealthcare46amip4/tv_bind_serial.php',
      '${AppDefine.mcsaURL}newhealthcare46amip3/tv_bind_serial.php',
      '${AppDefine.mcsaURL}newhealthcare46docp/tv_bind_serial.php',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 8));
        _log('bind $url status=${response.statusCode} body=${response.body}');
        if (response.statusCode != 200) continue;
        final data = json.decode(response.body);
        if (data is Map && data['status']?.toString() == 'ok') {
          _log(
              'bound sn=$sn code=$code mst_id=$mstId action=${data['action']}');
          return;
        }
      } catch (e) {
        _log('bind $url failed $e');
      }
    }
    _bindStarted = false;
    _log('bind failed sn=$sn code=$code mst_id=$mstId');
  }

  /// 測定POST用のシリアル。Google TV は Android ID。
  Future<List<String>> resolvePostSerials() async {
    if (_androidId.isEmpty) {
      _androidId = await TvUtil.getAndroidId();
    }
    _log('post sn=$_androidId');
    if (_androidId.isEmpty) return const [];
    return <String>[_androidId];
  }
}
