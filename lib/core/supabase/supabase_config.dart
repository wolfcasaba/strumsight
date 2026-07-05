/// Supabase connection config for the music-theory backend (configure via --dart-define once chosen).
///
/// Values are injected at build time via --dart-define so NO key is ever
/// committed to source:
///   flutter build web --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// The project URL is public and defaulted. The anon key (the same PUBLIC
/// legacy-JWT anon key the web app ships) must be provided; when it's missing
/// the app runs in "mock mode" (no backend calls) — how design previews run.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// True only when a key has been supplied — gates real backend wiring.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// Dev-only auto-login (for previews/screenshots). Supplied via --dart-define;
  /// NEVER committed. Lets a headless build show real per-user data without
  /// typing into CanvasKit text fields.
  static const String debugEmail = String.fromEnvironment(
    'DEBUG_EMAIL',
    defaultValue: '',
  );
  static const String debugPassword = String.fromEnvironment(
    'DEBUG_PASSWORD',
    defaultValue: '',
  );
  static bool get hasDebugLogin =>
      debugEmail.isNotEmpty && debugPassword.isNotEmpty;
}
