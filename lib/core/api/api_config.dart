import '../../app/config/app_config.dart';

/// DEPRECATED compatibility layer (E01-R03 §3.6).
///
/// The validated boot-time configuration lives in
/// `lib/app/config/app_config.dart` (`AppConfig` + `appConfigProvider`), which
/// every in-tree consumer now uses. This shim only keeps any out-of-tree code
/// compiling until it migrates; it will be REMOVED once Epic 1's config
/// migration completes (tracked by SDD Ch2 Kör 3 §3.6 — no separate issue).
///
/// Every define name and default below is re-exported from [AppConfig] rather
/// than re-typed (WP-G, 2026-09-06): a second literal copy of
/// `http://10.0.2.2:8000` here was a second source of truth that could drift
/// from the one the app actually boots on.
///
/// These raw values are NOT the shipped development configuration: a
/// development build with no `STRUMSIGHT_API_URL` define resolves
/// [AppConfig.liveApiBaseUrl] through `AppConfig.apiBaseUrlFor`, and its
/// account layer defaults ON through `FeatureFlags.forShippedBuild`.
@Deprecated('Use AppConfig via appConfigProvider (lib/app/config/).')
class ApiConfig {
  const ApiConfig._();

  @Deprecated('Use AppConfig.apiBaseUrlFor / appConfigProvider apiBaseUrl.')
  static const String baseUrl = AppConfig.rawApiBaseUrl;

  @Deprecated('Use appConfigProvider flags.accountEnabled.')
  static const bool accountEnabled = AppConfig.rawAccountEnabled;

  @Deprecated('Use appConfigProvider diagnosticsToken.')
  static const String diagToken = AppConfig.rawDiagnosticsToken;
}
