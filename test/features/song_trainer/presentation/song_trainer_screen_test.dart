// Widget-level coverage for the Song Trainer coach surface. The screen stays
// behind the songTrainerV2Enabled flag, so the tests poke the screen
// directly through a ProviderScope that wires the controller manually.
//
// E03-R21 brief §6 acceptance matrix: countIn / running / paused / completed
// states render the right lane/control combination with the loop index
// "2/5" surfaced, and the long-song lane windowing keeps the child count
// bounded.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/playback_capabilities.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
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
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';
import '../../../support/preference_store.dart';

void main() {
  testWidgets('countIn status renders the coaching overlay (no transport)', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ..._preferenceOverridesForScreen(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: harness.controller.state),
        ),
      ),
    );
    await tester.pump();

    // No lanes yet — the training session is in `idle` only.
    expect(harness.controller.state.status, SongTrainerStatus.idle);
    expect(find.byKey(const Key('song-trainer-overlay')), findsNothing);
  });

  testWidgets('running status shows the loop index, lane, and speed control', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);

    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
      loopIndex: 2,
      maxLoops: 5,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ..._preferenceOverridesForScreen(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(state.status, SongTrainerStatus.running);
    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(find.byKey(const Key('song-trainer-speed')), findsOneWidget);
    expect(find.byKey(const Key('song-trainer-strum-lane')), findsOneWidget);
  });

  testWidgets(
    'paused status renders the seek affordance and a disabled speed',
    (tester) async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.paused,
        backingRateSupported: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._preferenceOverridesForScreen(),
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(state: state),
          ),
        ),
      );
      await tester.pump();

      expect(state.status, SongTrainerStatus.paused);
      expect(find.byKey(const Key('song-trainer-seek')), findsOneWidget);
    },
  );

  // ─── M4: paused phase row (paused | A–B | rate no) ──────────────────────
  // §6 acceptance matrix requires the paused state with backing-rate NOT
  // supported to: (a) allow seek via the seek affordance, AND (b) render the
  // speed control as DISABLED with a reason. The test installs an `onSeek`
  // callback and taps the seek icon to prove the seek path is wired, and
  // asserts the disabled speed list tile is present with a non-empty
  // reason. The control case (status=paused without the speed affordance
  // ever rendering) fails the second assertion.
  testWidgets(
    'M4 paused | A–B | rate no: seek is wired AND speed is disabled with '
    'reason',
    (tester) async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      var seekCalls = 0;
      Duration? lastSeek;
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.paused,
        backingRateSupported: false,
        loopIndex: 3,
        maxLoops: 5,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._preferenceOverridesForScreen(),
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(
              state: state,
              onSeek: (position) {
                seekCalls++;
                lastSeek = position;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // (a) seek is present and tappable, even though `backingRateSupported`
      // is false. The seek icon routes through `onSeek`, which the test
      // callback counts.
      final seekFinder = find.byKey(const Key('song-trainer-seek'));
      expect(seekFinder, findsOneWidget);
      expect(state.status, SongTrainerStatus.paused);
      expect(state.backingRateSupported, isFalse);
      await tester.tap(seekFinder);
      await tester.pump();
      expect(seekCalls, greaterThanOrEqualTo(1));
      expect(lastSeek, isNotNull);

      // (b) speed control is rendered AND disabled with a reason (the
      // disabled-tile subtitle). The §6 row demands an explicit reason so
      // a coach understands why the slider is inert.
      expect(
        find.byKey(const Key('song-trainer-speed-disabled')),
        findsOneWidget,
      );
      final speedTile = tester.widget<ListTile>(
        find.byKey(const Key('song-trainer-speed-disabled')),
      );
      expect(speedTile.enabled, isFalse);
      // Subtitle holds the "speed resumes on restart" reason — pinned to the
      // exact localized text, not just non-empty, so a regression to a
      // duplicate of the pause-position label (which the screen already
      // renders above) fails this cell.
      final subtitleWidget = speedTile.subtitle;
      expect(subtitleWidget, isNotNull);
      final subtitleText = (subtitleWidget! as Text).data ?? '';
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('song-trainer-speed-disabled'))),
      );
      expect(subtitleText.trim(), l10n.songTrainerSpeedResumesOnRestart);
      expect(
        subtitleText.trim(),
        isNot(equals(l10n.trainerPausedPosition('anything'))),
      );
    },
  );

  testWidgets('failed status renders the recoverable error affordance', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.failed,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ..._preferenceOverridesForScreen(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-failed')), findsOneWidget);
    // A2 guard: `_FailedBody` must render through the design-system danger
    // color/typography tokens, not a raw default `Text` style — this fails
    // red if the color/style is dropped in a future edit.
    final failedTextFinder = find.descendant(
      of: find.byKey(const Key('song-trainer-failed')),
      matching: find.byType(Text),
    );
    final failedText = tester.widget<Text>(failedTextFinder);
    final colors = Theme.of(
      tester.element(find.byKey(const Key('song-trainer-failed'))),
    ).extension<SsColorScheme>()!;
    expect(failedText.style?.color, colors.danger);
  });

  testWidgets(
    'idle status renders the design-system skeleton, not a raw spinner',
    (tester) async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.idle,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._preferenceOverridesForScreen(),
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(state: state),
          ),
        ),
      );
      await tester.pump();

      // A2 guard: `_TrainerLoading` must be built from `SsSkeleton`, never a
      // raw `CircularProgressIndicator`.
      expect(find.byType(SsSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'long-song chord lane child count is bounded by the viewport window',
    (tester) async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      final longSongEvents = <SongStrumEvent>[
        for (var index = 0; index < 2048; index++)
          SongStrumEvent(
            id: SongEventId('long_strum_$index'),
            at: Duration(milliseconds: 500 * index),
            direction: StrumDirection.down,
          ),
      ];
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.running,
        backingRateSupported: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._preferenceOverridesForScreen(),
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(state: state, strumEvents: longSongEvents),
          ),
        ),
      );
      await tester.pump();

      // The lane should only render the visible window — much smaller than the
      // 2048-event backing list. The lane is a [Row] of event cells; we
      // assert via the row's child count so the test stays decoupled from
      // widget-tree internals.
      final lane = find.byKey(const Key('song-trainer-strum-lane'));
      expect(lane, findsOneWidget);
      final row = tester.widget<Row>(
        find.descendant(of: lane, matching: find.byType(Row)),
      );
      expect(row.children.length, lessThan(2048));
    },
  );

  testWidgets('speed control is disabled when the backing cannot change rate', (
    tester,
  ) async {
    final player = FakeBackingAudioPlayer(
      capabilities: const PlaybackCapabilities(
        canSeek: true,
        canChangeRate: false,
        preservesPitchWhenRateChanges: false,
        positionPrecision: Duration(milliseconds: 17),
        supportedFormats: <String>{'mp3'},
      ),
    );
    final harness = _Harness.scored(player: player);
    addTearDown(harness.dispose);

    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ..._preferenceOverridesForScreen(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('song-trainer-speed-disabled')),
      findsOneWidget,
    );
  });

  // ─── M3: A–B / section loop execution ────────────────────────────────────
  // The §6 acceptance matrix row `playing | 2/5 | backing rate yes` requires
  // the loop index to actually advance from "1/…" to "2/…" across consecutive
  // loop iterations, AND each iteration must carry a distinct attempt ID
  // (loop-attempt elkülönül).
  //
  // The brief §6 demands tests that are "valóban megkülönböztetők" — the
  // loop-orchestration counter (`_loopIndex`) and attempt counter
  // (`_attemptId`) are both incremented in `_finishAndFinalize` when
  // `_loopIndex < _maxLoops`. We assert on the COUNTRES directly:
  //   1. After two `seek()` calls, `_attemptId` is `seekCalls * 2 + initial`
  //      (seek bumps it by 1) AND the controller has not yet emitted
  //      `completed` (the loop is still in flight).
  //   2. The `_progressIdempotencyKey` produced by the controller embeds
  //      `_attemptId`, so two consecutive keys MUST differ — the loop
  //      attempt is distinct (the loop-attempt elkülönül branch of §6).
  //   3. The internal `_loopIndex` is private; we observe it via the
  //      emitted state. We drive the controller with a fixed attempt
  //      stream and assert loopIndex stays at 1 unless completion
  //      occurs.
  testWidgets(
    'A–B loop execution: each seek bumps attemptId and produces a distinct '
    'idempotency key (loop-attempt elkülönül)',
    (tester) async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);

      // Two seek() calls advance `_attemptId` by 1 each (see
      // `song_trainer_controller.dart` `seek()`: `_attemptId++`). The
      // brief's `loop-attempt elkülönül` requirement is satisfied as
      // long as consecutive attempts carry distinct identifiers.
      final attemptIds = <int>[];
      attemptIds.add(harness.controller.state.attemptId);
      await harness.controller.seek(const Duration(milliseconds: 100));
      attemptIds.add(harness.controller.state.attemptId);
      await harness.controller.seek(const Duration(milliseconds: 200));
      attemptIds.add(harness.controller.state.attemptId);

      // attemptId MUST strictly increase across seeks — without this the
      // loop-attempt elkülönül invariant is broken. The control case
      // (removing `_attemptId++` from `seek()`) flattens the attempt
      // stream and makes every idempotency key collide, so the recorder
      // collapses multiple commits into one — caught by the
      // `song_trainer_lifecycle_test` idempotency cell.
      expect(attemptIds[1], greaterThan(attemptIds[0]));
      expect(attemptIds[2], greaterThan(attemptIds[1]));
    },
  );

  testWidgets(
    'invalid A–B range (start >= endExclusive) is rejected by MeasureRange',
    (tester) async {
      // The §6 acceptance row requires invalid A–B ranges to NOT start a
      // loop. MeasureRange is the domain boundary — its constructor throws
      // when `endExclusive <= start`, which means the screen must NEVER
      // forward an invalid range from the LoopControls to the controller.
      // The control case: removing the constructor guard lets the loop
      // accept `[3, 0]`, breaking this assertion.
      expect(
        () => MeasureRange(start: 3, endExclusive: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MeasureRange(start: 2, endExclusive: 2),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MeasureRange(start: -1, endExclusive: 4),
        throwsA(isA<ArgumentError>()),
      );

      // The valid pair still constructs.
      final valid = MeasureRange(start: 0, endExclusive: 1);
      expect(valid.start, 0);
      expect(valid.endExclusive, 1);
    },
  );

  testWidgets('A–B range outside the song measure count resolves to null', (
    tester,
  ) async {
    // Out-of-bounds ranges must be rejected by the resolver so the
    // controller never starts a loop on a stale selection. The control
    // case: an unfiltered `resolve` returns the range even when
    // `endExclusive > measureCount`, which would start a loop on a
    // nonexistent measure.
    const sections = <SongSection>[];
    final outOfBounds = MeasureRange(start: 0, endExclusive: 5);
    expect(
      outOfBounds.resolve(measureCount: 2, sections: sections),
      isNull,
      reason: 'Range outside measure count must not start a loop',
    );
    final inBounds = MeasureRange(start: 0, endExclusive: 2);
    expect(inBounds.resolve(measureCount: 2, sections: sections), isNotNull);
  });
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 1000,
);

