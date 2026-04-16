import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Messages d’état pour la barre d’info en mode sommeil (gyroscope).
enum SleepRockGuide {
  /// Vitesse angulaire trop faible.
  rockTooSlow,

  /// Vitesse angulaire trop forte.
  rockTooFast,

  /// Bercement dans la plage cible.
  rockGood,
}

/// En mode sommeil : bercement gauche-droite via le gyroscope.
final class SleepRockingService {
  SleepRockingService({
    required this.onGuideChanged,
    required this.onEnergyDelta,
  });

  final void Function(SleepRockGuide guide) onGuideChanged;
  final void Function(int delta) onEnergyDelta;

  StreamSubscription<GyroscopeEvent>? _gyro;
  Timer? _secondTimer;

  bool _sleeping = false;

  double _ema = 0;
  SleepRockGuide _guide = SleepRockGuide.rockTooSlow;
  DateTime _prevSample = DateTime.now();

  /// Secondes cumulées dans la bande « bon bercement » sur l’intervalle d’1 s.
  double _goodSecondsThisTick = 0;

  static const double _emaAlpha = 0.12;

  static const double _goodLo = 0.32;
  static const double _goodHi = 1.02;

  void setSleeping(bool sleeping) {
    if (sleeping == _sleeping) return;
    _sleeping = sleeping;
    if (_sleeping) {
      _ema = 0;
      _goodSecondsThisTick = 0;
      _prevSample = DateTime.now();
      _guide = SleepRockGuide.rockTooSlow;
      onGuideChanged(_guide);
      _gyro = gyroscopeEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onGyro, onError: (_) {}, cancelOnError: false);
      _secondTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _onOneSecond(),
      );
    } else {
      unawaited(_gyro?.cancel());
      _gyro = null;
      _secondTimer?.cancel();
      _secondTimer = null;
    }
  }

  void _onGyro(GyroscopeEvent e) {
    if (!_sleeping) return;

    final DateTime now = DateTime.now();
    final double dt = now.difference(_prevSample).inMicroseconds / 1e6;
    _prevSample = now;
    final double dtClamped = dt.clamp(0.0, 0.22);

    // Balancement gauche-droite : combinaison des axes hors « pitch avant-arrière ».
    final double mag = sqrt(e.x * e.x + e.z * e.z);
    _ema = (1 - _emaAlpha) * _ema + _emaAlpha * mag;

    if (_ema >= _goodLo && _ema <= _goodHi) {
      _goodSecondsThisTick += dtClamped;
      _setGuide(SleepRockGuide.rockGood);
    } else if (_ema < _goodLo) {
      _setGuide(SleepRockGuide.rockTooSlow);
    } else {
      _setGuide(SleepRockGuide.rockTooFast);
    }
  }

  void _setGuide(SleepRockGuide g) {
    if (g == _guide) return;
    _guide = g;
    onGuideChanged(g);
  }

  void _onOneSecond() {
    if (!_sleeping) return;
    final double s = _goodSecondsThisTick.clamp(0.0, 1.0);
    final int gain = (2.0 * s).round().clamp(0, 2);
    if (gain > 0) {
      onEnergyDelta(gain);
    }
    _goodSecondsThisTick = 0;
  }

  void dispose() {
    setSleeping(false);
  }
}
