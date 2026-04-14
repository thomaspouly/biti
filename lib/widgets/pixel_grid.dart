import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import 'creature_painter.dart';

/// Grille pixel + créature, rendue avec [CustomPainter] (performant).
class PixelGrid extends StatelessWidget {
  const PixelGrid({
    super.key,
    required this.model,
    required this.creature,
    required this.mood,
    required this.lean,
  });

  final PixelGridModel model;
  final Creature creature;
  final CreatureMood mood;
  final double lean;

  @override
  Widget build(BuildContext context) {
    final frame = CreatureSpriteLibrary.currentFrame(mood, creature.frameIndex);

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
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

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final cell = model.cellAt(x, y);
        final rect = Rect.fromLTWH(
          x * cellW,
          y * cellH,
          cellW + 0.5,
          cellH + 0.5,
        );
        final paint = Paint();

        if (cell.kind == CellKind.creature) {
          // Le sprite animé + penché est dessiné par [CreaturePainter].
          final alt = (x + y).isEven;
          paint.color = Color.lerp(baseEmpty, altEmpty, alt ? 0.12 : 0) ?? baseEmpty;
        } else if (cell.kind == CellKind.empty) {
          final alt = (x + y).isEven;
          paint.color = Color.lerp(
                cell.color,
                altEmpty,
                alt ? 0.12 : 0,
              ) ??
              cell.color;
        } else {
          paint.color = cell.color;
        }

        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) {
    return oldDelegate.model.paintEpoch != model.paintEpoch;
  }
}
