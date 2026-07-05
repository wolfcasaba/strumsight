import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme mode (light / dark / system), persisted in shared_preferences.
/// StrumSight is dark-first, so dark is the default; a `?theme=` query param
/// forces a mode for web previews/screenshots (and skips persistence).
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  ThemeMode build() {
    final override = _fromQuery();
    if (override != null) return override;
    _load();
    return ThemeMode.dark; // dark-first default until prefs load
  }

  ThemeMode? _fromQuery() {
    switch (Uri.base.queryParameters['theme']) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final name = _prefs!.getString(_key);
      // Don't clobber a mode the user set before prefs finished loading.
      if (name != null && !_userSet) {
        state = ThemeMode.values.byName(name);
      }
    } catch (_) {
      // Prefs unavailable → keep the dark-first default.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _userSet = true;
    state = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
