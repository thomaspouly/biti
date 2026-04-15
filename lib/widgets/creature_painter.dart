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

  static Color _remapPixel(Color c, BitiThemePair t) {
    if (c.a == 0) return c;
    final lum = c.computeLuminance().clamp(0.0, 1.0);
    return t.mix(0.12 + lum * 0.78);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty) return;

    final cellW = size.width / gridWidth;
    final cellH = size.height / gridHeight;
    final padX = cellW * gameBoardCellPaddingRatio;
    final padY = cellH * gameBoardCellPaddingRatio;
    final innerW = cellW - 2 * padX;
    final innerH = cellH - 2 * padY;

    final originX = creatureX * cellW + padX;
    final originY = creatureY * cellH + padY;

    final spritePixelW = frame.first.length * innerW;
    final spritePixelH = frame.length * innerH;
    final cx = originX + spritePixelW / 2;
    final cy = originY + spritePixelH / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(lean * 0.18 * math.pi);
    canvas.translate(-cx, -cy);

    for (var y = 0; y < frame.length; y++) {
      final row = frame[y];
      for (var x = 0; x < row.length; x++) {
        final color = row[x];
        if (color.a == 0) continue;
        final rect = Rect.fromLTWH(
          originX + x * innerW,
          originY + y * innerH,
          innerW + 0.5,
          innerH + 0.5,
        );
        final paint = Paint()..color = _remapPixel(color, theme);
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
