import '../config/app_config.dart';

/// Outcome of `AppBootstrap.run` (E01-R03). `main` switches on this: success
/// launches the app with the validated config injected; failure launches the
/// minimal failure screen — never a half-configured app.
sealed class BootstrapResult {
  const BootstrapResult();
}

final class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess({required this.config, required this.onboardingSeen});

  final AppConfig config;

  /// The persisted first-run flag, loaded before the first frame so the
  /// router can gate on it synchronously (no onboarding flicker).
  final bool onboardingSeen;
}

final class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure(this.problems);

  /// One entry per violated configuration rule.
  final List<String> problems;
}
