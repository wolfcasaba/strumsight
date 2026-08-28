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
///
/// **Staging is NOT a value of this enum** (ADR 0445 D3). It is a
/// backend-only deployment target: the client reaches it by pointing a
/// [development] or [lab] build's `STRUMSIGHT_API_URL` at the staging
/// backend, not by a fourth client flavor. [AppConfig.resolve] still refuses
/// a [production] build whose `apiBaseUrl` host names staging (ADR 0445 D5).
///
/// The backend's own `STRUMSIGHT_ENV` value set (`backend/app/config.py`,
/// ADR 0445 D1-D2) is `dev | lab | staging | prod` — a superset of this
/// enum's names, normalized at instantiation via aliases:
///
/// | Client build (this enum) | Backend `STRUMSIGHT_ENV` |
/// |---|---|
/// | [development] | `dev` (also accepts alias `development`) |
/// | [lab] | `lab` |
/// | *(no client build — backend-only)* | `staging` |
/// | [production] | `prod` (also accepts alias `production`) |
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
