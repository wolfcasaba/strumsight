import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/i18n/locale_provider.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/theme/theme_mode_provider.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/providers/confidence_threshold_provider.dart';
import 'package:strumsight/features/settings/providers/settings_sync.dart';
import 'package:strumsight/features/settings/providers/tuning_reference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

ProviderContainer _container({
  required FakeTokenStore tokens,
  required SettingsRepository settings,
  FakeAuthRepository? auth,
  bool accountEnabled = true,
  InMemoryKeyValueStore? preferenceStore,
}) {
  final config = AppConfig.resolve(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: FeatureFlags.forEnvironment(
      AppEnvironment.development,
      accountEnabled: accountEnabled,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'debug',
    appVersion: 'test',
  );
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      if (preferenceStore == null)
        ...preferenceOverrides()
      else
        preferenceStoreOverride(preferenceStore),
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      settingsRepositoryProvider.overrideWithValue(settings),
      // No debounce in tests.
      settingsSyncDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Let scheduled timers/microtasks (debounce, listener flush) run.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

final class _DelayedFirstFetchRepository implements SettingsRepository {
  _DelayedFirstFetchRepository({
    required this.firstResponse,
    required this.laterResponse,
  });

  final RemoteSettings firstResponse;
  final RemoteSettings laterResponse;
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> releaseFirst = Completer<void>();
  int fetchCalls = 0;

  @override
  Future<AppResult<RemoteSettings>> fetch() async {
    fetchCalls++;
    if (fetchCalls == 1) {
      firstStarted.complete();
      await releaseFirst.future;
      return Success(firstResponse);
    }
    return Success(laterResponse);
  }

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async =>
      Success(laterResponse);
}

RemoteSettings _remote(ThemeMode themeMode) => RemoteSettings(
  themeMode: themeMode,
  locale: null,
  confidenceThreshold: 0.45,
  tuningA4: 440,
);

final class _DelayedThemeWriteStore extends InMemoryKeyValueStore {
  final Completer<void> themeWriteStarted = Completer<void>();
  final Completer<void> releaseThemeWrite = Completer<void>();
  bool _delayNextThemeWrite = true;

  @override
  Future<void> writeString(String key, String value) async {
    if (key == StorageKeys.themeMode && _delayNextThemeWrite) {
      _delayNextThemeWrite = false;
      themeWriteStarted.complete();
      await releaseThemeWrite.future;
    }
    await super.writeString(key, value);
  }
}

final class _OutOfOrderUpdateRepository implements SettingsRepository {
  final Completer<void> firstUpdateStarted = Completer<void>();
  final Completer<void> releaseFirstUpdate = Completer<void>();
  final List<Map<String, Object?>> updates = [];
  double serverThreshold = 0.45;

  RemoteSettings get _current => RemoteSettings(
    themeMode: ThemeMode.system,
    locale: null,
    confidenceThreshold: serverThreshold,
    tuningA4: 440,
  );

  @override
  Future<AppResult<RemoteSettings>> fetch() async => Success(_current);

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async {
    final captured = Map<String, Object?>.of(patch);
    updates.add(captured);
    if (updates.length == 1) {
      firstUpdateStarted.complete();
      await releaseFirstUpdate.future;
    }
    serverThreshold = (captured['confidence_threshold'] as num).toDouble();
    return Success(_current);
  }
}

final class _SequencedFetchRepository implements SettingsRepository {
  _SequencedFetchRepository(this.responses);

  final List<RemoteSettings> responses;
  int fetchCalls = 0;

  @override
  Future<AppResult<RemoteSettings>> fetch() async {
    final index = fetchCalls.clamp(0, responses.length - 1);
    fetchCalls++;
    return Success(responses[index]);
  }

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async =>
      Success(responses.last);
}

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

  test('account-disabled sync ignores a stale stored token', () async {
    final settings = FakeSettingsRepository();
    final tokens = FakeTokenStore('stale-token');
    final container = _container(
      tokens: tokens,
      settings: settings,
      accountEnabled: false,
    );

    container.read(settingsSyncProvider);
    await _settle();

    expect(tokens.reads, 0);
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
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
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
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    // The pull wrote local state, but that must not trigger an update.
    expect(settings.updates, isEmpty);
  });

  test('a user edit during pull persistence survives and is pushed', () async {
    final store = _DelayedThemeWriteStore();
    final settings = FakeSettingsRepository(
      themeMode: ThemeMode.light,
      locale: const Locale('hu'),
    );
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
      preferenceStore: store,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await store.themeWriteStarted.future;

    await container.read(localeProvider.notifier).set(const Locale('en'));
    store.releaseThemeWrite.complete();
    await _settle();

    expect(container.read(localeProvider), const Locale('en'));
    expect(settings.updates, isNotEmpty);
    expect(settings.updates.last['locale'], 'en');
  });

  test('a same-field edit during pull persistence remains stored', () async {
    final store = _DelayedThemeWriteStore();
    final settings = FakeSettingsRepository(themeMode: ThemeMode.light);
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
      preferenceStore: store,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await store.themeWriteStarted.future;

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    store.releaseThemeWrite.complete();
    await _settle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(store.readString(StorageKeys.themeMode), ThemeMode.dark.name);
    expect(settings.updates, isNotEmpty);
    expect(settings.updates.last['theme_mode'], ThemeMode.dark.name);
  });

  test('a delayed pull cannot overwrite a newer local edit', () async {
    final settings = _DelayedFirstFetchRepository(
      firstResponse: _remote(ThemeMode.light),
      laterResponse: _remote(ThemeMode.system),
    );
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await settings.firstStarted.future;

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.system);
    settings.releaseFirst.complete();
    await _settle();

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test(
    'an old account pull cannot overwrite a newer account session',
    () async {
      final settings = _DelayedFirstFetchRepository(
        firstResponse: _remote(ThemeMode.light),
        laterResponse: _remote(ThemeMode.dark),
      );
      final auth = FakeAuthRepository();
      final container = _container(
        tokens: FakeTokenStore('account-a-token'),
        settings: settings,
        auth: auth,
      );
      container.read(settingsSyncProvider);
      await container.read(authControllerProvider.future);
      await settings.firstStarted.future;

      await container.read(authControllerProvider.notifier).logout();
      auth.user = const AuthUser(id: 2, email: 'other@strumsight.app');
      await container
          .read(authControllerProvider.notifier)
          .login('other@strumsight.app', 'sixstrings');
      await _settle();
      settings.releaseFirst.complete();
      await _settle();

      expect(settings.fetchCalls, 2);
      expect(container.read(authControllerProvider).value?.id, 2);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    },
  );

  test(
    'an old account disk write cannot overwrite the newer account settings',
    () async {
      final store = _DelayedThemeWriteStore();
      final settings = _SequencedFetchRepository([
        _remote(ThemeMode.light),
        _remote(ThemeMode.dark),
      ]);
      final auth = FakeAuthRepository();
      final container = _container(
        tokens: FakeTokenStore('account-a-token'),
        settings: settings,
        auth: auth,
        preferenceStore: store,
      );
      container.read(settingsSyncProvider);
      await container.read(authControllerProvider.future);
      await store.themeWriteStarted.future;

      await container.read(authControllerProvider.notifier).logout();
      auth.user = const AuthUser(id: 2, email: 'other@strumsight.app');
      await container
          .read(authControllerProvider.notifier)
          .login('other@strumsight.app', 'sixstrings');
      await _settle();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      store.releaseThemeWrite.complete();
      await _settle();

      expect(container.read(authControllerProvider).value?.id, 2);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(store.readString(StorageKeys.themeMode), ThemeMode.dark.name);
    },
  );

  test('login after logout triggers a fresh settings pull', () async {
    final settings = FakeSettingsRepository();
    final container = _container(tokens: FakeTokenStore(), settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);

    final auth = container.read(authControllerProvider.notifier);
    await auth.login('player@strumsight.app', 'sixstrings');
    await _settle();
    await auth.logout();
    await auth.login('player@strumsight.app', 'sixstrings');
    await _settle();

    expect(settings.fetchCalls, 2);
  });

  test('pushes a local change to the backend when signed in', () async {
    final settings = FakeSettingsRepository();
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull settles

    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();

    expect(settings.updates, isNotEmpty);
    expect(settings.updates.last['confidence_threshold'], 0.8);
  });

  test(
    'settings pushes are single-flight and deliver the latest edit last',
    () async {
      final settings = _OutOfOrderUpdateRepository();
      final container = _container(
        tokens: FakeTokenStore('tok'),
        settings: settings,
      );
      container.read(settingsSyncProvider);
      await container.read(authControllerProvider.future);
      await _settle();

      await container.read(confidenceThresholdProvider.notifier).set(0.8);
      await settings.firstUpdateStarted.future;
      await container.read(confidenceThresholdProvider.notifier).set(0.9);
      await _settle();
      final callsWhileFirstWasBlocked = settings.updates.length;

      settings.releaseFirstUpdate.complete();
      await _settle();

      expect(callsWhileFirstWasBlocked, 1);
      expect(settings.updates, hasLength(2));
      expect(settings.serverThreshold, 0.9);
    },
  );

  test('pushes a tuning-reference change to the backend', () async {
    final settings = FakeSettingsRepository();
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull

    await container.read(tuningReferenceProvider.notifier).set(442);
    await _settle();

    expect(settings.updates.last['tuning_a4'], 442);
  });

  test(
    'register pushes local settings up (does not clobber them with defaults)',
    () async {
      final settings = FakeSettingsRepository(); // remote = defaults
      final container = _container(
        tokens: FakeTokenStore(),
        settings: settings,
      );
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
    },
  );

  test('a failed update is not retried automatically', () async {
    final settings = FakeSettingsRepository();
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle(); // initial pull

    settings.failNextUpdates = 1; // first push fails (offline)
    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();

    expect(settings.updates, hasLength(1));
    expect(settings.confidenceThreshold, isNot(0.8));

    // A later genuine edit sends the latest full patch; no background loop is
    // needed to recover the prior unsynced value.
    await container.read(tuningReferenceProvider.notifier).set(442);
    await _settle();
    expect(settings.updates, hasLength(2));
    expect(settings.updates.last['confidence_threshold'], 0.8);
    expect(settings.updates.last['tuning_a4'], 442);
  });

  test(
    'a PERMANENT rejection (401/422) is NOT retried — no infinite loop',
    () async {
      // Round 123: _sendPatch retried on ANY error with a 10s timer. An expired
      // 14-day JWT (401) or a validation 422 can never succeed, so that spun a
      // forever loop draining battery + hammering the server. A permanent 4xx
      // must be given up on (until the next genuine local change / re-login).
      final settings = FakeSettingsRepository();
      final container = _container(
        tokens: FakeTokenStore('tok'),
        settings: settings,
      );
      container.read(settingsSyncProvider);
      await container.read(authControllerProvider.future);
      await _settle(); // initial pull

      settings.updateFailure = const AuthenticationFailure(
        code: FailureCode.authSessionExpired,
      );
      await container.read(confidenceThresholdProvider.notifier).set(0.8);
      // Give any (buggy) retry timers several windows to fire.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        settings.updates.length,
        1,
        reason: 'a permanent 4xx must be attempted exactly once, not retried',
      );
      expect(container.read(authControllerProvider).value, isNull);
    },
  );

  test('a pull forbidden with 403 keeps the established session', () async {
    final settings = FakeSettingsRepository()
      ..fetchFailure = const AuthenticationFailure(
        code: FailureCode.authForbidden,
      );
    final tokens = FakeTokenStore('tok');
    final container = _container(tokens: tokens, settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    expect(container.read(authControllerProvider).value, isNotNull);
    expect(tokens.token, 'tok');
  });

  test('a settings update forbidden with 403 keeps the session', () async {
    final settings = FakeSettingsRepository();
    final tokens = FakeTokenStore('tok');
    final container = _container(tokens: tokens, settings: settings);
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    settings.updateFailure = const AuthenticationFailure(
      code: FailureCode.authForbidden,
    );
    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();

    expect(container.read(authControllerProvider).value, isNotNull);
    expect(tokens.token, 'tok');
  });

  test('a transient 5xx is still attempted only once', () async {
    final settings = FakeSettingsRepository();
    final container = _container(
      tokens: FakeTokenStore('tok'),
      settings: settings,
    );
    container.read(settingsSyncProvider);
    await container.read(authControllerProvider.future);
    await _settle();

    settings.updateFailure = const NetworkFailure(
      code: FailureCode.networkServer,
    );
    await container.read(confidenceThresholdProvider.notifier).set(0.8);
    await _settle();
    expect(
      settings.updates.length,
      1,
      reason: 'settings updates must never be replayed automatically',
    );
  });
}
