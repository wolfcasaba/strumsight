// Golden snapshots of the E13-R25 Song Trainer setup, Stage, result, and
// setlist-run screens, at a compact portrait phone (412×915) and the same
// frame at textScaler 2.0 — the two frames the round brief §7/A9 requires.
// Pattern and sizing follow the merged
// `test/ui/goldens/e13_r24_screens_golden_test.dart` precedent.
//
// E15-R05 correction: `theme` is `SsDarkTheme.data()`, not the original
// `AppTheme.dark()` — all four screens now use design-system components
// whose `Theme.of(context).extension<SsColorScheme>()!` null-check crashes
// under the bare legacy theme (`SsDarkTheme.data()` is additive-only,
// `AppTheme.dark()` + design-system extensions, ADR 0466 D2).
//
// Recorded on x86_64 (ADR 0426, §0.0/B/B5) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart' show SsDarkTheme;
import 'package:strumsight/features/practice/public.dart'
    hide BeatPosition, Tempo, Meter;
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[...preferenceOverrides(), ...overrides],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

SongDocument _setupDocument() {
  final now = DateTime.utc(2026, 8, 26);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-setup'),
    revision: 0,
    metadata: SongMetadata(title: 'Golden Setup Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'golden-setup.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
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

SongTrainerResult _resultFixture() {
  final measureResults = <SongMeasureTrainerResult>[
    for (var index = 0; index < 4; index++)
      SongMeasureTrainerResult(
        measureIndex: index,
        verdicts: const <SongTrainerVerdict>[],
        averageEventScore: 0.85 - (index * 0.1),
      ),
  ];
  return SongTrainerResult(
    sessionResult: PracticeSessionResult(
      id: 'golden-result',
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attempts: const <PracticeAttemptResult>[],
      finishReason: PracticeFinishReason.completedAllTargets,
      highestStableTempo: null,
      coachingSummary: const <String>[],
    ),
    verdicts: const <SongTrainerVerdict>[],
    measureResults: measureResults,
    sectionResults: const <SongSectionTrainerResult>[],
  );
}

SongSetlist _setlistFixture() => SongSetlist(
  id: 'golden-setlist',
  name: 'Golden Setlist',
  createdAt: DateTime.utc(2026, 8, 26),
  updatedAt: DateTime.utc(2026, 8, 26),
  items: <SongSetlistItem>[
    SongSetlistItem(id: 'first', songId: SongId('song-a')),
    SongSetlistItem(
      id: 'second',
      songId: SongId('song-b'),
      overrides: const SetlistItemOverrides(tuningOverrideCode: 'dropD'),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('trainer setup — $suffix', (tester) async {
      final repository = InMemorySongRepository();
      final document = _setupDocument();
      await repository.create(document);
      await _pump(
        tester,
        TrainerSetupScreen(songId: document.id.value),
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(repository),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r25_trainer_setup_$suffix');
    });

    testWidgets('song trainer stage (running) — $suffix', (tester) async {
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.running,
        backingRateSupported: true,
        loopIndex: 2,
        maxLoops: 5,
      );
      await _pump(
        tester,
        SongTrainerScreen(state: state),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r25_song_trainer_stage_$suffix');
    });

    testWidgets('song result — $suffix', (tester) async {
      await _pump(
        tester,
        SongResultScreen(result: _resultFixture()),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r25_song_result_$suffix');
    });

    testWidgets('setlist run — $suffix', (tester) async {
      await _pump(
        tester,
        SetlistSessionScreen(
          setlist: _setlistFixture(),
          mode: SetlistSessionMode.performance,
          availability: (_) => SetlistItemAvailability.ready,
          performanceRunner: (item) async =>
              SetlistItemResult.completed(itemId: item.id),
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r25_setlist_run_$suffix');
    });
  }
}
