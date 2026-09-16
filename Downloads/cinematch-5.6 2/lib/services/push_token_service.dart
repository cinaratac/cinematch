import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Saves FCM token(s) under users/{uid}/fcmTokens/{token}
class PushTokenService {
  PushTokenService._();
  static final PushTokenService I = PushTokenService._();

  // DÜZELTME: 'String?' yerine 'String' yaptık. Token refresh stream'i null dönmez.
  Stream<String>? _tokenStream;
  bool _isInitializing = false;

  Future<void> start() async {
    // Eğer zaten işlem yapılıyorsa tekrar başlatma
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Initial token save
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _saveToken(user.uid, token);
      }

      // Listen for token refresh
      if (_tokenStream == null) {
        _tokenStream = FirebaseMessaging.instance.onTokenRefresh;
        _tokenStream!.listen((t) async {
          final u = FirebaseAuth.instance.currentUser;
          // t artık String olduğu için hata vermez
          if (u != null) await _saveToken(u.uid, t);
        });
      }
    } catch (e) {
      // Hata olsa bile devam et
    } finally {
      _isInitializing = false; // Kilidi aç
    }
  }

  Future<void> stop() async {
    // No-op: we keep historical tokens for multi-device support.
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token);
      await ref.set({
        'token': token,
        'platform': Platform.operatingSystem,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
