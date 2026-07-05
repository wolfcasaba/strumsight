import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App theme mode (light / dark / system), toggleable at runtime from Settings.
/// Initial value can be forced for previews via the `?theme=` query param.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    switch (Uri.base.queryParameters['theme']) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  void setMode(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
