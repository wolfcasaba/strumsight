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

    test('rejects a staging-labelled host unconditionally (ADR 0445 D5)', () {
      // Feltétlen tiltás — nem csak akkor, ha egyben Lab-token is
      // használatban van (E12-R04 §0.0 R4).
      final problems = _problemsOf(
        () => _resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://staging.strumsight.app',
          accountEnabled: true,
        ),
      );
      expect(problems.single, contains('staging-labelled host'));
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

  group('staging-labelled host outside production', () {
    test('is accepted in lab and development (staging is backend-only, '
        'ADR 0445 D3)', () {
      for (final environment in [
        AppEnvironment.development,
        AppEnvironment.lab,
      ]) {
        expect(
          () => _resolve(
            environment: environment,
            apiBaseUrl: 'https://staging.strumsight.app',
            accountEnabled: true,
          ),
          returnsNormally,
          reason: '$environment must accept a staging-labelled host',
        );
      }
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

  group('practice rollout flags', () {
    test('environment defaults match the guarded rollout table', () {
      final development = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );
      expect(development.practiceEngineV2Enabled, isTrue);
      expect(development.migratedLearnEnabled, isTrue);
      expect(development.practiceDetailedHistoryEnabled, isTrue);

      final lab = FeatureFlags.forEnvironment(
        AppEnvironment.lab,
        accountEnabled: false,
      );
      expect(lab.practiceEngineV2Enabled, isTrue);
      expect(lab.migratedLearnEnabled, isTrue);
      expect(lab.practiceDetailedHistoryEnabled, isTrue);

      final production = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );
      expect(production.practiceEngineV2Enabled, isFalse);
      expect(production.migratedLearnEnabled, isFalse);
      expect(production.practiceDetailedHistoryEnabled, isFalse);
    });

    test(
      'rollout defaults resolve without configuration problems in every environment',
      () {
        for (final environment in AppEnvironment.values) {
          expect(
            () => _resolve(environment: environment),
            returnsNormally,
            reason: '$environment rollout defaults must form a valid config',
          );
        }
      },
    );

    test('new constructor fields are optional and part of value semantics', () {
      const defaults = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
      );
      expect(defaults.practiceEngineV2Enabled, isFalse);
      expect(defaults.migratedLearnEnabled, isFalse);
      expect(defaults.practiceDetailedHistoryEnabled, isFalse);

      const engine = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        practiceEngineV2Enabled: true,
      );
      const migrated = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        migratedLearnEnabled: true,
      );
      const detailedHistory = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        practiceDetailedHistoryEnabled: true,
      );
      const detailedHistoryCopy = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        practiceDetailedHistoryEnabled: true,
      );

      expect(engine, isNot(defaults));
      expect(migrated, isNot(defaults));
      expect(detailedHistory, isNot(defaults));
      expect(detailedHistoryCopy, detailedHistory);
      expect(detailedHistoryCopy.hashCode, detailedHistory.hashCode);
      expect(
        detailedHistory.hashCode,
        Object.hash(false, false, false, false, false, true),
      );
      expect(
        detailedHistory.toString(),
        allOf(
          contains('practiceEngineV2Enabled: false'),
          contains('migratedLearnEnabled: false'),
          contains('practiceDetailedHistoryEnabled: true'),
        ),
      );
    });

    test('migrated Learn fails closed without Practice Engine V2', () {
      final problems = _problemsOf(
        () => _resolve(
          apiBaseUrl: '',
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            migratedLearnEnabled: true,
          ),
        ),
      );

      expect(problems, hasLength(1));
      expect(problems.single, contains('migratedLearnEnabled'));
      expect(problems.single, contains('practiceEngineV2Enabled'));
    });

    test('detailed history fails closed without Practice Engine V2', () {
      final problems = _problemsOf(
        () => _resolve(
          apiBaseUrl: '',
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            practiceDetailedHistoryEnabled: true,
          ),
        ),
      );

      expect(problems, hasLength(1));
      expect(problems.single, contains('practiceDetailedHistoryEnabled'));
      expect(problems.single, contains('practiceEngineV2Enabled'));
    });

    test('collects both practice dependency violations in one pass', () {
      final problems = _problemsOf(
        () => _resolve(
          apiBaseUrl: '',
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            migratedLearnEnabled: true,
            practiceDetailedHistoryEnabled: true,
          ),
        ),
      );

      expect(
        problems,
        unorderedEquals([
          'migratedLearnEnabled requires practiceEngineV2Enabled.',
          'practiceDetailedHistoryEnabled requires practiceEngineV2Enabled.',
        ]),
      );
    });

    test('all practice flags stay offline when dependencies are valid', () {
      const flags = FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        practiceEngineV2Enabled: true,
        migratedLearnEnabled: true,
        practiceDetailedHistoryEnabled: true,
      );

      expect(flags.usesNetwork, isFalse);
      final config = _resolve(
        environment: AppEnvironment.production,
        apiBaseUrl: '',
        flags: flags,
      );
      expect(config.flags, same(flags));
    });
  });
}
