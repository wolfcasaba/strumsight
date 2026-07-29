import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/persisted_preference.dart';
import '../storage/storage_keys.dart';

/// App theme mode (light / dark / system), persisted through the injected
/// [KeyValueStore]. StrumSight is dark-first, so dark is the default; a
/// `?theme=` query param forces a mode for web previews/screenshots (and skips
/// the stored value).
class ThemeModeController extends Notifier<ThemeMode>
    with PersistedPreference<ThemeMode> {
  @override
  ThemeMode build() =>
      _fromQuery() ?? _parse(preferences.readString(StorageKeys.themeMode));

  ThemeMode? _fromQuery() => switch (Uri.base.queryParameters['theme']) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    'dark' => ThemeMode.dark,
    _ => null,
  };

  /// Unknown / absent stored name → the dark-first default. A value written by
  /// a future build must not crash an older one.
  ThemeMode _parse(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.dark,
  };

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await persist(
      StorageKeys.themeMode,
      (store) => store.writeString(StorageKeys.themeMode, mode.name),
    );
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
