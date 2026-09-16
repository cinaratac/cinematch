import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingDraftService {
  const OnboardingDraftService._();

  static String _key(String uid) => 'onboarding_draft_v1_$uid';

  static Future<Map<String, dynamic>?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      await prefs.remove(_key(uid));
      return null;
    }
  }

  static Future<void> save(String uid, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), jsonEncode(data));
  }

  static Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}
