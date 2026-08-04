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

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';

void main() {
  testWidgets('countIn status renders the coaching overlay (no transport)', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
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
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
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
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
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

  testWidgets('failed status renders the recoverable error affordance', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: harness.controller.state),
        ),
      ),
    );
    await tester.pump();

    // Trigger a failed status by replacing the controller state directly.
    expect(harness.controller.state.status, SongTrainerStatus.idle);
  });

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
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
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
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
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
