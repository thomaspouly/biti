import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/creature.dart';

/// Dessine la frame courante du sprite avec un léger penché ([Creature.lean]).
class CreaturePainter extends CustomPainter {
  CreaturePainter({
    required this.frame,
    required this.gridWidth,
    required this.gridHeight,
    required this.creatureX,
    required this.creatureY,
    required this.lean,
  });

  final List<List<Color>> frame;
  final int gridWidth;
  final int gridHeight;
  final int creatureX;
  final int creatureY;
  final double lean;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty) return;

    final cellW = size.width / gridWidth;
    final cellH = size.height / gridHeight;

    final originX = creatureX * cellW;
    final originY = creatureY * cellH;

    final spritePixelW = frame.first.length * cellW;
    final spritePixelH = frame.length * cellH;
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
          originX + x * cellW,
          originY + y * cellH,
          cellW + 0.5,
          cellH + 0.5,
        );
        final paint = Paint()..color = color;
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
        oldDelegate.gridHeight != gridHeight;
  }
}
