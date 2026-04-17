import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

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
import '../services/sleep_rocking_service.dart';
import '../theme/biti_theme_pair.dart';
import '../widgets/biti_transfer_button.dart';
import '../widgets/pixel_grid.dart';
import '../widgets/stat_bar.dart';
import 'biti_level_up_screen.dart';
import 'first_biti_screen.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Mode avec Biti principal (false = écran « plus de Biti » après envoi).
  bool _petMode = false;

  LifecycleService? _lifecycle;
  HeartbeatVibrationService? _heartbeat;
  SensorService? _sensors;
  SleepRockingService? _sleepRock;

  /// Intensité du bercement (sommeil) pour la jauge dans la zone d’état.
  final ValueNotifier<double> _sleepRockEma = ValueNotifier<double>(0);

  /// Une entrée par profil : tous visibles sur le même plateau.
  final Map<String, Creature> _creaturesById = <String, Creature>{};
  late PixelGridModel _grid;

  /// Invalide le placement quand la taille du terrain ou la liste d’ids change.
  String? _boardLayoutSig;

  AnimationController? _frameAnim;

  /// Zoom / pan du terrain (réinitialisable pour centrer sur le Biti).
  TransformationController? _terrainViewController;

  /// Repère le carré logique du terrain (côté [side] pour le recentrage caméra).
  final GlobalKey _terrainSquareKey = GlobalKey();

  late BitiCollection _collection;

  Timer? _moveTimer;
  Timer? _foodTimer;
  Timer? _persistDebounce;

  static const int _maxFoodDots = 12;

  /// Durée **continue** où au moins une jauge reste sous le seuil critique → mort (pas de nouvelle partie dans l’app).
  static const Duration bitiDeathAfterCriticalLowStreak = Duration(hours: 2);

  /// Délai entre deux pas sur la grille : plus court quand l’énergie est élevée.
  static int _moveIntervalMsForEnergy(int energy) {
    const int maxMs = 1700;
    const int minMs = 210;
    final double e = energy.clamp(0, 100) / 100.0;
    return (maxMs - e * (maxMs - minMs)).round().clamp(minMs, maxMs);
  }

  bool _stoppedForDeath = false;

  /// Case nourriture visée (Biti sélectionné s’y rend puis mange).
  int? _foodTargetGx;
  int? _foodTargetGy;

  /// Pastille nourriture « en route » : reste foncée jusqu’à la collecte ou l’annulation.
  int? _pendingFoodDarkGx;
  int? _pendingFoodDarkGy;

  /// Feedback visuel court après un tap sur une case du terrain.
  int? _tapIndicatorGx;
  int? _tapIndicatorGy;
  Timer? _tapIndicatorTimer;

  /// Mode caresse : la zone d’état (libellé sous les jauges) devient tactile.
  bool _caressZoneActive = false;
  double _caressDistAccum = 0;
  DateTime? _lastCaressVibrateAt;

  int _lastGrowthLevel = 1;

  /// [BitiProfile.id] du Biti principal (prefs), pour le badge dans l’espace info.
  String? _mainBitiProfileId;

  /// Mode balade (icône arbre) : pas réels → jauges + déplacement au retour / régularisation.
  bool _walkModeActive = false;
  StreamSubscription<StepCount>? _walkPedometerSub;
  int? _walkAnchorSteps;
  int? _lastKnownStepCount;
  bool _appLifecycleObserverRegistered = false;
  final List<(int, int)> _walkTrailCells = <(int, int)>[];

  static const int _walkStreamSettleMinDelta = 20;
  static const int _walkStepsPerGridCell = 20;
  static const int _walkTrailMaxPoints = 720;

  /// Pas accumulés en attente d’une case complète (20 pas → 1 case).
  int _walkStepsTowardNextCell = 0;

  /// Premier relevé podomètre au début de la balade (compteur en direct).
  int? _walkSessionStartSteps;

  /// Pas réellement « liquidés » pendant la session balade (somme des deltas).
  int _walkSessionStepsTotal = 0;

  /// Après arrêt balade : message dans la zone d’état pendant 5 s.
  String? _postWalkStepsMessage;
  Timer? _postWalkStepsTimer;

  /// Après arrêt balade : efface le tracé jaune après 10 s.
  Timer? _walkTrailClearTimer;

  BitiProfile? get _selected => _collection.selected;

  bool get _selectedIsMainBiti =>
      _mainBitiProfileId != null &&
      _selected != null &&
      _selected!.id == _mainBitiProfileId;

  Future<void> _refreshMainBitiProfileId() async {
    final String? id = await BitiStorage.mainBitiProfileId();
    if (!mounted) return;
    setState(() => _mainBitiProfileId = id);
  }

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

  /// Niveau max des **autres** profils (terrain commun sans le Biti sélectionné).
  int _maxLevelAmongOtherProfiles(String selectedId) {
    int m = 1;
    for (final BitiProfile p in _collection.profiles) {
      if (p.id == selectedId) continue;
      m = max(m, CreatureGrowth.levelFromXp(p.xp));
    }
    return m;
  }

  void _openBitiLevelUpCelebration(int fromLevel, int toLevel) {
    final BitiProfile? s = _selected;
    final LifecycleService? life = _lifecycle;
    if (s == null || life == null || !mounted) return;

    final int maxOther = _maxLevelAmongOtherProfiles(s.id);
    final int maxBefore = max(maxOther, fromLevel);
    final int maxAfter = max(maxOther, toLevel);
    final int oldSide = CreatureGrowth.terrainSideForLevel(maxBefore);
    final int newSide = CreatureGrowth.terrainSideForLevel(maxAfter);
    final bool terrainGrew = newSide > oldSide;

    final int oldSpan = CreatureGrowth.gridSpanForLevel(fromLevel);
    final int newSpan = CreatureGrowth.gridSpanForLevel(toLevel);
    final bool spanChanged = newSpan != oldSpan;

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext ctx) => BitiLevelUpScreen(
          newLevel: toLevel,
          previousLevel: fromLevel,
          bitiName: life.name,
          themePair: BitiThemePair.pairFor(s),
          mood: life.derivedMood,
          frameIndex: _selectedCreature.frameIndex,
          terrainOldSide: oldSide,
          terrainNewSide: newSide,
          terrainGrew: terrainGrew,
          oldSpriteSpan: oldSpan,
          newSpriteSpan: newSpan,
          spriteSpanChanged: spanChanged,
        ),
      ),
    );
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
        isSelected: _collection.profiles.length > 1,
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

    _sleepRock = SleepRockingService(
      onGuideChanged: (_) {},
      onEnergyDelta: (int d) {
        if (!mounted || d <= 0) return;
        _lifecycle?.addSleepRockEnergy(d);
      },
      rockingEmaOut: _sleepRockEma,
    );

    _sensors = SensorService(
      onShake: _lifecycle!.play,
      onTilt: (double v) {
        if (!mounted || _lifecycle!.sleeping) return;
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

    if (!_lifecycle!.sleeping && !_lifecycle!.isDead) {
      _scheduleMoveTick();
    }

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
    unawaited(_refreshMainBitiProfileId());
    if (_lifecycle!.sleeping) {
      _sleepRock?.setSleeping(true);
    }
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleObserverRegistered = true;
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
    _stopWalkModeSync(settle: true);
    if (!mounted) return;
    final bool hadCaress = _caressZoneActive;
    setState(() {
      _caressZoneActive = false;
      _foodTargetGx = null;
      _foodTargetGy = null;
      _pendingFoodDarkGx = null;
      _pendingFoodDarkGy = null;
      _collection = c;
      _lifecycle!.applyFromProfile(next);
      _reanchorCreatureForGrowth();
    });
    if (hadCaress) _heartbeat?.resumeAfterCaress();
    unawaited(_refreshMainBitiProfileId());
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
      _stopWalkModeSync(settle: true);
      if (!mounted) return;
      final bool hadCaress = _caressZoneActive;
      setState(() {
        _caressZoneActive = false;
        _foodTargetGx = null;
        _foodTargetGy = null;
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
        _collection = c;
        _lifecycle!.applyFromProfile(c.selected!);
        _reanchorCreatureForGrowth();
      });
      if (hadCaress) _heartbeat?.resumeAfterCaress();
      unawaited(_refreshMainBitiProfileId());
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
    if (_lifecycle!.sleeping || _lifecycle!.isDead) {
      _stopWalkModeSync(settle: !_lifecycle!.isDead);
    }
    _sleepRock?.setSleeping(_lifecycle!.sleeping && !_lifecycle!.isDead);
    if (_lifecycle!.isDead && !_stoppedForDeath) {
      _stoppedForDeath = true;
      _moveTimer?.cancel();
      _moveTimer = null;
      _foodTimer?.cancel();
      _foodTimer = null;
      _frameAnim?.stop();
      _sensors?.dispose();
    } else if (!_lifecycle!.isDead) {
      if (_lifecycle!.sleeping) {
        _moveTimer?.cancel();
        _moveTimer = null;
      } else {
        _ensureMoveTimerRunning();
      }
    }
    setState(() {
      if (_lifecycle!.sleeping || _lifecycle!.isDead) {
        _caressZoneActive = false;
        _foodTargetGx = null;
        _foodTargetGy = null;
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
      }
      _syncGrid();
    });
    _schedulePersist();
  }

  void _scheduleMoveTick() {
    _moveTimer?.cancel();
    if (!_petMode || _lifecycle == null) return;
    final LifecycleService life = _lifecycle!;
    if (life.isDead || life.sleeping) return;
    final int ms = _moveIntervalMsForEnergy(life.energy);
    _moveTimer = Timer(Duration(milliseconds: ms), _onMoveTimerFired);
  }

  void _onMoveTimerFired() {
    if (!mounted || _lifecycle == null) return;
    final LifecycleService life = _lifecycle!;
    if (life.isDead || life.sleeping) return;
    setState(() {
      if (!_walkModeActive && !_caressZoneActive) {
        if (_foodTargetGx != null && _foodTargetGy != null) {
          _stepTowardFoodTarget();
        } else {
          _randomStep();
        }
      }
      _eatFoodUnderSelectedCreature();
      _syncGrid();
    });
    _scheduleMoveTick();
  }

  void _ensureMoveTimerRunning() {
    if (!_petMode || _lifecycle == null) return;
    final LifecycleService life = _lifecycle!;
    if (life.isDead || life.sleeping) return;
    if (_moveTimer != null && _moveTimer!.isActive) return;
    _scheduleMoveTick();
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

    final int prevTracked = _lastGrowthLevel;
    final int nowLevel = life.growthLevel;
    if (nowLevel > prevTracked) {
      HapticFeedback.mediumImpact();
      final int fromLvl = prevTracked;
      final int toLvl = nowLevel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lifecycle == null || _selected == null) return;
        if (_lifecycle!.growthLevel < toLvl) return;
        _openBitiLevelUpCelebration(fromLvl, toLvl);
      });
    }
    _lastGrowthLevel = nowLevel;

    final List<String> stampIds = <String>[
      for (final String id in sortedIds)
        if (id != sel.id) id,
      sel.id,
    ];

    final List<({int x, int y, List<List<Color>> frame, BitiThemePair theme})>
    stamps =
        <({int x, int y, List<List<Color>> frame, BitiThemePair theme})>[];
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
      stamps.add((
        x: c.gridX,
        y: c.gridY,
        frame: frame,
        theme: BitiThemePair.pairFor(p),
      ));
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

  /// Coordonnées grille (cellule) couvertes par les pixels non transparents du sprite.
  List<(int, int)> _footprintCells(Creature c, SpriteFrame frame) {
    final List<(int, int)> out = <(int, int)>[];
    for (int fy = 0; fy < frame.length; fy++) {
      final List<Color> row = frame[fy];
      for (int fx = 0; fx < row.length; fx++) {
        if (row[fx].a == 0) continue;
        out.add((c.gridX + fx, c.gridY + fy));
      }
    }
    return out;
  }

  bool _spriteCoversCell(Creature c, SpriteFrame frame, int cellX, int cellY) {
    for (int fy = 0; fy < frame.length; fy++) {
      final List<Color> row = frame[fy];
      for (int fx = 0; fx < row.length; fx++) {
        if (row[fx].a == 0) continue;
        if (c.gridX + fx == cellX && c.gridY + fy == cellY) return true;
      }
    }
    return false;
  }

  /// Mange toute nourriture située sous l’empreinte du Biti sélectionné.
  void _eatFoodUnderSelectedCreature() {
    if (!_petMode || _lifecycle == null || _lifecycle!.isDead) return;
    final LifecycleService life = _lifecycle!;
    final Creature c = _selectedCreature;
    final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
      life.derivedMood,
      c.frameIndex,
      life.growthLevel,
    );
    final int? tx = _foodTargetGx;
    final int? ty = _foodTargetGy;
    bool ate = false;
    bool ateTargetFood = false;
    for (final (int gx, int gy) in _footprintCells(c, frame)) {
      if (_grid.cellAt(gx, gy).kind != CellKind.food) continue;
      final bool isWalkTarget =
          tx != null && ty != null && gx == tx && gy == ty;
      if (_grid.collectFoodAt(gx, gy)) {
        life.collectFoodMorsel();
        ate = true;
        if (isWalkTarget) ateTargetFood = true;
      }
    }
    if (ate) {
      HapticFeedback.mediumImpact();
      if (ateTargetFood) {
        _foodTargetGx = null;
        _foodTargetGy = null;
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
      }
    }
  }

  void _stepTowardFoodTarget() {
    final int? tx = _foodTargetGx;
    final int? ty = _foodTargetGy;
    if (tx == null || ty == null || _lifecycle == null) return;
    if (_grid.cellAt(tx, ty).kind != CellKind.food) {
      _foodTargetGx = null;
      _foodTargetGy = null;
      if (_pendingFoodDarkGx == tx && _pendingFoodDarkGy == ty) {
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
      }
      return;
    }
    final LifecycleService life = _lifecycle!;
    final Creature c = _selectedCreature;
    final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
      life.derivedMood,
      c.frameIndex,
      life.growthLevel,
    );
    if (_spriteCoversCell(c, frame, tx, ty)) {
      return;
    }
    final double scx = c.gridX + c.spriteWidth * 0.5;
    final double scy = c.gridY + c.spriteHeight * 0.5;
    final double fcx = tx + 0.5;
    final double fcy = ty + 0.5;
    if ((fcx - scx).abs() >= (fcy - scy).abs()) {
      c.gridX += fcx > scx ? 1 : -1;
    } else {
      c.gridY += fcy > scy ? 1 : -1;
    }
    c.clampToGrid(_grid.width, _grid.height);
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

  void _flashTapCellIndicator(int gx, int gy) {
    _tapIndicatorTimer?.cancel();
    setState(() {
      _tapIndicatorGx = gx;
      _tapIndicatorGy = gy;
    });
    _tapIndicatorTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _tapIndicatorGx = null;
        _tapIndicatorGy = null;
      });
    });
  }

  void _onCellTap(int gx, int gy) {
    if (!_petMode || _lifecycle == null || _lifecycle!.isDead) return;
    if (_grid.cellAt(gx, gy).kind != CellKind.food) {
      setState(() {
        _foodTargetGx = null;
        _foodTargetGy = null;
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
      });
      _flashTapCellIndicator(gx, gy);
      return;
    }
    _tapIndicatorTimer?.cancel();
    setState(() {
      _tapIndicatorGx = null;
      _tapIndicatorGy = null;
    });
    final LifecycleService life = _lifecycle!;
    final Creature c = _selectedCreature;
    final SpriteFrame frame = CreatureSpriteLibrary.currentFrame(
      life.derivedMood,
      c.frameIndex,
      life.growthLevel,
    );
    if (_spriteCoversCell(c, frame, gx, gy)) {
      if (_grid.collectFoodAt(gx, gy)) {
        life.collectFoodMorsel();
        HapticFeedback.mediumImpact();
      }
      setState(() {
        _foodTargetGx = null;
        _foodTargetGy = null;
        _pendingFoodDarkGx = null;
        _pendingFoodDarkGy = null;
        _syncGrid();
      });
      _schedulePersist();
      return;
    }
    setState(() {
      _foodTargetGx = gx;
      _foodTargetGy = gy;
      _pendingFoodDarkGx = gx;
      _pendingFoodDarkGy = gy;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_petMode || !_walkModeActive) return;
    if (state == AppLifecycleState.paused) {
      _flushWalkSteps(minDelta: 1);
    } else if (state == AppLifecycleState.resumed) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _flushWalkSteps(minDelta: 1);
      });
    }
  }

  void _stopWalkModeSync({required bool settle}) {
    if (!_walkModeActive) return;
    if (settle) {
      _flushWalkSteps(minDelta: 1);
    }
    final int sessionSteps = _walkSessionStepsTotal;
    _walkPedometerSub?.cancel();
    _walkPedometerSub = null;
    _walkModeActive = false;
    _walkAnchorSteps = null;
    _lastKnownStepCount = null;
    _walkSessionStartSteps = null;
    _walkStepsTowardNextCell = 0;
    _walkSessionStepsTotal = 0;
    if (settle) {
      _schedulePostWalkStepsMessage(sessionSteps);
      _walkTrailClearTimer?.cancel();
      _walkTrailClearTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _walkTrailCells.clear());
      });
    }
    _resetSystemUiOverlay();
  }

  void _resetSystemUiOverlay() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  void _flushWalkSteps({required int minDelta}) {
    if (!_walkModeActive || _lifecycle == null) return;
    if (_lifecycle!.isDead || _lifecycle!.sleeping) return;
    if (_caressZoneActive) return;
    if (_walkAnchorSteps == null || _lastKnownStepCount == null) return;
    final int delta = _lastKnownStepCount! - _walkAnchorSteps!;
    if (delta < minDelta) return;
    _walkSessionStepsTotal += delta;
    _walkAnchorSteps = _lastKnownStepCount;
    _lifecycle!.applyWalkSessionSteps(delta);
    _walkStepsTowardNextCell += delta;
    final int nCells = min(
      200,
      _walkStepsTowardNextCell ~/ _walkStepsPerGridCell,
    );
    _walkStepsTowardNextCell -= nCells * _walkStepsPerGridCell;
    if (!mounted) return;
    setState(() {
      _appendSimulatedWalkToTrail(nCells);
      _syncGrid();
    });
    _schedulePersist();
  }

  void _recordWalkTrailCenter(Creature c) {
    final int cx = c.gridX + c.spriteWidth ~/ 2;
    final int cy = c.gridY + c.spriteHeight ~/ 2;
    final (int, int) cell = (cx, cy);
    if (_walkTrailCells.isEmpty || _walkTrailCells.last != cell) {
      _walkTrailCells.add(cell);
      while (_walkTrailCells.length > _walkTrailMaxPoints) {
        _walkTrailCells.removeAt(0);
      }
    }
  }

  void _appendSimulatedWalkToTrail(int nCells) {
    if (nCells <= 0 || !_petMode) return;
    final Creature c = _selectedCreature;
    const List<List<int>> options = <List<int>>[
      <int>[-1, 0],
      <int>[1, 0],
      <int>[0, -1],
      <int>[0, 1],
    ];
    final Random r = Random();
    _recordWalkTrailCenter(c);
    for (int i = 0; i < nCells; i++) {
      final List<int> d = options[r.nextInt(options.length)];
      c.gridX += d[0];
      c.gridY += d[1];
      c.clampToGrid(_grid.width, _grid.height);
      _recordWalkTrailCenter(c);
    }
  }

  void _startWalkPedometer() {
    _walkPedometerSub?.cancel();
    _walkPedometerSub = Pedometer.stepCountStream.listen(
      (StepCount e) {
        if (!mounted || !_walkModeActive) return;
        _lastKnownStepCount = e.steps;
        if (_walkAnchorSteps == null) {
          _walkAnchorSteps = e.steps;
          _walkSessionStartSteps = e.steps;
          if (mounted) setState(() {});
          return;
        }
        if (!_caressZoneActive) {
          _flushWalkSteps(minDelta: _walkStreamSettleMinDelta);
        }
        if (mounted) setState(() {});
      },
      onError: (Object err) {
        if (!mounted) return;
        _stopWalkModeSync(settle: false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de lire les pas sur cet appareil.'),
          ),
        );
        setState(() {});
      },
    );
  }

  Future<void> _onWalkTreeTap() async {
    if (!_petMode || _lifecycle == null || !mounted) return;
    final LifecycleService life = _lifecycle!;
    if (life.isDead) return;
    if (life.sleeping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réveille Biti pour une balade.')),
      );
      return;
    }
    if (_walkModeActive) {
      _stopWalkModeSync(settle: true);
      setState(() {});
      return;
    }
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La balade avec pas réels est prévue sur téléphone (Android / iOS).',
          ),
        ),
      );
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final PermissionStatus st = await Permission.activityRecognition
          .request();
      if (!mounted) return;
      if (!st.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permission « Activité physique » nécessaire pour compter les pas.',
            ),
          ),
        );
        return;
      }
    }
    _walkTrailClearTimer?.cancel();
    setState(() {
      _walkTrailCells.clear();
      _walkModeActive = true;
      _walkAnchorSteps = null;
      _lastKnownStepCount = null;
      _walkSessionStartSteps = null;
      _walkStepsTowardNextCell = 0;
      _walkSessionStepsTotal = 0;
    });
    _startWalkPedometer();
  }

  void _schedulePostWalkStepsMessage(int totalSteps) {
    _postWalkStepsTimer?.cancel();
    final String msg;
    if (totalSteps <= 0) {
      msg = 'Balade terminée : aucun pas enregistré';
    } else if (totalSteps == 1) {
      msg = 'Balade terminée : 1 pas';
    } else {
      msg = 'Balade terminée : $totalSteps pas';
    }
    _postWalkStepsMessage = msg;
    if (mounted) setState(() {});
    _postWalkStepsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _postWalkStepsMessage = null);
    });
  }

  @override
  void dispose() {
    _postWalkStepsTimer?.cancel();
    _walkTrailClearTimer?.cancel();
    _resetSystemUiOverlay();
    _walkPedometerSub?.cancel();
    if (_appLifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _sleepRock?.dispose();
    _sleepRock = null;
    _sleepRockEma.dispose();
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
    _tapIndicatorTimer?.cancel();
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

  void _onCenterTerrainFromPanel() {
    if (!_petMode || _lifecycle == null) return;
    final BuildContext? ctx = _terrainSquareKey.currentContext;
    if (ctx == null) return;
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final double side = ro.size.width;
    _centerTerrainCameraOnSelectedBiti(side);
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
          top: false,
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
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const FirstBitiScreen(),
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
          top: false,
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

    /// Boutons réduire / centrer dans l’encadré infos (nettement plus petits que la barre du bas).
    final double infoActionTile = (_actionButtonSide(context) * 0.36).clamp(
      22.0,
      30.0,
    );
    final bool caressReady =
        _caressZoneActive && !life.sleeping && !life.isDead;
    final bool walkStatusHighlight =
        _walkModeActive && !life.sleeping && !life.isDead;
    final Color statusZoneFill = caressReady
        ? Color.lerp(uiPair.mix(0.16), uiPair.barAccent, 0.38) ??
              uiPair.mix(0.16)
        : walkStatusHighlight
        ? Color.lerp(uiPair.mix(0.16), uiPair.barAccent, 0.24) ??
              uiPair.mix(0.16)
        : uiPair.mix(0.16);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      color: uiPair.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 0, 7, 8),
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
                                                key: _terrainSquareKey,
                                                width: side,
                                                height: side,
                                                child: InteractiveViewer(
                                                  transformationController: tc,
                                                  minScale: 0.5,
                                                  maxScale: 5.0,
                                                  boundaryMargin:
                                                      EdgeInsets.only(
                                                        left: side * 0.15,
                                                        right: side * 0.15,
                                                        top: side * 0.08,
                                                        bottom: side * 0.01,
                                                      ),
                                                  child: FittedBox(
                                                    fit: BoxFit.fitHeight,

                                                    child: Container(
                                                      //    color: Colors.red,
                                                      width: side,
                                                      height: side,
                                                      child: PixelGrid(
                                                        model: _grid,
                                                        theme: uiPair,
                                                        boardBitis:
                                                            _boardBitisForPixelGrid(),
                                                        nameLabelColor: fgMuted,
                                                        onCellTap: _onCellTap,
                                                        tapIndicatorGx:
                                                            _tapIndicatorGx,
                                                        tapIndicatorGy:
                                                            _tapIndicatorGy,
                                                        pendingFoodDarkGx:
                                                            _pendingFoodDarkGx,
                                                        pendingFoodDarkGy:
                                                            _pendingFoodDarkGy,
                                                        walkTrailCellCenters:
                                                            List<
                                                              (int, int)
                                                            >.from(
                                                              _walkTrailCells,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
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
                                    padding: EdgeInsets.only(
                                      right: _collection.profiles.length > 1
                                          ? 40
                                          : 0,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        if (_selectedIsMainBiti &&
                                            _collection.profiles.length > 1)
                                          ...<Widget>[
                                            Icon(
                                              Icons.home_rounded,
                                              size: 22,
                                              color: fg.withValues(alpha: 0.92),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                        Expanded(
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
                                        const SizedBox(width: 8),
                                        _SquareAction(
                                          size: infoActionTile,
                                          panelColor: panel,
                                          foreground: fg,
                                          icon:
                                              Icons.center_focus_strong_rounded,
                                          semanticLabel: 'Centrer sur Biti',
                                          onTap: _onCenterTerrainFromPanel,
                                        ),
                                      ],
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
                                          fill:
                                              displayGrowthLevel >=
                                                  CreatureGrowth.maxGrowthLevel
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
                                      color: statusZoneFill,
                                      borderRadius: BorderRadius.circular(10),
                                      border: caressReady
                                          ? Border.all(
                                              color: uiPair.barAccent
                                                  .withValues(alpha: 0.65),
                                              width: 1.8,
                                            )
                                          : walkStatusHighlight
                                          ? Border.all(
                                              color: uiPair.barAccent
                                                  .withValues(alpha: 0.45),
                                              width: 1.4,
                                            )
                                          : null,
                                    ),
                                    child: caressReady
                                        ? GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onPanStart: _onCaressPanStart,
                                            onPanUpdate: _onCaressPanUpdate,
                                            onPanEnd: _onCaressPanEnd,
                                            onPanCancel: _onCaressPanCancel,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                    horizontal: 12,
                                                  ),
                                              child: Text(
                                                _statusZoneLine(
                                                  mood,
                                                ).toUpperCase(),
                                                textAlign: TextAlign.center,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      color: fg,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      letterSpacing: 0.5,
                                                    ),
                                              ),
                                            ),
                                          )
                                        : life.sleeping
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 12,
                                            ),
                                            child:
                                                ValueListenableBuilder<double>(
                                                  valueListenable:
                                                      _sleepRockEma,
                                                  builder:
                                                      (
                                                        BuildContext context,
                                                        double ema,
                                                        _,
                                                      ) {
                                                        return _SleepRockGauge(
                                                          ema: ema,
                                                          pair: uiPair,
                                                          fg: fg,
                                                          fgMuted: fgMuted,
                                                        );
                                                      },
                                                ),
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 12,
                                            ),
                                            child: Text(
                                              _statusZoneLine(
                                                mood,
                                              ).toUpperCase(),
                                              textAlign: TextAlign.center,
                                              maxLines: 3,
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
                            if (_collection.profiles.length > 1)
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
                        walkModeActive: _walkModeActive,
                        walkTreePanelColor: _walkModeActive
                            ? Color.lerp(
                                    panel,
                                    uiPair.barAccent.withValues(alpha: 0.42),
                                    0.52,
                                  ) ??
                                  panel
                            : panel,
                        onWalk: () => unawaited(_onWalkTreeTap()),
                        onSleep: life.sleep,
                        onSettings: () => _showSettings(context),
                        sleeping: life.sleeping,
                        caressActive: _caressZoneActive,
                        caressUsable: !life.isDead && !life.sleeping,
                        caressPanelColor: _caressZoneActive
                            ? Color.lerp(
                                    panel,
                                    uiPair.barAccent.withValues(alpha: 0.38),
                                    0.55,
                                  ) ??
                                  panel
                            : panel,
                        onCaress: life.isDead
                            ? null
                            : () {
                                if (life.sleeping) return;
                                final bool next = !_caressZoneActive;
                                setState(() {
                                  _caressZoneActive = next;
                                });
                                if (next) {
                                  _heartbeat?.pauseForCaress();
                                } else {
                                  _heartbeat?.resumeAfterCaress();
                                  if (_walkModeActive) {
                                    _flushWalkSteps(minDelta: 1);
                                  }
                                }
                              },
                        caressTooltip: life.isDead
                            ? null
                            : life.sleeping
                            ? 'Réveille Biti pour utiliser la caresse'
                            : _caressZoneActive
                            ? 'Glisse sur la zone d’état sous les jauges'
                            : 'Caresser : active le mode puis glisse sur la zone d’état',
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
    return raw.clamp(48, 72);
  }

  void _onCaressPanStart(DragStartDetails details) {
    _caressDistAccum = 0;
    if (_caressZoneActive) {
      HapticFeedback.lightImpact();
    }
  }

  void _onCaressPanUpdate(DragUpdateDetails details) {
    if (!_caressZoneActive || _lifecycle == null) return;
    if (_lifecycle!.isDead || _lifecycle!.sleeping) return;
    _caressDistAccum += details.delta.distance;
    const double segment = 14;
    while (_caressDistAccum >= segment) {
      _caressDistAccum -= segment;
      final DateTime now = DateTime.now();
      if (_lastCaressVibrateAt == null ||
          now.difference(_lastCaressVibrateAt!) >=
              const Duration(milliseconds: 85)) {
        _lastCaressVibrateAt = now;
        HapticFeedback.selectionClick();
      }
      _lifecycle!.registerCaressStroke();
    }
  }

  void _onCaressPanEnd(DragEndDetails details) {
    _caressDistAccum = 0;
  }

  void _onCaressPanCancel() {
    _caressDistAccum = 0;
  }

  /// Texte principal de la zone d’état (balade, résumé pas, ou libellé habituel).
  String _statusZoneLine(CreatureMood mood) {
    if (_postWalkStepsMessage != null) {
      return _postWalkStepsMessage!;
    }
    if (_walkModeActive && !_lifecycle!.isDead && !_lifecycle!.sleeping) {
      if (_walkSessionStartSteps != null && _lastKnownStepCount != null) {
        final int n = max(0, _lastKnownStepCount! - _walkSessionStartSteps!);
        return 'Balade · $n pas';
      }
      return 'Balade · démarrage…';
    }
    return _bitiStatusLabel(mood);
  }

  /// Libellé d’état (faim, sommeil, fatigue, humeur…) pour l’encadré sous le terrain.
  String _bitiStatusLabel(CreatureMood mood) {
    final LifecycleService life = _lifecycle!;
    if (life.sleeping) {
      return 'Sommeil';
    }
    if (_caressZoneActive && !life.isDead) {
      return 'Caressez';
    }
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
            'Biti évolue avec le temps : la **faim** baisse toutes les quelques '
            'secondes ; l’**énergie** et l’**humeur** baissent beaucoup plus '
            'lentement (environ **12 h** pour parcourir toute la jauge sans les '
            'recharger).\n\n'
            '• Jouer : coûte de l’énergie mais remonte l’humeur ; secouer le '
            'téléphone déclenche aussi une partie.\n'
            '• Dormir : berce doucement le téléphone de gauche à droite (gyroscope) : '
            'l’énergie remonte jusqu’à +2 par seconde si le rythme est bon ; sous les '
            'jauges, une jauge indique trop lent à gauche, trop rapide à droite, et la '
            'zone centrale verte est la bonne cadence.\n'
            '• Caresse : touche l’icône main dans la barre du bas pour activer le mode, '
            'puis glisse le doigt sur la zone d’état (sous les jauges) : le téléphone '
            'vibre et l’humeur remonte peu à peu.\n'
            '• Paramètres : cette aide et le transfert Bluetooth.\n\n'
            'Les vibrations rythment comme un pouls : plus l’énergie est basse, '
            'plus le rythme ralentit.\n\n'
            'Sur le **terrain** : pince avec deux doigts pour zoomer (jusqu’à ×4), '
            'glisse pour te déplacer quand tu es zoomé.\n\n'
            'Les points verts sont de la nourriture : appuie dessus pour la '
            'récolter (ça remonte un peu la faim et donne +${CreatureGrowth.xpPerFoodAction} XP).\n\n'
            'La **taille** de Biti suit **${CreatureGrowth.maxGrowthLevel} niveaux** '
            'selon l’XP : +${CreatureGrowth.xpPerSecondWhenAlive} XP par seconde tant '
            'qu’il est vivant. Paliers (XP cumulée) : par ex. niveau 2 à '
            '${CreatureGrowth.xpLevelStarts[1]} XP, niveau 6 à '
            '${CreatureGrowth.xpLevelStarts[5]} XP, niveau ${CreatureGrowth.maxGrowthLevel} '
            'à partir de ${CreatureGrowth.xpLevelStarts[CreatureGrowth.maxGrowthLevel - 1]} '
            'XP (sprite et terrain au maximum). La jauge verte = progression vers le '
            'prochain niveau.\n\n'
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
    final BitiThemePair chrome = _uiPair();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: chrome.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => _BitiSettingsSheet(
        onShowHelp: () {
          Navigator.pop(ctx);
          _showHelp(context);
        },
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
              unawaited(_refreshMainBitiProfileId());
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
                          'L’envoi inclut le profil (stats et apparence enregistrées).',
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

/// Barre d’actions carrées (Balade, Dormir, Caresse, Paramètres).
class _BitiActionBar extends StatelessWidget {
  const _BitiActionBar({
    required this.buttonSide,
    required this.panelColor,
    required this.foreground,
    required this.walkModeActive,
    required this.walkTreePanelColor,
    required this.onWalk,
    required this.onSleep,
    required this.onSettings,
    required this.sleeping,
    required this.caressActive,
    required this.caressUsable,
    required this.caressPanelColor,
    this.onCaress,
    this.caressTooltip,
  });

  final double buttonSide;
  final Color panelColor;
  final Color foreground;
  final bool walkModeActive;
  final Color walkTreePanelColor;
  final VoidCallback onWalk;
  final VoidCallback onSleep;
  final VoidCallback onSettings;
  final bool sleeping;
  final bool caressActive;
  final bool caressUsable;
  final Color caressPanelColor;
  final VoidCallback? onCaress;
  final String? caressTooltip;

  @override
  Widget build(BuildContext context) {
    const double gap = 8.0;
    final Color caressFg = caressUsable
        ? foreground
        : foreground.withValues(alpha: 0.35);
    final Color sleepPanel = sleeping
        ? Color.lerp(panelColor, const Color(0xFF1A1D24), 0.58) ?? panelColor
        : panelColor;
    final Color sleepFg = sleeping
        ? foreground.withValues(alpha: 0.38)
        : foreground;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _SquareAction(
          size: buttonSide,
          panelColor: walkTreePanelColor,
          foreground: foreground,
          icon: Icons.park_rounded,
          semanticLabel: walkModeActive ? 'Balade (active)' : 'Balade',
          tooltip: walkModeActive
              ? 'Appuie pour terminer la balade et appliquer les derniers pas'
              : 'Mode balade : le compteur de pas s’affiche sous les jauges ; humeur et déplacement suivent tes pas',
          onTap: onWalk,
        ),
        const SizedBox(width: gap),
        _SquareAction(
          size: buttonSide,
          panelColor: sleepPanel,
          foreground: sleepFg,
          icon: Icons.bedtime_rounded,
          semanticLabel: sleeping ? 'Réveiller' : 'Dormir',
          tooltip: sleeping
              ? 'Nuit : appuie pour réveiller Biti'
              : 'Appuie pour passer la nuit (sommeil)',
          onTap: onSleep,
        ),
        const SizedBox(width: gap),
        _SquareAction(
          size: buttonSide,
          panelColor: caressPanelColor,
          foreground: caressFg,
          icon: Icons.front_hand_rounded,
          semanticLabel: caressActive ? 'Caresse (actif)' : 'Caresse',
          tooltip: caressTooltip,
          enabled: onCaress != null && caressUsable,
          onTap: caressUsable ? onCaress : null,
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
    this.onTap,
    this.tooltip,
    this.enabled = true,
  });

  final double size;
  final Color panelColor;
  final Color foreground;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final double iconSize = (size * 0.48).clamp(22.0, 32.0);
    final bool tappable = enabled && onTap != null;
    Widget child = Semantics(
      button: true,
      enabled: tappable,
      label: semanticLabel,
      child: Material(
        color: panelColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tappable ? onTap : null,
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
    final String? tip = tooltip;
    if (tip != null && tip.isNotEmpty) {
      child = Tooltip(message: tip, child: child);
    }
    return child;
  }
}

/// Jauge bercement (sommeil) : gauche trop lent, droite trop rapide, bandeau central = bon rythme.
class _SleepRockGauge extends StatelessWidget {
  const _SleepRockGauge({
    required this.ema,
    required this.pair,
    required this.fg,
    required this.fgMuted,
  });

  final double ema;
  final BitiThemePair pair;
  final Color fg;
  final Color fgMuted;

  @override
  Widget build(BuildContext context) {
    const double emaMax = SleepRockingService.rockEmaDisplayMax;
    const double loFrac = SleepRockingService.rockGoodEmaLo / emaMax;
    const double hiFrac = SleepRockingService.rockGoodEmaHi / emaMax;
    final double markerFrac = (ema / emaMax).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Trop lent',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Trop rapide',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            const double h = 10;
            final double bandLeft = loFrac * w;
            final double bandW = (hiFrac - loFrac) * w;
            final double mx = (markerFrac * w).clamp(6.0, w - 6.0);

            return SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(h * 0.5),
                      color: pair.mix(0.14),
                    ),
                    child: SizedBox(width: w, height: h),
                  ),
                  Positioned(
                    left: bandLeft,
                    width: bandW,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(h * 0.5),
                        color: pair.barAccent.withValues(alpha: 0.48),
                      ),
                      child: const SizedBox(height: h),
                    ),
                  ),
                  Positioned(
                    left: mx - 5,
                    top: -3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fg,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const SizedBox(width: 10, height: 16),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Berce gauche ↔ droite : vise la zone verte',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: fgMuted, height: 1.3),
        ),
      ],
    );
  }
}

class _BitiSettingsSheet extends StatelessWidget {
  const _BitiSettingsSheet({
    required this.onShowHelp,
    required this.onOpenTransfer,
  });

  final VoidCallback onShowHelp;
  final VoidCallback onOpenTransfer;

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
                  onTap: onShowHelp,
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
                  onTap: onOpenTransfer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