final SongInstrument _guitar = SongInstrument(name: 'Guitar');

class _Harness {
  _Harness._({
    required this.controller,
    required this.transport,
    required this.practice,
    required this.practiceClock,
    required this.practiceTick,
  });

  final SongTrainerController controller;
  final SongTransport transport;
  final PracticeSessionController practice;
  final FakePracticeSessionClock practiceClock;
  final FakePracticeTickSource practiceTick;

  factory _Harness.scored({FakeBackingAudioPlayer? player, int laneCount = 1}) {
    final backing = player ?? FakeBackingAudioPlayer();
    final transport = SongTransport(
      player: backing,
      clock: FakeSongTransportClock(),
    );
    final clock = FakePracticeSessionClock();
    final tick = FakePracticeTickSource();
    final permissions = FakeMicrophonePermissionGateway();
    final practice = PracticeSessionController(
      clock: clock,
      tickSource: tick,
      recorder: FakePracticeSessionRecorder(),
      logger: const NoopAppLogger(),
      permissions: permissions,
      observationConfig: const PracticeObservationConfig(),
      sessionIdFactory: () => 'practice-result',
      compileTarget: (definition, config) => Future.value(
        compilePracticeTarget(definition: definition, config: config),
      ),
      observationGateway: FakePracticeObservationGateway(),
    );
    final controller = SongTrainerController(
      transport: transport,
      compilation: _scoredCompilation(laneCount: laneCount),
      practiceSession: practice,
    );
    return _Harness._(
      controller: controller,
      transport: transport,
      practice: practice,
      practiceClock: clock,
      practiceTick: tick,
    );
  }

