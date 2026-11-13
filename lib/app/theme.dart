import 'package:flutter/material.dart';

/// Designsystem der App. Farben je Sportart und Bausteine folgen mit den Bereichen (Phase 3).
abstract final class AppTheme {
  static const _seed = Color(0xFFE8622C);

  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
    );
  }
}
