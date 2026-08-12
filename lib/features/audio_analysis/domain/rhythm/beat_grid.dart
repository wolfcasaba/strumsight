import '../analysis_capability.dart';
import 'beat_point.dart';

/// Provenance of a [BeatGrid.beatsPerBar] value (SDD Ch7 §14.4).
enum BeatsPerBarSource { target, legacyDefault }

/// R12-local target-first adapter input: an ordered beat timebase and its
/// bar length. Not `AnalysisTarget` — that contract belongs to E06-R13 and
/// does not exist yet (ADR 0230 §2).
final class BeatGridTargetInput {
  BeatGridTargetInput({
    required List<Duration> beatTimes,
    required this.beatsPerBar,
  }) : beatTimes = List<Duration>.unmodifiable(beatTimes) {
    if (beatsPerBar <= 0) {
      throw ArgumentError.value(beatsPerBar, 'beatsPerBar');
    }
    Duration? previous;
    for (final time in this.beatTimes) {
      if (time.isNegative) throw ArgumentError.value(time, 'beatTimes');
      if (previous != null && time <= previous) {
        throw ArgumentError('beatTimes must be strictly increasing.');
      }
      previous = time;
    }
  }

  final List<Duration> beatTimes;
  final int beatsPerBar;
}

/// Time-indexed beat/bar aggregate (SDD Ch7 §14.1). Never fused with an
/// `AnalysisDocument` or `AnalysisMetricResult` in this round (ADR 0230 §3).
final class BeatGrid {
  BeatGrid({
    required List<BeatPoint> beats,
    required List<BarPoint> bars,
    required this.beatsPerBar,
    required this.beatsPerBarSource,
    required this.status,
    required this.meterStatus,
  }) : beats = List<BeatPoint>.unmodifiable(beats),
       bars = List<BarPoint>.unmodifiable(bars) {
    if (beatsPerBar <= 0) {
      throw ArgumentError.value(beatsPerBar, 'beatsPerBar');
    }
    if (status != CapabilityStatus.available &&
        status != CapabilityStatus.degraded) {
      throw ArgumentError.value(status, 'status');
    }
    Duration? previous;
    for (final beat in this.beats) {
      if (previous != null && beat.time <= previous) {
        throw ArgumentError('BeatGrid.beats must be strictly increasing.');
      }
      previous = beat.time;
    }
    previous = null;
    for (final bar in this.bars) {
      if (previous != null && bar.time <= previous) {
        throw ArgumentError('BeatGrid.bars must be strictly increasing.');
      }
      previous = bar.time;
    }
  }

  final List<BeatPoint> beats;
  final List<BarPoint> bars;
  final int beatsPerBar;
  final BeatsPerBarSource beatsPerBarSource;
  final CapabilityStatus status;

  /// Whether metre (time signature) was actively determined. Free-play
  /// inference never determines metre in this round (SDD Ch7 §14.4), so
  /// this is always [CapabilityStatus.notApplicable] outside a target grid.
  final CapabilityStatus meterStatus;
}
