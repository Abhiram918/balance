import 'package:flutter/material.dart';

class AppColors {
  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF5F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);

  static const Color lightPeriwinkle = Color(0xFFDDE8FF);
  static const Color lightLavender = Color(0xFFEAE1FC);
  static const Color lightMint = Color(0xFFDDF3E6);
  static const Color lightPeach = Color(0xFFFBE7D7);

  static const Color lightTextPrimary = Color(0xFF202438);
  static const Color lightTextSecondary = Color(0xFF6E7485);

  static const Color lightPrimaryBlue = Color(0xFF637FC2);
  static const Color lightLavenderAccent = Color(0xFF7959B5);
  static const Color lightGreenAccent = Color(0xFF397B59);

  // Dark Theme Colors
  static const Color darkBackground = Color(0xFF171922);
  static const Color darkSurface = Color(0xFF222530);
  static const Color darkSurfaceSecondary = Color(0xFF2A2E3B);

  static const Color darkTextPrimary = Color(0xFFF3F4FA);
  static const Color darkTextSecondary = Color(0xFFB0B5C5);

  static const Color darkBlueSurface = Color(0xFF293650);
  static const Color darkLavenderSurface = Color(0xFF362E49);
  static const Color darkGreenSurface = Color(0xFF263C33);
  static const Color darkPeachSurface = Color(0xFF453329);

  static const Color darkPrimaryBlue = Color(0xFF8BA6E9); // Adjusted for dark
  static const Color darkLavenderAccent = Color(0xFFA58DE3);
  static const Color darkGreenAccent = Color(0xFF61A883);
}

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color background;
  final Color surface;
  final Color surfaceSecondary;

  final Color textPrimary;
  final Color textSecondary;

  final Color primaryAccent;
  final Color lavenderAccent;
  final Color greenAccent;

  final Color cardBlue;
  final Color cardLavender;
  final Color cardMint;
  final Color cardPeach;

  AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.primaryAccent,
    required this.lavenderAccent,
    required this.greenAccent,
    required this.cardBlue,
    required this.cardLavender,
    required this.cardMint,
    required this.cardPeach,
  });

  @override
  ThemeExtension<AppThemeColors> copyWith() {
    return this;
  }

  @override
  ThemeExtension<AppThemeColors> lerp(
    ThemeExtension<AppThemeColors>? other,
    double t,
  ) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      lavenderAccent: Color.lerp(lavenderAccent, other.lavenderAccent, t)!,
      greenAccent: Color.lerp(greenAccent, other.greenAccent, t)!,
      cardBlue: Color.lerp(cardBlue, other.cardBlue, t)!,
      cardLavender: Color.lerp(cardLavender, other.cardLavender, t)!,
      cardMint: Color.lerp(cardMint, other.cardMint, t)!,
      cardPeach: Color.lerp(cardPeach, other.cardPeach, t)!,
    );
  }

  static AppThemeColors light = AppThemeColors(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceSecondary: const Color(0xFFF0F1F6),
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    primaryAccent: AppColors.lightPrimaryBlue,
    lavenderAccent: AppColors.lightLavenderAccent,
    greenAccent: AppColors.lightGreenAccent,
    cardBlue: AppColors.lightPeriwinkle,
    cardLavender: AppColors.lightLavender,
    cardMint: AppColors.lightMint,
    cardPeach: AppColors.lightPeach,
  );

  static AppThemeColors dark = AppThemeColors(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceSecondary: AppColors.darkSurfaceSecondary,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    primaryAccent: AppColors.darkPrimaryBlue,
    lavenderAccent: AppColors.darkLavenderAccent,
    greenAccent: AppColors.darkGreenAccent,
    cardBlue: AppColors.darkBlueSurface,
    cardLavender: AppColors.darkLavenderSurface,
    cardMint: AppColors.darkGreenSurface,
    cardPeach: AppColors.darkPeachSurface,
  );
}
