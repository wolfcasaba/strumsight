// Javító sáv 2026-09-06 (R8, audit §5.2 "A `SongResultScreen` retry/next
// callbackjei").
//
// The result route used to be built with the mapped result alone, so both
// CTAs rendered with `onPressed: null` — permanently dead buttons on the
// screen every session ends on.
//
// D1 — Retry relaunches the session route with the SAME config.
// D2 — Next starts the following section of the same song.
// D3 — Next falls back to the song overview when no section follows.
// D4 — without a config the CTAs stay honestly disabled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart'
    as song_time;
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_route.dart';
import 'package:strumsight/features/song_trainer/presentation/song_trainer_launch.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

void main() {
  testWidgets('D1 — retry relaunches the same config', (tester) async {
    final document = _document();
    final config = _config(document, MeasureRange(start: 0, endExclusive: 1));
    final harness = await _pump(tester, document: document, config: config);

    await tester.tap(find.byKey(const Key('song-result-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-session')), findsOneWidget);
    final inputs = harness.sessionExtra! as SongTrainerControllerInputs;
    expect(inputs.config, config);
    expect(inputs.config!.range, MeasureRange(start: 0, endExclusive: 1));
  });

  testWidgets('D2 — next starts the following section', (tester) async {
    final document = _document();
    final config = _config(document, MeasureRange(start: 0, endExclusive: 1));
    final harness = await _pump(tester, document: document, config: config);

    await tester.tap(find.byKey(const Key('song-result-next-section')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-session')), findsOneWidget);
    final inputs = harness.sessionExtra! as SongTrainerControllerInputs;
    expect(inputs.config!.range, MeasureRange(start: 1, endExclusive: 2));
    expect(inputs.config!.selection, SectionRange(SongSectionId('outro')));
    // Everything else the user chose is carried over verbatim.
    expect(inputs.config!.targetSpeed, config.targetSpeed);
    expect(inputs.config!.countInBars, config.countInBars);
    expect(inputs.config!.trackId, config.trackId);
  });

  testWidgets('D3 — next falls back to the song overview', (tester) async {
    final document = _document();
    final config = _config(document, MeasureRange(start: 1, endExclusive: 2));
    await _pump(tester, document: document, config: config);

    await tester.tap(find.byKey(const Key('song-result-next-section')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-overview')), findsOneWidget);
  });

  testWidgets('D4 — no config keeps both CTAs disabled', (tester) async {
    final document = _document();
    await _pump(tester, document: document, config: null);

    final retry = tester.widget<SsButton>(
      find.byKey(const Key('song-result-retry')),
    );
    final next = tester.widget<SsButton>(
      find.byKey(const Key('song-result-next-section')),
    );
    expect(retry.onPressed, isNull);
    expect(next.onPressed, isNull);
  });
}

final class _RouteHarness {
  Object? sessionExtra;
}

Future<_RouteHarness> _pump(
  WidgetTester tester, {
  required SongDocument document,
  required TrainerConfig? config,
}) async {
  final harness = _RouteHarness();
  final repository = InMemorySongRepository();
  await repository.create(document);
  final router = GoRouter(
    initialLocation: '/result',
    routes: <RouteBase>[
      GoRoute(
        path: '/result',
        builder: (_, _) => SongTrainerResultRoute(
          args: SongTrainerResultArgs(result: _result(), config: config),
        ),
      ),
      GoRoute(
        path: AppRoutes.songTrainerSession,
        builder: (_, state) {
          harness.sessionExtra = state.extra;
          return const Scaffold(
            key: Key('stub-session'),
            body: SizedBox.shrink(),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.songTrainerOverview,
        builder: (_, _) =>
            const Scaffold(key: Key('stub-overview'), body: SizedBox.shrink()),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        songRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// A result with no verdicts: the route then asks for no progress
/// projection, which keeps this test focused on the two CTAs.
SongTrainerResult _result() => SongTrainerResult(
  sessionResult: const PracticeSessionResult(
    id: 'practice-result',
    activeDuration: Duration(seconds: 4),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: null,
    coachingSummary: <String>[],
  ),
  verdicts: const <SongTrainerVerdict>[],
  measureResults: <SongMeasureTrainerResult>[
    SongMeasureTrainerResult(
      measureIndex: 0,
      verdicts: const <SongTrainerVerdict>[],
      averageEventScore: 0.5,
    ),
  ],
  sectionResults: const <SongSectionTrainerResult>[],
);

/// Two measures; the second one is a section, so "next section" has exactly
/// one candidate from measure 0 and none from measure 1.
SongDocument _document() {
  final now = DateTime.utc(2026, 9, 7);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('result-song'),
    revision: 0,
    metadata: SongMetadata(title: 'Result song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'result.song',
      sha256: 'c' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: song_time.BeatPosition.fromBeats(4)),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('outro'),
        name: 'Outro',
        startMeasure: 1,
        endMeasureExclusive: 2,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
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

/// Pitch mode: the compiler short-circuits to the playback-only compilation,
/// so the launcher succeeds without authored events.
TrainerConfig _config(SongDocument document, MeasureRange range) =>
    TrainerConfig(
      songId: document.id,
      songRevision: document.revision,
      trackId: SongTrackId('chords'),
      selection: range,
      range: range,
      mode: TrainerMode.pitch,
      targetSpeed: 0.75,
      countInBars: 2,
      metronomeEnabled: false,
      loopConfig: LoopConfig(range: range),
      tuningReminder: null,
      capo: 0,
      capoReminder: false,
    );
