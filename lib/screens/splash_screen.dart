import 'dart:async';

import 'package:flutter/material.dart';

import '../models/biti_collection.dart';
import 'first_biti_screen.dart';
import 'home_screen.dart';

/// Mascotte centrée pendant 2 s, puis passage à [HomeScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.initialCollection});

  final BitiCollection initialCollection;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Duration _duration = Duration(seconds: 2);
  static const Color _background = Color(0xFFD6C7A1);

  @override
  void initState() {
    super.initState();
    unawaited(_goNext());
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(_duration);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => widget.initialCollection.isEmpty
            ? const FirstBitiScreen()
            : HomeScreen(initialCollection: widget.initialCollection),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.25,
            child: Image.asset(
              'assets/branding/biti_app_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