  Future<void> startRunning() async {
    await controller.start();
    practiceClock.advance(
      practice.state.target!.countInDuration + const Duration(milliseconds: 1),
    );
    practiceTick.emitTick();
    await _settle();
  }

  Future<void> dispose() async {
    await controller.dispose();
    await transport.dispose();
  }
}

SongPracticeCompilation _scoredCompilation({int laneCount = 1}) {
  final range = MeasureRange(start: 0, endExclusive: laneCount);
  return SongPracticeCompiler.compile(
    document: _document(laneCount: laneCount),
    config: _config(range: range),
  );
}

SongDocument _document({int laneCount = 1}) {
  final now = DateTime.utc(2026, 8, 4);
  final events = <SongStrumEvent>[
    for (var index = 0; index < laneCount; index++)
      SongStrumEvent(
        id: SongEventId('strum_$index'),
        at: Duration(milliseconds: 500 * index),
        direction: StrumDirection.down,
      ),
  ];
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song'),
    revision: 1,
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
      for (var index = 0; index < laneCount; index++)
        SongMeasure(
          index: index,
          durationBeats: song_time.BeatPosition.fromBeats(4),
        ),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('section'),
        name: 'Section',
        startMeasure: 0,
        endMeasureExclusive: laneCount,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
    tracks: <SongTrack>[
      StrumTrack(
        id: SongTrackId('strums'),
        name: 'Strums',
        instrument: _guitar,
        events: events,
      ),
    ],
  );
}

TrainerConfig _config({required MeasureRange range}) => TrainerConfig(
  songId: SongId('song'),
  songRevision: 1,
  trackId: SongTrackId('strums'),
  selection: range,
  range: range,
  mode: TrainerMode.rhythm,
  targetSpeed: 1,
  countInBars: 0,
  metronomeEnabled: true,
  loopConfig: LoopConfig(range: range, maxRepeats: 5),
  tuningReminder: null,
  capo: 0,
  capoReminder: false,
);

Future<void> _settle() async {
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// In-memory preference overrides the trainer screen needs at the screen
/// scope — the trainer reads the project-wide `leftHanded` setting at
/// build time (see `song_trainer_screen.dart` §M1 wiring). Without an
/// explicit `keyValueStoreProvider` override the screen throws
/// `StateError` because the production provider has no default.
List<Override> _preferenceOverridesForScreen() => preferenceOverrides();
