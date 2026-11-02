import 'package:flutter/material.dart';

/// Identidad visual alineada al logo: azul profundo, blanco, acento rojo mesurado.
abstract final class AppColors {
  static const deepBlue = Color(0xFF0B2A4A);
  static const midBlue = Color(0xFF1A4B7A);
  static const signalCyan = Color(0xFF4DB6D4);
  static const accentRed = Color(0xFFC62828);
  static const surface = Color(0xFFF5F8FB);
  static const onDeep = Color(0xFFFFFFFF);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.deepBlue,
      primary: AppColors.deepBlue,
      secondary: AppColors.signalCyan,
      error: AppColors.accentRed,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepBlue,
        foregroundColor: AppColors.onDeep,
        centerTitle: true,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.deepBlue,
          foregroundColor: AppColors.onDeep,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.signalCyan.withValues(alpha: 0.25),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
