import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/biti_profile.dart';
import '../models/creature.dart';
import '../models/creature_growth.dart';

String _resolveBitiName(BitiProfile? restored) {
  if (restored == null) return BitiProfile.defaultName;
  final String n = restored.name.trim();
  return n.isEmpty ? BitiProfile.defaultName : n;
}

/// Gestion faim / énergie / humeur et dérivation de l’humeur affichée.
class LifecycleService extends ChangeNotifier {
  LifecycleService({
    this.tickInterval = const Duration(seconds: 2),
    this.criticalStreakDuration = const Duration(hours: 2),
    this.criticalGaugeThreshold = 20,
    BitiProfile? restored,
  }) : hunger = (restored?.hunger ?? 75).clamp(0, 100),
       energy = (restored?.energy ?? 80).clamp(0, 100),
       mood = (restored?.mood ?? 72).clamp(0, 100),
       xp = (restored?.xp ?? 0).clamp(0, 1 << 30),
       name = _resolveBitiName(restored),
       sleeping = restored?.sleeping ?? false,
       _dead = restored?.isDead ?? false {
    if (!_dead) {
      _tick = Timer.periodic(tickInterval, (_) => _onTick());
    }
  }

  bool _xpGrantsStarted = false;

  /// À appeler une fois que les écouteurs sont branchés (ex. depuis [HomeScreen]).
  void startXpGrants() {
    if (_xpGrantsStarted || _dead) return;
    _xpGrantsStarted = true;
    _xpTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dead) return;
      xp += CreatureGrowth.xpPerSecondWhenAlive;
      notifyListeners();
    });
  }

  final Duration tickInterval;

  /// Si faim, énergie ou humeur reste **strictement** sous ce seuil sans interruption
  /// pendant [criticalStreakDuration], Biti meurt (définitif pour cette session).
  final int criticalGaugeThreshold;

  /// Durée continue « en danger » avant la mort.
  final Duration criticalStreakDuration;

  int hunger;
  int energy;
  int mood;

  /// Nom de Biti (persisté).
  String name;

  /// XP cumulée (croissance : [CreatureGrowth.xpLevelStarts]).
  int xp;

  bool sleeping = false;
  DateTime? _excitedUntil;

  Timer? _tick;
  Timer? _xpTick;

  bool _dead;
  DateTime? _criticalSince;

  bool get isDead => _dead;

  /// Niveau de taille 1–6 dérivé de l’XP.
  int get growthLevel => CreatureGrowth.levelFromXp(xp);

  CreatureMood get derivedMood {
    if (_dead) return CreatureMood.idle;
    final DateTime now = DateTime.now();
    if (_excitedUntil != null && now.isBefore(_excitedUntil!)) {
      return CreatureMood.excited;
    }
    if (sleeping) return CreatureMood.sleeping;
    if (hunger < 28) return CreatureMood.hungry;
    if (mood > 78 && hunger > 42) return CreatureMood.happy;
    return CreatureMood.idle;
  }

  void _checkCriticalStreakAfterUpdate() {
    if (_dead) return;

    final bool critical =
        hunger < criticalGaugeThreshold ||
        energy < criticalGaugeThreshold ||
        mood < criticalGaugeThreshold;

    if (!critical) {
      _criticalSince = null;
      return;
    }

    _criticalSince ??= DateTime.now();
    if (DateTime.now().difference(_criticalSince!) >= criticalStreakDuration) {
      _dead = true;
      _criticalSince = null;
      _tick?.cancel();
      _tick = null;
      _xpTick?.cancel();
      _xpTick = null;
    }
  }

  void _onTick() {
    if (_dead) return;
    if (sleeping) {
      energy = min(100, energy + 2);
      hunger = max(0, hunger - 1);
      if (energy >= 96) {
        sleeping = false;
      }
    } else {
      hunger = max(0, hunger - 1);
      energy = max(0, energy - 1);
      mood = max(0, mood - 1);
    }
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Renommer Biti (persisté via l’écran).
  void setName(String newName) {
    if (_dead) return;
    final String n = newName.trim();
    if (n.isEmpty) return;
    name = n;
    notifyListeners();
  }

  /// Nourrir : remonte la faim et l’humeur légèrement.
  void feed() {
    if (_dead) return;
    hunger = min(100, hunger + 28);
    mood = min(100, mood + 6);
    xp += CreatureGrowth.xpPerFoodAction;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Récolte d’un point de nourriture sur la grille.
  void collectFoodMorsel() {
    if (_dead) return;
    hunger = min(100, hunger + 12);
    mood = min(100, mood + 3);
    xp += CreatureGrowth.xpPerFoodAction;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Nettoyage d’un excrément sur la grille (tap).
  void collectWasteCleanup() {
    if (_dead) return;
    xp += CreatureGrowth.xpPerWasteCleanup;
    notifyListeners();
  }

  /// Jouer : coûte un peu d’énergie, remonte l’humeur, court état excité.
  void play() {
    if (_dead) return;
    energy = max(0, energy - 12);
    hunger = max(0, hunger - 4);
    mood = min(100, mood + 22);
    _excitedUntil = DateTime.now().add(const Duration(seconds: 3));
    sleeping = false;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Endormir / réveiller (toggle) pour récupérer de l’énergie.
  void sleep() {
    if (_dead) return;
    sleeping = !sleeping;
    if (sleeping) {
      _excitedUntil = null;
    }
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Instantané pour [BitiStorage].
  BitiProfile toProfile() {
    return BitiProfile(
      name: name,
      hunger: hunger,
      energy: energy,
      mood: mood,
      xp: xp,
      sleeping: sleeping,
      isDead: isDead,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _xpTick?.cancel();
    super.dispose();
  }
}
