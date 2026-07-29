import '../../core/storage/key_value_store.dart';
import '../config/app_config.dart';

/// Outcome of `AppBootstrap.run` (E01-R03). `main` switches on this: success
/// launches the app with the validated config injected; failure launches the
/// minimal failure screen — never a half-configured app.
sealed class BootstrapResult {
  const BootstrapResult();
}

final class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess({
    required this.config,
    required this.onboardingSeen,
    required this.keyValueStore,
  });

  final AppConfig config;

  /// The persisted first-run flag, loaded before the first frame so the
  /// router can gate on it synchronously (no onboarding flicker).
  final bool onboardingSeen;

  /// The opened, migrated preference store (E01-R05). `main` injects it into
  /// `keyValueStoreProvider`; nothing else may open one.
  final KeyValueStore keyValueStore;
}

final class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure(this.problems);

  /// One entry per violated configuration rule.
  final List<String> problems;
}
