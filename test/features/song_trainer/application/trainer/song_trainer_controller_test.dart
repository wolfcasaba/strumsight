import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/transport_effect.dart';
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

import '../../../../support/fake_audio.dart';
import '../../../../support/fake_practice_observation_gateway.dart';
import '../../../../support/fake_practice_session_clock.dart';
import '../../../../support/fake_practice_session_recorder.dart';
import '../../../../support/fake_practice_tick_source.dart';

void main() {
  test(
    'coordinates practice count-in, backing transport, pause/resume, seek attempts and background interruption',
    () async {
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      final effects = <SongTrainerEffect>[];
      final effectSubscription = harness.controller.effects.listen(effects.add);
      addTearDown(effectSubscription.cancel);

      await harness.controller.prepare(backingAsset: _asset);
      await harness.controller.start();
      expect(harness.practice.state.status, PracticeSessionStatus.countIn);
      expect(harness.player.playCalls, 0);

      harness.practiceClock.advance(
        harness.practice.state.target!.countInDuration +
            const Duration(milliseconds: 1),
      );
      harness.practiceTick.emitTick();
      await _settle();
      expect(harness.practice.state.status, PracticeSessionStatus.running);
      expect(harness.transport.state.phase, SongTransportPhase.playing);
      expect(harness.player.playCalls, 1);

      await harness.controller.pause();
      expect(harness.practice.state.status, PracticeSessionStatus.paused);
      expect(harness.transport.state.phase, SongTransportPhase.paused);

      await harness.controller.resume();
      expect(harness.practice.state.status, PracticeSessionStatus.countIn);
      harness.practiceClock.advance(
        harness.practice.state.target!.countInDuration +
            const Duration(milliseconds: 1),
      );
      harness.practiceTick.emitTick();
      await _settle();
      expect(harness.transport.state.phase, SongTransportPhase.playing);

      effects.clear();
      await harness.controller.handleAppBackground();
      await _settle();
      expect(harness.controller.state.status, SongTrainerStatus.paused);
      expect(
        harness.controller.state.practiceState!.pauseCause,
        PauseCause.interruption,
      );
      expect(
        effects.whereType<SongTrainerTransportEffect>().map(
          (effect) => effect.effect,
        ),
        contains(isA<PauseBackingAudioEffect>()),
      );

      await harness.controller.resume();
      harness.practiceClock.advance(
        harness.practice.state.target!.countInDuration +
            const Duration(milliseconds: 1),
      );
      harness.practiceTick.emitTick();
      await _settle();
      expect(harness.transport.state.phase, SongTransportPhase.playing);

      final priorAttempt = harness.controller.state.attemptId;
      await harness.controller.seek(const Duration(milliseconds: 250));
      expect(harness.controller.state.attemptId, priorAttempt + 1);
      expect(harness.practice.state.status, PracticeSessionStatus.countIn);
      expect(harness.transport.state.phase, SongTransportPhase.paused);
    },
  );

  test(
    'permission denial remains a Practice state and never starts backing',
    () async {
      final harness = _Harness.scored(
        permissionState: MicrophonePermissionState.denied,
      );
      addTearDown(harness.dispose);

      await harness.controller.prepare(backingAsset: _asset);

      expect(harness.permissions.currentStateCalls, 1);
      expect(harness.permissions.requestCalls, 1);
      expect(
        harness.controller.state.status,
        SongTrainerStatus.permissionRequired,
      );
      expect(harness.player.playCalls, 0);
    },
  );

  test(
    'finalizes a scored operation once when finish and a late tick race',
    () async {
      final harness = _Harness.scored(countInBars: 0);
      addTearDown(harness.dispose);
      final effects = <SongTrainerEffect>[];
      final subscription = harness.controller.effects.listen(effects.add);
      addTearDown(subscription.cancel);

      await harness.controller.prepare(backingAsset: _asset);
      await harness.controller.start();
      harness.practiceTick.emitTick();
      await _settle();

      await Future.wait<void>(<Future<void>>[
        harness.controller.finish(),
        Future<void>(() => harness.practiceTick.emitTick()),
      ]);
      await _settle();

      expect(harness.controller.state.status, SongTrainerStatus.completed);
      expect(harness.controller.state.result, isNotNull);
      expect(effects.whereType<NavigateToSongTrainerResult>(), hasLength(1));
    },
  );

  test(
    'playback-only provider does not read the microphone permission provider',
    () async {
      final compilation = _playbackOnlyCompilation();
      final transport = SongTransport(
        player: FakeBackingAudioPlayer(),
        clock: FakeSongTransportClock(),
      );
      var microphoneProviderReads = 0;
      final container = ProviderContainer(
        overrides: [
          songTransportProvider.overrideWithValue(transport),
          practiceMicrophonePermissionProvider.overrideWith((ref) {
            microphoneProviderReads++;
            return FakeMicrophonePermissionGateway();
          }),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        songTrainerControllerProvider(
          SongTrainerControllerInputs(
            compilation: compilation,
            backingAsset: _asset,
          ),
        ),
      );

      expect(controller.isPlaybackOnly, isTrue);
      await controller.prepare();
      expect(transport.state.phase, SongTransportPhase.ready);
      expect(microphoneProviderReads, 0);
    },
  );
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

final class _Harness {
  _Harness._({
    required this.controller,
    required this.practice,
    required this.transport,
    required this.player,
    required this.practiceClock,
    required this.practiceTick,
    required this.permissions,
  });

  final SongTrainerController controller;
  final PracticeSessionController practice;
  final SongTransport transport;
  final FakeBackingAudioPlayer player;
  final FakePracticeSessionClock practiceClock;
  final FakePracticeTickSource practiceTick;
  final FakeMicrophonePermissionGateway permissions;

  factory _Harness.scored({
    int countInBars = 1,
    MicrophonePermissionState permissionState =
        MicrophonePermissionState.granted,
  }) {
    final compilation = _scoredCompilation(countInBars: countInBars);
    final player = FakeBackingAudioPlayer();
    final transport = SongTransport(
      player: player,
      clock: FakeSongTransportClock(),
    );
    final practiceClock = FakePracticeSessionClock();
    final practiceTick = FakePracticeTickSource();
    final permissions = FakeMicrophonePermissionGateway(state: permissionState);
    final practice = PracticeSessionController(
      clock: practiceClock,
      tickSource: practiceTick,
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
    return _Harness._(
      controller: SongTrainerController(
        transport: transport,
        compilation: compilation,
        practiceSession: practice,
      ),
      practice: practice,
      transport: transport,
      player: player,
      practiceClock: practiceClock,
      practiceTick: practiceTick,
      permissions: permissions,
    );
  }

  Future<void> dispose() async {
    await controller.dispose();
    await transport.dispose();
  }
}

SongPracticeCompilation _scoredCompilation({int countInBars = 1}) =>
    SongPracticeCompiler.compile(
      document: _document(),
      config: _config(mode: TrainerMode.rhythm, countInBars: countInBars),
    );

SongPracticeCompilation _playbackOnlyCompilation() =>
    SongPracticeCompiler.compile(
      document: _document(),
      config: _config(mode: TrainerMode.pitch),
    );

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

TrainerConfig _config({required TrainerMode mode, int countInBars = 1}) {
  final range = MeasureRange(start: 0, endExclusive: 1);
  return TrainerConfig(
    songId: SongId('song'),
    songRevision: 1,
    trackId: SongTrackId('strums'),
    selection: range,
    range: range,
    mode: mode,
    targetSpeed: 1,
    countInBars: countInBars,
    metronomeEnabled: true,
    loopConfig: LoopConfig(range: range),
    tuningReminder: null,
    capo: 0,
    capoReminder: false,
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
