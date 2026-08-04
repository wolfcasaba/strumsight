import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_config.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_gateway.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_capability.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/note_scoring_models.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/note_lane.dart';

void main() {
  test(
    'controller starts only monophonic pitch scoring and resolves capo without a transposition field',
    () async {
      final startedAt = DateTime.utc(2026, 8, 4);
      final gateway = _FakePitchGateway();
      final session = MonophonicPitchSession.fromSongNotes(
        gateway: gateway,
        startedAt: startedAt,
        capability: const SongPitchCapability(
          display: true,
          scoring: true,
          isMonophonic: true,
        ),
        capo: 2,
        notes: <SongNoteEvent>[
          SongNoteEvent(
            id: SongEventId('e2'),
            start: Duration.zero,
            duration: const Duration(milliseconds: 300),
            midiPitch: 40,
          ),
        ],
      );
      expect(session.targets.single.midiPitch, 42);
      final controller = SongTrainerController(
        transport: SongTransport(
          player: FakeBackingAudioPlayer(),
          clock: FakeSongTransportClock(),
        ),
        compilation: const SongPracticeCompilation.playbackOnly(),
        pitchSession: session,
      );
      final updates = <NoteScoringUpdate>[];
      final subscription = controller.noteUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      await controller.prepare();
      expect(gateway.startCalls, 1);

      gateway.emit(
        PitchObservation(
          observedAt: startedAt.add(const Duration(milliseconds: 80)),
          frequencyHz: 82.41,
          midiPitch: 42,
          centsFromNearest: 0,
          clarity: 0.85,
          rms: 0.014,
          stable: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        updates.single.noteUpdates.single.pitchGrade,
        NotePitchGrade.exact,
      );

      await controller.pause();
      expect(gateway.stopCalls, 1);
      await controller.resume();
      expect(gateway.startCalls, 2);
      await controller.seek(Duration.zero);
      expect(gateway.stopCalls, 2);
      await controller.resume();
      expect(gateway.startCalls, 3);
    },
  );

  test('controller never starts a polyphonic pitch session', () async {
    final gateway = _FakePitchGateway();
    final session = MonophonicPitchSession.fromSongNotes(
      gateway: gateway,
      startedAt: DateTime.utc(2026, 8, 4),
      capability: const SongPitchCapability(
        display: true,
        scoring: false,
        isMonophonic: false,
      ),
      capo: 0,
      notes: const <SongNoteEvent>[],
    );
    final controller = SongTrainerController(
      transport: SongTransport(
        player: FakeBackingAudioPlayer(),
        clock: FakeSongTransportClock(),
      ),
      compilation: const SongPracticeCompilation.playbackOnly(),
      pitchSession: session,
    );
    addTearDown(controller.dispose);

    await controller.prepare();

    expect(gateway.startCalls, 0);
  });

  testWidgets('note lane renders each resolved target as a feedback segment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteLane(
          targets: const <NoteScoringTarget>[
            NoteScoringTarget(
              id: 'e2',
              midiPitch: 40,
              start: Duration.zero,
              duration: Duration(milliseconds: 100),
            ),
            NoteScoringTarget(
              id: 'a2',
              midiPitch: 45,
              start: Duration(milliseconds: 100),
              duration: Duration(milliseconds: 100),
            ),
          ],
          update: const NoteScoringUpdate(
            compensatedAt: Duration.zero,
            noteUpdates: <NoteScoringNoteUpdate>[
              NoteScoringNoteUpdate(
                targetId: 'e2',
                pitchGrade: NotePitchGrade.exact,
                onsetGrade: NoteOnsetGrade.onTime,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('note-lane-e2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('note-lane-a2')), findsOneWidget);
  });
}

final class _FakePitchGateway implements PitchObservationGateway {
  final StreamController<PitchObservation> _observations =
      StreamController<PitchObservation>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<PitchObservation> get observations => _observations.stream;

  @override
  Future<AppResult<void>> start(PitchObservationConfig config) async {
    startCalls++;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls++;
    return const Success<void>(null);
  }

  void emit(PitchObservation observation) => _observations.add(observation);
}
