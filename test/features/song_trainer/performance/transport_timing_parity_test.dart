import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/vision/song_vision_adapter.dart';
import 'package:strumsight/features/song_trainer/domain/models/note_scoring_models.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_vision_summary.dart';
import 'package:strumsight/features/song_trainer/domain/services/monophonic_note_scorer.dart';
import 'package:strumsight/features/vision/domain/integration/public.dart';

void main() {
  test(
    'fixed song loop transport timeline and scoring are bit-identical with Vision on or off',
    () async {
      final audioOnly = await _runFixedSongLoop(visionEnabled: false);
      final withVision = await _runFixedSongLoop(visionEnabled: true);

      expect(withVision.transportTimeline, audioOnly.transportTimeline);
      expect(withVision.scoringResult, audioOnly.scoringResult);
      expect(withVision.visionSummary!.loops, hasLength(2));
      expect(
        withVision.visionSummary!.loops[1].quality,
        VisionMetricState.notObservable,
      );
    },
  );

  test(
    'normal, warm and hot thermal decisions never stop the playing song',
    () async {
      for (final entry in <int, VisionCadence>{
        0: VisionCadence.full,
        VisionCadencePolicy.reducedCadenceThermalLoad: VisionCadence.reduced,
        VisionCadencePolicy.audioOnlyThermalLoad: VisionCadence.audioOnly,
      }.entries) {
        final player = FakeBackingAudioPlayer();
        final transport = SongTransport(
          player: player,
          clock: FakeSongTransportClock(),
        );
        addTearDown(transport.dispose);
        await transport.dispatch(PrepareSongTransport(asset: _asset));
        await transport.dispatch(const StartSongTransport());

        final decision = const VisionCadencePolicy().decide(
          thermalLoad: VisionThermalLoad(entry.key),
          supportsVision: true,
        );
        final summary = _adapter.aggregate(
          contract: _contract,
          visionSessionId: 'thermal-session',
          songId: 'song-id',
          cadenceDecision: decision,
          loops: <SongVisionLoopObservation>[_loop('thermal-${entry.key}')],
        );

        expect(decision.cadence, entry.value);
        expect(summary.cadence, entry.value);
        expect(transport.state.phase, SongTransportPhase.playing);
        expect(transport.state.backingStatus, BackingPlaybackStatus.playing);
        expect(player.pauseCalls, 0);
      }
    },
  );
}

final VisionSongContract _contract = VisionSongContract(
  id: 'vision.song.v1',
  setupProfile: VisionSetupProfile.practiceBalanced,
  minimumPostureSectionDuration: Duration(seconds: 30),
);

const SongVisionAdapter _adapter = SongVisionAdapter(
  postureDriftFor: _postureDrift,
);

double _postureDrift(SongVisionLoopObservation _) => 0.2;

Future<_ParitySnapshot> _runFixedSongLoop({required bool visionEnabled}) async {
  final player = FakeBackingAudioPlayer();
  final clock = FakeSongTransportClock();
  final transport = SongTransport(player: player, clock: clock);
  final timeline = <String>[];
  try {
    await transport.dispatch(PrepareSongTransport(asset: _asset));
    _record(timeline, transport);
    await transport.dispatch(const StartSongTransport());
    _record(timeline, transport);
    clock.advance(const Duration(seconds: 1));
    _record(timeline, transport);
    await transport.dispatch(const PauseSongTransport());
    _record(timeline, transport);
    await transport.dispatch(const ResumeSongTransport());
    clock.advance(const Duration(milliseconds: 500));
    _record(timeline, transport);

    final scoringResult = _scoreFixedLoop();
    final visionSummary = visionEnabled
        ? _adapter.aggregate(
            contract: _contract,
            visionSessionId: 'vision-session',
            songId: 'song-id',
            cadenceDecision: const VisionCadenceDecision(VisionCadence.full),
            loops: <SongVisionLoopObservation>[
              _loop('loop-1'),
              SongVisionLoopObservation(
                loopIterationId: 'loop-2',
                sectionId: 'section-a',
                sectionDuration: const Duration(seconds: 31),
                quality: VisionMetricState.notObservable,
              ),
            ],
          )
        : null;
    return _ParitySnapshot(
      transportTimeline: timeline,
      scoringResult: scoringResult,
      visionSummary: visionSummary,
    );
  } finally {
    await transport.dispose();
  }
}

void _record(List<String> timeline, SongTransport transport) {
  final state = transport.state;
  timeline.add(
    '${state.phase.name}|${state.backingStatus.name}|${state.activePosition.inMicroseconds}',
  );
}

NoteScoringResult _scoreFixedLoop() {
  final startedAt = DateTime.utc(2026, 8, 8);
  final scorer = MonophonicNoteScorer(
    startedAt: startedAt,
    targets: const <NoteScoringTarget>[
      NoteScoringTarget(
        id: 'loop-note',
        midiPitch: 45,
        start: Duration(seconds: 1),
        duration: Duration(milliseconds: 500),
      ),
    ],
  );
  scorer.observe(
    PitchObservation(
      observedAt: startedAt.add(const Duration(milliseconds: 1080)),
      frequencyHz: 110,
      midiPitch: 45,
      centsFromNearest: 12,
      clarity: 0.85,
      rms: 0.014,
      stable: true,
    ),
  );
  scorer.advance(const Duration(seconds: 2));
  return scorer.finalize();
}

SongVisionLoopObservation _loop(String id) => SongVisionLoopObservation(
  loopIterationId: id,
  sectionId: 'section-a',
  sectionDuration: const Duration(seconds: 31),
  quality: VisionMetricState.good,
  strokeConsistency: 0.9,
  handTravel: 0.4,
);

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('parity-backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 1024,
  mimeType: 'audio/mpeg',
  durationMs: 10000,
);

final class _ParitySnapshot {
  const _ParitySnapshot({
    required this.transportTimeline,
    required this.scoringResult,
    required this.visionSummary,
  });

  final List<String> transportTimeline;
  final NoteScoringResult scoringResult;
  final SongVisionSummary? visionSummary;
}
