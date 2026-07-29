/// Which environment this build is configured for (E01-R03, SDD Ch2 Kör 3).
///
/// Selected at build time:
///
/// ```bash
/// flutter build apk --dart-define=STRUMSIGHT_ENV=production
/// ```
///
/// Absent define → [development]. An *unknown* value is NOT coerced to a
/// default — [tryParse] returns null and bootstrap turns that into a
/// controlled configuration failure (a typo like `STRUMSIGHT_ENV=prod` must
/// surface loudly, not silently ship a development config).
enum AppEnvironment {
  /// Local development: emulator loopback API default, diagnostics and Lab
  /// mode available, permissive validation.
  development,

  /// The user-facing diagnostics build (Lab APK): like development but meant
  /// for a real device; diagnostics upload + Lab mode available.
  lab,

  /// Store/production build: fail-closed validation — see `AppConfig.resolve`.
  production;

  /// The dart-define name.
  static const String defineName = 'STRUMSIGHT_ENV';

  /// The value the [defineName] dart-define carries in this build
  /// (compile-time constant; empty string means "not provided").
  static const String rawDefine = String.fromEnvironment(defineName);

  /// Parse a raw define value. Empty/absent → [development]. Unknown → null
  /// (the caller must fail, not guess).
  static AppEnvironment? tryParse(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return AppEnvironment.development;
    for (final env in AppEnvironment.values) {
      if (env.name == v) return env;
    }
    return null;
  }
}
