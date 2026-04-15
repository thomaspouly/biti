import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/biti_collection.dart';
import '../models/biti_profile.dart';
import '../theme/biti_theme_pair.dart';
import 'lifecycle_service.dart';

/// Persistance [SharedPreferences] : liste de Biti + sélection.
class BitiStorage {
  BitiStorage._();

  static const String _collectionKey = 'biti_collection_v2';
  static const String _profileKeyV1 = 'biti_profile_v1';
  static const String _guestKeyV1 = 'biti_guest_profile_v1';
  static const String _themePresetKey = 'biti_theme_preset_v1';
  static const String _legacyAutostartKey = 'biti_legacy_autostart_v1';

  static BitiProfile? _decodeProfile(String raw) {
    try {
      final Map<String, dynamic> map =
          jsonDecode(raw) as Map<String, dynamic>;
      return BitiProfile.fromJson(map);
    } on Object {
      return null;
    }
  }

  /// Charge la collection ; migre v1 → v2 si besoin.
  static Future<BitiCollection> loadCollection() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_collectionKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Map<String, dynamic> map =
            jsonDecode(raw) as Map<String, dynamic>;
        return BitiCollection.fromJson(map);
      } on Object {
        /* fallback migration */
      }
    }

    final BitiProfile? primary = _readV1Primary(prefs);
    if (primary != null) {
      final BitiProfile? guest = _readV1Guest(prefs);
      final List<BitiProfile> list = <BitiProfile>[primary];
      if (guest != null) list.add(guest);
      final BitiCollection migrated = BitiCollection(
        profiles: list,
        selectedId: primary.id,
      );
      await saveCollection(migrated);
      await prefs.remove(_profileKeyV1);
      await prefs.remove(_guestKeyV1);
      return migrated;
    }

    if (prefs.getBool(_legacyAutostartKey) != true) {
      await prefs.setBool(_legacyAutostartKey, true);
      final BitiThemePair d = BitiThemePair.presets[0];
      final BitiProfile seed = BitiProfile(
        id: BitiProfile.createId(),
        name: BitiProfile.defaultName,
        hunger: 75,
        energy: 80,
        mood: 72,
        xp: 0,
        sleeping: false,
        isDead: false,
        themePresetIndex: 0,
        customColorA: d.a.toARGB32(),
        customColorB: d.b.toARGB32(),
      );
      final BitiCollection first = BitiCollection(
        profiles: <BitiProfile>[seed],
        selectedId: seed.id,
      );
      await saveCollection(first);
      return first;
    }

    return const BitiCollection(profiles: <BitiProfile>[]);
  }

  static BitiProfile? _readV1Primary(SharedPreferences prefs) {
    final String? raw = prefs.getString(_profileKeyV1);
    if (raw == null || raw.isEmpty) return null;
    return _decodeProfile(raw);
  }

  static BitiProfile? _readV1Guest(SharedPreferences prefs) {
    final String? raw = prefs.getString(_guestKeyV1);
    if (raw == null || raw.isEmpty) return null;
    return _decodeProfile(raw);
  }

  static Future<void> saveCollection(BitiCollection collection) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _collectionKey,
      jsonEncode(collection.toJson()),
    );
  }

  /// Fusionne les stats du cycle de vie dans le profil [base] puis enregistre.
  static Future<void> saveLifecycleIntoProfile(
    LifecycleService life,
    BitiProfile base,
  ) async {
    final BitiProfile merged = base.copyWith(
      name: life.name,
      hunger: life.hunger,
      energy: life.energy,
      mood: life.mood,
      xp: life.xp,
      sleeping: life.sleeping,
      isDead: life.isDead,
    );
    final BitiCollection c = await loadCollection();
    await saveCollection(c.upsertProfile(merged));
  }

  /// Ajoute un Biti vierge et le renvoie (déjà persisté, sélectionné).
  static Future<BitiProfile> addNewBiti() async {
    final BitiCollection c = await loadCollection();
    final BitiThemePair d = BitiThemePair.presets[0];
    final BitiProfile p = BitiProfile(
      id: BitiProfile.createId(),
      name: BitiProfile.defaultName,
      hunger: 75,
      energy: 80,
      mood: 72,
      xp: 0,
      sleeping: false,
      isDead: false,
      themePresetIndex: 0,
      customColorA: d.a.toARGB32(),
      customColorB: d.b.toARGB32(),
    );
    final BitiCollection next = BitiCollection(
      profiles: <BitiProfile>[...c.profiles, p],
      selectedId: p.id,
    );
    await saveCollection(next);
    return p;
  }

  /// Réception BLE : ajoute le profil reçu (nouvel [id] si absent) et le sélectionne.
  static Future<BitiProfile> appendReceivedProfile(BitiProfile received) async {
    final BitiCollection c = await loadCollection();
    BitiProfile withId = received.id.trim().isEmpty
        ? received.copyWith(id: BitiProfile.createId())
        : received;
    if (c.profiles.any((BitiProfile p) => p.id == withId.id)) {
      withId = withId.copyWith(id: BitiProfile.createId());
    }
    final BitiCollection next = BitiCollection(
      profiles: <BitiProfile>[...c.profiles, withId],
      selectedId: withId.id,
    );
    await saveCollection(next);
    return withId;
  }

  /// Après envoi réussi : retire ce profil de la liste.
  static Future<void> removeProfileById(String id) async {
    final BitiCollection c = await loadCollection();
    final List<BitiProfile> list = <BitiProfile>[
      for (final BitiProfile p in c.profiles)
        if (p.id != id) p,
    ];
    String? newSel = c.selectedId;
    if (newSel == id || (newSel != null && !list.any((BitiProfile p) => p.id == newSel))) {
      newSel = list.isEmpty ? null : list.first.id;
    }
    await saveCollection(BitiCollection(profiles: list, selectedId: newSel));
  }

  static Future<void> clearAllProfiles() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_collectionKey);
    await prefs.remove(_profileKeyV1);
    await prefs.remove(_guestKeyV1);
  }

  /// Met à jour l’apparence / meta sans toucher aux stats (ex. thème depuis les réglages).
  static Future<void> upsertProfile(BitiProfile profile) async {
    final BitiCollection c = await loadCollection();
    await saveCollection(c.upsertProfile(profile));
  }

  /// Change le Biti actif (sans modifier les stats).
  static Future<void> setSelectedId(String id) async {
    final BitiCollection c = await loadCollection();
    if (!c.profiles.any((BitiProfile p) => p.id == id)) return;
    await saveCollection(c.copyWith(selectedId: id));
  }

  /// Index thème global (écran vide, splash) — conservé pour rétrocompat.
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
