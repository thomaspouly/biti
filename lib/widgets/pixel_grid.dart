import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import '../theme/biti_theme_pair.dart';
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
    required this.theme,
    this.onCellTap,
  });

  final PixelGridModel model;
  final Creature creature;
  final CreatureMood mood;
  final double lean;

  /// Niveau de croissance 1–6 ([CreatureGrowth]).
  final int growthLevel;

  /// Couleurs du terrain : uniquement des points sur le segment thème.
  final BitiThemePair theme;

  /// Coordonnées grille : excrément, nourriture, etc.
  final void Function(int gridX, int gridY)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final frame = CreatureSpriteLibrary.currentFrame(
      mood,
      creature.frameIndex,
      growthLevel,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final cellW = width / model.width;
        final cellH = height / model.height;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: PixelGridPainter(model: model, theme: theme),
            ),
            CustomPaint(
              painter: CreaturePainter(
                frame: frame,
                gridWidth: model.width,
                gridHeight: model.height,
                creatureX: creature.gridX,
                creatureY: creature.gridY,
                lean: lean,
                theme: theme,
              ),
            ),
            if (onCellTap != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final p = details.localPosition;
                    final t = _tapCellWithSlop(model, p.dx, p.dy, cellW, cellH);
                    onCellTap!(t.$1, t.$2);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class PixelGridPainter extends CustomPainter {
  PixelGridPainter({required this.model, required this.theme});

  final PixelGridModel model;
  final BitiThemePair theme;

  /// Fond uniforme du terrain (un peu plus foncé sur le segment thème).
  Color get _terrainBase => theme.mix(0.0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width;
    final h = model.height;
    final cellW = size.width / w;
    final cellH = size.height / h;

    final padX = cellW * gameBoardCellPaddingRatio;
    final padY = cellH * gameBoardCellPaddingRatio;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final cell = model.cellAt(x, y);
        final rCell = Rect.fromLTWH(
          x * cellW + padX,
          y * cellH + padY,
          cellW - 2 * padX + 0.5,
          cellH - 2 * padY + 0.5,
        );
        final corner = Radius.circular(
          (math.min(rCell.width, rCell.height) * 0.3).clamp(0.6, 5.0),
        );
        final rRCell = RRect.fromRectAndRadius(rCell, corner);
        final paint = Paint();

        if (cell.kind == CellKind.waste) {
          paint.color = _terrainBase;
          canvas.drawRRect(rRCell, paint);
          paint.color = theme.mix(0.8);
          final r = math.min(rCell.width, rCell.height) * 0.38;
          canvas.drawCircle(rCell.center, r, paint);
        } else if (cell.kind == CellKind.food) {
          paint.color = _terrainBase;
          canvas.drawRRect(rRCell, paint);
          paint.color = theme.mix(0.36);
          final r = math.min(rCell.width, rCell.height) * 0.38;
          canvas.drawCircle(rCell.center, r, paint);
        } else if (cell.kind == CellKind.filled) {
          paint.color = theme.mix(0.88);
          canvas.drawRRect(rRCell, paint);
        } else {
          paint.color = _terrainBase;
          canvas.drawRRect(rRCell, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) {
    return oldDelegate.model.paintEpoch != model.paintEpoch ||
        oldDelegate.theme != theme;
  }
}
