import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/creature.dart';
import '../models/grid.dart';
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
  late final SensorService _sensors;
  late final Creature _creature;
  late final PixelGridModel _grid;

  late final AnimationController _frameAnim;

  Timer? _moveTimer;

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
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_syncGrid);
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

  @override
  void dispose() {
    _frameAnim.removeStatusListener(_onFrameAnimStatus);
    _frameAnim.dispose();
    _moveTimer?.cancel();
    _lifecycle.removeListener(_onLifeChanged);
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
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
