import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const BitiApp());
}

class BitiApp extends StatelessWidget {
  const BitiApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}
