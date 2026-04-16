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
  }) : _ticksPerEnergyMoodPoint = max(
         1,
         _energyMoodFullDrainDuration.inMilliseconds ~/
             (max(1, tickInterval.inMilliseconds) * 100),
       ),
       hunger = (restored?.hunger ?? 75).clamp(0, 100),
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

  /// Temps réel pour perdre **100** points d’énergie ou d’humeur (hors sommeil), au rythme des ticks.
  static const Duration _energyMoodFullDrainDuration = Duration(hours: 12);

  /// Un pas d’énergie + humeur tous les [_ticksPerEnergyMoodPoint] ticks (faim inchangée).
  final int _ticksPerEnergyMoodPoint;

  int _energyMoodDecayCounter = 0;

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

  /// Throttle des caresses (zone d’état) pour l’humeur.
  DateTime? _lastCaressMoodAt;

  static const Duration _caressMoodMinGap = Duration(milliseconds: 550);

  bool get isDead => _dead;

  /// Niveau de taille dérivé de l’XP (voir [CreatureGrowth.maxGrowthLevel]).
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
      hunger = max(0, hunger - 1);
      // L’énergie en sommeil vient du berçage (gyroscope), pas du tick périodique.
    } else {
      hunger = max(0, hunger - 1);
      _energyMoodDecayCounter++;
      if (_energyMoodDecayCounter >= _ticksPerEnergyMoodPoint) {
        _energyMoodDecayCounter = 0;
        energy = max(0, energy - 1);
        mood = max(0, mood - 1);
      }
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

  /// Nourrir : remonte la faim et l’humeur un peu.
  void feed() {
    if (_dead) return;
    hunger = min(100, hunger + 28);
    mood = min(100, mood + 2);
    xp += CreatureGrowth.xpPerFoodAction;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Récolte d’un point de nourriture sur la grille.
  void collectFoodMorsel() {
    if (_dead) return;
    hunger = min(100, hunger + 12);
    mood = min(100, mood + 1);
    xp += CreatureGrowth.xpPerFoodAction;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Jouer : coûte un peu d’énergie, remonte l’humeur modérément, court état excité.
  void play() {
    if (_dead) return;
    energy = max(0, energy - 12);
    hunger = max(0, hunger - 4);
    mood = min(100, mood + 8);
    _excitedUntil = DateTime.now().add(const Duration(seconds: 3));
    sleeping = false;
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Caresse (glisser sur la zone d’état) : petit gain d’humeur, limité par [_caressMoodMinGap].
  /// Retourne `true` si l’humeur a été ajustée (persist recommandé).
  bool registerCaressStroke() {
    if (_dead || sleeping) return false;
    final DateTime now = DateTime.now();
    if (_lastCaressMoodAt != null &&
        now.difference(_lastCaressMoodAt!) < _caressMoodMinGap) {
      return false;
    }
    if (mood >= 100) return false;
    _lastCaressMoodAt = now;
    mood = min(100, mood + 1);
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
    return true;
  }

  /// Endormir / réveiller (toggle). En sommeil, l’énergie remonte via le berçage (gyro).
  void sleep() {
    if (_dead) return;
    sleeping = !sleeping;
    if (sleeping) {
      _excitedUntil = null;
    }
    _checkCriticalStreakAfterUpdate();
    notifyListeners();
  }

  /// Énergie gagnée pendant le sommeil (berçage correct), plafonnée à 100.
  void addSleepRockEnergy(int delta) {
    if (_dead || !sleeping || delta <= 0) return;
    energy = min(100, energy + delta);
    notifyListeners();
  }

  /// Remplace les champs persistables (ex. après un transfert BLE depuis le stockage).
  void applyFromProfile(BitiProfile p) {
    hunger = p.hunger.clamp(0, 100);
    energy = p.energy.clamp(0, 100);
    mood = p.mood.clamp(0, 100);
    xp = p.xp.clamp(0, 1 << 30);
    name = _resolveBitiName(p);
    sleeping = p.sleeping;
    _dead = p.isDead;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _xpTick?.cancel();
    super.dispose();
  }
}
