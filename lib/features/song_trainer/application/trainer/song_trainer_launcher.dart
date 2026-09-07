// Javító sáv 2026-09-06 (R3, `docs/ui/apk-functionality-audit-2026-09-06.md`
// §1.3): the shipped Song Trainer never ran. `TrainerSetupScreen`'s Start
// button hands a completed `TrainerConfig` to `onComplete`, but the router
// registered the screen WITHOUT a handler, and the session route
// (`/song-trainer/session/:songId`) requires `SongTrainerControllerInputs` as
// `extra` — which nothing in `lib/` ever built. This is the missing step:
// document → practice compilation → controller inputs.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../song_trainer_providers.dart';
import 'song_practice_compiler.dart';

/// Stable failure codes of [SongTrainerLauncher.prepare].
abstract final class SongTrainerLaunchFailureCode {
  /// The song the config was built for is no longer in the repository.
  static const String songMissing = 'songTrainerLaunch.songMissing';

  /// The config no longer matches the stored document (revision moved, the
  /// track or the range disappeared) — the setup has to be redone.
  static const String staleConfig = 'songTrainerLaunch.staleConfig';
}

/// Turns a completed setup [TrainerConfig] into the inputs the session route
/// needs. Pure application logic over the song repository — no navigation.
final class SongTrainerLauncher {
  const SongTrainerLauncher({required SongRepository songRepository})
    : _songRepository = songRepository; // ignore: prefer_initializing_formals

  final SongRepository _songRepository;

  Future<AppResult<SongTrainerControllerInputs>> prepare(
    TrainerConfig config,
  ) async {
    final loaded = await _songRepository.get(config.songId);
    switch (loaded) {
      case Failure<SongDocument?>(:final error):
        return Failure<SongTrainerControllerInputs>(error);
      case Success<SongDocument?>(value: null):
        return const Failure<SongTrainerControllerInputs>(
          StorageFailure(code: SongTrainerLaunchFailureCode.songMissing),
        );
      case Success<SongDocument?>(:final value?):
        return compile(document: value, config: config);
    }
  }

  /// The synchronous half of [prepare]: the compiler's identity / track /
  /// range checks throw [ArgumentError] on a config the document no longer
  /// supports — surfaced as [SongTrainerLaunchFailureCode.staleConfig], never
  /// as a crash on the Start button.
  static AppResult<SongTrainerControllerInputs> compile({
    required SongDocument document,
    required TrainerConfig config,
  }) {
    final SongPracticeCompilation compilation;
    try {
      compilation = SongPracticeCompiler.compile(
        document: document,
        config: config,
      );
    } on ArgumentError catch (error) {
      return Failure<SongTrainerControllerInputs>(
        StorageFailure(
          code: SongTrainerLaunchFailureCode.staleConfig,
          cause: error,
        ),
      );
    }
    return Success<SongTrainerControllerInputs>(
      SongTrainerControllerInputs(
        compilation: compilation,
        backingAsset: backingAssetOf(document),
        config: config,
      ),
    );
  }

  /// The asset the document's first backing-audio track references, or
  /// `null` when there is no backing track or its asset is not attached
  /// (the setup screen shows that case as "missing backing asset").
  static SongAssetReference? backingAssetOf(SongDocument document) {
    for (final track in document.tracks) {
      if (track is! BackingAudioTrack) continue;
      for (final asset in document.assets) {
        if (asset.id == track.assetId) return asset;
      }
    }
    return null;
  }
}

/// Production launcher over the bootstrap-provided song repository.
final songTrainerLauncherProvider = Provider<SongTrainerLauncher>((ref) {
  return SongTrainerLauncher(songRepository: ref.watch(songRepositoryProvider));
});
