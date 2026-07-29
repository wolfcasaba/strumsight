import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'app/bootstrap/bootstrap_result.dart';
import 'app/config/app_config.dart';
import 'app/strumsight_app.dart';
import 'core/storage/storage_providers.dart';
import 'features/onboarding/onboarding_provider.dart';

export 'app/strumsight_app.dart' show StrumSightApp;

/// Minimal by design (E01-R03 §3.4): binding → bootstrap → run the app with
/// the validated config injected, or the failure screen. Everything else
/// (config validation, platform loads) lives in [AppBootstrap].
Future<void> main() async {
  // StrumSight is fully offline / on-device by default — no backend init here.
  WidgetsFlutterBinding.ensureInitialized();
  final result = await AppBootstrap.run();
  runApp(switch (result) {
    BootstrapFailure(:final problems) => BootstrapFailureApp(
      problems: problems,
    ),
    BootstrapSuccess(
      :final config,
      :final onboardingSeen,
      :final keyValueStore,
    ) =>
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          keyValueStoreProvider.overrideWithValue(keyValueStore),
          onboardingSeenProvider.overrideWith(
            () => OnboardingController(onboardingSeen),
          ),
        ],
        child: const StrumSightApp(),
      ),
  });
}
