// E17-R03 (ADR 0522) — composition of the Setlist session from the shipped
// Song Trainer application layer.
//
// The `SetlistSessionScreen` was designed with injected seams (`availability`,
// `performanceRunner`, `createPracticeRunner`) and no production code ever
// filled them. This file is the single place that does: it answers item
// availability from the real song repositories, and it builds the per-item
// runners on the same setup → compile → Stage pipeline the single-song
// Trainer route uses (`SongTrainerSetupController`, `SongPracticeCompiler`,
// `SongTrainerControllerInputs`).
//
// Layering (AGENTS.md §7): no Flutter navigation, `BuildContext` or router
// here. Showing a song's Stage is the presentation layer's job, so it is
// injected as a [SetlistItemStagePresenter] callback and awaited per item —
// the runner resolves when the guitarist leaves that Stage.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../data/migration/legacy_song_adapter.dart';
import '../../data/migration/legacy_song_reader.dart';
import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/repositories/song_repository.dart';
import '../song_trainer_providers.dart';
import '../trainer/song_practice_compiler.dart';
import '../trainer/song_trainer_setup_controller.dart';
import 'setlist_session_controller.dart';

/// One setlist item resolved to the document and controller inputs its
/// Stage needs. The presentation layer shows it; nothing here does.
final class SetlistItemStage {
  const SetlistItemStage({
    required this.item,
    required this.document,
    required this.inputs,
  });

  final SongSetlistItem item;
  final SongDocument document;
  final SongTrainerControllerInputs inputs;
}

/// Shows one item's Stage and completes once the guitarist has left it,
/// returning the time the Stage was on screen (the item's active duration).
typedef SetlistItemStagePresenter =
    Future<Duration> Function(SetlistItemStage stage);

/// Everything `SetlistSessionScreen` needs for one (setlist, songbook) pair.
final class SetlistSessionComposition {
  const SetlistSessionComposition({
    required this.setlist,
    required this.availability,
    required this.performanceRunner,
    required this.createPracticeRunner,
  });

  /// The V2 projection of the legacy setlist (in memory, never persisted —
  /// see [SetlistSessionComposer.compose]).
  final SongSetlist setlist;

  /// Answers from the songbook resolved at composition time.
  final SetlistAvailabilityResolver availability;

  /// Playback-only per-item runner.
  final SetlistItemRunner performanceRunner;

  /// Scored per-item runner factory — `SetlistSessionScreen` only calls it in
  /// practice mode, so performance sessions never build scoring work.
  final SetlistItemRunner Function() createPracticeRunner;
}

/// Builds a [SetlistSessionComposition] for a legacy setlist.
///
/// **Songbook — "the real song repositories":** each referenced song id is
/// looked up in the V2 [SongRepository] first (the migrated / V2-edited
/// document wins); a song that only exists in the legacy songbook is adapted
/// in memory through the same [LegacySongReader] + [LegacySongAdapter] pair
/// the E03-R08 migration uses (deterministic, lossless, no persistence). An
/// id found in neither is `missingSong` — the resolver never answers a
/// constant `ready` (brief §9).
///
/// **Convert-on-entry decision:** the legacy setlist is projected into a
/// [SongSetlist] on EVERY entry with the exact mapping of
/// `LegacySetlistAdapter.persistV2` (id = `SongIdValidator.safeFilename`,
/// item id = `'<setlistId>-<index>'`, availability from songbook presence),
/// but NOT persisted. `persistV2` has no caller in production today and the
/// legacy `setlistsProvider` remains the single source of truth the detail
/// screen edits; writing a copy into the V2 store on each launch would
/// create a second, silently diverging record. The projection is therefore
/// a pure, in-memory view, recomputed from the latest legacy edit each time.
final class SetlistSessionComposer {
  const SetlistSessionComposer({
    required SongRepository songs,
    required ClockSupplier clock,
    LegacySongReader reader = const LegacySongReader(),
    LegacySongAdapter adapter = const LegacySongAdapter(),
  }) : _songs = songs,
       _clock = clock,
       _reader = reader,
       _adapter = adapter;

  final SongRepository _songs;
  final ClockSupplier _clock;
  final LegacySongReader _reader;
  final LegacySongAdapter _adapter;

