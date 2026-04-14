import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Capteurs : secousse → callback ; gyro → inclinaison pour le penché visuel.
class SensorService {
  SensorService({
    required this.onShake,
    required this.onTilt,
    this.shakeThreshold = 14.0,
    this.shakeCooldown = const Duration(milliseconds: 1200),
  });

  final VoidCallback onShake;
  final void Function(double leanNormalized) onTilt;

  final double shakeThreshold;
  final Duration shakeCooldown;

  StreamSubscription<UserAccelerometerEvent>? _userAccel;
  StreamSubscription<GyroscopeEvent>? _gyro;

  DateTime _lastShakeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Démarre l’écoute (échoue silencieusement sur plateformes sans capteur).
  void start() {
    _userAccel = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onUserAccel, onError: (_) {}, cancelOnError: false);

    _gyro = gyroscopeEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onGyro, onError: (_) {}, cancelOnError: false);
  }

  void _onUserAccel(UserAccelerometerEvent e) {
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag < shakeThreshold) return;
    final now = DateTime.now();
    if (now.difference(_lastShakeAt) < shakeCooldown) return;
    _lastShakeAt = now;
    onShake();
  }

  void _onGyro(GyroscopeEvent e) {
    // Légère réaction visuelle : combine les axes pour un penché ressenti.
    final lean = (e.y * 0.08 + e.x * 0.04).clamp(-1.0, 1.0);
    onTilt(lean);
  }

  void dispose() {
    unawaited(_userAccel?.cancel());
    unawaited(_gyro?.cancel());
    _userAccel = null;
    _gyro = null;
  }
}
