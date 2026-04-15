import 'dart:math';

import 'package:flutter/foundation.dart';

/// Données persistées d’un Biti (identité, stats, apparence).
@immutable
class BitiProfile {
  const BitiProfile({
    required this.id,
    required this.name,
    required this.hunger,
    required this.energy,
    required this.mood,
    required this.xp,
    this.sleeping = false,
    this.isDead = false,
    this.themePresetIndex = 0,
    this.customColorA,
    this.customColorB,
  });

  /// Identifiant stable (liste, transfert, suppression).
  final String id;

  factory BitiProfile.fromJson(Map<String, dynamic> json) {
    final dynamic rawName = json['name'];
    final String name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : defaultName;
    final String id = _readId(json['id'], name: name, xp: json['xp']);
    return BitiProfile(
      id: id,
      name: name,
      hunger: _readInt(json['hunger'], fallback: 75).clamp(0, 100),
      energy: _readInt(json['energy'], fallback: 80).clamp(0, 100),
      mood: _readInt(json['mood'], fallback: 72).clamp(0, 100),
      xp: _readInt(json['xp'], fallback: 0).clamp(0, 1 << 30),
      sleeping: json['sleeping'] == true,
      isDead: json['isDead'] == true,
      themePresetIndex: _readInt(
        json['themePresetIndex'],
        fallback: 0,
      ).clamp(0, 1 << 20),
      customColorA: _readNullableInt(json['customColorA']),
      customColorB: _readNullableInt(json['customColorB']),
    );
  }

  static String createId() =>
      'b_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  static String _readId(Object? raw, {required String name, Object? xp}) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final int x = _readInt(xp, fallback: 0);
    return 'legacy_${name.hashCode}_$x';
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static const String defaultName = 'Biti';

  final String name;
  final int hunger;
  final int energy;
  final int mood;
  final int xp;
  final bool sleeping;
  final bool isDead;

  /// Index dans [BitiThemePair.presets] si pas de couleurs perso.
  final int themePresetIndex;

  /// Couleur « claire » (ARGB 32 bits), optionnelle.
  final int? customColorA;

  /// Couleur « foncée » (ARGB 32 bits), optionnelle.
  final int? customColorB;

  /// Sérialisation complète (stockage + transfert BLE : apparence toujours présente).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'hunger': hunger,
    'energy': energy,
    'mood': mood,
    'xp': xp,
    'sleeping': sleeping,
    'isDead': isDead,
    'themePresetIndex': themePresetIndex,
    'customColorA': customColorA,
    'customColorB': customColorB,
  };

  BitiProfile copyWith({
    String? id,
    String? name,
    int? hunger,
    int? energy,
    int? mood,
    int? xp,
    bool? sleeping,
    bool? isDead,
    int? themePresetIndex,
    Object? customColorA = _sentinel,
    Object? customColorB = _sentinel,
  }) {
    return BitiProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      hunger: hunger ?? this.hunger,
      energy: energy ?? this.energy,
      mood: mood ?? this.mood,
      xp: xp ?? this.xp,
      sleeping: sleeping ?? this.sleeping,
      isDead: isDead ?? this.isDead,
      themePresetIndex: themePresetIndex ?? this.themePresetIndex,
      customColorA: identical(customColorA, _sentinel)
          ? this.customColorA
          : customColorA as int?,
      customColorB: identical(customColorB, _sentinel)
          ? this.customColorB
          : customColorB as int?,
    );
  }

  static const Object _sentinel = Object();

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }
}
