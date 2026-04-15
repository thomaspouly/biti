import 'package:flutter/material.dart';

import 'models/biti_profile.dart';
import 'screens/home_screen.dart';
import 'services/biti_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final restored = await BitiStorage.load();
  runApp(BitiApp(restoredProfile: restored));
}

class BitiApp extends StatelessWidget {
  const BitiApp({super.key, this.restoredProfile});

  /// Profil restauré depuis les préférences, ou `null` pour une nouvelle partie.
  final BitiProfile? restoredProfile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
      ),
      home: HomeScreen(restoredProfile: restoredProfile),
    );
  }
}
