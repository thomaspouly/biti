import 'package:flutter/material.dart';

/// Jauge 0–100 (texte + barre Material).
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.labelColor,
    this.valueColor,
    this.trackBackgroundColor,
    this.compactColumn = false,
  });

  final String label;
  final int value;
  final Color color;

  /// Couleur du libellé (défaut : blanc atténué, pour fond sombre).
  final Color? labelColor;

  /// Couleur de la valeur numérique.
  final Color? valueColor;

  /// Fond de la piste de progression.
  final Color? trackBackgroundColor;

  /// Colonne étroite centrée (ex. plusieurs jauges sur une ligne).
  final bool compactColumn;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 100) / 100.0;
    final lc = labelColor ?? Colors.white70;
    final track = trackBackgroundColor ?? Colors.white12;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: lc,
          height: 1.05,
        );
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: v,
        minHeight: compactColumn ? 9 : 8,
        backgroundColor: track,
        color: color,
      ),
    );

    if (compactColumn) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
            const SizedBox(height: 6),
            bar,
          ],
        ),
      );
    }

    final valueStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: valueColor ?? Colors.white54,
          height: 1.05,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: labelStyle),
              Text('${value.clamp(0, 100)}', style: valueStyle),
            ],
          ),
          const SizedBox(height: 3),
          bar,
        ],
      ),
    );
  }
}
