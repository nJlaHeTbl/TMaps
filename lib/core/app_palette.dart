import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const ink = Color(0xFF102A2A);
  static const emerald = Color(0xFF0CAF78);

  /// Emerald darkened for text on light backgrounds (5.4:1 on white, WCAG AA).
  /// Plain [emerald] is only 2.8:1 and is meant for icons on tinted fills.
  static const emeraldText = Color(0xFF0B7A54);

  /// Star rating colour with at least 3:1 contrast on light and dark surfaces.
  static const ratingStar = Color(0xFFB45309);
  static const mint = Color(0xFF42E6A4);
  static const aqua = Color(0xFF0EA5B7);
  static const sky = Color(0xFF3B82F6);
  static const violet = Color(0xFF7C3AED);
  static const coral = Color(0xFFFF6B55);
  static const pink = Color(0xFFDB2777);
  static const canvas = Color(0xFFF2FBF7);
  static const surface = Color(0xFFFCFFFD);
  static const muted = Color(0xFF64748B);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF0CAF78), Color(0xFF0EA5B7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const warmGradient = LinearGradient(
    colors: [Color(0xFFFF8A5B), Color(0xFFFF4F81)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
