import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import 'creature_painter.dart';

/// Rayon de recherche en cases autour du tap.
const int _tapSearchRadiusCells = 4;

/// Au-delà de cette distance (× taille de case), on ne « colle » pas au caca / nourriture.
const double _tapSlopInCellUnits = 1.9;

/// Retourne la case [CellKind.waste] ou [CellKind.food] la plus proche du doigt, sinon la case directement sous le tap.
(int gx, int gy) _tapCellWithSlop(
  PixelGridModel model,
  double lx,
  double ly,
  double cellW,
  double cellH,
) {
  final w = model.width;
  final h = model.height;
  final gx0 = (lx / cellW).floor().clamp(0, w - 1);
  final gy0 = (ly / cellH).floor().clamp(0, h - 1);

  final maxDist = math.max(cellW, cellH) * _tapSlopInCellUnits;
  final maxDist2 = maxDist * maxDist;

  var bestD2 = maxDist2 + 1.0;
  var bestGx = gx0;
  var bestGy = gy0;
  var found = false;

  for (var dy = -_tapSearchRadiusCells; dy <= _tapSearchRadiusCells; dy++) {
    for (var dx = -_tapSearchRadiusCells; dx <= _tapSearchRadiusCells; dx++) {
      final gx = gx0 + dx;
      final gy = gy0 + dy;
      if (gx < 0 || gx >= w || gy < 0 || gy >= h) continue;
      final kind = model.cellAt(gx, gy).kind;
      if (kind != CellKind.waste && kind != CellKind.food) continue;

      final cx = (gx + 0.5) * cellW;
      final cy = (gy + 0.5) * cellH;
      final d2 = (lx - cx) * (lx - cx) + (ly - cy) * (ly - cy);
      if (d2 <= maxDist2 && d2 < bestD2) {
        bestD2 = d2;
        bestGx = gx;
        bestGy = gy;
        found = true;
      }
    }
  }

  if (found) {
    return (bestGx, bestGy);
  }
  return (gx0, gy0);
}

/// Grille pixel + créature, rendue avec [CustomPainter] (performant).
class PixelGrid extends StatelessWidget {
  const PixelGrid({
    super.key,
    required this.model,
    required this.creature,
    required this.mood,
    required this.lean,
    required this.growthLevel,
    this.onCellTap,
  });

  final PixelGridModel model;
  final Creature creature;
  final CreatureMood mood;
  final double lean;

  /// Niveau de croissance 1–6 ([CreatureGrowth]).
  final int growthLevel;

  /// Coordonnées grille : excrément, nourriture, etc.
  final void Function(int gridX, int gridY)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final frame = CreatureSpriteLibrary.currentFrame(
      mood,
      creature.frameIndex,
      growthLevel,
    );

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          final cellW = side / model.width;
          final cellH = side / model.height;
          return SizedBox(
            width: side,
            height: side,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: PixelGridPainter(model: model),
                  size: Size.square(side),
                ),
                CustomPaint(
                  painter: CreaturePainter(
                    frame: frame,
                    gridWidth: model.width,
                    gridHeight: model.height,
                    creatureX: creature.gridX,
                    creatureY: creature.gridY,
                    lean: lean,
                  ),
                  size: Size.square(side),
                ),
                if (onCellTap != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        final p = details.localPosition;
                        final t = _tapCellWithSlop(
                          model,
                          p.dx,
                          p.dy,
                          cellW,
                          cellH,
                        );
                        onCellTap!(t.$1, t.$2);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class PixelGridPainter extends CustomPainter {
  PixelGridPainter({required this.model});

  final PixelGridModel model;

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width;
    final h = model.height;
    final cellW = size.width / w;
    final cellH = size.height / h;

    const baseEmpty = Color(0xFF16213E);
    const altEmpty = Color(0xFF1A1A2E);
    const grout = Color(0xFF0C1018);

    final padX = cellW * gameBoardCellPaddingRatio;
    final padY = cellH * gameBoardCellPaddingRatio;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final cell = model.cellAt(x, y);
        final full = Rect.fromLTWH(
          x * cellW,
          y * cellH,
          cellW + 0.5,
          cellH + 0.5,
        );
        final inner = Rect.fromLTWH(
          x * cellW + padX,
          y * cellH + padY,
          cellW - 2 * padX,
          cellH - 2 * padY,
        );
        final paint = Paint();

        canvas.drawRect(full, paint..color = grout);

        if (cell.kind == CellKind.creature) {
          // Le sprite animé + penché est dessiné par [CreaturePainter].
          final alt = (x + y).isEven;
          paint.color = Color.lerp(baseEmpty, altEmpty, alt ? 0.12 : 0) ?? baseEmpty;
          canvas.drawRect(inner, paint);
        } else if (cell.kind == CellKind.empty) {
          final alt = (x + y).isEven;
          paint.color = Color.lerp(
                cell.color,
                altEmpty,
                alt ? 0.12 : 0,
              ) ??
              cell.color;
          canvas.drawRect(inner, paint);
        } else if (cell.kind == CellKind.waste) {
          final alt = (x + y).isEven;
          paint.color = Color.lerp(baseEmpty, altEmpty, alt ? 0.12 : 0) ?? baseEmpty;
          canvas.drawRect(inner, paint);
          paint.color = cell.color;
          final r = math.min(inner.width, inner.height) * 0.38;
          canvas.drawCircle(inner.center, r, paint);
        } else if (cell.kind == CellKind.food) {
          final alt = (x + y).isEven;
          paint.color = Color.lerp(baseEmpty, altEmpty, alt ? 0.12 : 0) ?? baseEmpty;
          canvas.drawRect(inner, paint);
          paint.color = cell.color;
          final r = math.min(inner.width, inner.height) * 0.38;
          canvas.drawCircle(inner.center, r, paint);
        } else {
          paint.color = cell.color;
          canvas.drawRect(inner, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) {
    return oldDelegate.model.paintEpoch != model.paintEpoch;
  }
}
