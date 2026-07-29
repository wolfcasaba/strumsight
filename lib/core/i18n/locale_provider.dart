import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/persisted_preference.dart';
import '../storage/storage_keys.dart';

/// The user's chosen app locale, or null for the system default. Persisted
/// through the injected [KeyValueStore] (same durability model as theme).
class LocaleNotifier extends Notifier<Locale?>
    with PersistedPreference<Locale?> {
  @override
  Locale? build() {
    final code = preferences.readString(StorageKeys.locale);
    return code == null || code.isEmpty ? null : Locale(code);
  }

  /// Set the locale (null = follow the system) and persist it.
  Future<void> set(Locale? locale) async {
    state = locale;
    await persist(
      StorageKeys.locale,
      (store) => locale == null
          ? store.remove(StorageKeys.locale)
          : store.writeString(StorageKeys.locale, locale.languageCode),
    );
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
