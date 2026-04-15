import 'package:flutter/material.dart';

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

  @override
  bool operator ==(Object other) {
    return other is BitiThemePair &&
        other.a.toARGB32() == a.toARGB32() &&
        other.b.toARGB32() == b.toARGB32();
  }

  @override
  int get hashCode => Object.hash(a.toARGB32(), b.toARGB32());
}
