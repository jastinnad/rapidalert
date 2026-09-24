import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RapidAlertColors {
  // Matches the website's auth palette (public/css/auth.css --auth-primary /
  // --auth-primary-deep) for visual consistency between web and mobile.
  static const primaryRed = Color(0xFFEF4444);
  static const emergencyRed = Color(0xFFDC2626);
  static const brightOrange = Color(0xFFF97316);
  static const orangeAccent = Color(0xFFFF8F3D);
  static const operationsBlue = Color(0xFF214A9A);
  static const success = Color(0xFF1FA463);
  static const warning = Color(0xFFFF9800);
  static const background = Color(0xFFF4F6FA);
  static const card = Colors.white;
  static const border = Color(0xFFE4E7EC);
  static const darkText = Color(0xFF1E293B);
  static const lightText = Color(0xFF64748B);
}

ThemeData buildRapidAlertTheme() {
  // The website uses Inter (public/css/auth.css); match it here too.
  final baseText = GoogleFonts.interTextTheme();

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: RapidAlertColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RapidAlertColors.primaryRed,
      brightness: Brightness.light,
      primary: RapidAlertColors.primaryRed,
      secondary: RapidAlertColors.operationsBlue,
    ),
    textTheme: baseText.copyWith(
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: RapidAlertColors.darkText,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: RapidAlertColors.darkText,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: RapidAlertColors.darkText,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        color: RapidAlertColors.darkText,
      ),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: RapidAlertColors.darkText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: RapidAlertColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RapidAlertColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}

// Mirrors the website's auth screen gradient
// (public/css/auth.css .auth-right: 140deg, #ef4444 -> #dc2626 -> #b91c1c).
LinearGradient get authGradient => const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFFB91C1C)],
);
