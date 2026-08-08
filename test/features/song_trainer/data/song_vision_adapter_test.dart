import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/vision/song_vision_adapter.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_vision_summary.dart';
import 'package:strumsight/features/vision/domain/integration/public.dart';

void main() {
  final contract = VisionSongContract(
    id: 'vision.song.v1',
    setupProfile: VisionSetupProfile.practiceBalanced,
    minimumPostureSectionDuration: Duration(seconds: 30),
  );

  test(
    'preserves every loop and marks missing quality rather than dropping it',
    () {
      var postureCalls = 0;
      final adapter = SongVisionAdapter(
        postureDriftFor: (_) {
          postureCalls++;
          return 0.12;
        },
      );

      final summary = adapter.aggregate(
        contract: contract,
        visionSessionId: 'vision-session',
        songId: 'song-id',
        cadenceDecision: const VisionCadenceDecision(VisionCadence.full),
        loops: <SongVisionLoopObservation>[
          _loop(
            id: 'loop-1',
            duration: const Duration(seconds: 30),
            quality: VisionMetricState.good,
          ),
          _loop(
            id: 'loop-2',
            duration: const Duration(seconds: 31),
            quality: VisionMetricState.notObservable,
          ),
        ],
      );

      expect(summary.loops, hasLength(2));
      expect(summary.loops[0].quality, VisionMetricState.good);
      expect(summary.loops[0].postureDrift, 0.12);
      expect(summary.loops[1].quality, VisionMetricState.notObservable);
      expect(summary.loops[1].hasSufficientVisionQuality, isFalse);
      expect(summary.loops[1].strokeConsistency, isNull);
      expect(summary.loops[1].handTravel, isNull);
      expect(summary.loops[1].postureDrift, isNull);
      expect(postureCalls, 1);
    },
  );

  test(
    'runs posture drift only at and above the documented section threshold',
    () {
      var postureCalls = 0;
      final adapter = SongVisionAdapter(
        postureDriftFor: (_) {
          postureCalls++;
          return 0.2;
        },
      );

      final summary = adapter.aggregate(
        contract: contract,
        visionSessionId: 'vision-session',
        songId: 'song-id',
        cadenceDecision: const VisionCadenceDecision(VisionCadence.full),
        loops: <SongVisionLoopObservation>[
          _loop(id: 'below', duration: const Duration(seconds: 29)),
          _loop(id: 'at', duration: const Duration(seconds: 30)),
          _loop(id: 'above', duration: const Duration(seconds: 31)),
        ],
      );

      expect(postureCalls, 2);
      expect(summary.loops[0].postureDrift, isNull);
      expect(summary.loops[1].postureDrift, 0.2);
      expect(summary.loops[2].postureDrift, 0.2);
    },
  );

  test(
    'audio-only and disabled decisions retain loops without Vision claims',
    () {
      for (final cadence in <VisionCadence>[
        VisionCadence.audioOnly,
        VisionCadence.visionDisabled,
      ]) {
        var postureCalls = 0;
        final summary =
            SongVisionAdapter(
              postureDriftFor: (_) {
                postureCalls++;
                return 0.2;
              },
            ).aggregate(
              contract: contract,
              visionSessionId: 'vision-session',
              songId: 'song-id',
              cadenceDecision: VisionCadenceDecision(cadence),
              loops: <SongVisionLoopObservation>[
                _loop(id: cadence.name, duration: const Duration(seconds: 31)),
              ],
            );

        expect(summary.cadence, cadence);
        expect(summary.loops, hasLength(1));
        expect(summary.loops.single.quality, VisionMetricState.notObservable);
        expect(summary.loops.single.strokeConsistency, isNull);
        expect(summary.loops.single.handTravel, isNull);
        expect(summary.loops.single.postureDrift, isNull);
        expect(postureCalls, 0);
      }
    },
  );
}

SongVisionLoopObservation _loop({
  required String id,
  required Duration duration,
  VisionMetricState quality = VisionMetricState.good,
}) => SongVisionLoopObservation(
  loopIterationId: id,
  sectionId: 'section-a',
  sectionDuration: duration,
  quality: quality,
  strokeConsistency: 0.9,
  handTravel: 0.4,
);
