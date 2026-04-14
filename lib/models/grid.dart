import 'package:flutter/material.dart';

/// État logique d'une cellule dans le monde grille.
enum CellKind {
  /// Cellule vide (fond).
  empty,

  /// Obstacle ou décor (bordure, etc.).
  filled,

  /// Occupée par un pixel de la créature (synchronisé avec le sprite).
  creature,

  /// Excrément (pixel marron) ; nettoyé par tap.
  waste,

  /// Nourriture (point vert) ; récolte au tap.
  food,
}

/// Une cellule de la grille : couleur affichée + sémantique.
@immutable
class GridCell {
  const GridCell({
    this.color = const Color(0xFF16213E),
    this.kind = CellKind.empty,
  });

  final Color color;
  final CellKind kind;

  GridCell copyWith({Color? color, CellKind? kind}) {
    return GridCell(color: color ?? this.color, kind: kind ?? this.kind);
  }
}

/// Grille 2D paramétrable : seul monde de la créature.
class PixelGridModel {
  PixelGridModel({
    required this.width,
    required this.height,
    Color emptyColor = const Color(0xFF16213E),
    Color borderColor = const Color(0xFF0F3460),
  }) : _emptyColor = emptyColor,
       _borderColor = borderColor,
       cells = List.generate(
         height,
         (_) => List<GridCell>.filled(width, GridCell(color: emptyColor)),
       ) {
    _applyBorder();
  }

  final int width;
  final int height;
  final List<List<GridCell>> cells;

  final Color _emptyColor;
  final Color _borderColor;

  /// Marron excrément (visible sur la grille).
  static const Color wasteColor = Color(0xFF5D4037);

  /// Nombre max de pixels d’excrément sur la grille à la fois.
  static const int maxWastePieces = 20;

  /// Vert nourriture (pastille).
  static const Color foodColor = Color(0xFF00B894);

  /// Incrémenté à chaque mutation pour forcer le repaint du [CustomPainter].
  int paintEpoch = 0;

  void _bump() => paintEpoch++;

  void _applyBorder() {
    for (var x = 0; x < width; x++) {
      cells[0][x] = GridCell(color: _borderColor, kind: CellKind.filled);
      cells[height - 1][x] = GridCell(
        color: _borderColor,
        kind: CellKind.filled,
      );
    }
    for (var y = 0; y < height; y++) {
      cells[y][0] = GridCell(color: _borderColor, kind: CellKind.filled);
      cells[y][width - 1] = GridCell(
        color: _borderColor,
        kind: CellKind.filled,
      );
    }
  }

  GridCell cellAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return GridCell(color: _emptyColor, kind: CellKind.empty);
    }
    return cells[y][x];
  }

  void setCell(int x, int y, GridCell cell) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    cells[y][x] = cell;
  }

  int countWaste() {
    var n = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (cells[y][x].kind == CellKind.waste) n++;
      }
    }
    return n;
  }

  /// Place un pixel d’excrément si la case est libre (pas bordure, pas créature).
  bool tryPlaceWaste(int x, int y) {
    if (countWaste() >= maxWastePieces) return false;
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    final c = cells[y][x];
    if (c.kind != CellKind.empty) return false;
    cells[y][x] = const GridCell(color: wasteColor, kind: CellKind.waste);
    _bump();
    return true;
  }

  /// Retire l’excrément à cette case ; retourne vrai si une case a été nettoyée.
  bool removeWasteAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    if (cells[y][x].kind != CellKind.waste) return false;
    cells[y][x] = GridCell(color: _emptyColor, kind: CellKind.empty);
    _bump();
    return true;
  }

  /// Place un point de nourriture sur une case vide (intérieur de la grille).
  bool tryPlaceFood(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    final c = cells[y][x];
    if (c.kind != CellKind.empty) return false;
    cells[y][x] = const GridCell(color: foodColor, kind: CellKind.food);
    _bump();
    return true;
  }

  /// Retire la nourriture à cette case ; retourne vrai si une unité a été récoltée.
  bool collectFoodAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    if (cells[y][x].kind != CellKind.food) return false;
    cells[y][x] = GridCell(color: _emptyColor, kind: CellKind.empty);
    _bump();
    return true;
  }

  int countFood() {
    var n = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (cells[y][x].kind == CellKind.food) n++;
      }
    }
    return n;
  }

  /// Efface toutes les cellules marquées [CellKind.creature] (revient au fond).
  void clearCreatureCells() {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = cells[y][x];
        if (c.kind == CellKind.creature) {
          cells[y][x] = GridCell(color: _emptyColor, kind: CellKind.empty);
        }
      }
    }
    _bump();
  }

  /// Peint la silhouette du sprite courant sur la grille (pixels non transparents).
  void syncCreatureFootprint(
    int originX,
    int originY,
    List<List<Color>> frame,
  ) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = cells[y][x];
        if (c.kind == CellKind.creature) {
          cells[y][x] = GridCell(color: _emptyColor, kind: CellKind.empty);
        }
      }
    }
    for (var fy = 0; fy < frame.length; fy++) {
      final row = frame[fy];
      for (var fx = 0; fx < row.length; fx++) {
        final pixel = row[fx];
        if (pixel.a == 0) continue;
        final gx = originX + fx;
        final gy = originY + fy;
        if (gx >= 0 && gx < width && gy >= 0 && gy < height) {
          final existing = cells[gy][gx];
          if (existing.kind == CellKind.filled) continue;
          if (existing.kind == CellKind.waste) continue;
          if (existing.kind == CellKind.food) continue;
          cells[gy][gx] = GridCell(color: pixel, kind: CellKind.creature);
        }
      }
    }
    _bump();
  }
}
