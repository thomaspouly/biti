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
import '../theme/biti_theme_pair.dart';
import '../widgets/pixel_grid.dart';
import '../widgets/stat_bar.dart';

String _deathDurationLabel(Duration d) {
  final int minutes = d.inMinutes;
  if (minutes >= 60 && minutes % 60 == 0) {
    final int h = minutes ~/ 60;
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
  late final LifecycleService _lifecycle;
  late final HeartbeatVibrationService _heartbeat;
  late final SensorService _sensors;
  late final Creature _creature;
  late PixelGridModel _grid;

  late final AnimationController _frameAnim;

  Timer? _moveTimer;
  Timer? _foodTimer;
  Timer? _persistDebounce;

  static const int _maxFoodDots = 12;

  /// Durée **continue** où au moins une jauge reste sous le seuil critique → mort (pas de nouvelle partie dans l’app).
  static const Duration bitiDeathAfterCriticalLowStreak = Duration(hours: 2);

  bool _stoppedForDeath = false;

  int _lastGrowthLevel = 1;

  /// Combinaison de 2 couleurs (index dans [BitiThemePair.presets]).
  int _themePresetIndex = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = LifecycleService(restored: widget.restoredProfile);
    final int initialSide = CreatureGrowth.terrainSideForLevel(
      _lifecycle.growthLevel,
    );
    _grid = PixelGridModel(width: initialSide, height: initialSide);
    _creature = Creature(
      gridX: (initialSide - 1) ~/ 2,
      gridY: (initialSide - 1) ~/ 2,
      spriteWidth: 1,
      spriteHeight: 1,
    );
    _lastGrowthLevel = _lifecycle.growthLevel;

    _sensors = SensorService(
      onShake: _lifecycle.play,
      onTilt: (double v) {
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
        for (int i = 0; i < 5; i++) {
          _trySpawnFood();
        }
      });
      unawaited(_loadSavedTheme());
    });
  }

  Future<void> _loadSavedTheme() async {
    final int i = await BitiStorage.loadThemePresetIndex();
    if (!mounted) return;
    setState(() => _themePresetIndex = i);
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
      final CreatureMood mood = _lifecycle.derivedMood;
      final int n = CreatureSpriteLibrary.framesFor(mood).length;
      _creature.advanceFrame(n);
      _syncGrid();
    });
    _frameAnim.forward(from: 0);
  }

  void _syncGrid() {
    final CreatureMood mood = _lifecycle.derivedMood;
    final int lvl = _lifecycle.growthLevel;
    final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
      mood,
      _creature.frameIndex,
      lvl,
    );
    _creature.spriteWidth = frame.first.length;
    _creature.spriteHeight = frame.length;

    final int terrainSide = CreatureGrowth.terrainSideForLevel(lvl);
    if (terrainSide != _grid.width || terrainSide != _grid.height) {
      _grid = PixelGridModel(width: terrainSide, height: terrainSide);
      _creature.gridX = (terrainSide - _creature.spriteWidth) ~/ 2;
      _creature.gridY = (terrainSide - _creature.spriteHeight) ~/ 2;
    }

    if (lvl > _lastGrowthLevel) {
      HapticFeedback.mediumImpact();
    }
    _lastGrowthLevel = lvl;

    _creature.clampToGrid(_grid.width, _grid.height);
    _grid.syncCreatureFootprint(_creature.gridX, _creature.gridY, frame);
  }

  void _randomStep() {
    const List<List<int>> options = <List<int>>[
      <int>[-1, 0],
      <int>[1, 0],
      <int>[0, -1],
      <int>[0, 1],
    ];
    final List<int> d = options[Random().nextInt(options.length)];
    _creature.gridX += d[0];
    _creature.gridY += d[1];
    _creature.clampToGrid(_grid.width, _grid.height);
  }

  /// Chance d’ajouter un pixel marron **uniquement** à la case du **centre** du
  /// sprite (milieu de la boîte grille), après un déplacement.
  void _tryDropWaste() {
    if (_lifecycle.sleeping) return;
    final double jitter = 0.45 + Random().nextDouble() * 1.1;
    if (Random().nextDouble() > 0.38 / 15 * jitter) return;

    final int w = _creature.spriteWidth;
    final int h = _creature.spriteHeight;
    final int cx = _creature.gridX + (w - 1) ~/ 2;
    final int cy = _creature.gridY + (h - 1) ~/ 2;
    _grid.tryPlaceWaste(cx, cy);
  }

  void _trySpawnFood() {
    if (_lifecycle.sleeping) return;
    if (_grid.countFood() >= _maxFoodDots) return;
    // Probabilité par tick réduite de 50 % vs l’ancien barème (0,35 → 0,175).
    if (Random().nextDouble() > 0.175) return;
    for (int i = 0; i < 24; i++) {
      final int w = _grid.width;
      final int h = _grid.height;
      final int x = 1 + Random().nextInt(w - 2);
      final int y = 1 + Random().nextInt(h - 2);
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
                  children: <Widget>[
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

    final CreatureMood mood = _lifecycle.derivedMood;
    final int displayGrowthLevel = _lifecycle.growthLevel;
    final double levelFill = CreatureGrowth.levelFillProgressFromXp(
      _lifecycle.xp,
    );
    final BitiThemePair pair = BitiThemePair.presetOrDefault(_themePresetIndex);
    final Color fg = pair.textStrong;
    final Color fgMuted = pair.textMuted;
    final Color trackBg = pair.trackBackground;
    final Color panel = pair.panel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      color: pair.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _lifecycle.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _LevelGaugeColumn(
                              level: displayGrowthLevel,
                              fill: displayGrowthLevel >= 6 ? 1.0 : levelFill,
                              labelColor: fgMuted,
                              trackBackgroundColor: trackBg,
                              barColor: pair.barAccent,
                            ),
                          ),
                          Expanded(
                            child: StatBar(
                              label: 'FAIM',
                              value: _lifecycle.hunger,
                              color: pair.barSecondary(0.04),
                              labelColor: fgMuted,
                              trackBackgroundColor: trackBg,
                              compactColumn: true,
                            ),
                          ),
                          Expanded(
                            child: StatBar(
                              label: 'ÉNERGIE',
                              value: _lifecycle.energy,
                              color: pair.barSecondary(-0.06),
                              labelColor: fgMuted,
                              trackBackgroundColor: trackBg,
                              compactColumn: true,
                            ),
                          ),
                          Expanded(
                            child: StatBar(
                              label: 'HUMEUR',
                              value: _lifecycle.mood,
                              color: pair.barSecondary(0.1),
                              labelColor: fgMuted,
                              trackBackgroundColor: trackBg,
                              compactColumn: true,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 2,
                      ),
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                              final double maxW = constraints.maxWidth;

                              return SizedBox(
                                width: maxW,
                                height: maxW,
                                child: PixelGrid(
                                  model: _grid,
                                  creature: _creature,
                                  mood: mood,
                                  lean: _creature.lean,
                                  growthLevel: _lifecycle.growthLevel,
                                  theme: pair,
                                  onCellTap: _onCellTap,
                                ),
                              );
                            },
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 90),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pair.mix(0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          child: Text(
                            _bitiStatusLabel(mood).toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _BitiActionBar(
                        buttonSide: _actionButtonSide(context),
                        panelColor: panel,
                        foreground: fg,
                        onFeed: _lifecycle.feed,
                        onPlay: _lifecycle.play,
                        onSleep: _lifecycle.sleep,
                        onSettings: () => _showSettings(context),
                        sleeping: _lifecycle.sleeping,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _actionButtonSide(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width - 32;
    const double gap = 8.0;
    final double raw = (w - 3 * gap) / 4;
    return raw.clamp(56, 80);
  }

  /// Libellé d’état (faim, sommeil, fatigue, humeur…) pour l’encadré sous le terrain.
  String _bitiStatusLabel(CreatureMood mood) {
    if (_lifecycle.sleeping) return 'Endormi';
    if (mood == CreatureMood.excited) return 'Excité';
    if (mood == CreatureMood.hungry) return 'Affamé';
    if (mood == CreatureMood.happy) return 'Heureux';
    if (_lifecycle.energy < 28) return 'Fatigué';
    if (_lifecycle.mood < 30) return 'Morose';
    return 'Calme';
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Aide'),
        content: SingleChildScrollView(
          child: Text(
            'Biti évolue avec le temps : la faim, l’énergie et l’humeur changent '
            'toutes les quelques secondes.\n\n'
            '• Nourrir : remonte la faim et un peu l’humeur, +${CreatureGrowth.xpPerFoodAction} XP.\n'
            '• Jouer : coûte de l’énergie mais remonte l’humeur ; secouer le '
            'téléphone déclenche aussi une partie.\n'
            '• Dormir : récupère de l’énergie tant que Biti dort.\n'
            '• Paramètres : **5 combinaisons** de 2 couleurs (tout l’écran et le '
            'terrain en dégradé entre ces deux couleurs), nom de Biti, et cette aide.\n\n'
            'Les vibrations rythment comme un pouls : plus l’énergie est basse, '
            'plus le rythme ralentit.\n\n'
            'Des pixels marron peuvent apparaître **au centre de Biti** : appuie '
            'dessus pour nettoyer (+${CreatureGrowth.xpPerWasteCleanup} XP).\n\n'
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
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    final BitiThemePair pair = BitiThemePair.presetOrDefault(_themePresetIndex);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pair.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => _BitiSettingsSheet(
        initialPresetIndex: _themePresetIndex,
        lifecycle: _lifecycle,
        onPresetSelected: (int i) {
          setState(() => _themePresetIndex = i);
          unawaited(BitiStorage.saveThemePresetIndex(i));
        },
        onShowHelp: () {
          Navigator.pop(ctx);
          _showHelp(context);
        },
        onNameSaved: _schedulePersist,
      ),
    );
  }
}

/// Jauge « niveau » (libellé LVL + barre de remplissage vers le palier suivant).
class _LevelGaugeColumn extends StatelessWidget {
  const _LevelGaugeColumn({
    required this.level,
    required this.fill,
    required this.labelColor,
    required this.trackBackgroundColor,
    required this.barColor,
  });

  final int level;
  final double fill;
  final Color labelColor;
  final Color trackBackgroundColor;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final TextStyle? labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(
          color: labelColor,
          height: 1.05,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'LVL $level'.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: trackBackgroundColor,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d’actions carrées (Nourrir, Jouer, Dormir, Paramètres).
class _BitiActionBar extends StatelessWidget {
  const _BitiActionBar({
    required this.buttonSide,
    required this.panelColor,
    required this.foreground,
    required this.onFeed,
    required this.onPlay,
    required this.onSleep,
    required this.onSettings,
    required this.sleeping,
  });

  final double buttonSide;
  final Color panelColor;
  final Color foreground;
  final VoidCallback onFeed;
  final VoidCallback onPlay;
  final VoidCallback onSleep;
  final VoidCallback onSettings;
  final bool sleeping;

  @override
  Widget build(BuildContext context) {
    const double gap = 8.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _SquareAction(
          size: buttonSide,
          panelColor: panelColor,
          foreground: foreground,
          icon: Icons.restaurant_rounded,
          semanticLabel: 'Nourrir',
          onTap: onFeed,
        ),
        const SizedBox(width: gap),
        _SquareAction(
          size: buttonSide,
          panelColor: panelColor,
          foreground: foreground,
          icon: Icons.sports_esports_rounded,
          semanticLabel: 'Jouer',
          onTap: onPlay,
        ),
        const SizedBox(width: gap),
        _SquareAction(
          size: buttonSide,
          panelColor: panelColor,
          foreground: foreground,
          icon: sleeping ? Icons.alarm_rounded : Icons.bedtime_rounded,
          semanticLabel: sleeping ? 'Réveiller' : 'Dormir',
          onTap: onSleep,
        ),
        const SizedBox(width: gap),
        _SquareAction(
          size: buttonSide,
          panelColor: panelColor,
          foreground: foreground,
          icon: Icons.settings_rounded,
          semanticLabel: 'Paramètres',
          onTap: onSettings,
        ),
      ],
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.size,
    required this.panelColor,
    required this.foreground,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final double size;
  final Color panelColor;
  final Color foreground;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double iconSize = (size * 0.48).clamp(24.0, 34.0);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: panelColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(icon, color: foreground, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

class _BitiSettingsSheet extends StatefulWidget {
  const _BitiSettingsSheet({
    required this.initialPresetIndex,
    required this.lifecycle,
    required this.onPresetSelected,
    required this.onShowHelp,
    required this.onNameSaved,
  });

  final int initialPresetIndex;
  final LifecycleService lifecycle;
  final void Function(int index) onPresetSelected;
  final VoidCallback onShowHelp;
  final VoidCallback onNameSaved;

  @override
  State<_BitiSettingsSheet> createState() => _BitiSettingsSheetState();
}

class _BitiSettingsSheetState extends State<_BitiSettingsSheet> {
  late int _presetIndex;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _presetIndex = widget.initialPresetIndex.clamp(
      0,
      BitiThemePair.presets.length - 1,
    );
    _nameCtrl = TextEditingController(text: widget.lifecycle.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(int i) {
    final int clamped = i.clamp(0, BitiThemePair.presets.length - 1);
    setState(() => _presetIndex = clamped);
    widget.onPresetSelected(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final Color sheetFg = Colors.white.withValues(alpha: 0.94);
    const Color sheetMuted = Colors.white70;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 14,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Paramètres',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: sheetFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline, color: sheetMuted),
                title: Text('Aide', style: TextStyle(color: sheetFg)),
                trailing: const Icon(Icons.chevron_right, color: sheetMuted),
                onTap: widget.onShowHelp,
              ),
              const Divider(color: Colors.white24),
              const SizedBox(height: 6),
              Text(
                'Nom de Biti',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: sheetFg),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: sheetFg),
                cursorColor: sheetFg,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.22),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: sheetFg.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (String s) {
                  widget.lifecycle.setName(s);
                  widget.onNameSaved();
                  FocusScope.of(context).unfocus();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Valide avec Entrée pour enregistrer le nom.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: sheetMuted),
              ),
              const SizedBox(height: 18),
              Text(
                'Thème (2 couleurs)',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: sheetFg),
              ),
              const SizedBox(height: 6),
              Text(
                'Tout l’écran et le terrain utilisent uniquement un dégradé entre '
                'ces deux couleurs.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: sheetMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              for (
                int i = 0;
                i < BitiThemePair.presets.length;
                i++
              ) ...<Widget>[
                if (i > 0) const SizedBox(height: 10),
                _ThemePresetRow(
                  index: i,
                  pair: BitiThemePair.presets[i],
                  selected: _presetIndex == i,
                  onTap: () => _selectPreset(i),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePresetRow extends StatelessWidget {
  const _ThemePresetRow({
    required this.index,
    required this.pair,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final BitiThemePair pair;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2.5 : 1,
            ),
            gradient: LinearGradient(colors: <Color>[pair.a, pair.b]),
          ),
          child: Text(
            'Combinaison ${index + 1}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 4,
                  color: Color(0x99000000),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
