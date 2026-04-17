import 'package:flutter/material.dart';

import '../models/biti_profile.dart';

/// Paire de couleurs : tout l’UI et le terrain utilisent uniquement des points
/// sur le segment **[a] → [b]** ([mix]).
@immutable
class BitiThemePair {
  const BitiThemePair({required this.a, required this.b});

  /// Extrémité « claire » du dégradé (fond, cases claires).
  final Color a;

  /// Extrémité « sombre » du dégradé (texte, accents).
  final Color b;

  Color mix(double t) => Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  bool get _aIsLighter => a.computeLuminance() >= b.computeLuminance();

  /// Texte / icônes lisibles sur le fond principal.
  Color get textStrong => _aIsLighter ? b : a;

  /// Texte secondaire (jauges).
  Color get textMuted => mix(_aIsLighter ? 0.52 : 0.48);

  /// Fond des pistes de jauge.
  Color get trackBackground =>
      mix(_aIsLighter ? 0.28 : 0.72).withValues(alpha: 0.55);

  /// Panneaux (boutons, feuille paramètres).
  Color get panel => mix(0.2);

  /// Remplissage « fort » des barres (faim / énergie / humeur / niveau).
  Color get barAccent => mix(0.6);

  /// Remplissage alternatif pour distinguer les jauges (toujours sur le même segment).
  Color barSecondary(double offset) => mix((0.58 + offset).clamp(0.0, 1.0));

  /// Fond plein de l’écran de jeu (sans dégradé).
  Color get screenBackground => mix(0.08);

  /// Couleur d’affichage d’un pixel de sprite sur le **terrain** (cases grille).
  ///
  /// Même logique que l’ancien rendu overlay : luminance du pixel source → segment [a]→[b].
  Color mapSpritePixelColor(Color c) {
    if (c.a == 0) return c;
    final double lum = c.computeLuminance().clamp(0.0, 1.0);
    return mix(0.12 + lum * 0.78);
  }

  /// Cellule vivante du corps GoL : **0** = nouvelle, **1** = 1 génération, **2** = 2, **3+** = 3 ou plus.
  ///
  /// Dégradé **uniquement à partir de [a]** : plus **clair** quand la cellule est récente,
  /// plus **foncé** quand elle est ancienne (valeur HSV décroissante avec l’âge).
  Color creatureCellColorForSurvivalStreak(int streak) {
    final double t = streak.clamp(0, 3) / 3.0;
    final HSVColor h = HSVColor.fromColor(a);
    final double vScale = 1.0 - 0.58 * t;
    return h
        .withValue((h.value * vScale).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: a.a);
  }

  /// Fond de la feuille paramètres (proche de l’extrémité sombre pour texte clair).
  Color get sheetBackground => mix(_aIsLighter ? 0.9 : 0.14);

  /// Cinq combinaisons prédéfinies (ordre : clair → foncé).
  static const List<BitiThemePair> presets = <BitiThemePair>[
    BitiThemePair(a: Color(0xFFC6BBAA), b: Color(0xFF010000)),
    BitiThemePair(a: Color(0xFF2A1111), b: Color(0xFFCEBDB6)),
    BitiThemePair(a: Color(0xFF000000), b: Color(0xFFC6BEAC)),
    BitiThemePair(a: Color(0xFF95D5B2), b: Color(0xFF1B4332)),
    BitiThemePair(a: Color(0xFFF4E285), b: Color(0xFF6F1D1B)),
    BitiThemePair(a: Color(0xFFE0C3FF), b: Color(0xFF3C096C)),
    BitiThemePair(a: Color(0xFFFFEDD8), b: Color(0xFF432818)),
  ];

  static BitiThemePair presetOrDefault(int index) {
    if (index < 0 || index >= presets.length) {
      return presets[0];
    }
    return presets[index];
  }

  /// Thème du Biti : combinaison perso ou préréglage.
  static BitiThemePair pairFor(BitiProfile profile) {
    final int? ca = profile.customColorA;
    final int? cb = profile.customColorB;
    if (ca != null && cb != null) {
      return BitiThemePair(a: Color(ca), b: Color(cb));
    }
    return presetOrDefault(profile.themePresetIndex);
  }

  @override
  bool operator ==(Object other) {
    return other is BitiThemePair &&
        other.a.toARGB32() == a.toARGB32() &&
        other.b.toARGB32() == b.toARGB32();
  }

  @override
  int get hashCode => Object.hash(a.toARGB32(), b.toARGB32());
}
