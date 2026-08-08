import 'package:strumsight/features/vision/domain/integration/public.dart';

/// One aggregate-only Vision observation associated with a Song Trainer loop.
final class SongVisionLoopObservation {
  SongVisionLoopObservation({
    required this.loopIterationId,
    required this.sectionId,
    required this.sectionDuration,
    required this.quality,
    this.strokeConsistency,
    this.handTravel,
  }) {
    if (loopIterationId.trim().isEmpty) {
      throw ArgumentError.value(
        loopIterationId,
        'loopIterationId',
        'Must not be empty.',
      );
    }
    if (sectionId.trim().isEmpty) {
      throw ArgumentError.value(sectionId, 'sectionId', 'Must not be empty.');
    }
    if (sectionDuration.isNegative) {
      throw ArgumentError.value(
        sectionDuration,
        'sectionDuration',
        'Must not be negative.',
      );
    }
    _validateMetric(strokeConsistency, 'strokeConsistency');
    _validateMetric(handTravel, 'handTravel');
  }

  final String loopIterationId;
  final String sectionId;
  final Duration sectionDuration;

  /// `notObservable` is an explicit missing-quality marker, never a drop.
  final VisionMetricState quality;
  final double? strokeConsistency;
  final double? handTravel;

  static void _validateMetric(double? value, String name) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and non-negative.',
      );
    }
  }
}

/// Vision summary kept alongside Song Trainer's audio-only result.
final class SongVisionSummary {
  SongVisionSummary({
    required this.visionSessionId,
    required this.songId,
    required this.cadence,
    required List<SongVisionLoopSummary> loops,
  }) : loops = List<SongVisionLoopSummary>.unmodifiable(loops) {
    if (visionSessionId.trim().isEmpty) {
      throw ArgumentError.value(
        visionSessionId,
        'visionSessionId',
        'Must not be empty.',
      );
    }
    if (songId.trim().isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Must not be empty.');
    }
  }

  final String visionSessionId;
  final String songId;
  final VisionCadence cadence;
  final List<SongVisionLoopSummary> loops;
}

/// One visible result row for every completed loop iteration.
final class SongVisionLoopSummary {
  SongVisionLoopSummary({
    required this.loopIterationId,
    required this.sectionId,
    required this.quality,
    this.strokeConsistency,
    this.handTravel,
    this.postureDrift,
  });

  final String loopIterationId;
  final String sectionId;
  final VisionMetricState quality;
  final double? strokeConsistency;
  final double? handTravel;

  /// Null means the section was too short or posture was not observable.
  final double? postureDrift;

  bool get hasSufficientVisionQuality => quality == VisionMetricState.good;
}
