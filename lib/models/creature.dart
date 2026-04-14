import 'package:flutter/material.dart';

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
  final int spriteWidth;
  final int spriteHeight;

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

  static SpriteFrame currentFrame(CreatureMood mood, int index) {
    final frames = framesFor(mood);
    return frames[index % frames.length];
  }
}

const Color _t = Colors.transparent;
const Color _b = Color(0xFF6C5CE7);
const Color _d = Color(0xFF5F4FD8);
const Color _w = Color(0xFFE8E8E8);
const Color _k = Color(0xFF2D3436);
const Color _r = Color(0xFFE17055);
const Color _y = Color(0xFFFDCB6E);

List<SpriteFrame> _idle() => [
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkwwkbb.',
        '.bbbbbbbb.',
        '..bbbbbb..',
        '...bbbb...',
        '..........',
      ]),
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkddkbb.',
        '.bbbbbbbb.',
        '..bbbbbb..',
        '...bbbb...',
        '..........',
      ]),
    ];

List<SpriteFrame> _hungry() => [
      _parse([
        '..........',
        '...dddd...',
        '..dddddd..',
        '.dddddddd.',
        '.ddwwwwdd.',
        '.ddkrrkdd.',
        '.dddddddd.',
        '..dddddd..',
        '...dddd...',
        '..........',
      ]),
    ];

List<SpriteFrame> _happy() => [
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkwwkbb.',
        '.bbbyybb..',
        '..bbbbbb..',
        '...bbbb...',
        '..........',
      ]),
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkwwkbb.',
        '..byyyyb..',
        '..bbbbbb..',
        '...bbbb...',
        '..........',
      ]),
    ];

List<SpriteFrame> _sleeping() => [
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbkkkkbb.',
        '.bbbbbbbb.',
        '..byybb...',
        '...bbbb...',
        '....z.....',
        '..........',
      ]),
      _parse([
        '..........',
        '...bbbb...',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbkkkkbb.',
        '.bbbbbbbb.',
        '..byybb...',
        '...bbbb...',
        '...zz.....',
        '..........',
      ]),
    ];

List<SpriteFrame> _excited() => [
      _parse([
        'y........y',
        '.ybbbbbb.',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkwwkbb.',
        '.bbbbbbbb.',
        '..byyyyb..',
        '.ybbbbbby.',
        'y........y',
      ]),
      _parse([
        'y........y',
        '.ybbbbbb.',
        '..bbbbbb..',
        '.bbbbbbbb.',
        '.bbwwwwbb.',
        '.bbkwwkbb.',
        '.bbbbbbbb.',
        '..byyyyb..',
        '.ybbbbbby.',
        'y........y',
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
