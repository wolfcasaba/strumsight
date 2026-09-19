/// Composition root for the Setlist V2 session (E17-R03, ADR 0585 D3/D4).
///
/// Both the availability resolver and the item runners built here close over
/// the SHIPPED trainer pipeline (`SongRepository`, `SongTrainerSessionLauncher`,
/// `SongTrainerSessionRoute`) — nothing here invents a new song-loading or
/// scoring path, and none of it touches `SetlistSessionController`'s own
/// semantics.
library;

import 'package:flutter/material.dart';
import 'package:strumsight/features/practice/public.dart'
    show PracticeFinishReason;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/music/tuning.dart';
import '../../domain/models/loop_config.dart';
import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../../presentation/screens/song_trainer_session_route.dart';
import '../trainer/song_trainer_session_launcher.dart';
import 'setlist_session_controller.dart';

/// Builds the sync availability resolver (D3, layer 1) from a ONE-TIME
/// [SongRepository.list] snapshot taken when the setlist session starts. A
/// setlist item whose song is missing from the snapshot, or present but
/// trashed, is `missingSong`; every other item starts `ready` — deeper
/// failures (a stale revision, an uncompilable track) are only knowable by
/// actually trying to launch, which is the runner's job (layer 2). This
/// never returns a constant `ready`: an empty snapshot marks every item
/// `missingSong`.
SetlistAvailabilityResolver buildSetlistAvailabilityResolver(
  List<SongSummary> snapshot,
) {
  final bySongId = <String, SongSummary>{
    for (final summary in snapshot) summary.documentId.value: summary,
  };
  return (item) {
    final summary = bySongId[item.songId.value];
    if (summary == null || summary.trashed) {
      return SetlistItemAvailability.missingSong;
    }
    return SetlistItemAvailability.ready;
  };
}

/// Loads the ONE-TIME index snapshot [buildSetlistAvailabilityResolver]
/// locks over. `includeTrashed` is required so a trashed song is visible
/// (and excluded) instead of looking identical to a missing one.
Future<List<SongSummary>> loadSetlistAvailabilitySnapshot(
  SongRepository repository,
) => repository.list(const SongQuery(includeTrashed: true));

/// Builds the scored Practice runner (D3 layer 2 + D4).
///
/// `TrainerMode.rhythm` is the broadest-compatible scoring lane — chord,
/// strum AND note tracks all compile a scored definition under it
/// (`SongPracticeCompiler._profileFor`) — so any real scorable track
/// produces an actual scored session, never a synthesized one.
SetlistItemRunner buildSetlistPracticeRunner({
  required BuildContext context,
  required SongRepository repository,
  required SongTrainerSessionLauncher launcher,
}) =>
    (item) => _runSetlistItem(
      context: context,
      repository: repository,
      launcher: launcher,
      item: item,
      mode: TrainerMode.rhythm,
    );

/// Builds the playback-only Performance runner (D3 layer 2).
///
/// `TrainerMode.pitch` forces `SongPracticeCompiler.compile` to return a
/// playback-only compilation unconditionally (its very first branch) — no
/// `PracticeSessionController`, so no scored Practice session and no
/// microphone, matching `SetlistSessionController`'s own contract
/// ("Performance ... never constructs a scoring runner on this boundary").
SetlistItemRunner buildSetlistPerformanceRunner({
  required BuildContext context,
  required SongRepository repository,
  required SongTrainerSessionLauncher launcher,
}) =>
    (item) => _runSetlistItem(
      context: context,
      repository: repository,
      launcher: launcher,
      item: item,
      mode: TrainerMode.pitch,
    );

Future<SetlistItemResult> _runSetlistItem({
  required BuildContext context,
  required SongRepository repository,
  required SongTrainerSessionLauncher launcher,
  required SongSetlistItem item,
  required TrainerMode mode,
}) async {
  final loaded = await repository.get(item.songId);
  final SongDocument? document = switch (loaded) {
    Success(:final value) => value,
    Failure() => null,
  };
  if (document == null) {
    return SetlistItemResult.skipped(
      itemId: item.id,
      availability: SetlistItemAvailability.missingSong,
    );
  }
  final config = _trainerConfigFor(item: item, document: document, mode: mode);
  if (config == null) {
    return SetlistItemResult.skipped(
      itemId: item.id,
      availability: SetlistItemAvailability.invalidConfig,
    );
  }
  final launched = await launcher(config);
  switch (launched) {
    case Failure(:final error):
      return SetlistItemResult.skipped(
        itemId: item.id,
        availability: _availabilityForLaunchFailure(error.code),
      );
    case Success(:final value):
      if (!context.mounted) {
        return SetlistItemResult.skipped(
          itemId: item.id,
          availability: SetlistItemAvailability.invalidConfig,
        );
      }
      final outcome = await Navigator.of(context)
          .push<SongTrainerSessionOutcome>(
            MaterialPageRoute<SongTrainerSessionOutcome>(
              builder: (_) => SongTrainerSessionRoute(
                songId: value.songId.value,
                args: value,
                returnResultToCaller: true,
              ),
            ),
          );
      return _resultFor(item: item, outcome: outcome);
  }
}

