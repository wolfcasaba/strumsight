import 'analysis_event.dart';
import 'analysis_segment.dart';

final class TempoPoint {
  TempoPoint({required this.time, required this.bpm}) {
    if (time.isNegative || !bpm.isFinite || bpm <= 0) {
      throw ArgumentError('Invalid tempo point.');
    }
  }
  final Duration time;
  final double bpm;
}

final class DynamicPoint {
  DynamicPoint({required this.time, required this.dbfs}) {
    if (time.isNegative || !dbfs.isFinite) {
      throw ArgumentError('Invalid dynamic point.');
    }
  }
  final Duration time;
  final double dbfs;
}

/// Immutable collection of all time-indexed V2 analysis evidence.
final class AnalysisTimeline {
  AnalysisTimeline({
    required this.duration,
    List<AnalysisEvent> events = const <AnalysisEvent>[],
    List<ChordSegment> chordSegments = const <ChordSegment>[],
    List<BeatEvent> beats = const <BeatEvent>[],
    List<Duration> bars = const <Duration>[],
    List<TempoPoint> tempoPoints = const <TempoPoint>[],
    List<PitchSegment> pitchSegments = const <PitchSegment>[],
    List<DynamicPoint> dynamicPoints = const <DynamicPoint>[],
  }) : events = List<AnalysisEvent>.unmodifiable(events),
       chordSegments = List<ChordSegment>.unmodifiable(chordSegments),
       beats = List<BeatEvent>.unmodifiable(beats),
       bars = List<Duration>.unmodifiable(bars),
       tempoPoints = List<TempoPoint>.unmodifiable(tempoPoints),
       pitchSegments = List<PitchSegment>.unmodifiable(pitchSegments),
       dynamicPoints = List<DynamicPoint>.unmodifiable(dynamicPoints) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration');
    }
    if (this.bars.any((bar) => bar.isNegative || bar > duration)) {
      throw ArgumentError('Bar anchors must be within the timeline.');
    }
  }

  final Duration duration;
  final List<AnalysisEvent> events;
  final List<ChordSegment> chordSegments;
  final List<BeatEvent> beats;
  final List<Duration> bars;
  final List<TempoPoint> tempoPoints;
  final List<PitchSegment> pitchSegments;
  final List<DynamicPoint> dynamicPoints;
}
