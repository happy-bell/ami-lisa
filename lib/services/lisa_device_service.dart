import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/appdefine.dart';

/// TVリサ（サブスク版）のアクティベーションと契約状態の確認。
///
/// テレビでは文字入力をさせない。画面に6桁の番号を出し、家族が会員ページで
/// その番号を入れると紐付く。以後テレビは端末トークンだけを保持し、
/// パスワードは一切持たない。会員ページから解除されればトークンが無効になる。
class LisaDeviceService {
  LisaDeviceService._();
  static final LisaDeviceService instance = LisaDeviceService._();

  static const _prefsToken = 'lisa_device_token';

  static const _timeout = Duration(seconds: 10);

  void _log(String line) {
    // ignore: avoid_print
    print('[Lisa] $line');
  }

  String get _base => '${AppDefine.baseURL}lisa/device/';

  // --------------------------------------------------------------------
  // 端末トークンの保存・取得
  // --------------------------------------------------------------------

  static Future<String> savedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsToken) ?? '';
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsToken, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsToken);
  }

  // --------------------------------------------------------------------
  // アクティベーション
  // --------------------------------------------------------------------

  /// 6桁の番号を発行してもらう。画面に大きく表示する。
  Future<LisaCode?> requestCode(String androidId) async {
    try {
      final res = await http.post(
        Uri.parse('${_base}code'),
        body: {'android_id': androidId},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        _log('code status=${res.statusCode}');
        return null;
      }
      final data = json.decode(res.body);
      if (data is! Map || data['ok'] != true) return null;
      _log('code=${data['code']}');
      return LisaCode(
        code: (data['code'] ?? '').toString(),
        claimToken: (data['claim_token'] ?? '').toString(),
        expiresIn: (data['expires_in'] is int) ? data['expires_in'] as int : 600,
      );
    } catch (e) {
      _log('requestCode error $e');
      return null;
    }
  }

  /// 紐付けが済んだかを確認する。済んでいれば端末トークンを保存して true。
  ///
  /// 戻り値は 'waiting' / 'linked' / 'expired' / 'error'。
  Future<String> pollStatus(String claimToken) async {
    try {
      final res = await http.post(
        Uri.parse('${_base}status'),
        body: {'claim_token': claimToken},
      ).timeout(_timeout);
      if (res.statusCode != 200) return 'error';

      final data = json.decode(res.body);
      if (data is! Map) return 'error';

      final state = (data['state'] ?? '').toString();
      if (state != 'linked') return state.isEmpty ? 'error' : state;

      final token = (data['device_token'] ?? '').toString();
      if (token.isEmpty) return 'error';
      await saveToken(token);
      _log('linked mst_id=${data['mst_id']}');
      return 'linked';
    } catch (e) {
      _log('pollStatus error $e');
      return 'error';
    }
  }

  // --------------------------------------------------------------------
  // ログインと契約状態
  // --------------------------------------------------------------------

  /// 端末トークンでログインする。応答は既存の app/login と同じ形。
  /// 解除済みなら null を返すので、呼び出し側はアクティベーション画面へ戻す。
  Future<Map<String, dynamic>?> loginWithToken() async {
    final token = await savedToken();
    if (token.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('${_base}login'),
        body: {'device_token': token, 'device': 'tv'},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        _log('login status=${res.statusCode}');
        return null;
      }
      final data = json.decode(res.body);
      if (data is! Map) return null;
      if (data['cnt'] != '1') {
        _log('login rejected: ${data['lisa'] ?? data['cnt']}');
        // 解除された場合はトークンを捨て、次回アクティベーション画面から始める。
        if (data['lisa'] == 'revoked') await clearToken();
        return null;
      }
      return Map<String, dynamic>.from(data);
    } catch (e) {
      _log('loginWithToken error $e');
      return null;
    }
  }

  /// 契約状態の確認と生存通知。
  ///
  /// 返す値は次の4つ。
  ///   active  … 使ってよい
  ///   revoked … 解除・解約された。使わせてはいけない
  ///   unknown … 契約が見つからない。判断がつかないので止めない
  ///   offline … 通信できなかった。止めない
  ///
  /// **通信できないときに止めないのが肝心**。回線が切れただけで
  /// 見守りが使えなくなると、本当に困るときに役に立たない。
  /// 止めるのは、サーバーがはっきり「解除された」と答えたときだけにする。
  Future<String> checkEntitlement() async {
    final token = await savedToken();
    if (token.isEmpty) return 'revoked';
    try {
      final res = await http.post(
        Uri.parse('${_base}session'),
        body: {'device_token': token},
      ).timeout(_timeout);
      if (res.statusCode != 200) {
        _log('session HTTP ${res.statusCode}');
        return 'offline';
      }

      final data = json.decode(res.body);
      if (data is! Map) return 'offline';

      if (data['ok'] == true) {
        _log('契約あり status=${data['status']} limit=${data['feature_limit']}');
        return 'active';
      }

      final state = (data['state'] ?? '').toString();
      _log('session state=$state');
      return state == 'revoked' ? 'revoked' : 'unknown';
    } catch (e) {
      _log('checkEntitlement 通信できず $e');
      return 'offline';
    }
  }
}

class LisaCode {
  LisaCode({required this.code, required this.claimToken, required this.expiresIn});

  final String code;
  final String claimToken;
  final int expiresIn;

  /// 表示用に3桁ずつ区切る。「477 091」のように読み上げやすくする。
  String get spaced =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}
