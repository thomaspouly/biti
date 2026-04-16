import 'package:flutter/material.dart';

import '../models/biti_collection.dart';
import '../models/biti_profile.dart';
import '../services/biti_storage.dart';
import '../theme/biti_sprite_palette.dart';
import '../theme/biti_theme_pair.dart';
import 'game_onboarding_carousel_screen.dart';

/// Premier lancement sans Biti : nom + couleurs A/B du sprite, puis jeu.
class FirstBitiScreen extends StatefulWidget {
  const FirstBitiScreen({super.key});

  @override
  State<FirstBitiScreen> createState() => _FirstBitiScreenState();
}

class _FirstBitiScreenState extends State<FirstBitiScreen> {
  late TextEditingController _nameCtrl;
  late int _colorA;
  late int _colorB;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final BitiThemePair d = BitiThemePair.presets[0];
    _colorA = d.a.toARGB32();
    _colorB = d.b.toARGB32();
    _nameCtrl = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickColor(BuildContext context, {required bool forA}) async {
    final int? picked = await showBitiTintPickerDialog(
      context,
      currentArgb: forA ? _colorA : _colorB,
      title: forA ? 'Couleur claire (A)' : 'Couleur foncée (B)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (forA) {
        _colorA = picked;
      } else {
        _colorB = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final BitiCollection c = await BitiStorage.createFirstBiti(
        name: _nameCtrl.text,
        colorAArgb: _colorA,
        colorBArgb: _colorB,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GameOnboardingCarouselScreen(collection: c),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0B0E14);
    const Color panel = Color(0xFF12161F);
    const Color fg = Color(0xFFE8ECF2);
    const Color muted = Color(0xFFB8C0CC);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Crée ton Biti',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choisis un nom et deux couleurs pour ton personnage sur le terrain.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Nom',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: fg),
                    cursorColor: fg,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'ex. ${BitiProfile.defaultName}',
                      hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
                      filled: true,
                      fillColor: panel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2A3140)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: fg.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Couleurs du biti',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _pickColor(context, forA: true),
                          icon: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Color(_colorA),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38),
                            ),
                          ),
                          label: const Text('Couleur A'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _pickColor(context, forA: false),
                          icon: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Color(_colorB),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38),
                            ),
                          ),
                          label: const Text('Couleur B'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : () => _submit(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Commencer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
