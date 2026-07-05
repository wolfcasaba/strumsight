import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App theme mode (light / dark / system), toggleable at runtime from Settings.
/// StrumSight is dark-first, so dark is the default; a `?theme=` query param
/// can force a mode for web previews/screenshots.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    switch (Uri.base.queryParameters['theme']) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  void setMode(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
