/// Base URL of the optional StrumSight account backend.
///
/// Override at build time:
///   flutter run --dart-define=STRUMSIGHT_API_URL=https://api.example.com
///
/// Default targets the Android emulator's host loopback (10.0.2.2 == the dev
/// machine's localhost). Detection never uses this — it is the account layer
/// only, and the app is fully usable with no backend reachable.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'STRUMSIGHT_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Whether the optional account layer (login + settings sync) is available.
  /// OFF by default — there is no hosted backend yet, and a Sign-in button that
  /// always fails is worse than none. Turn on once the backend is deployed:
  ///   flutter build apk \
  ///     --dart-define=STRUMSIGHT_ACCOUNT=true \
  ///     --dart-define=STRUMSIGHT_API_URL=https://your-host.example
  static const bool accountEnabled = bool.fromEnvironment(
    'STRUMSIGHT_ACCOUNT',
    defaultValue: false,
  );

  /// Shared secret for the Lab-mode diagnostics endpoint (`POST /diagnostics`),
  /// sent as the `X-Diag-Token` header. This is NOT a user credential — it only
  /// gates the anonymous, opt-in diagnostics upload (Lab mode). Override the
  /// dev default for a real deployment:
  ///   flutter build apk --dart-define=STRUMSIGHT_DIAG_TOKEN=`your-secret`
  static const String diagToken = String.fromEnvironment(
    'STRUMSIGHT_DIAG_TOKEN',
    defaultValue: 'strumsight-lab-dev',
  );
}
