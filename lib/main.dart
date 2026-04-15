import 'package:flutter/material.dart';

import 'models/biti_profile.dart';
import 'screens/home_screen.dart';
import 'services/biti_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final BitiProfile? restored = await BitiStorage.load();
  runApp(BitiApp(restoredProfile: restored));
}

class BitiApp extends StatelessWidget {
  const BitiApp({super.key, this.restoredProfile});

  /// Profil restauré depuis les préférences, ou `null` pour une nouvelle partie.
  final BitiProfile? restoredProfile;

  @override
  Widget build(BuildContext context) {
    const double textScale = 1.2;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C5CE7),
      brightness: Brightness.dark,
    );
    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Orev',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0B0E14),
    );
    return MaterialApp(
      title: 'Biti',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamily: 'Orev',
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        ),
        primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: 'Orev',
          bodyColor: colorScheme.onPrimary,
          displayColor: colorScheme.onPrimary,
        ),
      ),
      builder: (BuildContext context, Widget? child) {
        if (child == null) return const SizedBox.shrink();
        final MediaQueryData mq = MediaQuery.of(context);
        final double combined = mq.textScaler.scale(1.0) * textScale;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(combined)),
          child: child,
        );
      },
      home: HomeScreen(restoredProfile: restoredProfile),
    );
  }
}
