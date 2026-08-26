import 'package:amiapp/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui';

/// FCM バックグラウンド着信 → TVオーバーレイ表示
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    name: 'jpfrinurse',
    options: DefaultFirebaseOptions.currentPlatform,
  );
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    var waiting = prefs.getString('tv_TV_CALL_WAITING') == '1';
    var autoReceive = prefs.getString('tv_AUTO_RECEIVE') == '1';
    if (!waiting || !autoReceive) {
      final appString = prefs.getString('appsettings');
      if (appString != null) {
        waiting = waiting ||
            appString.contains('"TV_CALL_WAITING":"1"') ||
            appString.contains('"TV_CALL_WAITING": "1"');
        autoReceive = autoReceive ||
            appString.contains('"AUTO_RECEIVE":"1"') ||
            appString.contains('"AUTO_RECEIVE": "1"');
      }
    }
    var piLayout = prefs.getString('tv_TV_LAYOUT') == 'pi';
    final appStringForLayout = prefs.getString('appsettings');
    if (appStringForLayout != null) {
      piLayout = piLayout ||
          appStringForLayout.contains('"TV_LAYOUT":"pi"') ||
          appStringForLayout.contains('"TV_LAYOUT": "pi"');
    }
    if (!waiting && !piLayout) return;

    final callerId = _callerIdFromMessage(message);
    if (callerId.isEmpty) return;

    const channel = MethodChannel('jp.amiplus.lisa/tv');
    try {
      await channel.invokeMethod('captureForegroundApp');
    } catch (_) {}
    await channel.invokeMethod('wakeScreen');
    // ami-EX / ami-LiSA とも自動応答ONなら確認なしで繋ぐ。
    if (autoReceive) {
      await channel.invokeMethod('acceptIncomingCall', {
        'callerId': callerId,
        'callerName': '着信',
      });
    } else {
      await channel.invokeMethod('showIncomingCallOverlay', {
        'callerId': callerId,
        'callerName': '着信',
      });
    }
  } catch (e) {
    // ignore
  }
}

String _callerIdFromMessage(RemoteMessage message) {
  final data = message.data;
  for (final key in ['udid', 'callerId', 'from', 'id']) {
    final v = data[key]?.toString();
    if (v != null && v.isNotEmpty) return v;
  }
  final body = message.notification?.body ?? '';
  final title = message.notification?.title ?? '';
  for (final text in [title, body]) {
    var pos1 = text.indexOf('[');
    var pos2 = text.indexOf(']');
    if (pos1 < 0 || pos2 <= pos1) {
      pos1 = text.indexOf('【');
      pos2 = text.indexOf('】');
    }
    if (pos1 >= 0 && pos2 > pos1) {
      return text.substring(pos1 + 1, pos2);
    }
  }
  return '';
}
