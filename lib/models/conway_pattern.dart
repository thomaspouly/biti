import 'package:flutter/material.dart';

/// Oscillateur (ou motif) décrit dans [assets/conway_life_patterns.json].
@immutable
class BitiConwayPattern {
  const BitiConwayPattern({
    required this.id,
    required this.name,
    required this.period,
    required this.width,
    required this.height,
    required this.rleBody,
  });

  final int id;
  final String name;
  final int period;
  final int width;
  final int height;
  final String rleBody;

  int get bboxMaxSide => width > height ? width : height;
}
