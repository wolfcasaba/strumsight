import 'package:strumsight/features/song_trainer/domain/models/song_vision_summary.dart';
import 'package:strumsight/features/vision/domain/integration/public.dart';

/// Computes a posture-drift aggregate only after the Song section is eligible.
typedef PostureDriftFor = double? Function(SongVisionLoopObservation loop);

/// Projects optional Vision observations into Song Trainer result summaries.
///
/// This adapter has no transport dependency: cadence changes only the optional
/// Vision projection, leaving backing playback and audio scoring untouched.
final class SongVisionAdapter {
  const SongVisionAdapter({required PostureDriftFor postureDriftFor})
    : _postureDriftFor = postureDriftFor;

  final PostureDriftFor _postureDriftFor;

  SongVisionSummary aggregate({
    required VisionSongContract contract,
    required String visionSessionId,
    required String songId,
    required VisionCadenceDecision cadenceDecision,
    required List<SongVisionLoopObservation> loops,
  }) => SongVisionSummary(
    visionSessionId: visionSessionId,
    songId: songId,
    cadence: cadenceDecision.cadence,
    loops: <SongVisionLoopSummary>[
      for (final loop in loops)
        _summaryFor(
          loop: loop,
          contract: contract,
          cadenceDecision: cadenceDecision,
        ),
    ],
  );

  SongVisionLoopSummary _summaryFor({
    required SongVisionLoopObservation loop,
    required VisionSongContract contract,
    required VisionCadenceDecision cadenceDecision,
  }) {
    if (!cadenceDecision.isVisionEnabled) {
      return SongVisionLoopSummary(
        loopIterationId: loop.loopIterationId,
        sectionId: loop.sectionId,
        quality: VisionMetricState.notObservable,
      );
    }

    final hasSufficientQuality = loop.quality == VisionMetricState.good;
    final postureDrift =
        hasSufficientQuality &&
            loop.sectionDuration >= contract.minimumPostureSectionDuration
        ? _postureDriftFor(loop)
        : null;
    return SongVisionLoopSummary(
      loopIterationId: loop.loopIterationId,
      sectionId: loop.sectionId,
      quality: loop.quality,
      strokeConsistency: hasSufficientQuality ? loop.strokeConsistency : null,
      handTravel: hasSufficientQuality ? loop.handTravel : null,
      postureDrift: postureDrift,
    );
  }
}
