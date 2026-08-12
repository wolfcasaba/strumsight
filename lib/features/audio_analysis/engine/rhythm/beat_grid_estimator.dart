import '../../domain/analysis_capability.dart';
import '../../domain/rhythm/beat_grid.dart';
import '../../domain/rhythm/beat_point.dart';

/// Free-play beat inference strategy, injectable so tests can prove the
/// target-first path never invokes it (SDD Ch7 §14.5, ADR 0230 §2).
abstract interface class FreePlayBeatInference {
  List<BeatPoint> infer({
    required List<Duration> eventTimes,
    required Duration clipDuration,
  });
}

/// Onset-interval based free-play beat inference (SDD Ch7 §14.1).
///
/// Uses the same `dt > 0.05 s` near-simultaneous filter as the legacy V1
/// tempo formula, then the upper-median interval as the beat period.
final class DefaultFreePlayBeatInference implements FreePlayBeatInference {
  const DefaultFreePlayBeatInference();

  static const double _minimumIntervalSeconds = 0.05;

  @override
  List<BeatPoint> infer({
    required List<Duration> eventTimes,
    required Duration clipDuration,
  }) {
    if (eventTimes.length < 2) return const <BeatPoint>[];
    final times = List<Duration>.of(eventTimes)..sort();
    final intervals = <double>[];
    for (var i = 1; i < times.length; i++) {
      final dt = (times[i] - times[i - 1]).inMicroseconds / 1e6;
      if (dt > _minimumIntervalSeconds) intervals.add(dt);
    }
    if (intervals.isEmpty) return const <BeatPoint>[];
    final sortedIntervals = List<double>.of(intervals)..sort();
    final period = sortedIntervals[sortedIntervals.length ~/ 2];
    if (period <= 0) return const <BeatPoint>[];

    final startSeconds = times.first.inMicroseconds / 1e6;
    final durationSeconds = clipDuration.inMicroseconds / 1e6;
    final beats = <BeatPoint>[];
    var index = 0;
    var t = startSeconds;
    while (t <= durationSeconds + 1e-9) {
      final deviation = _nearestEventDeviation(t, times);
      final confidence = (1 - (deviation / period)).clamp(0.1, 1.0);
      beats.add(
        BeatPoint(
          index: index,
          time: Duration(microseconds: (t * 1e6).round()),
          confidence: confidence,
          source: BeatSource.estimated,
        ),
      );
      index++;
      t += period;
    }
    return beats;
  }

  double _nearestEventDeviation(double timeSeconds, List<Duration> times) {
    var nearest = double.infinity;
    for (final event in times) {
      final eventSeconds = event.inMicroseconds / 1e6;
      final deviation = (eventSeconds - timeSeconds).abs();
      if (deviation < nearest) nearest = deviation;
    }
    return nearest;
  }
}

/// Builds the [BeatGrid], preferring a supplied target timebase over
/// inference (SDD Ch7 §14.5). When [BeatGridTargetInput] is present, the
/// free-play inference strategy is never invoked.
final class BeatGridEstimator {
  const BeatGridEstimator({
    this.freePlayInference = const DefaultFreePlayBeatInference(),
  });

  final FreePlayBeatInference freePlayInference;

  static const int legacyDefaultBeatsPerBar = 4;

  BeatGrid estimate({
    required List<Duration> eventTimes,
    required Duration clipDuration,
    BeatGridTargetInput? target,
  }) {
    if (clipDuration.isNegative) {
      throw ArgumentError.value(clipDuration, 'clipDuration');
    }
    if (target != null) return _fromTarget(target);

    final inferred = freePlayInference.infer(
      eventTimes: eventTimes,
      clipDuration: clipDuration,
    );
    return BeatGrid(
      beats: inferred,
      bars: _barsFor(inferred, legacyDefaultBeatsPerBar),
      beatsPerBar: legacyDefaultBeatsPerBar,
      beatsPerBarSource: BeatsPerBarSource.legacyDefault,
      status: inferred.length >= 2
          ? CapabilityStatus.available
          : CapabilityStatus.degraded,
      meterStatus: CapabilityStatus.notApplicable,
    );
  }

  BeatGrid _fromTarget(BeatGridTargetInput target) {
    final beats = <BeatPoint>[
      for (var i = 0; i < target.beatTimes.length; i++)
        BeatPoint(
          index: i,
          time: target.beatTimes[i],
          confidence: 1,
          source: BeatSource.target,
        ),
    ];
    return BeatGrid(
      beats: beats,
      bars: _barsFor(beats, target.beatsPerBar),
      beatsPerBar: target.beatsPerBar,
      beatsPerBarSource: BeatsPerBarSource.target,
      status: beats.length >= 2
          ? CapabilityStatus.available
          : CapabilityStatus.degraded,
      meterStatus: CapabilityStatus.available,
    );
  }

  static List<BarPoint> _barsFor(List<BeatPoint> beats, int beatsPerBar) {
    final bars = <BarPoint>[];
    var barIndex = 0;
    for (var i = 0; i < beats.length; i += beatsPerBar) {
      bars.add(
        BarPoint(
          index: barIndex,
          time: beats[i].time,
          beatsPerBar: beatsPerBar,
        ),
      );
      barIndex++;
    }
    return bars;
  }
}
