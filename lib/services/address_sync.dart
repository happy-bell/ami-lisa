import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/services/appmanager.dart';

/// 通話相手の一覧（アドレス帳）をサーバーから取り直す。
///
/// これまで一覧はログイン時に受け取ったものを使い回すだけで、
/// 取り直す手段は「設定 → リスト更新」しかなかった。そのため
/// あとから増えた家族や、登録し直したテレビが一覧に出てこなかった。
///
/// 起動のたびに取り直せば、利用者が設定を触らなくても最新になる。
class AddressSync {
  AddressSync._();

  /// 取り直しの間隔。短くしてもサーバーに負担がかかるだけで、
  /// 家族が増えるのはそう頻繁ではない。
  static const _minInterval = Duration(minutes: 10);

  static DateTime? _lastAt;
  static bool _running = false;

  /// サーバーから取り直して保存する。
  ///
  /// 取れたら保存済みの中身を返す。取れなければ null を返し、
  /// **保存済みの一覧はそのまま残す**。通信できないときに
  /// 一覧が空になると、電話をかけられなくなってしまう。
  static Future<dynamic> fetch({bool force = false}) async {
    if (_running) return null;

    if (!force) {
      final last = _lastAt;
      if (last != null && DateTime.now().difference(last) < _minInterval) {
        return null;
      }
    }

    final url = _url();
    if (url.isEmpty) return null;

    _running = true;
    try {
      final res = await Dio().get(url).timeout(const Duration(seconds: 15));
      final data = res.data;
      if (data == null) return null;

      final key = AppDefine.amiApp ? 'address' : 'ADDRESS';
      final list = data[key];
      if (list == null) {
        // ignore: avoid_print
        print('[AddressSync] $key が入っていない');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('address', json.encode(list));
      _lastAt = DateTime.now();
      // ignore: avoid_print
      print('[AddressSync] 一覧を更新しました');
      return list;
    } catch (e) {
      // ignore: avoid_print
      print('[AddressSync] 取得できず $e');
      return null;
    } finally {
      _running = false;
    }
  }

  /// 取得先。ログインの種類によって窓口が違う。
  static String _url() {
    try {
      if (AppDefine.amiApp) {
        final code = AppManager.settings['DELEGATORCODE'];
        final token = AppManager.settings['api_token'];
        if (code == null || token == null) return '';

        if (AppManager.isManager) {
          return '${AppDefine.baseURL}app/staff_address_list'
              '?code=$code&token=$token';
        }
        final mstId =
            (AppManager.settings['MYID'] ?? '').toString().replaceAll('${code}_', '');
        return '${AppDefine.baseURL}app/address_list'
            '?code=$code&mst_id=$mstId&token=$token';
      }

      final host = AppManager.settings['MCSURL'];
      if (host == null || host.toString().isEmpty) return '';
      return 'https://$host/json/appaddresslist'
          '?gcd=${AppManager.settings['MCSGROUPCODE']}'
          '&ccd=${AppManager.settings['MCSCLINICCODE']}'
          '&group=${AppManager.settings['addressGroup']}'
          '&id=${AppManager.settings['myId']}'
          '&token=${AppDefine.getRMSToken()}';
    } catch (e) {
      // ignore: avoid_print
      print('[AddressSync] 取得先を組み立てられず $e');
      return '';
    }
  }
}
