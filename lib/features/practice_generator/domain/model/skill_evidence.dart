/// Confidence-aware, source-normalised skill evidence (ADR 0260, SDD Ch8
/// Kör 5).
///
/// A [SkillEvidence] carries only derived measurements plus provenance —
/// never raw audio/video, a sample, or a file path to one (ADR 0254 §2,
/// ADR 0260 §1). Performance and discomfort are deliberately separate value
/// objects (ADR 0260 §2): averaging them would make a painful practice
/// session look like a weak one, and the downstream reducer (Kör 6) would
/// respond by scheduling *more* of what hurt.
library;

import '../id/planner_ids.dart';

/// Where a [SkillEvidence] measurement originated. The concrete adapters for
/// each source are a later round's work (Kör 7-8); this is only the shared
/// vocabulary they will report through.
enum EvidenceSource {
  learn('learn'),
  progress('progress'),
  analyzeV2('analyzeV2'),
  selfReport('selfReport');

  const EvidenceSource(this.code);

  final String code;

  static EvidenceSource fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'EvidenceSource',
  );

  @override
  String toString() => code;
}

/// A stable category for a learner's discomfort self-report. The free-text
/// note that may accompany it is never logged (ADR 0260 §4) — only this
/// category is safe to put in a structured log field.
enum DiscomfortCategory {
  none('none'),
  tension('tension'),
  pain('pain'),
  fatigue('fatigue'),
  frustration('frustration');

  const DiscomfortCategory(this.code);

  final String code;

  static DiscomfortCategory fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'DiscomfortCategory',
  );

  @override
  String toString() => code;
}

/// A derived performance measurement for one skill. No raw sample, no frame,
/// no file path — only the numeric outcome of an already-completed analysis.
final class PerformanceEvidence {
  PerformanceEvidence({
    required String metricCode,
    required this.value,
    this.sampleCount = 1,
  }) : metricCode = _requireText(metricCode, 'metricCode') {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    if (sampleCount < 1) {
      throw ArgumentError.value(
        sampleCount,
        'sampleCount',
        'must be at least 1',
      );
    }
  }

  /// A stable code for what was measured (e.g. `chordChangeAccuracy`).
  final String metricCode;

  /// The normalised measurement itself. Range semantics are metric-specific
  /// and out of scope for this round.
  final double value;

  /// How many underlying observations this value summarises.
  final int sampleCount;

  @override
  bool operator ==(Object other) =>
      other is PerformanceEvidence &&
      metricCode == other.metricCode &&
      value == other.value &&
      sampleCount == other.sampleCount;

  @override
  int get hashCode => Object.hash(metricCode, value, sampleCount);
}

/// A learner's own discomfort signal, kept on its own scale (ADR 0260 §2).
///
/// This type intentionally has NO free-text field (ADR 0260 §1, §4): a
/// learner's self-report note is transient input at the ingestion boundary
/// (see `EvidenceAggregator.ingest`'s `discomfortNote` parameter) and is
/// discarded there — it never becomes part of the persisted/exportable
/// evidence model, so there is nothing here that could leak into storage,
/// serialization, or a log sink.
final class DiscomfortReport {
  DiscomfortReport({required this.category});

  final DiscomfortCategory category;

  @override
  bool operator ==(Object other) =>
      other is DiscomfortReport && category == other.category;

  @override
  int get hashCode => category.hashCode;
}

/// Immutable, versioned, confidence-aware observation about a skill.
///
/// [sourceOutcomeId] is the deduplication key (ADR 0260 §3): the same
/// underlying practice must resolve to one evidence record no matter how
/// many adapters report it. [measuredAt] must not be after [capturedAt] (the
/// caller-supplied reference instant at which this evidence entered the
/// system) — a "future" measurement is a controlled error, not a silent
/// correction (ADR 0260 §6). The domain never reads a wall clock: both
/// timestamps are supplied by the caller.
final class SkillEvidence {
  SkillEvidence({
    required String skillId,
    required this.source,
    required this.sourceOutcomeId,
    required int measurementVersion,
    required DateTime measuredAt,
    required DateTime capturedAt,
    required double confidence,
    DateTime? validUntil,
    this.performance,
    this.discomfort,
  }) : skillId = _requireText(skillId, 'skillId'),
       measurementVersion = _requireVersion(measurementVersion),
       measuredAt = measuredAt.toUtc(),
       capturedAt = capturedAt.toUtc(),
       confidence = _requireConfidence(confidence),
       validUntil = validUntil?.toUtc() {
    if (this.measuredAt.isAfter(this.capturedAt)) {
      throw ArgumentError.value(
        measuredAt,
        'measuredAt',
        'must not be after capturedAt (future measurement)',
      );
    }
    if (this.validUntil != null && this.validUntil!.isBefore(this.measuredAt)) {
      throw ArgumentError.value(
        validUntil,
        'validUntil',
        'must not be before measuredAt',
      );
    }
    if (performance == null && discomfort == null) {
      throw ArgumentError(
        'SkillEvidence must carry at least one of performance or discomfort',
      );
    }
  }

  final String skillId;
  final EvidenceSource source;

  /// Dedup key: the identifier of the outcome record in the reporting
  /// source. Two adapters reporting the same practice must agree on this.
  final OutcomeId sourceOutcomeId;

  /// Version of the measurement/adapter that produced this evidence.
  final int measurementVersion;

  final DateTime measuredAt;

  /// Reference instant this evidence was captured/ingested, supplied by the
  /// caller as an explicit deterministic clock reading, not read internally;
  /// used only to bound [measuredAt].
  final DateTime capturedAt;

  /// Normalised reliability in the inclusive `[0, 1]` range.
  final double confidence;

  /// Inclusive expiry. `null` means the evidence never expires by itself.
  final DateTime? validUntil;

  final PerformanceEvidence? performance;
  final DiscomfortReport? discomfort;

  /// Whether this evidence is still valid at [asOf] (boundary inclusive).
  bool isValidAt(DateTime asOf) =>
      validUntil == null || !asOf.toUtc().isAfter(validUntil!);

  @override
  bool operator ==(Object other) =>
      other is SkillEvidence &&
      skillId == other.skillId &&
      source == other.source &&
      sourceOutcomeId == other.sourceOutcomeId &&
      measurementVersion == other.measurementVersion &&
      measuredAt == other.measuredAt &&
      capturedAt == other.capturedAt &&
      confidence == other.confidence &&
      validUntil == other.validUntil &&
      performance == other.performance &&
      discomfort == other.discomfort;

  @override
  int get hashCode => Object.hash(
    skillId,
    source,
    sourceOutcomeId,
    measurementVersion,
    measuredAt,
    capturedAt,
    confidence,
    validUntil,
    performance,
    discomfort,
  );
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

int _requireVersion(int value) {
  if (value < 1) {
    throw ArgumentError.value(
      value,
      'measurementVersion',
      'must be at least 1',
    );
  }
  return value;
}

double _requireConfidence(double value) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      'confidence',
      'must be a finite value from 0 to 1',
    );
  }
  return value;
}

T _decodeEnumCode<T extends Enum>({
  required String? code,
  required List<T> values,
  required String Function(T value) codeOf,
  required String typeName,
}) {
  if (code == null || code.trim().isEmpty) {
    throw ArgumentError.value(code, 'code', '$typeName code must not be empty');
  }
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  throw ArgumentError.value(code, 'code', 'Unknown $typeName code: $code');
}
