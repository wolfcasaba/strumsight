import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

// E01-R03 (SDD Ch2 Kör 3) — the mandated configuration tests: development,
// lab and production configs resolve; production is fail-closed on HTTP URLs,
// loopback hosts, dev/missing diagnostics tokens and Lab availability; with
// every network feature off no URL rule applies (nothing initialises an API).

AppConfig _resolve({
  AppEnvironment environment = AppEnvironment.development,
  String apiBaseUrl = AppConfig.devApiBaseUrl,
  FeatureFlags? flags,
  bool accountEnabled = false,
  String diagnosticsToken = AppConfig.devDiagnosticsToken,
}) {
  return AppConfig.resolve(
    environment: environment,
    apiBaseUrl: apiBaseUrl,
    flags:
        flags ??
        FeatureFlags.forEnvironment(
          environment,
          accountEnabled: accountEnabled,
        ),
    diagnosticsToken: diagnosticsToken,
    buildMode: 'debug',
    appVersion: '1.0.0+1',
  );
}

List<String> _problemsOf(void Function() act) {
  try {
    act();
  } on ConfigurationException catch (e) {
    return e.problems;
  }
  fail('expected ConfigurationException');
}

void main() {
  group('development configuration', () {
    test('resolves with the dev defaults (emulator loopback, dev token)', () {
      final config = _resolve();
      expect(config.environment, AppEnvironment.development);
      expect(config.apiBaseUrl, AppConfig.devApiBaseUrl);
      expect(config.flags.accountEnabled, isFalse);
      expect(config.flags.diagnosticsEnabled, isTrue);
      expect(config.flags.labModeAvailable, isTrue);
    });

    test('rejects a malformed URL even in development', () {
      final problems = _problemsOf(
        () => _resolve(apiBaseUrl: 'not a url', accountEnabled: true),
      );
      expect(problems.single, contains('not a valid http(s) URL'));
    });
  });

  group('lab configuration', () {
    test('resolves: diagnostics + Lab available, http loopback allowed', () {
      final config = _resolve(environment: AppEnvironment.lab);
      expect(config.flags.diagnosticsEnabled, isTrue);
      expect(config.flags.labModeAvailable, isTrue);
      expect(config.apiBaseUrl, AppConfig.devApiBaseUrl);
    });
  });

  group('production configuration', () {
    test('resolves with account on + HTTPS host + no diagnostics', () {
      final config = _resolve(
        environment: AppEnvironment.production,
        apiBaseUrl: 'https://api.strumsight.example',
        accountEnabled: true,
      );
      expect(config.flags.accountEnabled, isTrue);
      // forEnvironment: production never gets diagnostics/Lab by default.
      expect(config.flags.diagnosticsEnabled, isFalse);
      expect(config.flags.labModeAvailable, isFalse);
    });

    test('rejects an HTTP URL when the account is on', () {
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: 'http://api.strumsight.example',
          accountEnabled: true,
        ),
      );
      expect(problems.single, contains('HTTPS'));
    });

    test('rejects loopback/development hosts', () {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        final problems = _problemsOf(
          () => _resolve(
            environment: AppEnvironment.production,
            apiBaseUrl: 'https://$host:8000',
            accountEnabled: true,
          ),
        );
        expect(
          problems.single,
          contains('development host'),
          reason: 'host $host must be rejected',
        );
      }
    });

    test('rejects the development diagnostics token', () {
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.strumsight.example',
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: false,
          ),
        ),
      );
      expect(problems.single, contains('development token'));
    });

    test('rejects a missing (empty) diagnostics token', () {
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.strumsight.example',
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: false,
          ),
          diagnosticsToken: '  ',
        ),
      );
      expect(problems.single, contains('requires a STRUMSIGHT_DIAG_TOKEN'));
    });

    test('rejects Lab availability in a production artifact', () {
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: true,
          ),
        ),
      );
      expect(problems.single, contains('Lab mode'));
    });

    test('reports EVERY violated rule at once, not just the first', () {
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: 'http://localhost:8000',
          flags: const FeatureFlags(
            accountEnabled: true,
            diagnosticsEnabled: true,
            labModeAvailable: true,
          ),
        ),
      );
      expect(problems, hasLength(4)); // http + loopback + dev token + lab
    });

    test('with account off no API is initialised — the dev URL is unused '
        'and does not fail production', () {
      final config = _resolve(environment: AppEnvironment.production);
      expect(config.flags.usesNetwork, isFalse);
      // The offline production build keeps working with the compile-time
      // default URL because nothing will ever dial it.
      expect(config.apiBaseUrl, AppConfig.devApiBaseUrl);
    });
  });

  test('toString never leaks the URL or the token', () {
    final config = _resolve(
      environment: AppEnvironment.production,
      apiBaseUrl: 'https://secret-host.example',
      flags: const FeatureFlags(
        accountEnabled: true,
        diagnosticsEnabled: true,
        labModeAvailable: false,
      ),
      diagnosticsToken: 'super-secret-token',
    );
    expect(config.toString(), isNot(contains('secret')));
  });
}
