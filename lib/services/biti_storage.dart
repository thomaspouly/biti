import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/biti_profile.dart';
import '../theme/biti_theme_pair.dart';
import 'lifecycle_service.dart';

/// Persistance [SharedPreferences] du profil Biti.
class BitiStorage {
  BitiStorage._();

  static const String _profileKey = 'biti_profile_v1';
  static const String _themePresetKey = 'biti_theme_preset_v1';

  static Future<BitiProfile?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> map = jsonDecode(raw) as Map<String, dynamic>;
      return BitiProfile.fromJson(map);
    } on Object {
      return null;
    }
  }

  static Future<void> save(BitiProfile profile) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  static Future<void> saveFromLifecycle(LifecycleService lifecycle) {
    return save(lifecycle.toProfile());
  }

  /// Index 0…4 dans [BitiThemePair.presets].
  static Future<int> loadThemePresetIndex() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? i = prefs.getInt(_themePresetKey);
    if (i == null || i < 0 || i >= BitiThemePair.presets.length) {
      return 0;
    }
    return i;
  }

  static Future<void> saveThemePresetIndex(int index) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int clamped = index.clamp(0, BitiThemePair.presets.length - 1);
    await prefs.setInt(_themePresetKey, clamped);
  }
}
