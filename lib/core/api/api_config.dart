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
}
