import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import '../theme/biti_theme_pair.dart';

/// Dessine la frame courante du sprite avec un léger penché ([Creature.lean]).
/// Couleurs uniquement sur le segment [theme.a] → [theme.b].
class CreaturePainter extends CustomPainter {
  CreaturePainter({
    required this.frame,
    required this.gridWidth,
    required this.gridHeight,
    required this.creatureX,
    required this.creatureY,
    required this.lean,
    required this.theme,
  });

  final List<List<Color>> frame;
  final int gridWidth;
  final int gridHeight;
  final int creatureX;
  final int creatureY;
  final double lean;
  final BitiThemePair theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty) return;

    final double cellW = size.width / gridWidth;
    final double cellH = size.height / gridHeight;
    final double padX = cellW * gameBoardCellPaddingRatio;
    final double padY = cellH * gameBoardCellPaddingRatio;
    final double innerW = cellW - 2 * padX;
    final double innerH = cellH - 2 * padY;

    final double originX = creatureX * cellW + padX;
    final double originY = creatureY * cellH + padY;

    final double spritePixelW = frame.first.length * innerW;
    final double spritePixelH = frame.length * innerH;
    final double cx = originX + spritePixelW / 2;
    final double cy = originY + spritePixelH / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(lean * 0.18 * math.pi);
    canvas.translate(-cx, -cy);

    for (int y = 0; y < frame.length; y++) {
      final List<Color> row = frame[y];
      for (int x = 0; x < row.length; x++) {
        final Color color = row[x];
        if (color.a == 0) continue;
        final Rect rect = Rect.fromLTWH(
          originX + x * innerW,
          originY + y * innerH,
          innerW + 0.5,
          innerH + 0.5,
        );
        final Paint paint = Paint()..color = theme.mapSpritePixelColor(color);
        canvas.drawRect(rect, paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CreaturePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.creatureX != creatureX ||
        oldDelegate.creatureY != creatureY ||
        oldDelegate.lean != lean ||
        oldDelegate.gridWidth != gridWidth ||
        oldDelegate.gridHeight != gridHeight ||
        oldDelegate.theme != theme;
  }
}
