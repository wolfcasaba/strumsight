// WP-H1 — a `SetlistItemRunner` typedef ÉLES implementációja.
//
// A három kimenetel mérve: végigjátszott tétel (`completed`), félbehagyott
// tétel (`partial`, a ténylegesen eltöltött idővel) és el sem induló tétel
// (`failed`). A negyedik cella azt méri, hogy a Performance mód valóban
// lejátszás-only bemenetet ad át — mikrofonos Practice fordítás nélkül.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_item_session_runner.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_result_mapper.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart'
    as song_time;

void main() {
  test('a finished song comes back as a completed item with its duration',
      () async {
    final repository = InMemorySongRepository();
    await repository.create(_document());
    final clock = _StepClock();
    final runner = SetlistItemSessionRunner(
      repository: repository,
      clock: clock.now,
      launchSession: (songId, inputs) async {
        clock.advance(const Duration(minutes: 3));
        return _result();
      },
    );

    final outcome = await runner.runPractice(_item());

    expect(outcome.status, SetlistItemResultStatus.completed);
    expect(outcome.itemId, 'item-1');
    expect(outcome.activeDuration, const Duration(minutes: 3));
    expect(outcome.repairRequired, isFalse);
  });

  test('leaving the session without a result is a partial item, not a '
      'completed or failed one', () async {
    final repository = InMemorySongRepository();
    await repository.create(_document());
    final clock = _StepClock();
    final runner = SetlistItemSessionRunner(
      repository: repository,
      clock: clock.now,
      launchSession: (songId, inputs) async {
        clock.advance(const Duration(seconds: 42));
        // A munkamenet-útvonal eredmény NÉLKÜL zárult: a tanuló elhagyta.
        return null;
      },
    );

    final outcome = await runner.runPractice(_item());

    expect(outcome.status, SetlistItemResultStatus.partial);
    expect(outcome.activeDuration, const Duration(seconds: 42));
    expect(
      outcome.repairRequired,
      isFalse,
      reason: 'a félbehagyott tételen nincs mit megjavítani',
    );
  });

  test('a missing song fails the item instead of launching an empty session',
      () async {
    var launches = 0;
    final runner = SetlistItemSessionRunner(
      repository: InMemorySongRepository(),
      launchSession: (songId, inputs) async {
        launches++;
        return _result();
      },
    );

    final outcome = await runner.runPractice(_item());

    expect(outcome.status, SetlistItemResultStatus.failed);
    expect(outcome.availability, SetlistItemAvailability.missingSong);
    expect(outcome.repairRequired, isTrue);
    expect(launches, 0);
  });

  test('an out-of-range speed override fails the item at compile time',
      () async {
    final repository = InMemorySongRepository();
    await repository.create(_document());
    var launches = 0;
    final runner = SetlistItemSessionRunner(
      repository: repository,
      launchSession: (songId, inputs) async {
        launches++;
        return _result();
      },
    );

    final outcome = await runner.runPractice(
      _item(overrides: const SetlistItemOverrides(speedMultiplier: 3)),
    );

    expect(outcome.status, SetlistItemResultStatus.failed);
    expect(outcome.availability, SetlistItemAvailability.invalidConfig);
    expect(launches, 0);
  });

  test('performance mode launches a playback-only session — no scored '
      'compilation, no microphone', () async {
    final repository = InMemorySongRepository();
    await repository.create(_document());
    SongTrainerControllerInputs? captured;
    final runner = SetlistItemSessionRunner(
      repository: repository,
      launchSession: (songId, inputs) async {
        captured = inputs;
        return null;
      },
    );

    await runner.runPerformance(_item());

    expect(captured, isNotNull);
    expect(captured!.compilation.isPlaybackOnly, isTrue);
    expect(captured!.compilation.definition, isNull);
  });

  test('practice mode launches a scored session compiled from the item '
      'overrides', () async {
    final repository = InMemorySongRepository();
    await repository.create(_document());
    SongTrainerControllerInputs? captured;
    SongId? capturedSongId;
    final runner = SetlistItemSessionRunner(
      repository: repository,
      launchSession: (songId, inputs) async {
        capturedSongId = songId;
        captured = inputs;
        return null;
      },
    );

    await runner.runPractice(_item());

    expect(capturedSongId, SongId('song'));
    expect(captured!.compilation.isPlaybackOnly, isFalse);
    expect(captured!.compilation.definition, isNotNull);
  });

  test('a performance item whose declared backing asset is gone fails with '
      'missingAsset', () async {
    final repository = InMemorySongRepository();
    await repository.create(_documentWithMissingBacking());
    var launches = 0;
    final runner = SetlistItemSessionRunner(
      repository: repository,
      launchSession: (songId, inputs) async {
        launches++;
        return null;
      },
    );

    final outcome = await runner.runPerformance(_item(songId: 'song-backing'));

    expect(outcome.status, SetlistItemResultStatus.failed);
    expect(outcome.availability, SetlistItemAvailability.missingAsset);
    expect(launches, 0);
  });
}

final class _StepClock {
  DateTime _now = DateTime.utc(2026, 9, 6, 10);

  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

SongSetlistItem _item({
  String songId = 'song',
  SetlistItemOverrides overrides = const SetlistItemOverrides(),
}) => SongSetlistItem(
  id: 'item-1',
  songId: SongId(songId),
  overrides: overrides,
);

SongTrainerResult _result() => SongResultMapper.map(
  sessionResult: const PracticeSessionResult(
    id: 'practice-result',
    activeDuration: Duration(minutes: 3),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: null,
    coachingSummary: <String>[],
  ),
  references: const {},
);

final SongInstrument _guitar = SongInstrument(name: 'Guitar');

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song'),
    revision: 0,
    metadata: SongMetadata(title: 'Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.json',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('section'),
        name: 'Section',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
    tracks: <SongTrack>[
      StrumTrack(
        id: SongTrackId('strums'),
        name: 'Strums',
        instrument: _guitar,
        events: <SongStrumEvent>[
          SongStrumEvent(
            id: SongEventId('strum'),
            at: Duration.zero,
            direction: StrumDirection.down,
          ),
        ],
      ),
    ],
  );
}

/// Egy dal, ami kíséret-sávot HIRDET, de az eszközt nem hivatkozza az
/// `assets` lista — pontosan az az eset, amit a performance mód nem tud
/// lejátszani.
SongDocument _documentWithMissingBacking() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song-backing'),
    revision: 0,
    metadata: SongMetadata(title: 'Backing song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.json',
      sha256: 'b' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    assets: const <SongAssetReference>[],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('section'),
        name: 'Section',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
    tracks: <SongTrack>[
      BackingAudioTrack(
        id: SongTrackId('backing'),
        name: 'Backing',
        instrument: SongInstrument(name: 'Backing track'),
        assetId: SongAssetId('missing'),
        gridOffset: Duration.zero,
      ),
    ],
  );
}
