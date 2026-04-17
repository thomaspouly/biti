import '../services/conway_pattern_catalog.dart';

/// Croissance de Biti : **XP** cumulée → niveaux **0 … maxGrowthLevel** (voir [xpLevelStarts]).
class CreatureGrowth {
  CreatureGrowth._();

  /// XP gagnée **chaque seconde** tant que Biti n’est pas mort.
  static const int xpPerSecondWhenAlive = 1;

  /// XP pour **Nourrir** (bouton) ou **récolter** un point vert sur la grille.
  static const int xpPerFoodAction = 5;

  /// Plus grand indice de niveau (**0** = un pixel, sans GoL ; **≥ 1** = oscillateur du JSON).
  static int get maxGrowthLevel {
    if (!BitiConwayPatterns.isLoaded) return 0;
    return BitiConwayPatterns.instance.maxGameLevel;
  }

  /// Nombre de paliers XP (= [maxGrowthLevel] + 1).
  static int get levelSlotCount {
    if (!BitiConwayPatterns.isLoaded) return 1;
    return BitiConwayPatterns.instance.xpThresholds.length;
  }

  /// XP cumulée **minimale** pour être au niveau d’indice **i** (liste de longueur [levelSlotCount]).
  static List<int> get xpLevelStarts {
    if (!BitiConwayPatterns.isLoaded) return <int>[0];
    return BitiConwayPatterns.instance.xpThresholds;
  }

  /// Niveau entre **0** et [maxGrowthLevel] selon l’XP cumulée.
  static int levelFromXp(int xp) {
    if (!BitiConwayPatterns.isLoaded) return 0;
    final List<int> starts = BitiConwayPatterns.instance.xpThresholds;
    if (starts.isEmpty) return 0;
    final int x = xp < 0 ? 0 : xp;
    int level = 0;
    for (int i = 0; i < starts.length; i++) {
      if (x >= starts[i]) {
        level = i;
      }
    }
    return level.clamp(0, maxGrowthLevel);
  }

  /// Plus grand côté de la boîte du motif au niveau donné (niveau **0** → **1**).
  static int gridSpanForLevel(int level) {
    if (!BitiConwayPatterns.isLoaded) return 1;
    final int lv = level.clamp(0, maxGrowthLevel);
    return BitiConwayPatterns.instance.bboxMaxSideForGameLevel(lv);
  }

  /// Taille du **terrain** (carré) : max(bounding box) × **15** pour le niveau donné.
  static int terrainSideForLevel(int level) {
    final int span = gridSpanForLevel(level.clamp(0, maxGrowthLevel));
    return (span * 15).clamp(12, 1 << 20);
  }

  /// Remplissage **0.0–1.0** du segment XP jusqu’au **prochain** niveau.
  /// Au dernier niveau, retourne **1.0**.
  static double levelFillProgressFromXp(int xp) {
    if (!BitiConwayPatterns.isLoaded) return 1.0;
    final List<int> starts = BitiConwayPatterns.instance.xpThresholds;
    if (starts.length < 2) return 1.0;
    final int x = xp < 0 ? 0 : xp;
    final int lv = levelFromXp(x);
    if (lv >= maxGrowthLevel) return 1.0;
    final int start = starts[lv];
    final int end = starts[lv + 1];
    if (end <= start) return 1.0;
    return ((x - start) / (end - start)).clamp(0.0, 1.0);
  }
}
