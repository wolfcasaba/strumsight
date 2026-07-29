import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:package_info_plus/package_info_plus.dart';

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

      final onboardingSeen =
          await (loadOnboardingSeen ?? OnboardingController.load)();

      return BootstrapSuccess(config: config, onboardingSeen: onboardingSeen);
    } on ConfigurationFailure catch (e) {
      return BootstrapFailure(e.problems);
    } catch (e) {
      // An unexpected boot error is still a controlled failure screen, not a
      // crash-before-first-frame.
      return BootstrapFailure(['Bootstrap failed: $e']);
    }
  }

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
