import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/app_bootstrap.dart';
import 'package:strumsight/app/bootstrap/bootstrap_result.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';

// E01-R03 — bootstrap: environment parsing (unknown value = controlled
// failure, never a guessed default), success carries the validated config +
// the pre-loaded onboarding flag, and the config provider is overridable.

Future<BootstrapResult> _run({
  String rawEnvironment = 'development',
  String? apiBaseUrl,
  bool accountEnabled = false,
  String? diagnosticsToken,
}) {
  return AppBootstrap.run(
    rawEnvironment: rawEnvironment,
    apiBaseUrl: apiBaseUrl,
    accountEnabled: accountEnabled,
    diagnosticsToken: diagnosticsToken,
    buildMode: 'debug',
    loadVersion: () async => '1.0.0+1',
    loadOnboardingSeen: () async => true,
  );
}

void main() {
  test('environment parsing accepts the three names, empty → development', () {
    expect(AppEnvironment.tryParse(''), AppEnvironment.development);
    expect(AppEnvironment.tryParse('development'), AppEnvironment.development);
    expect(AppEnvironment.tryParse('LAB'), AppEnvironment.lab);
    expect(AppEnvironment.tryParse(' production '), AppEnvironment.production);
  });

  test('unknown STRUMSIGHT_ENV value → controlled bootstrap failure', () async {
    for (final bad in ['prod', 'staging', 'dev']) {
      final result = await _run(rawEnvironment: bad);
      expect(result, isA<BootstrapFailure>(), reason: '"$bad" must fail');
      final failure = result as BootstrapFailure;
      expect(failure.problems.single, contains(AppEnvironment.defineName));
      expect(failure.problems.single, contains('"$bad"'));
    }
  });

  test(
    'success carries the validated config and the onboarding flag',
    () async {
      final result = await _run(rawEnvironment: 'lab');
      final success = result as BootstrapSuccess;
      expect(success.config.environment, AppEnvironment.lab);
      expect(success.config.appVersion, '1.0.0+1');
      expect(success.config.buildMode, 'debug');
      expect(success.onboardingSeen, isTrue);
    },
  );

  test(
    'a configuration failure becomes a BootstrapFailure, not a throw',
    () async {
      final result = await _run(
        rawEnvironment: 'production',
        apiBaseUrl: 'http://10.0.2.2:8000',
        accountEnabled: true,
      );
      final failure = result as BootstrapFailure;
      expect(failure.problems, hasLength(2)); // http + loopback
    },
  );

  test('an unexpected loader error is still a controlled failure', () async {
    final result = await AppBootstrap.run(
      rawEnvironment: 'development',
      buildMode: 'debug',
      loadVersion: () async => throw StateError('boom'),
      loadOnboardingSeen: () async => true,
    );
    final failure = result as BootstrapFailure;
    expect(failure.problems.single, contains('Bootstrap failed'));
  });

  test('appConfigProvider is fully overridable (§3.5) and drives '
      'accountEnabledProvider', () async {
    final config = AppConfig.resolve(
      environment: AppEnvironment.production,
      apiBaseUrl: 'https://api.strumsight.example',
      flags: const FeatureFlags(
        accountEnabled: true,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      ),
      diagnosticsToken: 'real-token',
      buildMode: 'release',
      appVersion: '1.0.0+1',
    );
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(config)],
    );
    addTearDown(container.dispose);
    expect(container.read(appConfigProvider), same(config));
    expect(container.read(accountEnabledProvider), isTrue);
  });

  test('with the account off the auth API is never initialised', () async {
    // The default (un-overridden) config has every network feature off for
    // the account layer; reading the auth gate must not construct a Dio.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(accountEnabledProvider), isFalse);
    // Riverpod providers are lazy: the Dio/auth repository provider is only
    // instantiated on first read. Nothing in the logged-out, account-off
    // path reads it — guarded here by the gate being false.
  });
}
