import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// App-wide Material 3 themes (light & dark), branded for Music Theory (placeholder tokens).
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      brightness: brightness,
    );

    // True headings default to Montserrat (the web heading font); title/body/
    // label stay Poppins so buttons & labels are unaffected.
    final baseTextTheme = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final heading = TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: palette.ink,
    );
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.merge(heading),
      displayMedium: baseTextTheme.displayMedium?.merge(heading),
      displaySmall: baseTextTheme.displaySmall?.merge(heading),
      headlineLarge: baseTextTheme.headlineLarge?.merge(heading),
      headlineMedium: baseTextTheme.headlineMedium?.merge(heading),
      headlineSmall: baseTextTheme.headlineSmall?.merge(heading),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Poppins',
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.bg,
      extensions: [palette],
    );
  }
}
