import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/foundation/app_failure.dart';

import 'app_environment.dart';
import 'feature_flags.dart';

/// A configuration problem found by [AppConfig.resolve]. Controlled failure:
/// bootstrap catches it and shows the failure screen instead of launching a
/// misconfigured app (fail-closed).
///
/// Named `…Exception` because it is thrown; the corresponding *value* type in
/// the unified taxonomy is `ConfigurationFailure` (E01-R04,
/// `core/foundation/app_failure.dart`) — see [asFailure].
final class ConfigurationException implements Exception {
  const ConfigurationException(this.problems);

  /// Human-readable problems, one per violated rule.
  final List<String> problems;

  /// The same problem as an [AppFailure], for code that reports results
  /// instead of throwing.
  ConfigurationFailure asFailure([StackTrace? stackTrace]) =>
      ConfigurationFailure(cause: this, stackTrace: stackTrace);

  @override
  String toString() => 'ConfigurationException: ${problems.join('; ')}';
}

/// Validated application configuration (E01-R03, SDD Ch2 Kör 3 §3.3).
///
/// Built once during bootstrap via [AppConfig.resolve] and injected through
/// [appConfigProvider]. Detection stays 100% on-device regardless of anything
/// here — this configures the OPTIONAL account/diagnostics layers and guards
/// the availability stages of the on-device Practice rollout.
final class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.flags,
    required this.diagnosticsToken,
    required this.buildMode,
    required this.appVersion,
  });

  /// The dart-define names + compile-time raw values for this build.
  static const String apiUrlDefine = 'STRUMSIGHT_API_URL';
  static const String accountDefine = 'STRUMSIGHT_ACCOUNT';
  static const String diagTokenDefine = 'STRUMSIGHT_DIAG_TOKEN';

  /// Android-emulator host loopback — the default for a `lab` (and, without
  /// a define, a `production`) build. It is NOT the development default any
  /// more; see [defaultApiBaseUrl].
  static const String devApiBaseUrl = 'http://10.0.2.2:8000';

  /// The live StrumSight backend (WP-G, 2026-09-06). The tester APK is the
  /// one `.github/workflows/build-apk.yml` builds, and that protected
  /// workflow passes only `--dart-define=STRUMSIGHT_ENV=development` — so a
  /// development build with no `STRUMSIGHT_API_URL` define talks to the live
  /// backend instead of an emulator loopback that a real device cannot
  /// reach. An emulator developer passes the loopback explicitly:
  ///
  /// ```bash
  /// flutter run --dart-define=STRUMSIGHT_API_URL=http://10.0.2.2:8000
  /// ```
  static const String liveApiBaseUrl = 'https://casaba.app/strumsight';

  /// The shared dev secret for the Lab diagnostics endpoint. A production
  /// build with diagnostics may NOT ship this value.
  static const String devDiagnosticsToken = 'strumsight-lab-dev';

  static const String rawApiBaseUrl = String.fromEnvironment(
    apiUrlDefine,
    defaultValue: devApiBaseUrl,
  );
  static const bool rawAccountEnabled = bool.fromEnvironment(accountDefine);
  static const String rawDiagnosticsToken = String.fromEnvironment(
    diagTokenDefine,
    defaultValue: devDiagnosticsToken,
  );

  /// The `STRUMSIGHT_API_URL` value this build was given, or `null` when the
  /// define is ABSENT. `String.fromEnvironment` cannot express that
  /// difference (an absent define is indistinguishable from its
  /// `defaultValue`), so presence is measured with `bool.hasEnvironment` —
  /// the same const-compatible mechanism `feature_flags.dart` uses.
  static const String? definedApiBaseUrl = bool.hasEnvironment(apiUrlDefine)
      ? String.fromEnvironment(apiUrlDefine)
      : null;

  /// The `STRUMSIGHT_ACCOUNT` value this build was given, or `null` when the
  /// define is ABSENT (`bool.fromEnvironment` reads an absent define and an
  /// explicit `false` identically). `FeatureFlags.forShippedBuild` needs the
  /// difference: only an ABSENT define hands the decision to the
  /// environment.
  static const bool? definedAccountEnabled = bool.hasEnvironment(accountDefine)
      ? rawAccountEnabled
      : null;

  /// The API base URL a build that passed NO `STRUMSIGHT_API_URL` uses:
  /// [liveApiBaseUrl] for the development (tester) build, the unchanged
  /// emulator loopback everywhere else.
  static String defaultApiBaseUrl(AppEnvironment environment) =>
      environment == AppEnvironment.development
      ? liveApiBaseUrl
      : devApiBaseUrl;

  /// The resolved API base URL: an explicit `STRUMSIGHT_API_URL` define
  /// always wins, in every environment; only its absence falls back to
  /// [defaultApiBaseUrl]. [define] is injectable so the resolution is
  /// testable — a dart-define cannot be varied inside `flutter test`.
  static String apiBaseUrlFor(
    AppEnvironment environment, {
    String? define = definedApiBaseUrl,
  }) => define ?? defaultApiBaseUrl(environment);

  final AppEnvironment environment;

  /// Base URL of the optional account/diagnostics backend. Only meaningful
  /// when [FeatureFlags.usesNetwork]; an offline build never touches it.
  final String apiBaseUrl;

  final FeatureFlags flags;

  /// `X-Diag-Token` for the Lab diagnostics endpoint. NOT a user credential —
  /// it gates the anonymous, opt-in diagnostics upload only.
  final String diagnosticsToken;

  /// `debug` / `profile` / `release` (informational, e.g. diagnostics headers).
  final String buildMode;

  /// `version+build` from pubspec.yaml via package_info_plus, or `unknown`.
  final String appVersion;

  /// Validate and build the config. Throws [ConfigurationException] listing
  /// EVERY violated rule (not just the first) so a misconfigured build is
  /// fixed in one pass.
  ///
  /// In every environment, migrated Learn and detailed Practice history require
  /// Practice Engine V2 to be available.
  ///
  /// Production is fail-closed (§3.3):
  /// - any network-using flag ⇒ the URL must be a well-formed **https** URL,
  ///   must not point at a loopback (`localhost`, `127.0.0.1`, `10.0.2.2`),
  ///   and its host must not contain the `staging` substring — staging is a
  ///   backend-only deployment target, not a client build (ADR 0445 D3/D5);
  /// - diagnostics on ⇒ the token must be non-empty and not the dev default;
  /// - Lab mode must not be available in a production artifact (§14.5 — the
  ///   diagnostics device build is [AppEnvironment.lab]).
  ///
  /// Outside production the defaults are exactly what you want (the live
  /// backend for the development tester build — [defaultApiBaseUrl] — the
  /// emulator loopback for lab, and the dev token), but a *malformed* URL is
  /// still rejected — a typo'd `--dart-define=STRUMSIGHT_API_URL=...` should
  /// fail in development too, where it's cheap. Loopback and staging hosts
  /// stay accepted outside production and rejected inside it, unchanged by
  /// WP-G.
  static AppConfig resolve({
    required AppEnvironment environment,
    required String apiBaseUrl,
    required FeatureFlags flags,
    required String diagnosticsToken,
    required String buildMode,
    required String appVersion,
  }) {
    final problems = <String>[];
    final isProd = environment == AppEnvironment.production;

    if (flags.migratedLearnEnabled && !flags.practiceEngineV2Enabled) {
      problems.add('migratedLearnEnabled requires practiceEngineV2Enabled.');
    }

    if (flags.practiceDetailedHistoryEnabled &&
        !flags.practiceEngineV2Enabled) {
      problems.add(
        'practiceDetailedHistoryEnabled requires practiceEngineV2Enabled.',
      );
    }

    if (flags.usesNetwork) {
      final uri = Uri.tryParse(apiBaseUrl);
      final wellFormed =
          uri != null &&
          uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      if (apiBaseUrl.trim().isEmpty) {
        problems.add('$apiUrlDefine is empty but a network feature is on.');
      } else if (!wellFormed) {
        problems.add('$apiUrlDefine is not a valid http(s) URL: "$apiBaseUrl"');
      } else if (isProd) {
        if (uri.scheme != 'https') {
          problems.add('production requires an HTTPS $apiUrlDefine.');
        }
        const loopbacks = {'localhost', '127.0.0.1', '10.0.2.2'};
        if (loopbacks.contains(uri.host)) {
          problems.add(
            'production must not point at a development host '
            '("${uri.host}").',
          );
        }
        // Staging is a BACKEND deployment target, not a client build
        // (ADR 0445 D3/D5) — a production artifact must never resolve one,
        // unconditionally (not only when a Lab token is also in play).
        if (uri.host.toLowerCase().contains('staging')) {
          problems.add(
            'production must not point at a staging-labelled host '
            '("${uri.host}").',
          );
        }
      }
    }

    if (isProd && flags.diagnosticsEnabled) {
      if (diagnosticsToken.trim().isEmpty) {
        problems.add('production diagnostics requires a $diagTokenDefine.');
      } else if (diagnosticsToken == devDiagnosticsToken) {
        problems.add(
          'production diagnostics must not use the development token.',
        );
      }
    }

    if (isProd && flags.labModeAvailable) {
      problems.add(
        'Lab mode must not be available in a production artifact '
        '(build the lab environment instead).',
      );
    }

    if (problems.isNotEmpty) throw ConfigurationException(problems);

    return AppConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      flags: flags,
      diagnosticsToken: diagnosticsToken,
      buildMode: buildMode,
      appVersion: appVersion,
    );
  }

  @override
  String toString() =>
      'AppConfig(${environment.name}, $flags, $buildMode, '
      '$appVersion)'; // never prints the URL or token
}

/// The app-wide [AppConfig]. `main` overrides this with the bootstrap-validated
/// config; the default is a permissive development config so widget tests that
/// don't care about configuration keep working — override it in tests that do
/// (§3.5: fully overridable).
///
/// This default is TEST SCAFFOLDING, not the shipped development
/// configuration: it deliberately keeps calling
/// [FeatureFlags.forEnvironment] (the rollout boundary, account off,
/// Community off, no preview overlay) so that the hundreds of widget tests
/// reading it keep measuring one fixed, minimal flag set. The artifact a
/// tester installs is assembled by `AppBootstrap.run` through
/// [FeatureFlags.forShippedBuild] + [AppConfig.apiBaseUrlFor] (WP-G).
final appConfigProvider = Provider<AppConfig>(
  (_) => AppConfig(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: FeatureFlags.forEnvironment(
      AppEnvironment.development,
      accountEnabled: false,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'debug',
    appVersion: 'test',
  ),
);
