/// Ground-truth annotation types for the Audio Analysis evaluation harness
/// (E06-R29, ADR 0249). These types model an already-parsed manifest — the
/// typed-failure surface lives in `EvaluationManifestParser`, not here.
library;

/// Event kinds an evaluation manifest can annotate.
enum EvalEventType { onset, strum, chordChange, beat, noteOnset }

enum StrumDirectionLabel { down, up }

/// Coarse tempo slice used for `EvaluationReport` breakdowns.
enum TempoBand { slow, medium, fast, notApplicable }

enum SignalQualityTier { clean, noisy, clipped, quiet }

enum EvalMode { chord, monophonic, silence }

/// One timestamped event annotation (expected or detected).
final class EvalEvent {
  EvalEvent({
    required this.id,
    required this.timeMs,
    required this.type,
    this.direction,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (timeMs < 0) {
      throw ArgumentError.value(timeMs, 'timeMs', 'must not be negative');
    }
    if (direction != null && type != EvalEventType.strum) {
      throw ArgumentError.value(
        direction,
        'direction',
        'is only valid for strum events',
      );
    }
  }

  final String id;
  final int timeMs;
  final EvalEventType type;
  final StrumDirectionLabel? direction;
}

/// One labelled chord interval; `endMs >= startMs` is enforced at
/// construction so an invalid-chronology manifest never reaches the runner.
final class ChordSegment {
  ChordSegment({
    required this.label,
    required this.startMs,
    required this.endMs,
  }) {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (startMs < 0) {
      throw ArgumentError.value(startMs, 'startMs', 'must not be negative');
    }
    if (endMs < startMs) {
      throw ArgumentError.value(
        endMs,
        'endMs',
        'must be >= startMs ($startMs)',
      );
    }
  }

  final String label;
  final int startMs;
  final int endMs;
}

/// One monophonic pitch observation.
final class PitchPoint {
  PitchPoint({required this.timeMs, required this.hz}) {
    if (timeMs < 0) {
      throw ArgumentError.value(timeMs, 'timeMs', 'must not be negative');
    }
    if (!hz.isFinite || hz <= 0) {
      throw ArgumentError.value(hz, 'hz', 'must be finite and positive');
    }
  }

  final int timeMs;
  final double hz;
}

/// One `expected` or `detected` annotation set within a case.
final class AnnotationSet {
  AnnotationSet({
    List<EvalEvent> events = const <EvalEvent>[],
    List<ChordSegment> chordSegments = const <ChordSegment>[],
    this.tempoBpm,
    List<int> beatsMs = const <int>[],
    List<PitchPoint> pitchPoints = const <PitchPoint>[],
  }) : events = List<EvalEvent>.unmodifiable(events),
       chordSegments = List<ChordSegment>.unmodifiable(chordSegments),
       beatsMs = List<int>.unmodifiable(beatsMs),
       pitchPoints = List<PitchPoint>.unmodifiable(pitchPoints) {
    if (tempoBpm != null && (!tempoBpm!.isFinite || tempoBpm! <= 0)) {
      throw ArgumentError.value(
        tempoBpm,
        'tempoBpm',
        'must be finite and positive when present',
      );
    }
  }

  final List<EvalEvent> events;
  final List<ChordSegment> chordSegments;
  final double? tempoBpm;
  final List<int> beatsMs;
  final List<PitchPoint> pitchPoints;
}

/// One raw-score/correctness pair fed to `CalibrationFitter`.
final class ConfidenceObservation {
  ConfidenceObservation({required this.rawScore, required this.correct}) {
    if (!rawScore.isFinite || rawScore < 0 || rawScore > 1) {
      throw ArgumentError.value(
        rawScore,
        'rawScore',
        'must be finite and in [0, 1]',
      );
    }
  }

  final double rawScore;
  final bool correct;
}

/// One ground-truth case: an expected annotation set, the detector's
/// annotation set for the same clip, and the slice tags used to break the
/// report down by tempo band / signal quality / mode.
final class GroundTruthCase {
  GroundTruthCase({
    required this.id,
    required this.tempoBand,
    required this.signalQualityTier,
    required this.mode,
    required this.expected,
    required this.detected,
    List<ConfidenceObservation> confidenceObservations =
        const <ConfidenceObservation>[],
  }) : confidenceObservations = List<ConfidenceObservation>.unmodifiable(
         confidenceObservations,
       ) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
  }

  final String id;
  final TempoBand tempoBand;
  final SignalQualityTier signalQualityTier;
  final EvalMode mode;
  final AnnotationSet expected;
  final AnnotationSet detected;
  final List<ConfidenceObservation> confidenceObservations;
}

/// A fully parsed evaluation manifest: a schema version and its cases.
final class GroundTruthManifest {
  GroundTruthManifest({
    required this.schemaVersion,
    required List<GroundTruthCase> cases,
  }) : cases = List<GroundTruthCase>.unmodifiable(cases);

  /// The only schema version `EvaluationManifestParser` currently accepts.
  static const String supportedSchemaVersion = '1.0';

  final String schemaVersion;
  final List<GroundTruthCase> cases;
}
