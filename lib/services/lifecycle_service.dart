import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/creature.dart';

/// Gestion faim / énergie / humeur et dérivation de l’humeur affichée.
class LifecycleService extends ChangeNotifier {
  LifecycleService({
    this.tickInterval = const Duration(seconds: 2),
    int initialHunger = 75,
    int initialEnergy = 80,
    int initialMood = 72,
  })  : hunger = initialHunger.clamp(0, 100),
        energy = initialEnergy.clamp(0, 100),
        mood = initialMood.clamp(0, 100) {
    _tick = Timer.periodic(tickInterval, (_) => _onTick());
  }

  final Duration tickInterval;

  int hunger;
  int energy;
  int mood;

  bool sleeping = false;
  DateTime? _excitedUntil;

  Timer? _tick;

  CreatureMood get derivedMood {
    final now = DateTime.now();
    if (_excitedUntil != null && now.isBefore(_excitedUntil!)) {
      return CreatureMood.excited;
    }
    if (sleeping) return CreatureMood.sleeping;
    if (hunger < 28) return CreatureMood.hungry;
    if (mood > 78 && hunger > 42) return CreatureMood.happy;
    return CreatureMood.idle;
  }

  void _onTick() {
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
    notifyListeners();
  }

  /// Nourrir : remonte la faim et l’humeur légèrement.
  void feed() {
    hunger = min(100, hunger + 28);
    mood = min(100, mood + 6);
    notifyListeners();
  }

  /// Récolte d’un point de nourriture sur la grille.
  void collectFoodMorsel() {
    hunger = min(100, hunger + 12);
    mood = min(100, mood + 3);
    notifyListeners();
  }

  /// Jouer : coûte un peu d’énergie, remonte l’humeur, court état excité.
  void play() {
    energy = max(0, energy - 12);
    hunger = max(0, hunger - 4);
    mood = min(100, mood + 22);
    _excitedUntil = DateTime.now().add(const Duration(seconds: 3));
    sleeping = false;
    notifyListeners();
  }

  /// Endormir / réveiller (toggle) pour récupérer de l’énergie.
  void sleep() {
    sleeping = !sleeping;
    if (sleeping) {
      _excitedUntil = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
