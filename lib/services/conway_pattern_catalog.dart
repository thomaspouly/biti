import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/conway_rle.dart';
import '../models/conway_pattern.dart';
import '../theme/biti_theme_pair.dart';

/// Charge [assets/conway_life_patterns.json] une fois au démarrage ([load]).
class BitiConwayPatterns {
  BitiConwayPatterns._(
    this._sorted,
    this.xpThresholds,
    this._maskByGameLevel,
    this.maxGameLevel,
  );

  static BitiConwayPatterns? _instance;

  static BitiConwayPatterns get instance {
    final BitiConwayPatterns? i = _instance;
    if (i == null) {
      throw StateError('BitiConwayPatterns.load() doit être appelé avant runApp.');
    }
    return i;
  }

  static bool get isLoaded => _instance != null;

  final List<BitiConwayPattern> _sorted;

  /// XP cumulée **minimale** pour être au niveau d’indice **i** (liste de taille [maxGameLevel] + 1).
  final List<int> xpThresholds;

  final Map<int, List<List<bool>>> _maskByGameLevel;

  /// Indice de niveau le plus élevé (**0** = pixel seul ; **1 … maxGameLevel** = motifs JSON par `id`).
  final int maxGameLevel;

  /// Nombre d’entrées dans le catalogue (motifs).
  int get patternCount => _sorted.length;

  BitiConwayPattern? patternForGameLevel(int gameLevel) {
    if (gameLevel <= 0) return null;
    for (final BitiConwayPattern p in _sorted) {
      if (p.id == gameLevel) return p;
    }
    return null;
  }

  int bboxMaxSideForGameLevel(int gameLevel) {
    if (gameLevel <= 0) return 1;
    return patternForGameLevel(gameLevel)?.bboxMaxSide ?? 1;
  }

  /// Masque initial (vivant = true) pour le niveau **≥ 1** ; clé = [BitiConwayPattern.id].
  List<List<bool>>? aliveMaskForGameLevel(int gameLevel) {
    if (gameLevel <= 0) return null;
    return _maskByGameLevel[gameLevel];
  }

  /// Frame statique (motif initial) : toutes les cellules vivantes = « nouvelle » (streak 0).
  List<List<Color>> coloredInitialFrame(int gameLevel, BitiThemePair theme) {
    if (gameLevel <= 0) {
      return <List<Color>>[<Color>[theme.creatureCellColorForSurvivalStreak(0)]];
    }
    final List<List<bool>>? mask = _maskByGameLevel[gameLevel];
    if (mask == null || mask.isEmpty) {
      return <List<Color>>[<Color>[theme.creatureCellColorForSurvivalStreak(0)]];
    }
    return List<List<Color>>.generate(mask.length, (int y) {
      return List<Color>.generate(mask[y].length, (int x) {
        return mask[y][x]
            ? theme.creatureCellColorForSurvivalStreak(0)
            : Colors.transparent;
      });
    });
  }

  static List<int> _xpThresholdsForLevelCount(int levelCount) {
    if (levelCount <= 0) return <int>[0];
    const List<int> curve = <int>[
      0,
      180,
      650,
      2000,
      5500,
      14000,
      36000,
      82000,
      160000,
      280000,
      420000,
      600000,
    ];
    final List<int> out = List<int>.generate(levelCount, (int i) {
      final int idx = i < curve.length ? i : curve.length - 1;
      return curve[idx];
    });
    out[0] = 0;
    for (int i = 1; i < out.length; i++) {
      if (out[i] <= out[i - 1]) {
        out[i] = out[i - 1] + 400 + 200 * i;
      }
    }
    return out;
  }

  static Future<void> load() async {
    final String raw = await rootBundle.loadString('assets/conway_life_patterns.json');
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) {
      throw const FormatException('conway_life_patterns.json : racine attendue : tableau.');
    }
    final List<BitiConwayPattern> list = <BitiConwayPattern>[];
    final Map<int, List<List<bool>>> masks = <int, List<List<bool>>>{};
    for (final Object? e in decoded) {
      if (e is! Map<String, Object?>) continue;
      final Object? idRaw = e['id'];
      final int id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;
      final String name = '${e['name'] ?? ''}';
      final Object? per = e['period'];
      final int period = per is int ? per : int.tryParse('$per') ?? 1;
      final String rle = '${e['rle'] ?? ''}'.trim();
      if (id < 1 || rle.isEmpty) continue;
      final List<List<bool>> tight = ConwayRle.decodeBodyToTightGrid(rle);
      if (tight.isEmpty) continue;
      final int w = tight.first.length;
      final int h = tight.length;
      if (w < 1 || h < 1) continue;
      list.add(
        BitiConwayPattern(
          id: id,
          name: name,
          period: period,
          width: w,
          height: h,
          rleBody: rle,
        ),
      );
      masks[id] = List<List<bool>>.generate(
        h,
        (int y) => List<bool>.from(tight[y]),
      );
    }
    if (list.isEmpty) {
      list.add(
        const BitiConwayPattern(
          id: 1,
          name: 'Biti',
          period: 1,
          width: 1,
          height: 1,
          rleBody: 'o!',
        ),
      );
    }
    list.sort((BitiConwayPattern a, BitiConwayPattern b) => a.id.compareTo(b.id));
    final int maxLv = list.map((BitiConwayPattern p) => p.id).reduce(math.max);
    for (int lv = 1; lv <= maxLv; lv++) {
      if (!masks.containsKey(lv)) {
        throw FormatException(
          'conway_life_patterns.json : id de niveau manquant ($lv). '
          'Les ids doivent couvrir 1..$maxLv sans trou.',
        );
      }
    }
    final int levelCount = maxLv + 1;
    final List<int> xp = _xpThresholdsForLevelCount(levelCount);
    _instance = BitiConwayPatterns._(list, xp, masks, maxLv);
  }

  /// Pour tests / hot reload sans redémarrage complet.
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
