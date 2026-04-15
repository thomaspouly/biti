/// Croissance de Biti : **XP** cumulée → niveaux 1–6 (tailles sur grille inchangées).
class CreatureGrowth {
  CreatureGrowth._();

  /// XP gagnée **chaque seconde** tant que Biti n’est pas mort.
  static const int xpPerSecondWhenAlive = 1;

  /// XP pour **Nourrir** (bouton) ou **récolter** un point vert sur la grille.
  static const int xpPerFoodAction = 5;

  /// XP pour **nettoyer** un excrément (tap sur le pixel marron).
  static const int xpPerWasteCleanup = 2;

  /// XP cumulée **minimale** pour être au niveau donné (index = niveau − 1).
  ///
  /// Barème (équivalent grossier à l’ancienne progression temps : ~1 XP/s) :
  /// - Niv. 2 : 3 600 XP · Niv. 3 : 7 200 · Niv. 4 : 18 000 · Niv. 5 : 25 200 · Niv. 6 : 36 000
  static const List<int> xpLevelStarts = [0, 700, 3000, 6000, 12000, 24000];

  /// Niveau entre **1** et **6** selon l’XP cumulée.
  static int levelFromXp(int xp) {
    final x = xp < 0 ? 0 : xp;
    var level = 1;
    for (var i = 1; i < xpLevelStarts.length; i++) {
      if (x >= xpLevelStarts[i]) {
        level = i + 1;
      }
    }
    return level.clamp(1, 6);
  }

  /// Côté du sprite sur la grille (niveau 3 = 5×5, forme de référence).
  static int gridSpanForLevel(int level) {
    const spans = [1, 2, 5, 7, 9, 11];
    return spans[level.clamp(1, 6) - 1];
  }

  /// Remplissage **0.0–1.0** du segment XP jusqu’au **prochain** niveau.
  /// Au niveau **6**, retourne **1.0**.
  static double levelFillProgressFromXp(int xp) {
    final x = xp < 0 ? 0 : xp;
    final lv = levelFromXp(x);
    if (lv >= 6) return 1.0;
    final start = xpLevelStarts[lv - 1];
    final end = xpLevelStarts[lv];
    if (end <= start) return 1.0;
    return ((x - start) / (end - start)).clamp(0.0, 1.0);
  }
}
