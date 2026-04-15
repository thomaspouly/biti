import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/biti_transfer_bloc.dart';
import '../models/biti_collection.dart';
import '../models/biti_profile.dart';
import '../models/creature.dart';
import '../models/creature_growth.dart';
import '../models/grid.dart';
import '../services/biti_storage.dart';
import '../services/biti_transfer_service.dart';
import '../services/heartbeat_vibration_service.dart';
import '../services/lifecycle_service.dart';
import '../services/sensor_service.dart';
import '../theme/biti_theme_pair.dart';
import '../widgets/biti_transfer_button.dart';
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
  const HomeScreen({super.key, required this.initialCollection});

  /// Collection au moment de l’ouverture (peut être vide).
  final BitiCollection initialCollection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  /// Mode avec Biti principal (false = écran « plus de Biti » après envoi).
  bool _petMode = false;

  LifecycleService? _lifecycle;
  HeartbeatVibrationService? _heartbeat;
  SensorService? _sensors;

  /// Une entrée par profil : tous visibles sur le même plateau.
  final Map<String, Creature> _creaturesById = <String, Creature>{};
  late PixelGridModel _grid;

  /// Invalide le placement quand la taille du terrain ou la liste d’ids change.
  String? _boardLayoutSig;

  AnimationController? _frameAnim;

  /// Zoom / pan du terrain (réinitialisable pour centrer sur le Biti).
  TransformationController? _terrainViewController;

  late BitiCollection _collection;

  Timer? _moveTimer;
  Timer? _foodTimer;
  Timer? _persistDebounce;

  static const int _maxFoodDots = 12;

  /// Durée **continue** où au moins une jauge reste sous le seuil critique → mort (pas de nouvelle partie dans l’app).
  static const Duration bitiDeathAfterCriticalLowStreak = Duration(hours: 2);

  bool _stoppedForDeath = false;

  int _lastGrowthLevel = 1;

  BitiProfile? get _selected => _collection.selected;

  Creature get _selectedCreature => _creaturesById[_selected!.id]!;

  /// Humeur affichée à partir des stats persistées (Biti non sélectionné).
  CreatureMood _moodFromProfile(BitiProfile p) {
    if (p.isDead) return CreatureMood.idle;
    if (p.sleeping) return CreatureMood.sleeping;
    if (p.hunger < 28) return CreatureMood.hungry;
    if (p.mood > 78 && p.hunger > 42) return CreatureMood.happy;
    return CreatureMood.idle;
  }

  int _maxTerrainGrowthLevel() {
    int maxLv = 1;
    for (final BitiProfile p in _collection.profiles) {
      maxLv = max(maxLv, CreatureGrowth.levelFromXp(p.xp));
    }
    if (_lifecycle != null) {
      maxLv = max(maxLv, _lifecycle!.growthLevel);
    }
    return maxLv;
  }

  (int, int) _slotForIndex(int index, int sw, int sh, int gw, int gh) {
    const int pad = 2;
    const int stepX = 14;
    const int stepY = 14;
    final int innerW = gw - 2 * pad - sw;
    final int innerH = gh - 2 * pad - sh;
    if (innerW < 1 || innerH < 1) {
      return (pad, pad);
    }
    final int cols = max(1, innerW ~/ stepX);
    final int col = index % cols;
    final int row = index ~/ cols;
    int gx = pad + col * stepX;
    int gy = pad + row * stepY;
    if (gx > gw - sw - pad) gx = gw - sw - pad;
    if (gy > gh - sh - pad) gy = gh - sh - pad;
    return (gx, gy);
  }

  String _boardLayoutSignature() {
    final int side = CreatureGrowth.terrainSideForLevel(
      _maxTerrainGrowthLevel(),
    );
    final List<String> ids =
        _collection.profiles.map((BitiProfile p) => p.id).toList()..sort();
    return '$side|${ids.join(',')}';
  }

  void _maybeRelayoutBoard() {
    if (!_petMode || _lifecycle == null) return;
    final String sig = _boardLayoutSignature();
    if (sig == _boardLayoutSig) return;
    _boardLayoutSig = sig;
    _rebuildBoardPositions();
  }

  void _rebuildBoardPositions() {
    final int side = _grid.width;
    final List<String> ids =
        _collection.profiles.map((BitiProfile p) => p.id).toList()..sort();
    for (final String id in ids) {
      _creaturesById.putIfAbsent(
        id,
        () => Creature(gridX: 1, gridY: 1, spriteWidth: 1, spriteHeight: 1),
      );
    }
    _creaturesById.removeWhere((String k, _) => !ids.contains(k));

    final BitiProfile? sel = _selected;
    int i = 0;
    for (final String id in ids) {
      final Creature c = _creaturesById[id]!;
      final BitiProfile p = _collection.profiles.firstWhere(
        (BitiProfile x) => x.id == id,
      );
      final int gl = sel != null && id == sel.id && _lifecycle != null
          ? _lifecycle!.growthLevel
          : CreatureGrowth.levelFromXp(p.xp);
      final CreatureMood m = sel != null && id == sel.id && _lifecycle != null
          ? _lifecycle!.derivedMood
          : _moodFromProfile(p);
      final SpriteFrame fr = CreatureSpriteLibrary.currentFrame(
        m,
        id == sel?.id ? c.frameIndex : 0,
        gl,
      );
      c.spriteWidth = fr.first.length;
      c.spriteHeight = fr.length;
      final (int gx, int gy) = _slotForIndex(
        i,
        c.spriteWidth,
        c.spriteHeight,
        side,
        side,
      );
      c.gridX = gx;
      c.gridY = gy;
      c.clampToGrid(side, side);
      i++;
    }
  }

  List<PixelGridBoardBiti> _boardBitisForPixelGrid() {
    final BitiProfile? sel = _selected;
    if (sel == null || !_petMode || _lifecycle == null) {
      return const <PixelGridBoardBiti>[];
    }
    final LifecycleService life = _lifecycle!;
    final List<String> sorted =
        _collection.profiles.map((BitiProfile p) => p.id).toList()..sort();
    final List<PixelGridBoardBiti> out = <PixelGridBoardBiti>[];
    for (final String id in sorted) {
      if (id == sel.id) continue;
      final BitiProfile p = _collection.profiles.firstWhere(
        (BitiProfile x) => x.id == id,
      );
      final Creature c = _creaturesById[id]!;
      final String showName = p.name.trim().isEmpty
          ? BitiProfile.defaultName
          : p.name.trim();
      out.add(
        PixelGridBoardBiti(
          name: showName,
          creature: c,
          mood: _moodFromProfile(p),
          lean: 0,
          growthLevel: CreatureGrowth.levelFromXp(p.xp),
          creatureTheme: BitiThemePair.pairFor(p),
        ),
      );
    }
    final Creature sc = _creaturesById[sel.id]!;
    final String selName = life.name.trim().isEmpty
        ? BitiProfile.defaultName
        : life.name.trim();
    out.add(
      PixelGridBoardBiti(
        name: selName,
        creature: sc,
        mood: life.derivedMood,
        lean: sc.lean,
        growthLevel: life.growthLevel,
        creatureTheme: _creatureTintForSelected(),
        isSelected: true,
      ),
    );
    return out;
  }

  /// Interface (fond, jauges, barre d’actions) : toujours la combinaison 1.
  BitiThemePair _uiPair() => BitiThemePair.presets[0];

  /// Teinte du **sprite Biti** sur la grille (profil : préréglage + couleurs A/B perso).
  BitiThemePair _creatureTintForSelected() {
    final BitiProfile? s = _selected;
    if (s == null) return _uiPair();
    return BitiThemePair.pairFor(s);
  }

  /// Profil complet pour le BLE : stats à jour + [themePresetIndex] / couleurs perso.
  BitiProfile? _profileForTransfer() {
    final BitiProfile? s = _selected;
    final LifecycleService? life = _lifecycle;
    if (s == null || life == null) return null;
    return s.copyWith(
      name: life.name,
      hunger: life.hunger,
      energy: life.energy,
      mood: life.mood,
      xp: life.xp,
      sleeping: life.sleeping,
      isDead: life.isDead,
    );
  }

  @override
  void initState() {
    super.initState();
    _collection = widget.initialCollection;
    if (widget.initialCollection.isEmpty) {
      _petMode = false;
      _lifecycle = null;
      _grid = PixelGridModel(width: 5, height: 5);
      return;
    }

    final BitiProfile start = _collection.selected!;
    _petMode = true;
    _lifecycle = LifecycleService(restored: start);
    final int initialSide = CreatureGrowth.terrainSideForLevel(
      _maxTerrainGrowthLevel(),
    );
    _grid = PixelGridModel(width: initialSide, height: initialSide);
    _boardLayoutSig = null;
    _maybeRelayoutBoard();
    _lastGrowthLevel = _lifecycle!.growthLevel;
    _terrainViewController = TransformationController();

    _sensors = SensorService(
      onShake: _lifecycle!.play,
      onTilt: (double v) {
        if (!mounted) return;
        setState(() {
          final Creature c = _selectedCreature;
          c.lean = (c.lean * 0.88 + v * 0.12).clamp(-1.0, 1.0);
        });
      },
    );
    _sensors!.start();

    _lifecycle!.addListener(_onLifeChanged);
    _lifecycle!.startXpGrants();

    _heartbeat = HeartbeatVibrationService(_lifecycle!);
    _heartbeat!.start();

    _frameAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _frameAnim!.addStatusListener(_onFrameAnimStatus);
    _frameAnim!.forward();

    _moveTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted || _lifecycle!.isDead || _lifecycle!.sleeping) return;
      setState(() {
        _randomStep();
        _syncGrid();
        _tryDropWaste();
      });
    });

    _foodTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _lifecycle!.isDead || _lifecycle!.sleeping) return;
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
    });
  }

  Future<void> _switchToProfile(String id) async {
    if (!_petMode || _lifecycle == null) return;
    final BitiProfile? cur = _collection.selected;
    if (cur != null) {
      await BitiStorage.saveLifecycleIntoProfile(_lifecycle!, cur);
    }
    await BitiStorage.setSelectedId(id);
    final BitiCollection c = await BitiStorage.loadCollection();
    final BitiProfile? next = c.selected;
    if (next == null || !mounted) return;
    setState(() {
      _collection = c;
      _lifecycle!.applyFromProfile(next);
      _reanchorCreatureForGrowth();
    });
  }

  Future<void> _addBitiAndSelect() async {
    await BitiStorage.addNewBiti();
    final BitiCollection c = await BitiStorage.loadCollection();
    if (!mounted || c.selected == null) return;
    if (_petMode && _lifecycle != null) {
      final BitiProfile? cur = _collection.selected;
      if (cur != null) {
        await BitiStorage.saveLifecycleIntoProfile(_lifecycle!, cur);
      }
      setState(() {
        _collection = c;
        _lifecycle!.applyFromProfile(c.selected!);
        _reanchorCreatureForGrowth();
      });
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(initialCollection: c),
        ),
      );
    }
  }

  void _reanchorCreatureForGrowth() {
    if (!_petMode || _lifecycle == null) return;
    final int terrainSide = CreatureGrowth.terrainSideForLevel(
      _maxTerrainGrowthLevel(),
    );
    if (terrainSide != _grid.width || terrainSide != _grid.height) {
      _grid = PixelGridModel(width: terrainSide, height: terrainSide);
      _boardLayoutSig = null;
      _maybeRelayoutBoard();
    }
    _lastGrowthLevel = _lifecycle!.growthLevel;
  }

  void _showBitiPicker(BuildContext context) {
    final BitiThemePair chrome = _uiPair();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: chrome.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Mes Biti',
                  style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                    color: chrome.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(
                  'Nouveau Biti',
                  style: TextStyle(color: chrome.textStrong),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _addBitiAndSelect();
                },
              ),
              const Divider(height: 1),
              SizedBox(
                height: (MediaQuery.sizeOf(sheetCtx).height * 0.42).clamp(
                  120.0,
                  420.0,
                ),
                child: ListView.builder(
                  itemCount: _collection.profiles.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final BitiProfile p = _collection.profiles[i];
                    final bool sel = p.id == _collection.effectiveSelectedId;
                    final BitiThemePair rowPair = BitiThemePair.pairFor(p);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: rowPair.mix(0.5),
                        child: Text(
                          p.name.isNotEmpty
                              ? p.name.substring(0, 1).toUpperCase()
                              : '?',
                          style: TextStyle(color: rowPair.textStrong),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: TextStyle(
                          color: chrome.textStrong,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'XP ${p.xp} · faim ${p.hunger}',
                        style: TextStyle(color: chrome.textMuted),
                      ),
                      trailing: sel
                          ? Icon(Icons.check_circle, color: chrome.barAccent)
                          : null,
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        if (!sel) await _switchToProfile(p.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onLifeChanged() {
    if (!mounted || !_petMode || _lifecycle == null) return;
    if (_lifecycle!.isDead && !_stoppedForDeath) {
      _stoppedForDeath = true;
      _moveTimer?.cancel();
      _moveTimer = null;
      _foodTimer?.cancel();
      _foodTimer = null;
      _frameAnim?.stop();
      _sensors?.dispose();
    }
    setState(_syncGrid);
    _schedulePersist();
  }

  void _schedulePersist() {
    if (!_petMode || _lifecycle == null) return;
    final BitiProfile snapshot = _selected!;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _lifecycle == null) return;
      final BitiProfile? now = _selected;
      if (now == null || now.id != snapshot.id) return;
      unawaited(BitiStorage.saveLifecycleIntoProfile(_lifecycle!, now));
    });
  }

  void _onFrameAnimStatus(AnimationStatus status) {
    if (!_petMode || _lifecycle == null || _lifecycle!.isDead) return;
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      final CreatureMood mood = _lifecycle!.derivedMood;
      final int n = CreatureSpriteLibrary.framesFor(mood).length;
      _selectedCreature.advanceFrame(n);
      _syncGrid();
    });
    _frameAnim?.forward(from: 0);
  }

  void _syncGrid() {
    if (!_petMode || _lifecycle == null) return;
    final BitiProfile? sel = _selected;
    if (sel == null) return;

    final LifecycleService life = _lifecycle!;
    final int terrainSide = CreatureGrowth.terrainSideForLevel(
      _maxTerrainGrowthLevel(),
    );
    if (terrainSide != _grid.width || terrainSide != _grid.height) {
      _grid = PixelGridModel(width: terrainSide, height: terrainSide);
      _boardLayoutSig = null;
    }
    _maybeRelayoutBoard();

    final List<String> sortedIds =
        _collection.profiles.map((BitiProfile p) => p.id).toList()..sort();

    for (final String id in sortedIds) {
      final Creature c = _creaturesById[id]!;
      final BitiProfile p = _collection.profiles.firstWhere(
        (BitiProfile x) => x.id == id,
      );
      if (id == sel.id) {
        final CreatureMood mood = life.derivedMood;
        final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
          mood,
          c.frameIndex,
          life.growthLevel,
        );
        c.spriteWidth = frame.first.length;
        c.spriteHeight = frame.length;
      } else {
        final CreatureMood mood = _moodFromProfile(p);
        final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
          mood,
          0,
          CreatureGrowth.levelFromXp(p.xp),
        );
        c.spriteWidth = frame.first.length;
        c.spriteHeight = frame.length;
      }
      c.clampToGrid(_grid.width, _grid.height);
    }

    if (life.growthLevel > _lastGrowthLevel) {
      HapticFeedback.mediumImpact();
    }
    _lastGrowthLevel = life.growthLevel;

    final List<String> stampIds = <String>[
      for (final String id in sortedIds)
        if (id != sel.id) id,
      sel.id,
    ];

    final List<({int x, int y, List<List<Color>> frame})> stamps =
        <({int x, int y, List<List<Color>> frame})>[];
    for (final String id in stampIds) {
      final Creature c = _creaturesById[id]!;
      final BitiProfile p = _collection.profiles.firstWhere(
        (BitiProfile x) => x.id == id,
      );
      final CreatureMood mood = id == sel.id
          ? life.derivedMood
          : _moodFromProfile(p);
      final int gl = id == sel.id
          ? life.growthLevel
          : CreatureGrowth.levelFromXp(p.xp);
      final int fi = id == sel.id ? c.frameIndex : 0;
      final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
        mood,
        fi,
        gl,
      );
      stamps.add((x: c.gridX, y: c.gridY, frame: frame));
    }

    _grid.syncMultiCreatureFootprints(stamps);
  }

  void _randomStep() {
    const List<List<int>> options = <List<int>>[
      <int>[-1, 0],
      <int>[1, 0],
      <int>[0, -1],
      <int>[0, 1],
    ];
    final List<int> d = options[Random().nextInt(options.length)];
    final Creature c = _selectedCreature;
    c.gridX += d[0];
    c.gridY += d[1];
    c.clampToGrid(_grid.width, _grid.height);
  }

  /// Chance d’ajouter un pixel marron **uniquement** à la case du **centre** du
  /// sprite (milieu de la boîte grille), après un déplacement.
  void _tryDropWaste() {
    if (!_petMode || _lifecycle == null || _lifecycle!.sleeping) return;
    final double jitter = 0.45 + Random().nextDouble() * 1.1;
    if (Random().nextDouble() > 0.38 / 15 * jitter) return;

    final Creature c = _selectedCreature;
    final int w = c.spriteWidth;
    final int h = c.spriteHeight;
    final int cx = c.gridX + (w - 1) ~/ 2;
    final int cy = c.gridY + (h - 1) ~/ 2;
    _grid.tryPlaceWaste(cx, cy);
  }

  void _trySpawnFood() {
    if (!_petMode || _lifecycle == null || _lifecycle!.sleeping) return;
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
    if (!_petMode || _lifecycle == null || _lifecycle!.isDead) return;
    if (_grid.removeWasteAt(gx, gy)) {
      _lifecycle!.collectWasteCleanup();
      HapticFeedback.lightImpact();
      return;
    }
    if (_grid.collectFoodAt(gx, gy)) {
      _lifecycle!.collectFoodMorsel();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    final BitiProfile? s = _selected;
    if (_petMode && _lifecycle != null && s != null) {
      unawaited(BitiStorage.saveLifecycleIntoProfile(_lifecycle!, s));
    }
    if (_frameAnim != null) {
      _frameAnim!.removeStatusListener(_onFrameAnimStatus);
      _frameAnim!.dispose();
    }
    _moveTimer?.cancel();
    _foodTimer?.cancel();
    if (_lifecycle != null) {
      _lifecycle!.removeListener(_onLifeChanged);
      _heartbeat?.dispose();
      _lifecycle!.dispose();
    }
    if (!_stoppedForDeath) {
      _sensors?.dispose();
    }
    _terrainViewController?.dispose();
    super.dispose();
  }

  /// Centre du sprite du Biti sélectionné, en coordonnées du carré logique [0..side].
  Offset _selectedCreatureCenterInSidePixels(double side) {
    final Creature c = _selectedCreature;
    final int gw = _grid.width;
    final int gh = _grid.height;
    final double cellW = side / gw;
    final double cellH = side / gh;
    final double padX = cellW * gameBoardCellPaddingRatio;
    final double padY = cellH * gameBoardCellPaddingRatio;
    final double innerW = cellW - 2 * padX;
    final double innerH = cellH - 2 * padY;
    final double originX = c.gridX * cellW + padX;
    final double originY = c.gridY * cellH + padY;
    final double cx = originX + (c.spriteWidth * innerW) * 0.5;
    final double cy = originY + (c.spriteHeight * innerH) * 0.5;
    return Offset(cx, cy);
  }

  void _centerTerrainCameraOnSelectedBiti(double side) {
    final TransformationController? tc = _terrainViewController;
    if (tc == null || !_petMode || _lifecycle == null) return;
    final Offset focal = _selectedCreatureCenterInSidePixels(side);
    final double s = tc.value.getMaxScaleOnAxis().clamp(1.0, 4.0);
    tc.value = Matrix4.identity()
      ..translate(side * 0.5, side * 0.5)
      ..scale(s, s, 1.0)
      ..translate(-focal.dx, -focal.dy);
    HapticFeedback.lightImpact();
  }

  Widget _buildNoBitiScaffold(BuildContext context) {
    final BitiThemePair pair = BitiThemePair.presets[0];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      color: pair.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Biti'),
          backgroundColor: pair.panel,
          foregroundColor: pair.textStrong,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Spacer(),
                Icon(Icons.pets_outlined, size: 64, color: pair.textMuted),
                const SizedBox(height: 20),
                Text(
                  'Tu n’as plus de Biti',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: pair.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Après un envoi, ton Biti vit chez quelqu’un d’autre. '
                  'Demande à un ami de t’en transférer un avec Accueillir / Envoyer.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: pair.textMuted,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showBitiTransferSheet(context),
                  icon: const Icon(Icons.bluetooth_rounded),
                  label: const Text('Transfert Bluetooth'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await BitiStorage.addNewBiti();
                    final BitiCollection c = await BitiStorage.loadCollection();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => HomeScreen(initialCollection: c),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Créer un Biti'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_petMode) {
      return _buildNoBitiScaffold(context);
    }
    if (_lifecycle!.isDead) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        appBar: AppBar(
          title: Text(_lifecycle!.name),
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

    final LifecycleService life = _lifecycle!;
    final CreatureMood mood = life.derivedMood;
    final int displayGrowthLevel = life.growthLevel;
    final double levelFill = CreatureGrowth.levelFillProgressFromXp(life.xp);
    final BitiThemePair uiPair = _uiPair();
    final Color fg = uiPair.textStrong;
    final Color fgMuted = uiPair.textMuted;
    final Color trackBg = uiPair.trackBackground;
    final Color panel = uiPair.panel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      color: uiPair.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 8,
                        ),
                        child: LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                final double w = constraints.maxWidth;
                                final double h = constraints.maxHeight;
                                if (w <= 0 || h <= 0) {
                                  return const SizedBox.shrink();
                                }
                                final double side = min(w, h);
                                final double scaleCover = max(
                                  w / side,
                                  h / side,
                                );
                                final TransformationController tc =
                                    _terrainViewController!;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: w,
                                        height: h,
                                        child: ClipRect(
                                          child: Center(
                                            child: Transform.scale(
                                              scale: scaleCover,
                                              child: SizedBox(
                                                width: side,
                                                height: side,
                                                child: InteractiveViewer(
                                                  transformationController: tc,
                                                  minScale: 0.7,
                                                  maxScale: 5.0,
                                                  boundaryMargin:
                                                      EdgeInsets.all(
                                                        side * 1.5,
                                                      ),
                                                  clipBehavior: Clip.hardEdge,
                                                  child: SizedBox(
                                                    width: side,
                                                    height: side,
                                                    child: PixelGrid(
                                                      model: _grid,
                                                      theme: uiPair,
                                                      boardBitis:
                                                          _boardBitisForPixelGrid(),
                                                      nameLabelColor: fgMuted,
                                                      onCellTap: _onCellTap,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 6,
                                      bottom: 6,
                                      child: Material(
                                        color: panel.withValues(alpha: 0.92),
                                        elevation: 3,
                                        shadowColor: Colors.black45,
                                        shape: const CircleBorder(),
                                        child: IconButton(
                                          tooltip: 'Centrer sur Biti',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            Icons.center_focus_strong_rounded,
                                            color: fg,
                                          ),
                                          onPressed: () =>
                                              _centerTerrainCameraOnSelectedBiti(
                                                side,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: uiPair.mix(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: uiPair.mix(0.28),
                            width: 1.2,
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                14,
                                12,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.only(right: 40),
                                    child: Text(
                                      life.name.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: fg,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.4,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        child: _LevelGaugeColumn(
                                          level: displayGrowthLevel,
                                          fill: displayGrowthLevel >= 6
                                              ? 1.0
                                              : levelFill,
                                          labelColor: fgMuted,
                                          trackBackgroundColor: trackBg,
                                          barColor: uiPair.barAccent,
                                        ),
                                      ),
                                      Expanded(
                                        child: StatBar(
                                          label: 'FAIM',
                                          value: life.hunger,
                                          color: uiPair.barSecondary(0.04),
                                          labelColor: fgMuted,
                                          trackBackgroundColor: trackBg,
                                          compactColumn: true,
                                        ),
                                      ),
                                      Expanded(
                                        child: StatBar(
                                          label: 'ÉNERGIE',
                                          value: life.energy,
                                          color: uiPair.barSecondary(-0.06),
                                          labelColor: fgMuted,
                                          trackBackgroundColor: trackBg,
                                          compactColumn: true,
                                        ),
                                      ),
                                      Expanded(
                                        child: StatBar(
                                          label: 'HUMEUR',
                                          value: life.mood,
                                          color: uiPair.barSecondary(0.1),
                                          labelColor: fgMuted,
                                          trackBackgroundColor: trackBg,
                                          compactColumn: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: uiPair.mix(0.16),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        _bitiStatusLabel(mood).toUpperCase(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: fg,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: IconButton(
                                tooltip: 'Changer de Biti',
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  foregroundColor: fg,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _showBitiPicker(context),
                                icon: const Icon(Icons.swap_horiz_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _BitiActionBar(
                        buttonSide: _actionButtonSide(context),
                        panelColor: panel,
                        foreground: fg,
                        onPlay: life.play,
                        onSleep: life.sleep,
                        onTransfer: () => _showBitiTransferSheet(context),
                        onSettings: () => _showSettings(context),
                        sleeping: life.sleeping,
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
    return raw.clamp(52, 76);
  }

  /// Libellé d’état (faim, sommeil, fatigue, humeur…) pour l’encadré sous le terrain.
  String _bitiStatusLabel(CreatureMood mood) {
    final LifecycleService life = _lifecycle!;
    if (life.sleeping) return 'Endormi';
    if (mood == CreatureMood.excited) return 'Excité';
    if (mood == CreatureMood.hungry) return 'Affamé';
    if (mood == CreatureMood.happy) return 'Heureux';
    if (life.energy < 28) return 'Fatigué';
    if (life.mood < 30) return 'Morose';
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
            '• Jouer : coûte de l’énergie mais remonte l’humeur ; secouer le '
            'téléphone déclenche aussi une partie.\n'
            '• Dormir : récupère de l’énergie tant que Biti dort.\n'
            '• Paramètres : **palette** pour les deux couleurs du sprite Biti sur la '
            'grille, nom de Biti, et cette aide. L’ambiance de l’écran utilise la '
            'combinaison 1.\n\n'
            'Les vibrations rythment comme un pouls : plus l’énergie est basse, '
            'plus le rythme ralentit.\n\n'
            'Sur le **terrain** : pince avec deux doigts pour zoomer (jusqu’à ×4), '
            'glisse pour te déplacer quand tu es zoomé.\n\n'
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
    if (!_petMode || _lifecycle == null) return;
    final BitiProfile? sel = _selected;
    if (sel == null) return;
    final BitiThemePair chrome = _uiPair();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: chrome.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => _BitiSettingsSheet(
        profile: sel,
        lifecycle: _lifecycle!,
        onSpriteColorsSelected: (int a, int b) {
          final BitiProfile? cur = _selected;
          if (cur == null) return;
          final BitiProfile u = cur.copyWith(
            customColorA: a,
            customColorB: b,
            themePresetIndex: 0,
          );
          unawaited(() async {
            await BitiStorage.upsertProfile(u);
            if (!mounted) return;
            final BitiCollection c = await BitiStorage.loadCollection();
            if (mounted) setState(() => _collection = c);
          }());
        },
        onShowHelp: () {
          Navigator.pop(ctx);
          _showHelp(context);
        },
        onNameSaved: _schedulePersist,
        onOpenTransfer: () {
          Navigator.pop(ctx);
          _showBitiTransferSheet(context);
        },
      ),
    );
  }

  Future<void> _showBitiTransferSheet(BuildContext navigatorContext) async {
    if (_petMode && _lifecycle != null && _selected != null) {
      await BitiStorage.saveLifecycleIntoProfile(_lifecycle!, _selected!);
      if (!mounted) return;
      final BitiCollection synced = await BitiStorage.loadCollection();
      if (!mounted) return;
      setState(() => _collection = synced);
    }
    final BitiThemePair chrome = _uiPair();
    await showModalBottomSheet<void>(
      context: navigatorContext,
      isScrollControlled: true,
      backgroundColor: chrome.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext sheetCtx) {
        final double maxSheetHeight = MediaQuery.sizeOf(sheetCtx).height * 0.8;
        return BlocProvider<BitiTransferBloc>(
          create: (_) => BitiTransferBloc(),
          child: BlocListener<BitiTransferBloc, BitiTransferBlocState>(
            listenWhen:
                (BitiTransferBlocState prev, BitiTransferBlocState cur) =>
                    cur.phase == BitiTransferPhase.success &&
                    prev.phase != BitiTransferPhase.success,
            listener: (BuildContext ctx, BitiTransferBlocState state) async {
              if (!mounted) return;
              Navigator.of(ctx).pop();
              final bool sender =
                  state.transferRole == BitiTransferUserRole.send;
              if (sender) {
                if (!mounted) return;
                final BitiCollection c = await BitiStorage.loadCollection();
                if (!mounted) return;
                Navigator.of(navigatorContext).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => HomeScreen(initialCollection: c),
                  ),
                );
                return;
              }
              final BitiCollection c = await BitiStorage.loadCollection();
              if (!mounted || c.isEmpty) return;
              if (!_petMode) {
                Navigator.of(navigatorContext).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => HomeScreen(initialCollection: c),
                  ),
                );
                return;
              }
              setState(() {
                _collection = c;
                final BitiProfile? s = c.selected;
                if (s != null) {
                  _lifecycle!.applyFromProfile(s);
                  _reanchorCreatureForGrowth();
                }
                _syncGrid();
              });
              final BitiProfile? s = _collection.selected;
              if (s != null && _lifecycle != null) {
                unawaited(BitiStorage.saveLifecycleIntoProfile(_lifecycle!, s));
              }
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 22,
                    right: 22,
                    top: 14,
                    bottom: MediaQuery.viewPaddingOf(sheetCtx).bottom + 18,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
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
                          'Transférer Biti',
                          style: Theme.of(sheetCtx).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.94),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bluetooth : un téléphone choisit Accueillir (recevoir), '
                          'l’autre Envoyer (transférer son Biti). Active le Bluetooth sur les deux.',
                          style: Theme.of(sheetCtx).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70, height: 1.35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'L’envoi inclut le profil (dont la teinte du personnage sur '
                          'la grille définie dans Paramètres).',
                          style: Theme.of(sheetCtx).textTheme.bodySmall
                              ?.copyWith(color: Colors.white54, height: 1.35),
                        ),
                        const SizedBox(height: 18),
                        BitiTransferActions(
                          currentProfile: _profileForTransfer(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

/// Barre d’actions carrées (Jouer, Dormir, Échange, Paramètres).
class _BitiActionBar extends StatelessWidget {
  const _BitiActionBar({
    required this.buttonSide,
    required this.panelColor,
    required this.foreground,
    required this.onPlay,
    required this.onSleep,
    required this.onTransfer,
    required this.onSettings,
    required this.sleeping,
  });

  final double buttonSide;
  final Color panelColor;
  final Color foreground;
  final VoidCallback onPlay;
  final VoidCallback onSleep;
  final VoidCallback onTransfer;
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
          icon: Icons.phonelink_ring_rounded,
          semanticLabel: 'Échanger avec un autre téléphone',
          onTap: onTransfer,
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

/// Palette étendue pour la teinte du sprite (HSV + gris + accents).
List<Color> _spriteTintPalette() {
  final Set<int> seen = <int>{};
  final List<Color> out = <Color>[];
  void add(Color c) {
    final int k = c.toARGB32();
    if (seen.add(k)) {
      out.add(c);
    }
  }

  for (int i = 0; i <= 24; i++) {
    add(Color.lerp(const Color(0xFF121212), const Color(0xFFF8F8F8), i / 24)!);
  }
  for (double h = 0; h < 360; h += 15) {
    for (final double s in <double>[0.32, 0.52, 0.72, 0.9, 1.0]) {
      for (final double v in <double>[0.42, 0.6, 0.78, 0.92, 1.0]) {
        add(HSVColor.fromAHSV(1.0, h, s, v).toColor());
      }
    }
  }
  const List<Color> accents = <Color>[
    Color(0xFF5F27CD),
    Color(0xFFE17055),
    Color(0xFF00B894),
    Color(0xFFFDCB6E),
    Color(0xFF0984E3),
    Color(0xFFD63031),
    Color(0xFF6C5CE7),
    Color(0xFFFD79A8),
    Color(0xFF00CEC9),
    Color(0xFFE84393),
    Color(0xFF8E44AD),
    Color(0xFFF39C12),
    Color(0xFF1ABC9C),
    Color(0xFF34495E),
    Color(0xFF00B4D8),
    Color(0xFFFF6B6B),
    Color(0xFF2ECC71),
  ];
  for (final Color c in accents) {
    add(c);
  }
  return out;
}

class _BitiSettingsSheet extends StatefulWidget {
  const _BitiSettingsSheet({
    required this.profile,
    required this.lifecycle,
    required this.onSpriteColorsSelected,
    required this.onShowHelp,
    required this.onNameSaved,
    required this.onOpenTransfer,
  });

  final BitiProfile profile;
  final LifecycleService lifecycle;
  final void Function(int a, int b) onSpriteColorsSelected;
  final VoidCallback onShowHelp;
  final VoidCallback onNameSaved;
  final VoidCallback onOpenTransfer;

  @override
  State<_BitiSettingsSheet> createState() => _BitiSettingsSheetState();
}

class _BitiSettingsSheetState extends State<_BitiSettingsSheet> {
  late TextEditingController _nameCtrl;
  late int _colorA;
  late int _colorB;

  @override
  void initState() {
    super.initState();
    final BitiThemePair pair = BitiThemePair.pairFor(widget.profile);
    _colorA = pair.a.toARGB32();
    _colorB = pair.b.toARGB32();
    _nameCtrl = TextEditingController(text: widget.lifecycle.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<int?> _openTintColorPicker(
    BuildContext context, {
    required int currentArgb,
    required String title,
  }) {
    final List<Color> palette = _spriteTintPalette();
    return showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            height: 420,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                childAspectRatio: 1,
              ),
              itemCount: palette.length,
              itemBuilder: (BuildContext _, int i) {
                final Color c = palette[i];
                final bool sel = c.toARGB32() == currentArgb;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(ctx, c.toARGB32()),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.white24,
                          width: sel ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickColor(BuildContext context, {required bool forA}) async {
    final int? picked = await _openTintColorPicker(
      context,
      currentArgb: forA ? _colorA : _colorB,
      title: forA ? 'Couleur claire (A)' : 'Couleur foncée (B)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (forA) {
        _colorA = picked;
      } else {
        _colorB = picked;
      }
    });
    widget.onSpriteColorsSelected(_colorA, _colorB);
  }

  void _resetSpriteColorsToDefault() {
    final BitiThemePair d = BitiThemePair.presets[0];
    setState(() {
      _colorA = d.a.toARGB32();
      _colorB = d.b.toARGB32();
    });
    widget.onSpriteColorsSelected(_colorA, _colorB);
  }

  @override
  Widget build(BuildContext context) {
    final Color sheetFg = Colors.white.withValues(alpha: 0.94);
    const Color sheetMuted = Colors.white70;

    final double maxSheetHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: SafeArea(
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phonelink_ring, color: sheetMuted),
                  title: Text(
                    'Transférer vers un autre téléphone',
                    style: TextStyle(color: sheetFg),
                  ),
                  subtitle: Text(
                    'Bluetooth',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: sheetMuted),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: sheetMuted),
                  onTap: widget.onOpenTransfer,
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
                  'Couleurs du sprite (grille)',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: sheetFg),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisis deux teintes (A = clair, B = foncé) dans la palette : elles '
                  'définissent le dégradé du Biti sur le terrain uniquement. '
                  'Enregistrées sur ce profil et envoyées par Bluetooth.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: sheetMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                    gradient: LinearGradient(
                      colors: <Color>[Color(_colorA), Color(_colorB)],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickColor(context, forA: true),
                        icon: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(_colorA),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38),
                          ),
                        ),
                        label: const Text('Couleur A'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickColor(context, forA: false),
                        icon: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(_colorB),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38),
                          ),
                        ),
                        label: const Text('Couleur B'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _resetSpriteColorsToDefault,
                  child: const Text('Réinitialiser (combinaison 1)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
