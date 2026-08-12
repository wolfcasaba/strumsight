import 'dart:math' as math;

import '../../domain/pitch/monophonic_pitch_segment.dart';
import '../../domain/pitch/pitch_frame.dart';

/// Groups adjacent voiced frames into stable monophonic evidence segments.
final class MonophonicPitchSegmentBuilder {
  MonophonicPitchSegmentBuilder({
    this.minimumDuration = const Duration(milliseconds: 80),
    this.maximumAdjacentJumpCents = 100,
  }) {
    if (minimumDuration.isNegative || maximumAdjacentJumpCents <= 0) {
      throw ArgumentError('Pitch segment thresholds must be positive.');
    }
  }

  final Duration minimumDuration;
  final double maximumAdjacentJumpCents;

  List<MonophonicPitchSegment> build(List<PitchFrame> frames) {
    final segments = <MonophonicPitchSegment>[];
    final current = <PitchFrame>[];

    void flush() {
      if (current.isEmpty) return;
      final segment = _segmentFor(current);
      if (segment.duration >= minimumDuration) segments.add(segment);
      current.clear();
    }

    PitchFrame? previous;
    for (final frame in frames) {
      if (!frame.isVoiced) {
        flush();
        previous = null;
        continue;
      }
      if (previous != null &&
          _centsBetween(previous.frequencyHz!, frame.frequencyHz!).abs() >
              maximumAdjacentJumpCents) {
        flush();
      }
      current.add(frame);
      previous = frame;
    }
    flush();
    return List<MonophonicPitchSegment>.unmodifiable(segments);
  }

  MonophonicPitchSegment _segmentFor(List<PitchFrame> frames) {
    final frequencies = <double>[
      for (final frame in frames) frame.frequencyHz!,
    ];
    final medianHz = _median(frequencies);
    final midi = (69 + 12 * math.log(medianHz / 440) / math.ln2).round();
    final centsOffset = _centsFromMidi(medianHz, midi);
    final offsets = <double>[
      for (final frequency in frequencies) _centsFromMidi(frequency, midi),
    ];
    final last = frames.last;
    final frameHop = frames.length < 2
        ? Duration.zero
        : frames.last.time - frames[frames.length - 2].time;
    return MonophonicPitchSegment(
      start: frames.first.time,
      end: last.time + frameHop,
      medianHz: medianHz,
      medianMidi: midi.clamp(0, 127),
      centsOffset: centsOffset,
      // Half the voiced cent excursion is the stable, directly interpretable
      // deviation amplitude: a ±30-cent vibrato-like modulation reports ~30,
      // rather than its distribution-dependent standard deviation.
      stabilityCents: _halfRange(offsets),
      confidence: _mean(<double>[for (final frame in frames) frame.confidence]),
    );
  }
}

double centsBetween(double leftHz, double rightHz) =>
    1200 * math.log(rightHz / leftHz) / math.ln2;

double _centsBetween(double leftHz, double rightHz) =>
    centsBetween(leftHz, rightHz);

double _centsFromMidi(double frequencyHz, int midi) =>
    centsBetween(440 * math.pow(2, (midi - 69) / 12).toDouble(), frequencyHz);

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _mean(List<double> values) =>
    values.reduce((left, right) => left + right) / values.length;

double _halfRange(List<double> values) =>
    (values.reduce(math.max) - values.reduce(math.min)) / 2;
