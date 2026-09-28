import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RapidAlertColors {
  // Matches the website's palette (public/css/auth.css :root variables) so
  // web and mobile read as the same product.
  static const primaryRed = Color(0xFFEF4444);
  static const emergencyRed = Color(0xFFDC2626);
  static const brightOrange = Color(0xFFF97316);
  static const orangeAccent = Color(0xFFFF8F3D);
  static const operationsBlue = Color(0xFF214A9A);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFFF9800);
  static const background = Color(0xFFF8FAFC);
  static const card = Colors.white;
  static const border = Color(0xFFE5E7EB);
  static const darkText = Color(0xFF0F172A);
  static const lightText = Color(0xFF6B7280);

  // auth.css form details: link text, field labels, input focus ring.
  static const linkRed = Color(0xFFB91C1C);
  static const labelText = Color(0xFF334155);
  static const inputFocus = Color(0xFFF87171);
  static const inputIcon = Color(0xFF94A3B8);
  static const cardBorder = Color(0xFFE2E8F0);

  // Matches StatusMachine::color() on the backend exactly, so a report's
  // status color stays consistent between mobile and web.
  static const statusAssigned = Color(0xFFF59E0B);
  static const enRoute = Color(0xFF8B5CF6);
  static const onSceneAccent = Color(0xFF06B6D4);
  static const statusResolved = Color(0xFF22C55E);
  static const statusCompleted = Color(0xFF6B7280);

  // Matches the website's dispatch map exactly: responder marker/route
  // (public/js/responder-dispatch.js) and the evacuation finder's "you are
  // here" marker (public/js/evacuation.js) both use this same blue.
  static const dispatchBlue = Color(0xFF3B82F6);
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
    // auth.css inputs: 2px #e5e7eb border, radius 11, 46px tall, red focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      constraints: const BoxConstraints(minHeight: 46),
      hintStyle: baseText.bodyMedium?.copyWith(color: RapidAlertColors.inputIcon, fontSize: 14),
      prefixIconColor: RapidAlertColors.inputIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.inputFocus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.emergencyRed, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.emergencyRed, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.border, width: 2),
      ),
    ),
  );
}

// The website's red brand panel (auth.css .auth-right: 140deg,
// #ef4444 0% -> #dc2626 60% -> #b91c1c 100%).
LinearGradient get authGradient => const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFFB91C1C)],
  stops: [0, 0.6, 1],
);

// The website's primary buttons (auth.css .btn-primary: 135deg,
// #ef4444 -> #dc2626).
LinearGradient get authButtonGradient => const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
);
