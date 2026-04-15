import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/biti_profile.dart';
import 'lifecycle_service.dart';

/// Persistance [SharedPreferences] du profil Biti.
class BitiStorage {
  BitiStorage._();

  static const String _profileKey = 'biti_profile_v1';

  static Future<BitiProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BitiProfile.fromJson(map);
    } on Object {
      return null;
    }
  }

  static Future<void> save(BitiProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  static Future<void> saveFromLifecycle(LifecycleService lifecycle) {
    return save(lifecycle.toProfile());
  }
}
