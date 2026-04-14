import 'package:flutter/material.dart';

/// Jauge 0–100 sous la grille.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 100) / 100.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              Text(
                '${value.clamp(0, 100)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white54,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 10,
              backgroundColor: Colors.white12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
