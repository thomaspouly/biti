import 'package:flutter/material.dart';

import '../models/conway_pattern.dart';
import '../theme/biti_theme_pair.dart';
import 'conway_rle.dart';

/// Simulation du jeu de la vie sur une grille **w × h** (bords morts).
class ConwayLifeSimulator {
  /// Cellules mortes autour du motif RLE pour que le bord du **motif** ne coïncide
  /// pas avec le bord du simulateur (voisins « manquants » → extinctions artificielles).
  static const int finiteBoardMargin = 1;

  ConwayLifeSimulator._(this.width, this.height, List<List<bool>> alive)
    : _alive = alive,
      _next = List<List<bool>>.generate(
        height,
        (_) => List<bool>.filled(width, false),
      ),
      _age = List<List<int>>.generate(
        height,
        (int y) => List<int>.generate(width, (int x) => alive[y][x] ? 0 : -1),
      ),
      _nextAge = List<List<int>>.generate(
        height,
        (_) => List<int>.filled(width, -1),
      );

  final int width;
  final int height;
  final List<List<bool>> _alive;
  final List<List<bool>> _next;

  /// Nombre de générations **consécutives** en vie (0 = nouvelle), plafonné à 3 pour l’affichage.
  final List<List<int>> _age;
  final List<List<int>> _nextAge;

  /// Grille [gw + 2*m] × [gh + 2*m] avec le motif serré centré par translation (+m, +m).
  static List<List<bool>> _paddedBoardFromTight(
    List<List<bool>> g,
    int margin,
  ) {
    if (g.isEmpty) {
      final int s = 1 + 2 * margin;
      return List<List<bool>>.generate(
        s,
        (_) => List<bool>.filled(s, false),
      );
    }
    final int gh = g.length;
    final int gw = g.first.length;
    final int w = gw + 2 * margin;
    final int h = gh + 2 * margin;
    final List<List<bool>> out = List<List<bool>>.generate(
      h,
      (_) => List<bool>.filled(w, false),
    );
    for (int y = 0; y < gh; y++) {
      final List<bool> row = g[y];
      for (int x = 0; x < row.length; x++) {
        out[y + margin][x + margin] = row[x];
      }
    }
    return out;
  }

  factory ConwayLifeSimulator.fromPattern(BitiConwayPattern p) {
    final List<List<bool>> g = ConwayRle.decodeBodyToTightGrid(p.rleBody);
    final List<List<bool>> padded = _paddedBoardFromTight(g, finiteBoardMargin);
    final int ph = padded.length;
    final int pw = padded.first.length;
    final List<List<bool>> copy = List<List<bool>>.generate(
      ph,
      (int y) => List<bool>.from(padded[y]),
    );
    return ConwayLifeSimulator._(pw, ph, copy);
  }

  /// Repart du motif (mêmes dimensions que la grille courante).
  void resetFrom(BitiConwayPattern p) {
    final List<List<bool>> g = ConwayRle.decodeBodyToTightGrid(p.rleBody);
    final List<List<bool>> padded = _paddedBoardFromTight(g, finiteBoardMargin);
    if (padded.length != height || padded.first.length != width) {
      return;
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final bool live = padded[y][x];
        _alive[y][x] = live;
        _age[y][x] = live ? 0 : -1;
      }
    }
  }

  void step() {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int n = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final int nx = x + dx;
            final int ny = y + dy;
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            if (_alive[ny][nx]) n++;
          }
        }
        final bool live = _alive[y][x];
        _next[y][x] = (live && (n == 2 || n == 3)) || (!live && n == 3);
      }
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final bool nextLive = _next[y][x];
        if (!nextLive) {
          _nextAge[y][x] = -1;
        } else if (!_alive[y][x]) {
          _nextAge[y][x] = 0;
        } else {
          final int was = _age[y][x];
          final int prev = was < 0 ? 0 : was;
          _nextAge[y][x] = prev >= 3 ? 3 : prev + 1;
        }
      }
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        _alive[y][x] = _next[y][x];
        _age[y][x] = _nextAge[y][x];
      }
    }
  }

  /// Frame « sprite » : couleurs déjà calculées depuis **[a]** (pas [mapSpritePixelColor]).
  List<List<Color>> toSpriteFrame(BitiThemePair theme) {
    return List<List<Color>>.generate(height, (int y) {
      return List<Color>.generate(width, (int x) {
        if (!_alive[y][x]) return Colors.transparent;
        final int streak = _age[y][x] < 0 ? 0 : _age[y][x].clamp(0, 3);
        return theme.creatureCellColorForSurvivalStreak(streak);
      });
    });
  }
}
