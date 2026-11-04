import 'package:flutter/material.dart';

/// Palette chaude et calme : papier, encre, terre cuite.
class SlowColors {
  static const paper = Color(0xFFFAF6F0);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2B2622);
  static const muted = Color(0xFF7A6F66);
  static const line = Color(0xFFE8DFD4);
  static const terracotta = Color(0xFFB5543C);
  static const sage = Color(0xFF5E7A64);
  static const amber = Color(0xFFC98A2B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SlowColors.terracotta,
    surface: SlowColors.paper,
  ).copyWith(
    primary: SlowColors.terracotta,
    secondary: SlowColors.sage,
    onSurface: SlowColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: SlowColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: SlowColors.paper,
      foregroundColor: SlowColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'serif',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: SlowColors.ink,
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w600, color: SlowColors.ink),
      headlineSmall: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w600, color: SlowColors.ink),
      titleLarge: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w600, color: SlowColors.ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: SlowColors.ink),
      bodyLarge: TextStyle(height: 1.45, color: SlowColors.ink),
      bodyMedium: TextStyle(height: 1.4, color: SlowColors.ink),
      bodySmall: TextStyle(color: SlowColors.muted),
    ),
    cardTheme: CardThemeData(
      color: SlowColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SlowColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SlowColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SlowColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SlowColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        foregroundColor: SlowColors.ink,
        side: const BorderSide(color: SlowColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    chipTheme: const ChipThemeData(side: BorderSide(color: SlowColors.line)),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: SlowColors.paper,
      indicatorColor: Color(0xFFF1DED6),
    ),
  );
}
