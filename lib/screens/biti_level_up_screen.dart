import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../theme/biti_theme_pair.dart';
import '../widgets/creature_painter.dart';

/// Plein écran après une montée de niveau : nouvelle forme + déblocages.
class BitiLevelUpScreen extends StatelessWidget {
  const BitiLevelUpScreen({
    super.key,
    required this.newLevel,
    required this.previousLevel,
    required this.bitiName,
    required this.themePair,
    required this.mood,
    required this.frameIndex,
    required this.terrainOldSide,
    required this.terrainNewSide,
    required this.terrainGrew,
    required this.oldSpriteSpan,
    required this.newSpriteSpan,
    required this.spriteSpanChanged,
  });

  final int newLevel;
  final int previousLevel;
  final String bitiName;
  final BitiThemePair themePair;
  final CreatureMood mood;
  final int frameIndex;
  final int terrainOldSide;
  final int terrainNewSide;
  final bool terrainGrew;
  final int oldSpriteSpan;
  final int newSpriteSpan;
  final bool spriteSpanChanged;

  @override
  Widget build(BuildContext context) {
    final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
      mood,
      frameIndex,
      newLevel,
      patternTheme: themePair,
    );
    final int sw = frame.first.length;
    final int sh = frame.length;
    const int gridSize = 24;
    final int cx = (gridSize - sw) ~/ 2;
    final int cy = (gridSize - sh) ~/ 2;

    final Color bg = themePair.screenBackground;
    final Color fg = themePair.textStrong;
    final Color muted = themePair.textMuted;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                'Niveau $newLevel',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (previousLevel < newLevel)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Depuis le niveau $previousLevel',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                bitiName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: muted),
              ),
              const Spacer(),
              AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double side = c.maxWidth.clamp(0.0, 320.0);
                    return Center(
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: CustomPaint(
                          painter: CreaturePainter(
                            frame: frame,
                            gridWidth: gridSize,
                            gridHeight: gridSize,
                            creatureX: cx,
                            creatureY: cy,
                            lean: 0,
                            theme: themePair,
                            directCellColors: newLevel >= 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Débloqué',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _unlockChildren(context, fg, muted),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: themePair.barAccent,
                    foregroundColor: themePair.textStrong,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Continuer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _unlockChildren(BuildContext context, Color fg, Color muted) {
    final List<Widget> out = <Widget>[];

    if (terrainGrew) {
      out.add(
        _unlockRow(
          Icons.grid_on,
          'Zone de jeu',
          '$terrainOldSide×$terrainOldSide → $terrainNewSide×$terrainNewSide cases',
          fg,
          muted,
        ),
      );
    }

    if (spriteSpanChanged) {
      if (out.isNotEmpty) {
        out.add(const SizedBox(height: 14));
      }
      out.add(
        _unlockRow(
          Icons.straighten,
          'Taille sur la grille',
          '$oldSpriteSpan×$oldSpriteSpan → $newSpriteSpan×$newSpriteSpan cases',
          fg,
          muted,
        ),
      );
    }

    if (out.isEmpty) {
      out.add(
        Text(
          'Nouvelle étape de croissance : continue à t’occuper de ton Biti.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    }

    return out;
  }

  Widget _unlockRow(
    IconData icon,
    String title,
    String subtitle,
    Color fg,
    Color muted,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: themePair.mix(0.55), size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: muted, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