  /// Resolve the songbook, project the setlist and bind the runners.
  ///
  /// [legacySongs] is the legacy songbook in its persisted JSON shape (what
  /// `Song.toJson` / `StorageKeys.songs` hold) — the documented input of
  /// [LegacySongReader.readSong]. Only the ids [legacySetlist] references
  /// are resolved.
  Future<SetlistSessionComposition> compose({
    required LegacySetlistRecord legacySetlist,
    required List<Map<String, dynamic>> legacySongs,
    required SetlistItemStagePresenter presentStage,
  }) async {
    final songbook = await _resolveSongbook(legacySetlist.songIds, legacySongs);
    final setlist = _project(legacySetlist, songbook);
    return SetlistSessionComposition(
      setlist: setlist,
      availability: (item) => _availabilityOf(item, songbook),
      performanceRunner: (item) =>
          _runPerformance(item, songbook, presentStage),
      createPracticeRunner: () =>
          (item) => _runPractice(item, songbook, presentStage),
    );
  }

  Future<Map<String, SongDocument>> _resolveSongbook(
    List<String> songIds,
    List<Map<String, dynamic>> legacySongs,
  ) async {
    final songbook = <String, SongDocument>{};
    for (final songId in songIds) {
      if (songbook.containsKey(songId)) continue;
      final document =
          await _fromV2(songId) ?? _fromLegacy(songId, legacySongs);
      if (document != null) songbook[songId] = document;
    }
    return songbook;
  }

  Future<SongDocument?> _fromV2(String songId) async {
    final SongId typed;
    try {
      typed = SongId(songId);
    } on SongIdValidationException {
      return null;
    }
    final result = await _songs.get(typed);
    return switch (result) {
      Success(:final value) => value,
      Failure() => null,
    };
  }

  SongDocument? _fromLegacy(
    String songId,
    List<Map<String, dynamic>> legacySongs,
  ) {
    for (final json in legacySongs) {
      if (json['id'] != songId) continue;
      try {
        final record = _reader.readSong(json);
        return _adapter.adapt(record, importedAt: _clock().toUtc()).document;
      } on LegacySongReaderException {
        return null;
      } on SongIdValidationException {
        return null;
      }
    }
    return null;
  }

