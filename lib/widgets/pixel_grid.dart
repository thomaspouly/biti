import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import '../theme/biti_theme_pair.dart';
import 'creature_painter.dart';

/// Rayon de recherche en cases autour du tap.
const int _tapSearchRadiusCells = 4;

/// Au-delà de cette distance (× taille de case), on ne « colle » pas à la nourriture.
const double _tapSlopInCellUnits = 1.9;

/// Données pour afficher un Biti sur le plateau (plusieurs instances possibles).
@immutable
class PixelGridBoardBiti {
  const PixelGridBoardBiti({
    required this.name,
    required this.creature,
    required this.mood,
    required this.lean,
    required this.growthLevel,
    required this.creatureTheme,
    this.isSelected = false,
  });

  final String name;
  final Creature creature;
  final CreatureMood mood;
  final double lean;
  final int growthLevel;
  final BitiThemePair creatureTheme;

  /// Contour rouge sur le plateau ([PixelGrid]).
  final bool isSelected;
}

(int gx, int gy) _tapCellWithSlop(
  PixelGridModel model,
  double lx,
  double ly,
  double cellW,
  double cellH,
) {
  final int w = model.width;
  final int h = model.height;
  final int gx0 = (lx / cellW).floor().clamp(0, w - 1);
  final int gy0 = (ly / cellH).floor().clamp(0, h - 1);

  final double maxDist = math.max(cellW, cellH) * _tapSlopInCellUnits;
  final double maxDist2 = maxDist * maxDist;

  double bestD2 = maxDist2 + 1.0;
  int bestGx = gx0;
  int bestGy = gy0;
  bool found = false;

  for (int dy = -_tapSearchRadiusCells; dy <= _tapSearchRadiusCells; dy++) {
    for (int dx = -_tapSearchRadiusCells; dx <= _tapSearchRadiusCells; dx++) {
      final int gx = gx0 + dx;
      final int gy = gy0 + dy;
      if (gx < 0 || gx >= w || gy < 0 || gy >= h) continue;
      final CellKind kind = model.cellAt(gx, gy).kind;
      if (kind != CellKind.food) continue;

      final double cx = (gx + 0.5) * cellW;
      final double cy = (gy + 0.5) * cellH;
      final double d2 = (lx - cx) * (lx - cx) + (ly - cy) * (ly - cy);
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

/// Grille pixel + créatures, rendue avec [CustomPainter] (performant).
///
/// [boardBitis] : ordre de peinture ; en général le Biti sélectionné en **dernier** pour passer au-dessus.
class PixelGrid extends StatelessWidget {
  const PixelGrid({
    super.key,
    required this.model,
    required this.theme,
    required this.boardBitis,
    required this.nameLabelColor,
    this.onCellTap,
  });

  final PixelGridModel model;
  final BitiThemePair theme;

  /// Ordre = z-order (dernier au premier plan).
  final List<PixelGridBoardBiti> boardBitis;

  final Color nameLabelColor;

  final void Function(int gridX, int gridY)? onCellTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double cellW = width / model.width;
        final double cellH = height / model.height;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              painter: PixelGridPainter(model: model, theme: theme),
            ),
            for (final PixelGridBoardBiti b in boardBitis)
              CustomPaint(
                painter: CreaturePainter(
                  frame: CreatureSpriteLibrary.currentFrame(
                    b.mood,
                    b.creature.frameIndex,
                    b.growthLevel,
                  ),
                  gridWidth: model.width,
                  gridHeight: model.height,
                  creatureX: b.creature.gridX,
                  creatureY: b.creature.gridY,
                  lean: b.lean,
                  theme: b.creatureTheme,
                ),
              ),
            for (final PixelGridBoardBiti b in boardBitis)
              if (b.isSelected)
                _SelectedBitiOutline(
                  creature: b.creature,
                  cellW: cellW,
                  cellH: cellH,
                ),
            for (final PixelGridBoardBiti b in boardBitis)
              _BoardBitiNameLabel(
                name: b.name,
                creature: b.creature,
                cellW: cellW,
                cellH: cellH,
                color: nameLabelColor,
              ),
            if (onCellTap != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (TapUpDetails details) {
                    final Offset p = details.localPosition;
                    final (int, int) t = _tapCellWithSlop(
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
        );
      },
    );
  }
}

/// Cadre rouge aligné sur la boîte du sprite (même repère que [CreaturePainter]).
class _SelectedBitiOutline extends StatelessWidget {
  const _SelectedBitiOutline({
    required this.creature,
    required this.cellW,
    required this.cellH,
  });

  final Creature creature;
  final double cellW;
  final double cellH;

  static const Color _outline = Color.fromARGB(255, 202, 0, 0);

  @override
  Widget build(BuildContext context) {
    final double padX = cellW * gameBoardCellPaddingRatio;
    final double padY = cellH * gameBoardCellPaddingRatio;
    final double innerW = cellW - 2 * padX;
    final double innerH = cellH - 2 * padY;
    final double left = creature.gridX * cellW + padX;
    final double top = creature.gridY * cellH + padY;
    final double w = creature.spriteWidth * innerW;
    final double h = creature.spriteHeight * innerH;

    /// Espace entre le sprite et le trait rouge (px écran).
    final double gap = (math.min(cellW, cellH) * 0.3).clamp(2.0, 5.0);
    const double borderWidth = 1.5;
    final double boxW = w + 2 * gap;
    final double boxH = h + 2 * gap;
    final double r = (math.min(boxW, boxH) * 0.14).clamp(2.0, 8.0);
    return Positioned(
      left: left - gap,
      top: top - gap,
      width: boxW,
      height: boxH,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: _outline, width: borderWidth),
          ),
        ),
      ),
    );
  }
}

class _BoardBitiNameLabel extends StatelessWidget {
  const _BoardBitiNameLabel({
    required this.name,
    required this.creature,
    required this.cellW,
    required this.cellH,
    required this.color,
  });

  final String name;
  final Creature creature;
  final double cellW;
  final double cellH;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double cx = (creature.gridX + creature.spriteWidth * 0.5) * cellW;
    final double top = (creature.gridY + creature.spriteHeight) * cellH + 1;
    final double fontSize = (cellH * 0.26).clamp(7.0, 10.5);
    return Positioned(
      left: cx - 48,
      width: 96,
      top: top,
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.05,
          color: color.withOpacity(0.92),
          fontWeight: FontWeight.w500,
        ),
      ),
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
    final int w = model.width;
    final int h = model.height;
    final double cellW = size.width / w;
    final double cellH = size.height / h;

    final double padX = cellW * gameBoardCellPaddingRatio;
    final double padY = cellH * gameBoardCellPaddingRatio;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final GridCell cell = model.cellAt(x, y);
        final Rect rCell = Rect.fromLTWH(
          x * cellW + padX,
          y * cellH + padY,
          cellW - 2 * padX + 0.5,
          cellH - 2 * padY + 0.5,
        );
        final Radius corner = Radius.circular(
          (math.min(rCell.width, rCell.height) * 0.3).clamp(0.6, 5.0),
        );
        final RRect rRCell = RRect.fromRectAndRadius(rCell, corner);
        final Paint paint = Paint();

        if (cell.kind == CellKind.food) {
          paint.color = _terrainBase;
          canvas.drawRRect(rRCell, paint);
          paint.color = theme.mix(0.36);
          final double r = math.min(rCell.width, rCell.height) * 0.38;
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
