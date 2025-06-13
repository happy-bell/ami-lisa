import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:amiapp/app.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/services/appmanager.dart';

import 'notifiers/app_notifier.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  print('Handling a background message ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    name: 'jpfrinurse',
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );
  try {
    final token = await messaging.getToken();
    if (token != null) {
      AppManager.fcmtoken = token;
    }
    print('FCM TOKEN: $token');
  } catch (e) {
    print(e);
  }
  runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppStore()),
          ChangeNotifierProvider(create: (_) => AddressStore()),
        ],
        child: App(),
      )
  );
}
