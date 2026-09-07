// Javító sáv 2026-09-07 (R10) — the Setlist V2 list → ordered session →
// Song Trainer wiring the shipped APK never had
// (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2).
//
// B1 — the list renders the repository's setlists, and tapping one hands
//      THAT setlist to the open callback (the tap is a real control).
// B2 — an item's stored overrides reach the trainer config, with the
//      out-of-range speed clamped to the trainer's supported maximum.
// B3 — an item whose song is gone is a NAMED `missingSong` failure, never
//      a silently dropped item.
// B4 — the session runs items in order, one at a time, and ends after the
//      last one; an unavailable item is skipped without stopping the run.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/setlist/setlist_session_launch.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_controller.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_launcher.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets('B1 — the list renders stored setlists and a tap opens the '
      'tapped one', (tester) async {
    final setlist = _setlist();
    final controller = SetlistController(
      _MemorySetlistRepository(<SongSetlist>[setlist]),
    );
    final opened = <SongSetlist>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SetlistListScreenV2(
          controller: controller,
          clock: () => DateTime.utc(2026, 9, 7),
          onOpenSetlist: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gig Set'), findsOneWidget);
    expect(find.byKey(const Key('setlist-list-window')), findsOneWidget);

    await tester.tap(find.text('Gig Set'));
    await tester.pumpAndSettle();

    expect(opened.single.id, 'setlist-1');
  });

  test('B2 — stored overrides reach the config, speed clamped', () async {
    final repository = InMemorySongRepository();
    final document = _document();
    expect(await repository.create(document), isA<Success<void>>());
    final coordinator = _coordinator(repository);
    final item = SongSetlistItem(
      id: 'item-1',
      songId: document.id,
      overrides: const SetlistItemOverrides(
        // Deliberately outside the trainer's 0.5–1.5 range: the setlist
        // editor accepts it, the session must not.
        speedMultiplier: 2,
        loopCount: 3,
        countInBars: 2,
        capoOverride: 4,
      ),
    );

    final config = await coordinator.configFor(item);

    expect(config, isA<Success<TrainerConfig>>());
    final value = (config as Success<TrainerConfig>).value;
    expect(value.songId, document.id);
    expect(value.songRevision, document.revision);
    expect(value.targetSpeed, TrainerConfig.maximumSpeed);
    expect(value.loopConfig.maxRepeats, 3);
    expect(value.countInBars, 2);
    expect(value.capo, 4);
  });

  test('B2b — a config for a stored song compiles session inputs', () async {
    final repository = InMemorySongRepository();
    final document = _document();
    expect(await repository.create(document), isA<Success<void>>());
    final coordinator = _coordinator(repository);
    final item = SongSetlistItem(id: 'item-1', songId: document.id);

    final prepared = await coordinator.prepareItem(item);

    expect(prepared, isA<Success<SongTrainerControllerInputs>>());
  });

  test('B3 — a missing song is named, not silently dropped', () async {
    final coordinator = _coordinator(InMemorySongRepository());
    final item = SongSetlistItem(id: 'item-1', songId: SongId('gone'));

    final prepared = await coordinator.prepareItem(item);

    expect(prepared, isA<Failure<SongTrainerControllerInputs>>());
    final error = (prepared as Failure<SongTrainerControllerInputs>).error;
    expect(error.code, SetlistItemLaunchFailureCode.songMissing);
    expect(
      setlistAvailabilityForFailure(error.code),
      SetlistItemAvailability.missingSong,
    );
  });

  test('B4 — the session advances item by item to the last', () async {
    final order = <String>[];
    var concurrent = 0;
    final controller = SetlistSessionController(
      availability: (item) => item.initialAvailability,
      practiceRunner: (item) async {
        concurrent++;
        expect(concurrent, 1, reason: 'items must not overlap');
        order.add(item.id);
        await Future<void>.delayed(Duration.zero);
        concurrent--;
        return SetlistItemResult.completed(itemId: item.id);
      },
      performanceRunner: _unusedPerformanceRunner,
    );

    final result = await controller.run(
      setlist: _setlist(),
      mode: SetlistSessionMode.practice,
    );

    // item-2 is stored as `missingSong`, so it is skipped WITHOUT stopping
    // the run — the last item still gets its turn.
    expect(order, <String>['item-1', 'item-3']);
    expect(result.itemResults.map((r) => r.itemId).toList(), <String>[
      'item-1',
      'item-2',
      'item-3',
    ]);
    expect(result.itemResults.last.status, SetlistItemResultStatus.completed);
    expect(
      result.itemResults[1].availability,
      SetlistItemAvailability.missingSong,
    );
  });
}

Future<SetlistItemResult> _unusedPerformanceRunner(SongSetlistItem item) =>
    throw StateError('performance is not wired');

SetlistSessionCoordinator _coordinator(InMemorySongRepository repository) {
  return SetlistSessionCoordinator(
    songRepository: repository,
    launcher: SongTrainerLauncher(songRepository: repository),
  );
}

SongSetlist _setlist() {
  final now = DateTime.utc(2026, 9, 7);
  return SongSetlist(
    id: 'setlist-1',
    name: 'Gig Set',
    createdAt: now,
    updatedAt: now,
    items: <SongSetlistItem>[
      SongSetlistItem(id: 'item-1', songId: SongId('opener')),
      SongSetlistItem(
        id: 'item-2',
        songId: SongId('gone'),
        initialAvailability: SetlistItemAvailability.missingSong,
      ),
      SongSetlistItem(id: 'item-3', songId: SongId('closer')),
    ],
  );
}

SongDocument _document() {
  final now = DateTime.utc(2026, 9, 7);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('opener'),
    revision: 3,
    metadata: SongMetadata(title: 'Opener'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'opener.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 2,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
    ],
  );
}

final class _MemorySetlistRepository implements SetlistRepository {
  _MemorySetlistRepository(this._setlists);

  final List<SongSetlist> _setlists;

  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      Success<List<SongSetlist>>(_setlists);

  @override
  Future<AppResult<SongSetlist?>> get(String id) async {
    for (final setlist in _setlists) {
      if (setlist.id == id) return Success<SongSetlist?>(setlist);
    }
    return const Success<SongSetlist?>(null);
  }

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async {
    _setlists
      ..removeWhere((stored) => stored.id == setlist.id)
      ..add(setlist);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> delete(String id) async {
    _setlists.removeWhere((stored) => stored.id == id);
    return const Success<void>(null);
  }
}
