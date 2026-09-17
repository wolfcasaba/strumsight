/// Turns a finished [TrainerConfig] into everything the session route needs
/// (E16-R01/A2 + A3).
///
/// MEASURED gap this closes: `TrainerSetupScreen.onComplete` produced a
/// `TrainerConfig` and the route dropped it on the floor — there was not one
/// `push(songTrainerSession)` anywhere in `lib/`, so the Start button was
/// deaf and the session route unreachable. Even reached directly, the screen
/// received empty `chordEvents` / `strumEvents` / `sections` lists, so the
/// lanes rendered nothing.
///
/// The launcher is the single place where a config becomes a session: it
/// loads the document through the repository, compiles the scored (or
/// playback-only) Practice definition, and collects the lane data and the
/// loop boundary from that same document. It returns an [AppResult] rather
/// than throwing, so the caller can show a named failure instead of a crash.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_time_map.dart';
import '../song_trainer_providers.dart';
import 'song_practice_compiler.dart';

/// Stable failure codes the launcher can report to the setup screen.
abstract final class SongTrainerLaunchFailureCode {
  /// The configured song no longer matches the stored revision — the user
  /// edited it in another tab while the setup screen was open.
  static const String staleRevision = 'songTrainerLaunch.staleRevision';

  /// The document could not be compiled into a session (a stale range, a
  /// track that vanished, colliding event positions).
  static const String notPlayable = 'songTrainerLaunch.notPlayable';
}

/// Everything the session route renders and drives, resolved once.
final class SongTrainerSessionArgs {
  /// Stable constructor.
  const SongTrainerSessionArgs({
    required this.songId,
    required this.inputs,
    required this.chordEvents,
    required this.strumEvents,
    required this.noteEvents,
    required this.sections,
    required this.loopRangeEnd,
  });

  /// Identity of the song being practised.
  final SongId songId;

  /// Runtime inputs for the route-scoped controller.
  final SongTrainerControllerInputs inputs;

  /// Chord lane data, in document order.
  final List<SongChordEvent> chordEvents;

  /// Strum lane data, in document order.
  final List<SongStrumEvent> strumEvents;

  /// Tablature lane data, in document order.
  final List<SongNoteEvent> noteEvents;

  /// Sections the loop control offers.
  final List<SongSection> sections;

  /// Exact end of the configured range, so the running viewport clamps to
  /// the real loop boundary instead of running past the last measure.
  final Duration? loopRangeEnd;
}

/// Resolves a [TrainerConfig] into [SongTrainerSessionArgs].
typedef SongTrainerSessionLauncher =
    Future<AppResult<SongTrainerSessionArgs>> Function(TrainerConfig config);

/// Production launcher, bound to the repository the rest of the feature uses.
final songTrainerSessionLauncherProvider = Provider<SongTrainerSessionLauncher>(
  (ref) {
    final repository = ref.watch(songRepositoryProvider);
    return (config) =>
        loadSongTrainerSession(repository: repository, config: config);
  },
);

/// Loads and compiles one session. Never throws.
Future<AppResult<SongTrainerSessionArgs>> loadSongTrainerSession({
  required SongRepository repository,
  required TrainerConfig config,
}) async {
  final loaded = await repository.get(config.songId);
  if (loaded case Failure(:final error)) {
    return AppResult<SongTrainerSessionArgs>.failure(error);
  }
  final document = (loaded as Success<SongDocument?>).value;
  if (document == null) {
    return AppResult<SongTrainerSessionArgs>.failure(
      const StorageFailure(code: SongRepositoryErrorCode.notFound),
    );
  }
  if (document.revision != config.songRevision) {
    return AppResult<SongTrainerSessionArgs>.failure(
      const StorageFailure(code: SongTrainerLaunchFailureCode.staleRevision),
    );
  }

  final SongPracticeCompilation compilation;
  try {
    compilation = SongPracticeCompiler.compile(
      document: document,
      config: config,
    );
  } catch (_) {
    return AppResult<SongTrainerSessionArgs>.failure(
      const ValidationFailure(code: SongTrainerLaunchFailureCode.notPlayable),
    );
  }

  return AppResult<SongTrainerSessionArgs>.success(
    SongTrainerSessionArgs(
      songId: document.id,
      inputs: SongTrainerControllerInputs(
        compilation: compilation,
        backingAsset: backingAssetOf(document),
        maxLoops: config.loopConfig.maxRepeats ?? 1,
        targetSpeed: config.targetSpeed,
      ),
      chordEvents: _chordEventsOf(document),
      strumEvents: _strumEventsOf(document),
      noteEvents: _noteEventsOf(document),
      sections: document.sections,
      loopRangeEnd: rangeEndTimeOf(document, config),
    ),
  );
}

/// The backing asset the document's audio track points at, when the asset is
/// actually present. An orphan reference resolves to `null` so the transport
/// prepares silently rather than failing the whole session.
SongAssetReference? backingAssetOf(SongDocument document) {
  for (final track in document.tracks.whereType<BackingAudioTrack>()) {
    for (final asset in document.assets) {
      if (asset.id == track.assetId) return asset;
    }
  }
  return null;
}

/// Wall-clock end of the configured measure range.
Duration? rangeEndTimeOf(SongDocument document, TrainerConfig config) {
  final ordered = document.measures.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  var cursor = BeatPosition.zero;
  var seen = false;
  for (final SongMeasure measure in ordered) {
    if (measure.index >= config.range.endExclusive) break;
    cursor += measure.durationBeats;
    seen = true;
  }
  if (!seen) return null;
  return SongTimeMap.fromTempoMap(document.tempoMap).timeAt(cursor);
}

List<SongChordEvent> _chordEventsOf(SongDocument document) => <SongChordEvent>[
  for (final track in document.tracks.whereType<ChordTrack>())
    if (track.enabled) ...track.events,
];

List<SongStrumEvent> _strumEventsOf(SongDocument document) => <SongStrumEvent>[
  for (final track in document.tracks.whereType<StrumTrack>())
    if (track.enabled) ...track.events,
];

List<SongNoteEvent> _noteEventsOf(SongDocument document) => <SongNoteEvent>[
  for (final track in document.tracks.whereType<NoteTrack>())
    if (track.enabled) ...track.events,
];
