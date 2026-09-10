import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// このテレビに登録したスマートボタンを覚えておく。
///
/// **登録はテレビの中だけに持つ。** サーバーとのやりとりはしない。
/// （Webとの連携は後の作業）
///
/// 登録してから聞き取る形にしている。理由は3つ。
///   ・近所に同じ製品があっても拾わない（誤って呼び出さない）
///   ・チップ側で「そのMACだけ」に絞れる。起こされる回数が減り、
///     テレビのリモコン（BLE）への影響が小さくなる
///   ・未登録なら一切スキャンしない。既定で無害
class RatocButtonStore {
  RatocButtonStore._();
  static final RatocButtonStore instance = RatocButtonStore._();

  static const _prefsKeyMac = 'ratoc_button_mac';
  static const _prefsKeyName = 'ratoc_button_name';

  String _mac = '';
  String _name = '';

  /// 登録されている MAC。未登録なら空。
  String get mac => _mac;
  String get name => _name;
  bool get isRegistered => _mac.isNotEmpty;

  /// 見比べる形にそろえる。区切りを外して大文字にする。
  static String normalize(String v) =>
      v.replaceAll(RegExp(r'[:\-\s.]'), '').toUpperCase();

  bool matches(String candidate) =>
      isRegistered && normalize(candidate) == normalize(_mac);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mac = prefs.getString(_prefsKeyMac) ?? '';
      _name = prefs.getString(_prefsKeyName) ?? '';
    } catch (e) {
      debugPrint('[RatocStore] 読めず $e');
    }
    debugPrint(isRegistered
        ? '[RatocStore] 登録済み $_name ($_mac)'
        : '[RatocStore] 未登録');
  }

  Future<void> save(String mac, String name) async {
    _mac = mac.toUpperCase();
    _name = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyMac, _mac);
      await prefs.setString(_prefsKeyName, _name);
    } catch (e) {
      debugPrint('[RatocStore] 書けず $e');
    }
    debugPrint('[RatocStore] 登録 $_name ($_mac)');
  }

  Future<void> clear() async {
    _mac = '';
    _name = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyMac);
      await prefs.remove(_prefsKeyName);
    } catch (e) {
      debugPrint('[RatocStore] 消せず $e');
    }
    debugPrint('[RatocStore] 登録を外しました');
  }
}
