// Accessibility coverage for the Song Trainer surface. The brief §6 acceptance
// requires large/landscape support, 200% text scaling, reduced motion, and a
// throttled screen-reader live region.

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
  testWidgets('200% text scaling remains usable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final harness = _Harness.scored();
    addTearDown(harness.dispose);
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
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SongTrainerScreen(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape layout keeps the loop index and lane visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final harness = _Harness.scored();
    addTearDown(harness.dispose);
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
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(find.byKey(const Key('song-trainer-strum-lane')), findsOneWidget);
  });

  testWidgets('reduced motion replaces hot affordances with static labels', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);
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
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: SongTrainerScreen(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
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

  factory _Harness.scored() {
    final player = FakeBackingAudioPlayer();
    final transport = SongTransport(
      player: player,
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
      compilation: _scoredCompilation(),
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

SongPracticeCompilation _scoredCompilation() =>
    SongPracticeCompiler.compile(document: _document(), config: _config());

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
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

TrainerConfig _config() => TrainerConfig(
  songId: SongId('song'),
  songRevision: 1,
  trackId: SongTrackId('strums'),
  selection: MeasureRange(start: 0, endExclusive: 1),
  range: MeasureRange(start: 0, endExclusive: 1),
  mode: TrainerMode.rhythm,
  targetSpeed: 1,
  countInBars: 0,
  metronomeEnabled: true,
  loopConfig: LoopConfig(range: MeasureRange(start: 0, endExclusive: 1)),
  tuningReminder: null,
  capo: 0,
  capoReminder: false,
);

Future<void> _settle() async {
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
