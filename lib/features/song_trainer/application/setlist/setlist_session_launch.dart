// Javító sáv 2026-09-07 (R10, `docs/ui/apk-functionality-audit-2026-09-06.md`
// §5.2, "Setlist V2 lista + setlist-session bekötés"): the Setlist V2 list
// and the Setlist session screen both existed, but nothing in `lib/` ever
// turned a `SongSetlistItem` into the `SongTrainerControllerInputs` the
// session route needs — so a setlist could be edited and never played.
// This file is the missing application step: setlist item + its overrides
// → validated `TrainerConfig` → compiled trainer inputs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/loop_config.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../song_trainer_providers.dart';
import '../trainer/song_trainer_launcher.dart';
import '../trainer/song_trainer_setup_controller.dart';
import '../trainer/song_trainer_setup_state.dart';

/// Stable failure codes of [SetlistSessionCoordinator.prepareItem].
abstract final class SetlistItemLaunchFailureCode {
  /// The referenced song is not in the repository any more.
  static const String songMissing = 'setlistItemLaunch.songMissing';

  /// The song exists but offers no runnable scoring lane (no enabled,
  /// compatible track), so the setup could not produce a config.
  static const String notTrainable = 'setlistItemLaunch.notTrainable';

  /// The item pins a track the stored document no longer has.
  static const String trackUnavailable = 'setlistItemLaunch.trackUnavailable';

  /// The item pins a range that does not resolve inside the song.
  static const String rangeUnavailable = 'setlistItemLaunch.rangeUnavailable';
}

/// Maps a [prepareItem] failure onto the per-item readiness vocabulary the
/// Setlist session and its badges already speak, so a failed item is NAMED
/// on screen instead of quietly disappearing from the run.
SetlistItemAvailability setlistAvailabilityForFailure(String code) {
  if (code == SetlistItemLaunchFailureCode.songMissing) {
    return SetlistItemAvailability.missingSong;
  }
  if (code == SetlistItemLaunchFailureCode.trackUnavailable) {
    return SetlistItemAvailability.unsupportedTrack;
  }
  return SetlistItemAvailability.invalidConfig;
}

/// Turns one ordered setlist item into the inputs the Song Trainer session
/// route needs. Pure application logic — no navigation, no `BuildContext`.
///
/// The item's overrides are applied on TOP of the setup controller's own
/// validated defaults rather than instead of them: track selection, range
/// resolution and the scoring-lane capability matrix stay the setup
/// controller's job (one rule, one place), while speed, count-in, loop
/// count, capo and track pin come from the setlist.
final class SetlistSessionCoordinator {
  const SetlistSessionCoordinator({
    required this.songRepository,
    required this.launcher,
  });

  final SongRepository songRepository;
  final SongTrainerLauncher launcher;

  Future<AppResult<SongTrainerControllerInputs>> prepareItem(
    SongSetlistItem item,
  ) async {
    final config = await configFor(item);
    switch (config) {
      case Failure<TrainerConfig>(:final error):
        return Failure<SongTrainerControllerInputs>(error);
      case Success<TrainerConfig>(:final value):
        return launcher.prepare(value);
    }
  }

  /// The validated session config for [item], overrides applied.
  ///
  /// Public on purpose: it is the step where the setlist's stored overrides
  /// meet the trainer's own limits, so it has to be measurable on its own
  /// rather than only through a launched session.
  Future<AppResult<TrainerConfig>> configFor(SongSetlistItem item) async {
    final controller = SongTrainerSetupController(repository: songRepository);
    try {
      await controller.load(item.songId);
      final state = controller.state;
      if (state.status != SongTrainerSetupStatus.ready) {
        final missing = state.failureCode == SongRepositoryErrorCode.notFound;
        if (missing) {
          return _failure(SetlistItemLaunchFailureCode.songMissing);
        }
        return _failure(SetlistItemLaunchFailureCode.notTrainable);
      }
      final overrides = item.overrides;
      final pinnedTrack = overrides.trackId;
      if (pinnedTrack != null && !controller.selectTrack(pinnedTrack)) {
        return _failure(SetlistItemLaunchFailureCode.trackUnavailable);
      }
      if (!controller.selectRange(overrides.range)) {
        return _failure(SetlistItemLaunchFailureCode.rangeUnavailable);
      }
      final base = controller.complete();
      if (base == null) {
        return _failure(SetlistItemLaunchFailureCode.notTrainable);
      }
      final loops = overrides.loopCount > 1 ? overrides.loopCount : null;
      final config = TrainerConfig(
        songId: base.songId,
        songRevision: base.songRevision,
        trackId: base.trackId,
        selection: base.selection,
        range: base.range,
        mode: base.mode,
        // The setlist editor accepts any positive multiplier; the trainer
        // supports 0.5–1.5. Clamping is the honest reading of an
        // out-of-range stored value — refusing to run the item over a speed
        // preference would be a worse answer than running it at the nearest
        // supported speed.
        targetSpeed: _clampSpeed(overrides.speedMultiplier),
        countInBars: overrides.countInBars,
        metronomeEnabled: base.metronomeEnabled,
        loopConfig: LoopConfig(range: base.range, maxRepeats: loops),
        tuningReminder: base.tuningReminder,
        capo: overrides.capoOverride ?? base.capo,
        capoReminder: base.capoReminder,
      );
      return Success<TrainerConfig>(config);
    } finally {
      controller.dispose();
    }
  }
}

Failure<TrainerConfig> _failure(String code) {
  return Failure<TrainerConfig>(StorageFailure(code: code));
}

double _clampSpeed(double value) {
  if (!value.isFinite) return TrainerConfig.defaultSpeed;
  if (value < TrainerConfig.minimumSpeed) return TrainerConfig.minimumSpeed;
  if (value > TrainerConfig.maximumSpeed) return TrainerConfig.maximumSpeed;
  return value;
}

/// Production coordinator over the bootstrap-provided song repository.
final setlistSessionCoordinatorProvider = Provider<SetlistSessionCoordinator>((
  ref,
) {
  return SetlistSessionCoordinator(
    songRepository: ref.watch(songRepositoryProvider),
    launcher: ref.watch(songTrainerLauncherProvider),
  );
});
