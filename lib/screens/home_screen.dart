import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/creature.dart';
import '../models/grid.dart';
import '../services/heartbeat_vibration_service.dart';
import '../services/lifecycle_service.dart';
import '../services/sensor_service.dart';
import '../widgets/pixel_grid.dart';
import '../widgets/stat_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const int _gridW = 32;
  static const int _gridH = 32;

  late final LifecycleService _lifecycle;
  late final HeartbeatVibrationService _heartbeat;
  late final SensorService _sensors;
  late final Creature _creature;
  late final PixelGridModel _grid;

  late final AnimationController _frameAnim;

  Timer? _moveTimer;
  Timer? _foodTimer;

  static const int _maxFoodDots = 12;

  @override
  void initState() {
    super.initState();
    _lifecycle = LifecycleService();
    _creature = Creature(
      gridX: (_gridW - 10) ~/ 2,
      gridY: (_gridH - 10) ~/ 2,
      spriteWidth: 10,
      spriteHeight: 10,
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

    _heartbeat = HeartbeatVibrationService(_lifecycle);
    _heartbeat.start();

    _frameAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _frameAnim.addStatusListener(_onFrameAnimStatus);
    _frameAnim.forward();

    _moveTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted || _lifecycle.sleeping) return;
      setState(() {
        _randomStep();
        _syncGrid();
        _tryDropWaste();
      });
    });

    _foodTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _lifecycle.sleeping) return;
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
    setState(_syncGrid);
  }

  void _onFrameAnimStatus(AnimationStatus status) {
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
    final frame = CreatureSpriteLibrary.currentFrame(mood, _creature.frameIndex);
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
    if (Random().nextDouble() > 0.38 / 5) return;

    final w = _creature.spriteWidth;
    final h = _creature.spriteHeight;
    final cx = _creature.gridX;
    final cy = _creature.gridY;
    final bx = cx + w ~/ 2;
    final by = cy + h;

    final candidates = <(int, int)>[];
    for (var dy = 0; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = bx + dx;
        final y = by + dy;
        final insideSprite = x >= cx &&
            x < cx + w &&
            y >= cy &&
            y < cy + h;
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
    if (_grid.removeWasteAt(gx, gy)) {
      HapticFeedback.lightImpact();
      setState(() {});
      return;
    }
    if (_grid.collectFoodAt(gx, gy)) {
      _lifecycle.collectFoodMorsel();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _frameAnim.removeStatusListener(_onFrameAnimStatus);
    _frameAnim.dispose();
    _moveTimer?.cancel();
    _foodTimer?.cancel();
    _lifecycle.removeListener(_onLifeChanged);
    _heartbeat.dispose();
    _lifecycle.dispose();
    _sensors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = _lifecycle.derivedMood;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text('Biti'),
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white60,
                    ),
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
                      onPressed: _lifecycle.feed,
                      icon: const Icon(Icons.restaurant, size: 20),
                      label: const Text('Nourrir'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lifecycle.play,
                      icon: const Icon(Icons.sports_esports, size: 20),
                      label: const Text('Jouer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lifecycle.sleep,
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
        content: const SingleChildScrollView(
          child: Text(
            'Biti évolue avec le temps : la faim, l’énergie et l’humeur changent '
            'toutes les quelques secondes.\n\n'
            '• Nourrir : remonte la faim et un peu l’humeur.\n'
            '• Jouer : coûte de l’énergie mais remonte l’humeur ; secouer le '
            'téléphone déclenche aussi une partie.\n'
            '• Dormir : récupère de l’énergie tant que Biti dort.\n\n'
            'Les vibrations rythment comme un pouls : plus l’énergie est basse, '
            'plus le rythme ralentit.\n\n'
            'Des pixels marron peuvent apparaître : appuie dessus pour nettoyer.\n\n'
            'Les points verts sont de la nourriture : appuie dessus pour la '
            'récolter (ça remonte un peu la faim).',
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'D’autres options (sons, vibrations, thème…) pourront être '
                'ajoutées ici.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
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
