import 'package:flutter/material.dart';

/// Telegram-inspired light palette for the app.
class VeilColors {
  VeilColors._();

  static const Color primary = Color(0xFF3390EC);
  static const Color scaffold = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEDEFF1);
  static const Color secondaryText = Color(0xFF8A96A0);
  static const Color field = Color(0xFFF1F4F6);
  static const Color danger = Color(0xFFE5484D);

  static const Color chatWallpaper = Color(0xFFDCE6EF);
  static const Color bubbleIn = Color(0xFFFFFFFF);
  static const Color bubbleOut = Color(0xFFD6ECFB);

  static const List<Color> avatarPalette = <Color>[
    Color(0xFFF5866E),
    Color(0xFF6CC788),
    Color(0xFF9B8CF0),
    Color(0xFF4FBCEF),
    Color(0xFFEEA451),
    Color(0xFFE274A6),
  ];

  /// Deterministic avatar colour from a seed (e.g. the chat id).
  static Color avatarFor(String seed) =>
      avatarPalette[seed.hashCode.abs() % avatarPalette.length];
}

ThemeData buildVeilTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: VeilColors.primary,
      primary: VeilColors.primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: VeilColors.scaffold,
    appBarTheme: const AppBarTheme(
      backgroundColor: VeilColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    dividerColor: VeilColors.divider,
  );
}
