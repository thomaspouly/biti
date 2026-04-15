import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/biti_profile.dart';
import '../models/creature.dart';
import '../models/creature_growth.dart';
import '../models/grid.dart';
import '../services/biti_storage.dart';
import '../services/heartbeat_vibration_service.dart';
import '../services/lifecycle_service.dart';
import '../services/sensor_service.dart';
import '../widgets/pixel_grid.dart';
import '../widgets/stat_bar.dart';

String _deathDurationLabel(Duration d) {
  final minutes = d.inMinutes;
  if (minutes >= 60 && minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return '$h heure${h > 1 ? 's' : ''}';
  }
  return '$minutes minute${minutes > 1 ? 's' : ''}';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.restoredProfile});

  /// Données restaurées au lancement, ou `null` pour les valeurs par défaut.
  final BitiProfile? restoredProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  /// Terrain de jeu : base 32×32, agrandi d’un facteur **×1.3** (≈42 cellules).
  static const int _gridW = 42;
  static const int _gridH = 42;

  late final LifecycleService _lifecycle;
  late final HeartbeatVibrationService _heartbeat;
  late final SensorService _sensors;
  late final Creature _creature;
  late final PixelGridModel _grid;

  late final AnimationController _frameAnim;

  Timer? _moveTimer;
  Timer? _foodTimer;
  Timer? _persistDebounce;

  static const int _maxFoodDots = 12;

  /// Durée **continue** où au moins une jauge reste sous le seuil critique → mort (pas de nouvelle partie dans l’app).
  static const Duration bitiDeathAfterCriticalLowStreak = Duration(hours: 2);

  bool _stoppedForDeath = false;

  int _lastGrowthLevel = 1;

  @override
  void initState() {
    super.initState();
    _lifecycle = LifecycleService(
      criticalStreakDuration: bitiDeathAfterCriticalLowStreak,
      restored: widget.restoredProfile,
    );
    _creature = Creature(
      gridX: (_gridW - 1) ~/ 2,
      gridY: (_gridH - 1) ~/ 2,
      spriteWidth: 1,
      spriteHeight: 1,
    );
    _grid = PixelGridModel(width: _gridW, height: _gridH);

    _sensors = SensorService(
      onShake: _lifecycle.play,
      onTilt: (v) {
        if (!mounted) return;
        setState(() {
          _creature.lean = (_creature.lean * 0.88 + v * 0.12).clamp(-1.0, 1.0);
        });
      },
    );
    _sensors.start();

    _lifecycle.addListener(_onLifeChanged);
    _lifecycle.startXpGrants();

    _heartbeat = HeartbeatVibrationService(_lifecycle);
    _heartbeat.start();

    _frameAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _frameAnim.addStatusListener(_onFrameAnimStatus);
    _frameAnim.forward();

    _moveTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted || _lifecycle.isDead || _lifecycle.sleeping) return;
      setState(() {
        _randomStep();
        _syncGrid();
        _tryDropWaste();
      });
    });

    _foodTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _lifecycle.isDead || _lifecycle.sleeping) return;
      setState(_trySpawnFood);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _syncGrid();
        for (var i = 0; i < 5; i++) {
          _trySpawnFood();
        }
      });
    });
  }

  void _onLifeChanged() {
    if (!mounted) return;
    if (_lifecycle.isDead && !_stoppedForDeath) {
      _stoppedForDeath = true;
      _moveTimer?.cancel();
      _moveTimer = null;
      _foodTimer?.cancel();
      _foodTimer = null;
      _frameAnim.stop();
      _sensors.dispose();
    }
    setState(_syncGrid);
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(BitiStorage.saveFromLifecycle(_lifecycle));
    });
  }

  void _onFrameAnimStatus(AnimationStatus status) {
    if (_lifecycle.isDead) return;
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      final mood = _lifecycle.derivedMood;
      final n = CreatureSpriteLibrary.framesFor(mood).length;
      _creature.advanceFrame(n);
      _syncGrid();
    });
    _frameAnim.forward(from: 0);
  }

  void _syncGrid() {
    final mood = _lifecycle.derivedMood;
    final lvl = _lifecycle.growthLevel;
    if (lvl > _lastGrowthLevel) {
      HapticFeedback.mediumImpact();
    }
    _lastGrowthLevel = lvl;
    final frame = CreatureSpriteLibrary.currentFrame(
      mood,
      _creature.frameIndex,
      lvl,
    );
    _creature.spriteWidth = frame.first.length;
    _creature.spriteHeight = frame.length;
    _creature.clampToGrid(_grid.width, _grid.height);
    _grid.syncCreatureFootprint(_creature.gridX, _creature.gridY, frame);
  }

  void _randomStep() {
    const options = <List<int>>[
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    final d = options[Random().nextInt(options.length)];
    _creature.gridX += d[0];
    _creature.gridY += d[1];
    _creature.clampToGrid(_grid.width, _grid.height);
  }

  /// Chance d’ajouter un pixel marron près des « pieds » après un déplacement.
  void _tryDropWaste() {
    if (_lifecycle.sleeping) return;
    final jitter = 0.45 + Random().nextDouble() * 1.1;
    if (Random().nextDouble() > 0.38 / 15 * jitter) return;

    final w = _creature.spriteWidth;
    final h = _creature.spriteHeight;
    final cx = _creature.gridX;
    final cy = _creature.gridY;
    final bx = cx + w ~/ 2;
    final by = cy + h;

    final ring = 1 + Random().nextInt(3);
    final candidates = <(int, int)>[];
    for (var dy = 0; dy <= ring + 1; dy++) {
      for (var dx = -(ring + 1); dx <= ring + 1; dx++) {
        final x = bx + dx;
        final y = by + dy;
        final insideSprite = x >= cx && x < cx + w && y >= cy && y < cy + h;
        if (insideSprite) continue;
        candidates.add((x, y));
      }
    }
    candidates.shuffle(Random());
    for (final p in candidates) {
      if (_grid.tryPlaceWaste(p.$1, p.$2)) return;
    }
  }

  void _trySpawnFood() {
    if (_lifecycle.sleeping) return;
    if (_grid.countFood() >= _maxFoodDots) return;
    if (Random().nextDouble() > 0.35) return;
    for (var i = 0; i < 24; i++) {
      final x = 1 + Random().nextInt(_gridW - 2);
      final y = 1 + Random().nextInt(_gridH - 2);
      if (_grid.tryPlaceFood(x, y)) return;
    }
  }

  void _onCellTap(int gx, int gy) {
    if (_lifecycle.isDead) return;
    if (_grid.removeWasteAt(gx, gy)) {
      _lifecycle.collectWasteCleanup();
      HapticFeedback.lightImpact();
      return;
    }
    if (_grid.collectFoodAt(gx, gy)) {
      _lifecycle.collectFoodMorsel();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    unawaited(BitiStorage.saveFromLifecycle(_lifecycle));
    _frameAnim.removeStatusListener(_onFrameAnimStatus);
    _frameAnim.dispose();
    _moveTimer?.cancel();
    _foodTimer?.cancel();
    _lifecycle.removeListener(_onLifeChanged);
    _heartbeat.dispose();
    _lifecycle.dispose();
    if (!_stoppedForDeath) {
      _sensors.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lifecycle.isDead) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        appBar: AppBar(
          title: Text(_lifecycle.name),
          backgroundColor: const Color(0xFF12161F),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sentiment_very_dissatisfied,
                      size: 72,
                      color: Colors.white.withOpacity(0.85),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Biti n’est plus',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Une jauge (faim, énergie ou humeur) est restée trop basse '
                      'sans interruption trop longtemps.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Il n’y a pas de bouton pour recommencer : pour une nouvelle '
                      'partie, ferme complètement l’application puis rouvre-la.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white54,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final mood = _lifecycle.derivedMood;
    final displayGrowthLevel = _lifecycle.growthLevel;
    final levelFillPct =
        (CreatureGrowth.levelFillProgressFromXp(_lifecycle.xp) * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: Text(_lifecycle.name),
        backgroundColor: const Color(0xFF12161F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Aide',
            onPressed: () => _showHelp(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _moodLabel(mood),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 6),
              StatBar(
                label: displayGrowthLevel >= 6
                    ? 'Niveau max'
                    : 'Vers niveau ${displayGrowthLevel + 1}',
                value: levelFillPct,
                color: const Color(0xFF55EFC4),
              ),
              Text(
                '${_lifecycle.xp} XP',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white38),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: PixelGrid(
                      model: _grid,
                      creature: _creature,
                      mood: mood,
                      lean: _creature.lean,
                      growthLevel: _lifecycle.growthLevel,
                      onCellTap: _onCellTap,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF12161F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatBar(
                            label: 'Faim',
                            value: _lifecycle.hunger,
                            color: const Color(0xFFE17055),
                          ),
                          StatBar(
                            label: 'Énergie',
                            value: _lifecycle.energy,
                            color: const Color(0xFF74B9FF),
                          ),
                          StatBar(
                            label: 'Humeur',
                            value: _lifecycle.mood,
                            color: const Color(0xFFA29BFE),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lifecycle.isDead ? null : _lifecycle.feed,
                      icon: const Icon(Icons.restaurant, size: 20),
                      label: const Text('Nourrir'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lifecycle.isDead ? null : _lifecycle.play,
                      icon: const Icon(Icons.sports_esports, size: 20),
                      label: const Text('Jouer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lifecycle.isDead ? null : _lifecycle.sleep,
                      icon: Icon(
                        _lifecycle.sleeping ? Icons.alarm_on : Icons.bedtime,
                        size: 20,
                      ),
                      label: Text(_lifecycle.sleeping ? 'Réveiller' : 'Dormir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aide'),
        content: SingleChildScrollView(
          child: Text(
            'Biti évolue avec le temps : la faim, l’énergie et l’humeur changent '
            'toutes les quelques secondes.\n\n'
            '• Nourrir : remonte la faim et un peu l’humeur, +${CreatureGrowth.xpPerFoodAction} XP.\n'
            '• Jouer : coûte de l’énergie mais remonte l’humeur ; secouer le '
            'téléphone déclenche aussi une partie.\n'
            '• Dormir : récupère de l’énergie tant que Biti dort.\n\n'
            'Les vibrations rythment comme un pouls : plus l’énergie est basse, '
            'plus le rythme ralentit.\n\n'
            'Des pixels marron peuvent apparaître : appuie dessus pour nettoyer '
            '(+${CreatureGrowth.xpPerWasteCleanup} XP).\n\n'
            'Les points verts sont de la nourriture : appuie dessus pour la '
            'récolter (ça remonte un peu la faim et donne +${CreatureGrowth.xpPerFoodAction} XP).\n\n'
            'La **taille** de Biti suit des **niveaux** selon l’XP : +${CreatureGrowth.xpPerSecondWhenAlive} '
            'XP par seconde tant qu’il est vivant. Paliers cumulés : niveau 2 à '
            '${CreatureGrowth.xpLevelStarts[1]} XP, 3 à ${CreatureGrowth.xpLevelStarts[2]}, '
            '4 à ${CreatureGrowth.xpLevelStarts[3]}, 5 à ${CreatureGrowth.xpLevelStarts[4]}, '
            '6 à ${CreatureGrowth.xpLevelStarts[5]} (puis taille max). La jauge '
            'verte = progression vers le prochain niveau.\n\n'
            'Si une jauge reste trop basse (sous le seuil critique) sans '
            'interruption pendant au moins ${_deathDurationLabel(bitiDeathAfterCriticalLowStreak)}, '
            'Biti meurt. Il n’y a pas de recommencer dans l’app : ferme-la '
            'complètement puis rouvre-la pour une nouvelle partie.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Paramètres',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'D’autres options (sons, vibrations, thème…) pourront être '
                'ajoutées ici.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _moodLabel(CreatureMood m) {
    switch (m) {
      case CreatureMood.idle:
        return 'Calme';
      case CreatureMood.hungry:
        return 'Affamé';
      case CreatureMood.happy:
        return 'Heureux';
      case CreatureMood.sleeping:
        return 'Endormi';
      case CreatureMood.excited:
        return 'Excité';
    }
  }
}
