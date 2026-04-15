import 'package:flutter/material.dart';

import 'creature_growth.dart';

/// Humeur / état d’animation affiché (dérivé du [LifecycleService] + actions).
enum CreatureMood {
  idle,
  hungry,
  happy,
  sleeping,
  excited,
}

/// Une frame de sprite : grille de couleurs (alpha 0 = transparent).
typedef SpriteFrame = List<List<Color>>;

/// Position et animation de la créature dans la grille.
///
/// Les sprites peuvent être remplacés plus tard par des assets ou une fabrique
/// custom ([CreatureSpriteLibrary] reste le point d’extension).
class Creature {
  Creature({
    required this.gridX,
    required this.gridY,
    required this.spriteWidth,
    required this.spriteHeight,
  });

  int gridX;
  int gridY;

  /// Mis à jour selon le niveau de croissance (taille du sprite sur la grille).
  int spriteWidth;
  int spriteHeight;

  int frameIndex = 0;

  /// Inclinaison visuelle (-1..1), typiquement depuis le gyroscope.
  double lean = 0;

  void clampToGrid(int gridW, int gridH) {
    gridX = gridX.clamp(1, gridW - spriteWidth - 1);
    gridY = gridY.clamp(1, gridH - spriteHeight - 1);
  }

  void advanceFrame(int frameCount) {
    if (frameCount <= 0) return;
    frameIndex = (frameIndex + 1) % frameCount;
  }
}

/// Sprites procéduraux intégrés ; à terme : charger des frames custom ici.
class CreatureSpriteLibrary {
  CreatureSpriteLibrary._();

  static final Map<CreatureMood, List<SpriteFrame>> builtIn = {
    CreatureMood.idle: _idle(),
    CreatureMood.hungry: _hungry(),
    CreatureMood.happy: _happy(),
    CreatureMood.sleeping: _sleeping(),
    CreatureMood.excited: _excited(),
  };

  static List<SpriteFrame> framesFor(CreatureMood mood) {
    return builtIn[mood] ?? builtIn[CreatureMood.idle]!;
  }

  /// [growthLevel] entre 1 et 6 (voir [CreatureGrowth]).
  static SpriteFrame currentFrame(
    CreatureMood mood,
    int index,
    int growthLevel,
  ) {
    final lv = growthLevel.clamp(1, 6);
    final frames = framesFor(mood);
    final base = frames[index % frames.length];
    final span = CreatureGrowth.gridSpanForLevel(lv);
    switch (lv) {
      case 1:
        return _level1Frame(base, mood);
      case 2:
        return _scaleNearest(base, 2, 2);
      case 3:
        return base;
      default:
        return _scaleNearest(base, span, span);
    }
  }
}

const Color _t = Colors.transparent;
const Color _b = Color(0xFF6C5CE7);
const Color _d = Color(0xFF5F4FD8);
const Color _w = Color(0xFFE8E8E8);
const Color _k = Color(0xFF2D3436);
const Color _r = Color(0xFFE17055);
const Color _y = Color(0xFFFDCB6E);

SpriteFrame _level1Frame(SpriteFrame base, CreatureMood mood) {
  final cy = base.length ~/ 2;
  final cx = base.first.length ~/ 2;
  final c = base[cy][cx];
  if (c.a > 0) {
    return [
      [c],
    ];
  }
  return [
    [_moodBodyColor(mood)],
  ];
}

Color _moodBodyColor(CreatureMood mood) {
  switch (mood) {
    case CreatureMood.hungry:
      return _d;
    case CreatureMood.excited:
      return _y;
    case CreatureMood.sleeping:
      return _b;
    default:
      return _b;
  }
}

/// Agrandissement / réduction par voisin le plus proche (référence 5×5 → cible).
SpriteFrame _scaleNearest(SpriteFrame src, int outW, int outH) {
  if (src.isEmpty || src.first.isEmpty) return src;
  final sh = src.length;
  final sw = src.first.length;
  return List.generate(outH, (y) {
    return List.generate(outW, (x) {
      final sy = (y * sh / outH).floor().clamp(0, sh - 1);
      final sx = (x * sw / outW).floor().clamp(0, sw - 1);
      return src[sy][sx];
    });
  });
}

/// Sprites 5×5 (une lettre = un pixel de couleur, `.` = transparent).
List<SpriteFrame> _idle() => [
      _parse([
        '..b..',
        '.bbb.',
        'bwkwb',
        '.bbb.',
        '..b..',
      ]),
      _parse([
        '..b..',
        '.bbb.',
        'bkdkb',
        '.bbb.',
        '..b..',
      ]),
    ];

List<SpriteFrame> _hungry() => [
      _parse([
        '..d..',
        '.ddd.',
        'dwrwd',
        '.ddd.',
        '..d..',
      ]),
    ];

List<SpriteFrame> _happy() => [
      _parse([
        '..b..',
        '.bbb.',
        'bwkwb',
        'byyyb',
        '..b..',
      ]),
      _parse([
        '.y.y.',
        '.bbb.',
        'bwkwb',
        '.bbb.',
        '..b..',
      ]),
    ];

List<SpriteFrame> _sleeping() => [
      _parse([
        '..b..',
        '.bbb.',
        'bkkkb',
        '.bbb.',
        '..z..',
      ]),
      _parse([
        '..b..',
        '.bbb.',
        'bkkkb',
        '.bbb.',
        '..zz.',
      ]),
    ];

List<SpriteFrame> _excited() => [
      _parse([
        'y...y',
        '.bbb.',
        'bwkwb',
        'byyyb',
        'y...y',
      ]),
      _parse([
        'y.b.y',
        '.bbb.',
        'bwkwb',
        'byyyb',
        'y.b.y',
      ]),
    ];

SpriteFrame _parse(List<String> rows) {
  return rows
      .map(
        (row) => row.split('').map(_charToColor).toList(),
      )
      .toList();
}

Color _charToColor(String ch) {
  switch (ch) {
    case '.':
      return _t;
    case 'b':
      return _b;
    case 'd':
      return _d;
    case 'w':
      return _w;
    case 'k':
      return _k;
    case 'r':
      return _r;
    case 'y':
      return _y;
    case 'z':
      return _w;
    default:
      return _t;
  }
}
