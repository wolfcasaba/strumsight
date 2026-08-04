import 'trainer_range.dart';

/// Immutable loop preferences for a trainer session.
///
/// Loop playback itself belongs to the later transport round. Keeping the
/// selection here makes the hand-off explicit without acquiring playback
/// resources in setup.
final class LoopConfig {
  LoopConfig({
    required this.range,
    this.maxRepeats,
    this.pauseBetweenLoops = Duration.zero,
    this.countInEachLoop = false,
    this.autoAdvance = false,
  }) {
    if (maxRepeats != null && maxRepeats! <= 0) {
      throw ArgumentError.value(
        maxRepeats,
        'maxRepeats',
        'A loop repeat count must be positive when it is specified.',
      );
    }
    if (pauseBetweenLoops.isNegative) {
      throw ArgumentError.value(
        pauseBetweenLoops,
        'pauseBetweenLoops',
        'A loop pause cannot be negative.',
      );
    }
  }

  final MeasureRange range;
  final int? maxRepeats;
  final Duration pauseBetweenLoops;
  final bool countInEachLoop;
  final bool autoAdvance;

  @override
  bool operator ==(Object other) =>
      other is LoopConfig &&
      other.range == range &&
      other.maxRepeats == maxRepeats &&
      other.pauseBetweenLoops == pauseBetweenLoops &&
      other.countInEachLoop == countInEachLoop &&
      other.autoAdvance == autoAdvance;

  @override
  int get hashCode => Object.hash(
    range,
    maxRepeats,
    pauseBetweenLoops,
    countInEachLoop,
    autoAdvance,
  );
}
