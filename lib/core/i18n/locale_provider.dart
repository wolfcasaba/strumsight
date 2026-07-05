import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen app locale, or null for the system default. Persisted in
/// shared_preferences (same durability model as theme / fasting).
class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'app_locale';
  SharedPreferences? _prefs;

  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final code = _prefs!.getString(_key);
    if (code != null && code.isNotEmpty) state = Locale(code);
  }

  /// Set the locale (null = follow the system) and persist it.
  Future<void> set(Locale? locale) async {
    state = locale;
    _prefs ??= await SharedPreferences.getInstance();
    if (locale == null) {
      await _prefs!.remove(_key);
    } else {
      await _prefs!.setString(_key, locale.languageCode);
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
