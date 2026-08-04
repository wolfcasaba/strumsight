import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'app/bootstrap/bootstrap_result.dart';
import 'app/config/app_config.dart';
import 'app/strumsight_app.dart';
import 'core/storage/key_value_store.dart';
import 'core/storage/storage_providers.dart';
import 'features/diagnostics/providers/diagnostics_providers.dart';
import 'features/onboarding/onboarding_provider.dart';
import 'features/settings/providers/lab_mode_provider.dart';
import 'features/song_trainer/application/song_trainer_providers.dart';
import 'features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'features/song_trainer/domain/repositories/song_repository.dart';

export 'app/strumsight_app.dart' show StrumSightApp;

/// Minimal by design (E01-R03 §3.4): binding → bootstrap → run the app with
/// the validated config injected, or the failure screen. Everything else
/// (config validation, platform loads) lives in [AppBootstrap].
Future<void> main() async {
  // StrumSight is fully offline / on-device by default — no backend init here.
  WidgetsFlutterBinding.ensureInitialized();
  final result = await AppBootstrap.run();
  switch (result) {
    case BootstrapFailure(:final problems):
      runApp(BootstrapFailureApp(problems: problems));
    case BootstrapSuccess(
      :final config,
      :final onboardingSeen,
      :final keyValueStore,
    ):
      await _runAppWithSongTrainerRepositories(
        config: config,
        onboardingSeen: onboardingSeen,
        keyValueStore: keyValueStore,
      );
  }
}

Future<void> _runAppWithSongTrainerRepositories({
  required AppConfig config,
  required bool onboardingSeen,
  required KeyValueStore keyValueStore,
}) async {
  final bootstrapContainer = ProviderContainer();
  try {
    final SongRepository repository = await bootstrapContainer.read(
      songRepositoryBootProvider.future,
    );
    final SongAssetRepository assetRepository = await bootstrapContainer.read(
      songAssetRepositoryBootProvider.future,
    );
    runApp(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          keyValueStoreProvider.overrideWithValue(keyValueStore),
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(assetRepository),
          diagnosticsConsentProvider.overrideWith(
            (ref) => ref.watch(labModeProvider),
          ),
          onboardingSeenProvider.overrideWith(
            () => OnboardingController(onboardingSeen),
          ),
        ],
        child: const StrumSightApp(),
      ),
    );
  } finally {
    bootstrapContainer.dispose();
  }
}
