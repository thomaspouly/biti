import 'package:flutter/foundation.dart';

/// Données persistées de Biti (nom + stats principales).
@immutable
class BitiProfile {
  const BitiProfile({
    required this.name,
    required this.hunger,
    required this.energy,
    required this.mood,
    required this.xp,
    this.sleeping = false,
    this.isDead = false,
  });
  factory BitiProfile.fromJson(Map<String, dynamic> json) {
    final dynamic rawName = json['name'];
    final String name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : defaultName;
    return BitiProfile(
      name: name,
      hunger: _readInt(json['hunger'], fallback: 75).clamp(0, 100),
      energy: _readInt(json['energy'], fallback: 80).clamp(0, 100),
      mood: _readInt(json['mood'], fallback: 72).clamp(0, 100),
      xp: _readInt(json['xp'], fallback: 0).clamp(0, 1 << 30),
      sleeping: json['sleeping'] == true,
      isDead: json['isDead'] == true,
    );
  }

  static const String defaultName = 'Biti';

  /// Nom affiché (défaut : [defaultName]).
  final String name;

  final int hunger;
  final int energy;
  final int mood;
  final int xp;

  final bool sleeping;
  final bool isDead;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'hunger': hunger,
    'energy': energy,
    'mood': mood,
    'xp': xp,
    'sleeping': sleeping,
    'isDead': isDead,
  };

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }
}