/// Maps the Stage's own measured outcome onto a [SetlistItemResult] (D4).
/// Leaving without either measured signal firing is the `partial` branch
/// with a zero duration — a measured absence, never a synthesized
/// `completed`.
SetlistItemResult _resultFor({
  required SongSetlistItem item,
  required SongTrainerSessionOutcome? outcome,
}) {
  if (outcome == null) {
    return SetlistItemResult.partial(
      itemId: item.id,
      activeDuration: Duration.zero,
    );
  }
  final scored = outcome.scoredResult;
  if (scored != null) {
    final sessionResult = scored.sessionResult;
    return sessionResult.finishReason ==
            PracticeFinishReason.completedAllTargets
        ? SetlistItemResult.completed(
            itemId: item.id,
            activeDuration: sessionResult.activeDuration,
          )
        : SetlistItemResult.partial(
            itemId: item.id,
            activeDuration: sessionResult.activeDuration,
          );
  }
  return SetlistItemResult.completed(
    itemId: item.id,
    activeDuration: outcome.playbackActiveDuration!,
  );
}

/// Assembles a [TrainerConfig] for one setlist item, or `null` when the
/// document cannot supply the minimum a session needs (no track at all, or
/// a stale range) — that local failure maps to `invalidConfig` without ever
/// calling the launcher.
TrainerConfig? _trainerConfigFor({
  required SongSetlistItem item,
  required SongDocument document,
  required TrainerMode mode,
}) {
  final overrides = item.overrides;
  final trackId = overrides.trackId ?? _defaultTrackId(document.tracks);
  if (trackId == null) return null;
  final range = overrides.range.resolve(
    measureCount: document.measures.length,
    sections: document.sections,
  );
  if (range == null) return null;
  try {
    return TrainerConfig(
      songId: item.songId,
      songRevision: document.revision,
      trackId: trackId,
      selection: overrides.range,
      range: range,
      mode: mode,
      targetSpeed: overrides.speedMultiplier,
      countInBars: overrides.countInBars,
      metronomeEnabled: false,
      loopConfig: LoopConfig(range: range, maxRepeats: overrides.loopCount),
      tuningReminder: overrides.tuningOverrideCode == null
          ? null
          : Tunings.byId(overrides.tuningOverrideCode!),
      capo: overrides.capoOverride ?? 0,
      capoReminder: overrides.capoOverride != null,
    );
  } on ArgumentError {
    return null;
  }
}

/// The first enabled Chord/Strum/Note track, or (when none scores) simply
/// the first track in the document — `SongPracticeCompiler.compile` treats
/// any other track kind as playback-only rather than throwing, so this
/// never needs to report failure on its own.
SongTrackId? _defaultTrackId(List<SongTrack> tracks) {
  for (final track in tracks) {
    final scorable = switch (track) {
      ChordTrack(:final enabled) => enabled,
      StrumTrack(:final enabled) => enabled,
      NoteTrack(:final enabled) => enabled,
      _ => false,
    };
    if (scorable) return track.id;
  }
  return tracks.isEmpty ? null : tracks.first.id;
}

/// The bound D3 mapping from the launcher's own failure codes.
SetlistItemAvailability _availabilityForLaunchFailure(String code) =>
    switch (code) {
      SongRepositoryErrorCode.notFound => SetlistItemAvailability.missingSong,
      SongTrainerLaunchFailureCode.staleRevision =>
        SetlistItemAvailability.requiresMigration,
      SongTrainerLaunchFailureCode.notPlayable =>
        SetlistItemAvailability.invalidConfig,
      _ => SetlistItemAvailability.invalidConfig,
    };
