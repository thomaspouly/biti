import 'package:flutter/material.dart';

import '../theme/biti_theme_pair.dart';

/// Fraction du côté de case laissée vide autour du carreau (ex. `0.07` = **7 %** de chaque côté).
const double gameBoardCellPaddingRatio = 0.07;

/// État logique d'une cellule dans le monde grille.
enum CellKind {
  /// Cellule vide (fond).
  empty,

  /// Obstacle ou décor (bordure, etc.).
  filled,

  /// Occupée par un pixel de la créature (synchronisé avec le sprite).
  creature,

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
  }) : _emptyColor = emptyColor,
       cells = List<List<GridCell>>.generate(
         height,
         (_) => List<GridCell>.filled(width, GridCell(color: emptyColor)),
       );

  final int width;
  final int height;
  final List<List<GridCell>> cells;

  final Color _emptyColor;

  /// Vert nourriture (pastille).
  static const Color foodColor = Color(0xFF00B894);

  /// Incrémenté à chaque mutation pour forcer le repaint du [CustomPainter].
  int paintEpoch = 0;

  void _bump() => paintEpoch++;

  GridCell cellAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return GridCell(color: _emptyColor);
    }
    return cells[y][x];
  }

  void setCell(int x, int y, GridCell cell) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    cells[y][x] = cell;
  }

  /// Place un point de nourriture sur une case vide (intérieur de la grille).
  bool tryPlaceFood(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    final GridCell c = cells[y][x];
    if (c.kind != CellKind.empty) return false;
    cells[y][x] = const GridCell(color: foodColor, kind: CellKind.food);
    _bump();
    return true;
  }

  /// Retire la nourriture à cette case ; retourne vrai si une unité a été récoltée.
  bool collectFoodAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    if (cells[y][x].kind != CellKind.food) return false;
    cells[y][x] = GridCell(color: _emptyColor);
    _bump();
    return true;
  }

  int countFood() {
    int n = 0;
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        if (cells[y][x].kind == CellKind.food) n++;
      }
    }
    return n;
  }

  /// Efface toutes les cellules marquées [CellKind.creature] (revient au fond).
  void clearCreatureCells() {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final GridCell c = cells[y][x];
        if (c.kind == CellKind.creature) {
          cells[y][x] = GridCell(color: _emptyColor);
        }
      }
    }
    _bump();
  }

  void _stampCreatureFootprint(
    int originX,
    int originY,
    List<List<Color>> frame,
    BitiThemePair theme, {
    bool cellColorsAlreadyThemed = false,
  }) {
    for (int fy = 0; fy < frame.length; fy++) {
      final List<Color> row = frame[fy];
      for (int fx = 0; fx < row.length; fx++) {
        final Color pixel = row[fx];
        if (pixel.a == 0) continue;
        final int gx = originX + fx;
        final int gy = originY + fy;
        if (gx >= 0 && gx < width && gy >= 0 && gy < height) {
          final GridCell existing = cells[gy][gx];
          if (existing.kind == CellKind.filled) continue;
          if (existing.kind == CellKind.food) continue;
          final Color out = cellColorsAlreadyThemed
              ? pixel
              : theme.mapSpritePixelColor(pixel);
          cells[gy][gx] = GridCell(
            color: out,
            kind: CellKind.creature,
          );
        }
      }
    }
  }

  /// Peint la silhouette du sprite courant sur la grille (pixels non transparents).
  void syncCreatureFootprint(
    int originX,
    int originY,
    List<List<Color>> frame,
    BitiThemePair theme,
  ) {
    clearCreatureCells();
    _stampCreatureFootprint(originX, originY, frame, theme);
    _bump();
  }

  /// Deux Biti sur le même terrain (empreintes superposées possibles).
  void syncTwoCreatureFootprints(
    int aX,
    int aY,
    List<List<Color>> aFrame,
    BitiThemePair themeA,
    int bX,
    int bY,
    List<List<Color>> bFrame,
    BitiThemePair themeB,
  ) {
    clearCreatureCells();
    _stampCreatureFootprint(aX, aY, aFrame, themeA);
    _stampCreatureFootprint(bX, bY, bFrame, themeB);
    _bump();
  }

  /// Plusieurs Biti sur le même terrain (l’ordre des empreintes compte : la dernière domine en cas de chevauchement).
  void syncMultiCreatureFootprints(
    List<
        ({
          int x,
          int y,
          List<List<Color>> frame,
          BitiThemePair theme,
          bool cellColorsAlreadyThemed,
        })> stamps,
  ) {
    clearCreatureCells();
    for (
      final ({
        int x,
        int y,
        List<List<Color>> frame,
        BitiThemePair theme,
        bool cellColorsAlreadyThemed,
      }) s
      in stamps
    ) {
      _stampCreatureFootprint(
        s.x,
        s.y,
        s.frame,
        s.theme,
        cellColorsAlreadyThemed: s.cellColorsAlreadyThemed,
      );
    }
    _bump();
  }
}
