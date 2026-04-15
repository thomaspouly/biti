import 'package:flutter/foundation.dart';

import 'biti_profile.dart';

/// Liste de Biti persistée + celui affiché sur l’écran d’accueil.
@immutable
class BitiCollection {
  const BitiCollection({required this.profiles, this.selectedId});

  final List<BitiProfile> profiles;

  /// [id] du profil actif ; si absent ou invalide, le premier de la liste.
  final String? selectedId;

  bool get isEmpty => profiles.isEmpty;

  BitiProfile? get selected {
    if (profiles.isEmpty) return null;
    final String? sid = selectedId;
    if (sid != null) {
      for (final BitiProfile p in profiles) {
        if (p.id == sid) return p;
      }
    }
    return profiles.first;
  }

  String? get effectiveSelectedId => selected?.id;

  BitiCollection copyWith({
    List<BitiProfile>? profiles,
    String? selectedId,
    bool clearSelected = false,
  }) {
    return BitiCollection(
      profiles: profiles ?? this.profiles,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
    );
  }

  /// Remplace un profil par [id] ou l’ajoute.
  BitiCollection upsertProfile(BitiProfile p) {
    final List<BitiProfile> next = <BitiProfile>[
      for (final BitiProfile x in profiles)
        if (x.id != p.id) x,
      p,
    ];
    return copyWith(profiles: next);
  }

  factory BitiCollection.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['profiles'] as List<dynamic>?;
    final List<BitiProfile> list = <BitiProfile>[];
    if (raw != null) {
      for (final dynamic e in raw) {
        if (e is! Map<String, dynamic>) continue;
        list.add(BitiProfile.fromJson(e));
      }
    }
    final String? sid = json['selectedId'] as String?;
    return BitiCollection(profiles: list, selectedId: sid);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': 2,
    'selectedId': selectedId,
    'profiles': profiles.map((BitiProfile p) => p.toJson()).toList(),
  };
}
