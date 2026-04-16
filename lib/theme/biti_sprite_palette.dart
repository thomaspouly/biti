import 'package:flutter/material.dart';

/// Palette étendue pour la teinte du sprite (HSV + gris + accents).
List<Color> bitiSpriteTintPalette() {
  final Set<int> seen = <int>{};
  final List<Color> out = <Color>[];
  void add(Color c) {
    final int k = c.toARGB32();
    if (seen.add(k)) {
      out.add(c);
    }
  }

  for (int i = 0; i <= 24; i++) {
    add(Color.lerp(const Color(0xFF121212), const Color(0xFFF8F8F8), i / 24)!);
  }
  for (double h = 0; h < 360; h += 15) {
    for (final double s in <double>[0.32, 0.52, 0.72, 0.9, 1.0]) {
      for (final double v in <double>[0.42, 0.6, 0.78, 0.92, 1.0]) {
        add(HSVColor.fromAHSV(1.0, h, s, v).toColor());
      }
    }
  }
  const List<Color> accents = <Color>[
    Color(0xFF5F27CD),
    Color(0xFFE17055),
    Color(0xFF00B894),
    Color(0xFFFDCB6E),
    Color(0xFF0984E3),
    Color(0xFFD63031),
    Color(0xFF6C5CE7),
    Color(0xFFFD79A8),
    Color(0xFF00CEC9),
    Color(0xFFE84393),
    Color(0xFF8E44AD),
    Color(0xFFF39C12),
    Color(0xFF1ABC9C),
    Color(0xFF34495E),
    Color(0xFF00B4D8),
    Color(0xFFFF6B6B),
    Color(0xFF2ECC71),
  ];
  for (final Color c in accents) {
    add(c);
  }
  return out;
}

/// Dialogue grille de pastilles (même logique que les réglages Biti).
Future<int?> showBitiTintPickerDialog(
  BuildContext context, {
  required int currentArgb,
  required String title,
}) {
  final List<Color> palette = bitiSpriteTintPalette();
  return showDialog<int>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          height: 420,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 1,
            ),
            itemCount: palette.length,
            itemBuilder: (BuildContext _, int i) {
              final Color c = palette[i];
              final bool sel = c.toARGB32() == currentArgb;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx, c.toARGB32()),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.white24,
                        width: sel ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
        ],
      );
    },
  );
}
