import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/foundation/app_result.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/logger_provider.dart';
import '../../core/storage/key_value_store.dart';
import '../../core/storage/shared_preferences_store.dart';
import '../../core/storage/storage_migrator.dart';
import '../../features/onboarding/onboarding_provider.dart';
import '../config/app_config.dart';
import '../config/app_environment.dart';
import '../config/feature_flags.dart';
import 'bootstrap_result.dart';

/// Boot-time configuration assembly (E01-R03, SDD Ch2 Kör 3 §3.4).
///
/// Reads the build's dart-defines, validates them into an [AppConfig] and
/// loads the platform state the first frame needs. Every failure mode returns
/// a [BootstrapFailure] — bootstrap never throws into `main` and never lets a
/// misconfigured app start.
///
/// All inputs are injectable so tests can exercise every branch; the defaults
/// are the real compile-time defines and platform loaders.
abstract final class AppBootstrap {
  static Future<BootstrapResult> run({
    String? rawEnvironment,
    String? apiBaseUrl,
    bool? accountEnabled,
    String? diagnosticsToken,
    String? buildMode,
    Future<String> Function()? loadVersion,
    Future<bool> Function()? loadOnboardingSeen,
    Future<AppResult<KeyValueStore>> Function()? openStore,
    List<StorageMigration> migrations = appStorageMigrations,
    AppLogger? logger,
  }) async {
    try {
      final raw = rawEnvironment ?? AppEnvironment.rawDefine;
      final environment = AppEnvironment.tryParse(raw);
      if (environment == null) {
        return BootstrapFailure([
          'Unknown ${AppEnvironment.defineName} value: "$raw". '
              'Expected one of: '
              '${AppEnvironment.values.map((e) => e.name).join(', ')}.',
        ]);
      }

      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: accountEnabled ?? AppConfig.rawAccountEnabled,
      );

      final config = AppConfig.resolve(
        environment: environment,
        apiBaseUrl: apiBaseUrl ?? AppConfig.rawApiBaseUrl,
        flags: flags,
        diagnosticsToken: diagnosticsToken ?? AppConfig.rawDiagnosticsToken,
        buildMode: buildMode ?? _buildMode,
        appVersion: await (loadVersion ?? _loadVersion)(),
      );

      // One SharedPreferences instance for the whole app (E01-R05 §5.1). A
      // device whose preference store cannot be opened would drop every write,
      // so it is a controlled failure screen — not an app that quietly forgets
      // the user's songs, streak and settings.
      final log = logger ?? createDefaultAppLogger();
      final storeResult = await (openStore ?? _openStore)();
      if (storeResult case Failure(:final error)) {
        log.error(
          'bootstrap.storage_unavailable',
          error: error,
          stackTrace: error.stackTrace ?? StackTrace.current,
        );
        return BootstrapFailure([
          'Local storage is unavailable (${error.code}). '
              'StrumSight cannot start without on-device persistence.',
        ]);
      }
      final store = (storeResult as Success<KeyValueStore>).value;

      // Migrations run before the first read, and a failing one is logged and
      // retried next boot rather than blocking the app (§5.3).
      await StorageMigrator(
        store: store,
        logger: log,
        migrations: migrations,
      ).migrate();

      // Read AFTER the migrations, so a build that renamed the key still sees
      // the returning user's flag rather than restarting onboarding.
      final onboardingSeen = loadOnboardingSeen == null
          ? OnboardingController.readSeen(store)
          : await loadOnboardingSeen();

      return BootstrapSuccess(
        config: config,
        onboardingSeen: onboardingSeen,
        keyValueStore: store,
      );
    } on ConfigurationException catch (e) {
      return BootstrapFailure(e.problems);
    } catch (e) {
      // An unexpected boot error is still a controlled failure screen, not a
      // crash-before-first-frame.
      return BootstrapFailure(['Bootstrap failed: $e']);
    }
  }

  static Future<AppResult<KeyValueStore>> _openStore() async =>
      (await SharedPreferencesStore.open()).map<KeyValueStore>((s) => s);

  static String get _buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  /// pubspec version via the platform channel; never fails the boot.
  static Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }
}