  /// Mirrors `LegacySetlistAdapter.persistV2`'s mapping without the write.
  /// A blank legacy name falls back to the id, exactly as
  /// [LegacySongAdapter] does for an unnamed song's title — `SongSetlist`
  /// rejects an empty name.
  SongSetlist _project(
    LegacySetlistRecord legacy,
    Map<String, SongDocument> songbook,
  ) {
    final setlistId = SongIdValidator.safeFilename(legacy.id);
    final now = _clock().toUtc();
    final name = legacy.name.trim().isEmpty ? legacy.id : legacy.name;
    return SongSetlist(
      id: setlistId,
      name: name,
      items: <SongSetlistItem>[
        for (var index = 0; index < legacy.songIds.length; index++)
          SongSetlistItem(
            id: '$setlistId-$index',
            songId: SongId(legacy.songIds[index]),
            initialAvailability: songbook.containsKey(legacy.songIds[index])
                ? SetlistItemAvailability.ready
                : SetlistItemAvailability.missingSong,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  static SetlistItemAvailability _availabilityOf(
    SongSetlistItem item,
    Map<String, SongDocument> songbook,
  ) {
    if (songbook.containsKey(item.songId.value)) {
      return SetlistItemAvailability.ready;
    }
    return item.initialAvailability == SetlistItemAvailability.ready
        ? SetlistItemAvailability.missingSong
        : item.initialAvailability;
  }

  /// Performance: playback-only inputs, exactly the branch of
  /// `songTrainerControllerProvider` that constructs no Practice controller
  /// and therefore never resolves the microphone.
  Future<SetlistItemResult> _runPerformance(
    SongSetlistItem item,
    Map<String, SongDocument> songbook,
    SetlistItemStagePresenter presentStage,
  ) async {
    final document = songbook[item.songId.value];
    if (document == null) {
      return SetlistItemResult.skipped(
        itemId: item.id,
        availability: SetlistItemAvailability.missingSong,
      );
    }
    final active = await presentStage(
      SetlistItemStage(
        item: item,
        document: document,
        inputs: SongTrainerControllerInputs(
          compilation: const SongPracticeCompilation.playbackOnly(),
          backingAsset: _backingAssetOf(document),
        ),
      ),
    );
    return SetlistItemResult.completed(itemId: item.id, activeDuration: active);
  }

  /// Practice: the same defaults the Trainer Setup screen would pick
  /// (`SongTrainerSetupController` over the resolved document), with the
  /// item's speed / count-in / range / loop overrides applied, compiled by
  /// `SongPracticeCompiler` into scored inputs.
  ///
  /// A document the setup controller cannot configure (no trainable track)
  /// is a recoverable `unsupportedTrack` skip; a compilation the compiler
  /// rejects is an `invalidConfig` skip — never a thrown session.
  Future<SetlistItemResult> _runPractice(
    SongSetlistItem item,
    Map<String, SongDocument> songbook,
    SetlistItemStagePresenter presentStage,
  ) async {
    final document = songbook[item.songId.value];
    if (document == null) {
      return SetlistItemResult.skipped(
        itemId: item.id,
        availability: SetlistItemAvailability.missingSong,
      );
    }
    final setup = SongTrainerSetupController(
      repository: _SongbookRepository(songbook),
    );
    TrainerConfig? config;
    try {
      await setup.load(document.id);
      final overrides = item.overrides;
      setup.setTargetSpeed(
        overrides.speedMultiplier
            .clamp(TrainerConfig.minimumSpeed, TrainerConfig.maximumSpeed)
            .toDouble(),
      );
      setup.setCountInBars(overrides.countInBars);
      setup.selectRange(overrides.range);
      setup.setLoopEnabled(overrides.loopCount > 1);
      config = setup.complete();
    } finally {
      setup.dispose();
    }
    if (config == null) {
      return SetlistItemResult.skipped(
        itemId: item.id,
        availability: SetlistItemAvailability.unsupportedTrack,
      );
    }
    final SongPracticeCompilation compilation;
    try {
      compilation = SongPracticeCompiler.compile(
        document: document,
        config: config,
      );
    } on ArgumentError {
      return SetlistItemResult.skipped(
        itemId: item.id,
        availability: SetlistItemAvailability.invalidConfig,
      );
    }
    final active = await presentStage(
      SetlistItemStage(
        item: item,
        document: document,
        inputs: SongTrainerControllerInputs(
          compilation: compilation,
          backingAsset: _backingAssetOf(document),
        ),
      ),
    );
    return SetlistItemResult.completed(itemId: item.id, activeDuration: active);
  }

  static SongAssetReference? _backingAssetOf(SongDocument document) {
    final track = document.tracks.whereType<BackingAudioTrack>().firstOrNull;
    if (track == null) return null;
    return document.assets
        .where((asset) => asset.id == track.assetId)
        .firstOrNull;
  }
}

/// Read-only [SongRepository] over the resolved songbook, so the setup
/// controller derives the practice defaults from the SAME document the
/// runner stages (a legacy-only song is not in the V2 store to `get`).
final class _SongbookRepository implements SongRepository {
  const _SongbookRepository(this._songbook);

  final Map<String, SongDocument> _songbook;

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.success(_songbook[id.value]);

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async =>
      const AppResult<List<SongSummary>>.success(<SongSummary>[]);

  @override
  Future<AppResult<void>> create(SongDocument document) async => _readOnly();

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) async => _readOnly();

  @override
  Future<AppResult<void>> moveToTrash(SongId id) async => _readOnly();

  @override
  Future<AppResult<void>> restore(SongId id) async => _readOnly();

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) async => _readOnly();

  static AppResult<void> _readOnly() => const AppResult<void>.failure(
    StorageFailure(code: SongRepositoryErrorCode.notPersistable),
  );
}

/// Production composer: the real V2 song store + the Song Trainer clock.
/// `songRepositoryProvider` is wired by `main.dart`; widget tests override
/// it with `InMemorySongRepository`.
final setlistSessionComposerProvider = Provider<SetlistSessionComposer>((ref) {
  return SetlistSessionComposer(
    songs: ref.watch(songRepositoryProvider),
    clock: ref.watch(songTrainerClockProvider),
  );
});
