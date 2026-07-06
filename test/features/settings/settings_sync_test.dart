import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/i18n/locale_provider.dart';
import 'package:music_theory/core/theme/theme_mode_provider.dart';
import 'package:music_theory/features/auth/data/auth_repository.dart';
import 'package:music_theory/features/auth/data/token_store.dart';
import 'package:music_theory/features/auth/providers/auth_providers.dart';
import 'package:music_theory/features/settings/data/settings_repository.dart';
import 'package:music_theory/features/settings/providers/confidence_threshold_provider.dart';
import 'package:music_theory/features/settings/providers/settings_sync.dart';
import 'package:music_theory/features/settings/providers/tuning_reference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_settings.dart';

ProviderContainer _container({
  required FakeTokenStore tokens,
  required FakeSettingsRepository settings,
}) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      settingsRepositoryProvider.overrideWithValue(settings),
      // No debounce / fast retry in tests.
      settingsSyncDebounceProvider.overrideWithValue(Duration.zero),
      settingsSyncRetryProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Let scheduled timers/microtasks (debounce, listener flush) run.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() {
    // The local settings notifiers persist via shared_preferences — give them
    // a working in-memory mock so setMode/set don't throw in tests.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('does nothing while logged out', () async {
    final settings = FakeSettingsRepository();
    final container = _container(tokens: FakeTokenStore(), settings: settings);
    container.read(settingsSyncProvider); // instantiate
    await container.read(authControllerProvider.future);

    // A local change with no session must not touch the backend.
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    await _settle();

    expect(settings.fetchCalls, 0);
    expect(settings.updates, isEmpty);
  });

  test('pulls and applies the cloud profile on sign-in', () async {
    final settings = FakeSettingsRepository(
      themeMode: ThemeMode.light,
      locale: const Locale('hu'),
      confidenceThreshold: 0.7,
      tuningA4: 432,
    );
    // A stored token => the session restores => sign-in transition => pull.
    final container =
        _container(tokens: FakeTokenStore('tok'), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    expect(settings.fetchCalls, greaterThan(0));
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(localeProvider), const Locale('hu'));
    expect(container.read(confidenceThresholdProvider), 0.7);
    expect(container.read(tuningReferenceProvider), 432);
  });

  test('applying a pulled profile does not echo back as a push', () async {
    final settings = FakeSettingsRepository(themeMode: ThemeMode.light);
    final container =
        _container(tokens: FakeTokenStore('tok'), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    // The pull wrote local state, but that must not trigger an update.
    expect(settings.updates, isEmpty);
  });

  test('pushes a local change to the backend when signed in', () async {
    final settings = FakeSettingsRepository();
    final container =
        _container(tokens: FakeTokenStore('tok'), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull settles

    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();

    expect(settings.updates, isNotEmpty);
    expect(settings.updates.last['confidence_threshold'], 0.8);
  });

  test('pushes a tuning-reference change to the backend', () async {
    final settings = FakeSettingsRepository();
    final container =
        _container(tokens: FakeTokenStore('tok'), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull

    await container.read(tuningReferenceProvider.notifier).set(442);
    await _settle();

    expect(settings.updates.last['tuning_a4'], 442);
  });

  test('register pushes local settings up (does not clobber them with defaults)',
      () async {
    final settings = FakeSettingsRepository(); // remote = defaults
    final container = _container(tokens: FakeTokenStore(), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);

    // The user customised settings offline BEFORE creating an account.
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    await _settle();
    expect(settings.updates, isEmpty); // nothing pushed while logged out

    await container
        .read(authControllerProvider.notifier)
        .register('new@strumsight.app', 'sixstrings');
    await _settle();

    // Signup adopts the local settings as the cloud profile — not the reverse.
    expect(settings.updates, isNotEmpty);
    expect(settings.updates.last['theme_mode'], 'light');
    expect(container.read(themeModeProvider), ThemeMode.light); // unchanged
  });

  test('an offline push is retried, not silently dropped', () async {
    final settings = FakeSettingsRepository();
    final container =
        _container(tokens: FakeTokenStore('tok'), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull

    settings.failNextUpdates = 1; // first push fails (offline)
    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();

    // The failed attempt was retried (>=2 recorded) and eventually applied.
    expect(settings.updates.length, greaterThanOrEqualTo(2));
    expect(settings.confidenceThreshold, 0.8);
  });
}
