/// DEPRECATED compatibility layer (E01-R03 §3.6).
///
/// The validated boot-time configuration lives in
/// `lib/app/config/app_config.dart` (`AppConfig` + `appConfigProvider`), which
/// every in-tree consumer now uses. This shim only keeps any out-of-tree code
/// compiling until it migrates; it will be REMOVED once Epic 1's config
/// migration completes (tracked by SDD Ch2 Kör 3 §3.6 — no separate issue).
@Deprecated('Use AppConfig via appConfigProvider (lib/app/config/).')
class ApiConfig {
  const ApiConfig._();

  @Deprecated('Use AppConfig.rawApiBaseUrl / appConfigProvider apiBaseUrl.')
  static const String baseUrl = String.fromEnvironment(
    'STRUMSIGHT_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  @Deprecated('Use appConfigProvider flags.accountEnabled.')
  static const bool accountEnabled = bool.fromEnvironment('STRUMSIGHT_ACCOUNT');

  @Deprecated('Use appConfigProvider diagnosticsToken.')
  static const String diagToken = String.fromEnvironment(
    'STRUMSIGHT_DIAG_TOKEN',
    defaultValue: 'strumsight-lab-dev',
  );
}
