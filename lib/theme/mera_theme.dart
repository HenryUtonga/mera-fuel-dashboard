import 'package:flutter/material.dart';

class MeraColors {
  MeraColors._();

  // MERA corporate colours
  static const Color green = Color(0xFF18A94B);
  static const Color darkGreen = Color(0xFF174D35);
  static const Color deepGreen = Color(0xFF0B3828);
  static const Color gold = Color(0xFFF4B41A);

  // Dashboard neutrals
  static const Color background = Color(0xFFF7F8F7);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E6E3);

  static const Color text = Color(0xFF26332C);
  static const Color mutedText = Color(0xFF6F7772);

  static const Color paleGreen = Color(0xFFEAF7EE);
}

class MeraTheme {
  MeraTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: MeraColors.green,
      brightness: Brightness.light,
    ).copyWith(
      primary: MeraColors.green,
      secondary: MeraColors.gold,
      surface: MeraColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MeraColors.background,

      appBarTheme: const AppBarTheme(
        backgroundColor: MeraColors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),

      dividerTheme: const DividerThemeData(
        color: MeraColors.border,
        thickness: 1,
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: MeraColors.border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MeraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MeraColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: MeraColors.green,
            width: 1.5,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MeraColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MeraColors.green,
      ),
    );
  }
}