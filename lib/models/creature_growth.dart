/// Croissance de Biti : **XP** cumulée → niveaux (voir [xpLevelStarts], [maxGrowthLevel]).
class CreatureGrowth {
  CreatureGrowth._();

  /// XP gagnée **chaque seconde** tant que Biti n’est pas mort.
  static const int xpPerSecondWhenAlive = 1;

  /// XP pour **Nourrir** (bouton) ou **récolter** un point vert sur la grille.
  static const int xpPerFoodAction = 5;

  /// Nombre de niveaux (= longueur de [xpLevelStarts]).
  static int get maxGrowthLevel => xpLevelStarts.length;

  /// XP cumulée **minimale** pour être au niveau donné (index = niveau − 1).
  ///
  /// Paliers progressifs (résumé) : montée jusqu’au niveau [maxGrowthLevel] ;
  /// les derniers niveaux demandent plus d’XP cumulée.
  static const List<int> xpLevelStarts = <int>[
    0,
    700,
    3000,
    6000,
    12000,
    24000,
    42000,
    65000,
    95000,
    135000,
  ];

  /// Niveau entre **1** et [maxGrowthLevel] selon l’XP cumulée.
  static int levelFromXp(int xp) {
    final int x = xp < 0 ? 0 : xp;
    int level = 1;
    for (int i = 1; i < xpLevelStarts.length; i++) {
      if (x >= xpLevelStarts[i]) {
        level = i + 1;
      }
    }
    return level.clamp(1, maxGrowthLevel);
  }

  /// Côté du sprite sur la grille (niveau 3 = 5×5, forme de référence).
  static int gridSpanForLevel(int level) {
    const List<int> spans = <int>[
      1,
      2,
      5,
      7,
      9,
      11,
      13,
      15,
      17,
      19,
    ];
    return spans[level.clamp(1, maxGrowthLevel) - 1];
  }

  /// Taille du **terrain** (carré) en nombre de cases selon le niveau.
  /// Niveau **1** : 30×30, puis **+4** cases par niveau.
  static int terrainSideForLevel(int level) {
    const List<int> sides = <int>[
      30,
      34,
      38,
      42,
      46,
      50,
      54,
      58,
      62,
      66,
    ];
    return sides[level.clamp(1, maxGrowthLevel) - 1];
  }

  /// Remplissage **0.0–1.0** du segment XP jusqu’au **prochain** niveau.
  /// Au dernier niveau, retourne **1.0**.
  static double levelFillProgressFromXp(int xp) {
    final int x = xp < 0 ? 0 : xp;
    final int lv = levelFromXp(x);
    if (lv >= maxGrowthLevel) return 1.0;
    final int start = xpLevelStarts[lv - 1];
    final int end = xpLevelStarts[lv];
    if (end <= start) return 1.0;
    return ((x - start) / (end - start)).clamp(0.0, 1.0);
  }
}
