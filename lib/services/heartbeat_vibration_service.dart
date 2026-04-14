import 'dart:async';

import 'package:flutter/services.dart';

import 'lifecycle_service.dart';

/// Vibrations type « lub-dub » ; l’intervalle entre cycles ralentit quand l’énergie baisse.
class HeartbeatVibrationService {
  HeartbeatVibrationService(this._lifecycle);

  final LifecycleService _lifecycle;

  Timer? _timer;

  /// Durée d’un cycle cardiaque (du 1er choc au suivant), selon l’énergie (0–100).
  Duration _cycleFromEnergy() {
    final t = (_lifecycle.energy / 100).clamp(0.0, 1.0);
    // Haute énergie ≈ 72 bpm ; très basse ≈ 28 bpm (cycle plus long).
    const minMs = 520;
    const maxMs = 2150;
    final ms = (maxMs - t * (maxMs - minMs)).round();
    return Duration(milliseconds: ms);
  }

  void start() {
    _lifecycle.addListener(_onLifecycle);
    _onLifecycle();
  }

  void _onLifecycle() {
    if (_lifecycle.sleeping) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer == null) {
      _timer = Timer(Duration.zero, _onBeat);
    }
  }

  void _onBeat() {
    _timer = null;
    if (_lifecycle.sleeping) return;

    HapticFeedback.mediumImpact();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 95), () {
        if (!_lifecycle.sleeping) {
          HapticFeedback.lightImpact();
        }
      }),
    );

    _timer = Timer(_cycleFromEnergy(), _onBeat);
  }

  void dispose() {
    _lifecycle.removeListener(_onLifecycle);
    _timer?.cancel();
    _timer = null;
  }
}
