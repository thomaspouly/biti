import 'package:flutter/material.dart';

import '../services/conway_pattern_catalog.dart';
import '../theme/biti_theme_pair.dart';
import 'creature_growth.dart';

/// Humeur / état d’animation affiché (dérivé du [LifecycleService] + actions).
enum CreatureMood { idle, hungry, happy, sleeping, excited }

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

  static final Map<CreatureMood, List<SpriteFrame>> builtIn =
      <CreatureMood, List<SpriteFrame>>{
        CreatureMood.idle: _idle(),
        CreatureMood.hungry: _hungry(),
        CreatureMood.happy: _happy(),
        CreatureMood.sleeping: _sleeping(),
        CreatureMood.excited: _excited(),
      };

  static List<SpriteFrame> framesFor(CreatureMood mood) {
    return builtIn[mood] ?? builtIn[CreatureMood.idle]!;
  }

  static Color moodBodyColor(CreatureMood mood) => _moodBodyColor(mood);

  /// [growthLevel] entre **0** et [CreatureGrowth.maxGrowthLevel].
  ///
  /// Niveau **0** : un pixel (pas de motif GoL). Niveaux **≥ 1** : silhouette initiale
  /// du motif (oscillateur) colorée selon l’humeur — la simulation animée est gérée
  /// dans [HomeScreen] pour le Biti sélectionné.
  static SpriteFrame currentFrame(
    CreatureMood mood,
    int index,
    int growthLevel, {
    BitiThemePair? patternTheme,
  }) {
    final int lv = growthLevel.clamp(0, CreatureGrowth.maxGrowthLevel);
    if (lv == 0) {
      final List<SpriteFrame> frames = framesFor(mood);
      final SpriteFrame base = frames[index % frames.length];
      return _level0Frame(base, mood);
    }
    if (!BitiConwayPatterns.isLoaded) {
      return <List<Color>>[<Color>[_moodBodyColor(mood)]];
    }
    final Color c = _moodBodyColor(mood);
    final BitiThemePair t =
        patternTheme ?? BitiThemePair(a: c, b: c);
    return BitiConwayPatterns.instance.coloredInitialFrame(lv, t);
  }
}

const Color _t = Colors.transparent;
const Color _b = Color(0xFF6C5CE7);
const Color _d = Color(0xFF5F4FD8);
const Color _w = Color(0xFFE8E8E8);
const Color _k = Color(0xFF2D3436);
const Color _r = Color(0xFFE17055);
const Color _y = Color(0xFFFDCB6E);

SpriteFrame _level0Frame(SpriteFrame base, CreatureMood mood) {
  final int cy = base.length ~/ 2;
  final int cx = base.first.length ~/ 2;
  final Color c = base[cy][cx];
  if (c.a > 0) {
    return <List<Color>>[
      <Color>[c],
    ];
  }
  return <List<Color>>[
    <Color>[_moodBodyColor(mood)],
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

/// Sprites 5×5 (une lettre = un pixel de couleur, `.` = transparent).
List<SpriteFrame> _idle() => <SpriteFrame>[
  _parse(<String>['..b..', '.bbb.', 'bwkwb', '.bbb.', '..b..']),
  _parse(<String>['..b..', '.bbb.', 'bkdkb', '.bbb.', '..b..']),
];

List<SpriteFrame> _hungry() => <SpriteFrame>[
  _parse(<String>['..d..', '.ddd.', 'dwrwd', '.ddd.', '..d..']),
];

List<SpriteFrame> _happy() => <SpriteFrame>[
  _parse(<String>['..b..', '.bbb.', 'bwkwb', 'byyyb', '..b..']),
  _parse(<String>['.y.y.', '.bbb.', 'bwkwb', '.bbb.', '..b..']),
];

List<SpriteFrame> _sleeping() => <SpriteFrame>[
  _parse(<String>['..b..', '.bbb.', 'bkkkb', '.bbb.', '..z..']),
  _parse(<String>['..b..', '.bbb.', 'bkkkb', '.bbb.', '..zz.']),
];

List<SpriteFrame> _excited() => <SpriteFrame>[
  _parse(<String>['y...y', '.bbb.', 'bwkwb', 'byyyb', 'y...y']),
  _parse(<String>['y.b.y', '.bbb.', 'bwkwb', 'byyyb', 'y.b.y']),
];

SpriteFrame _parse(List<String> rows) {
  return rows
      .map((String row) => row.split('').map(_charToColor).toList())
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
