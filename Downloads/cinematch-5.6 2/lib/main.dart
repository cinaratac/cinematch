import 'dart:io'; // Platform kontrolü için eklendi
// ignore_for_file: deprecated_member_use

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/auth/auth_gate.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// App Check importu
import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Telefonlarda portreyi koru; tablet ve katlanabilirlerde yeniden
  // boyutlandırma ile kullanıcının yön tercihine izin ver.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
  final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
  final isCompact = logicalWidth < 600 || logicalHeight < 600;
  await SystemChrome.setPreferredOrientations(
    isCompact
        ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : DeviceOrientation.values,
  );

  // 2. Firebase Başlatma
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- KRİTİK iOS AYARI ---
  // Uygulama açıkken (foreground) bildirimlerin tepeden düşmesini sağlar.
  if (!kIsWeb && Platform.isIOS) {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
  }

  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode
        ? AndroidProvider.playIntegrity
        : AndroidProvider.debug,
    // App Attest her iOS cihazında kullanılamayabilir. Firebase'de hem App
    // Attest hem DeviceCheck yapılandırıldığı için release sürümünde güvenli
    // fallback kullan; aksi halde callable istekleri `unauthenticated` olur.
    appleProvider: kReleaseMode
        ? AppleProvider.appAttestWithDeviceCheckFallback
        : AppleProvider.debug,
  );

  // Firestore Ayarları
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024,
  );

  // --- KAYITLI TEMAYI YÜKLE ---
  final prefs = await SharedPreferences.getInstance();
  final String? savedTheme = prefs.getString('themeMode');

  if (savedTheme == 'light') {
    ThemeBridge.themeMode.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    ThemeBridge.themeMode.value = ThemeMode.dark;
  } else {
    ThemeBridge.themeMode.value = ThemeMode.system;
  }

  // Bildirim Servis Başlangıcı
  if (!kIsWeb) {
    await NotificationService.I.init();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeBridge.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: NotificationService.I.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Cinematch',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const AuthGate(),
        );
      },
    );
  }
}
