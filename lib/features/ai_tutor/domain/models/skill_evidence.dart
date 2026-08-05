import 'skill_node.dart';

/// Origin class for evidence consumed by the provider-neutral skill reducer.
enum SkillEvidenceSource {
  practiceSession,
  songSection,
  analyzeSession,
  userSelfReport,
  tutorAssessment,
}

/// Integer reliability weights for evidence origins.
abstract final class SkillEvidenceWeight {
  static const int directMeasurement = skillBasisPointScale;
  static const int userSelfReport = 4000;
  static const int tutorAssessment = 2000;
}

extension SkillEvidenceSourceWeight on SkillEvidenceSource {
  int get weightBasisPoints => switch (this) {
    SkillEvidenceSource.practiceSession ||
    SkillEvidenceSource.songSection ||
    SkillEvidenceSource.analyzeSession => SkillEvidenceWeight.directMeasurement,
    SkillEvidenceSource.userSelfReport => SkillEvidenceWeight.userSelfReport,
    SkillEvidenceSource.tutorAssessment => SkillEvidenceWeight.tutorAssessment,
  };
}

/// Stable exception emitted when a [SkillEvidence] value is invalid.
class SkillEvidenceValidationException implements Exception {
  SkillEvidenceValidationException._(this.code);

  /// One of [SkillEvidenceValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SkillEvidenceValidationException($code)';
}

/// Stable machine-readable codes emitted by evidence validation.
abstract final class SkillEvidenceValidationCode {
  static const String idEmpty = 'skillEvidence.id.empty';
  static const String provenanceEmpty = 'skillEvidence.provenance.empty';
  static const String comparisonKeyEmpty = 'skillEvidence.comparisonKey.empty';
  static const String comparableGroupEmpty =
      'skillEvidence.comparableGroup.empty';
  static const String scoreOutOfRange = 'skillEvidence.score.outOfRange';
  static const String schemaVersionMissing =
      'skillEvidence.schemaVersion.missing';
  static const String schemaVersionOutOfRange =
      'skillEvidence.schemaVersion.outOfRange';
  static const String scorerVersionMissing =
      'skillEvidence.scorerVersion.missing';
  static const String scorerVersionOutOfRange =
      'skillEvidence.scorerVersion.outOfRange';
}

/// Immutable, versioned observation that can be reduced into a skill estimate.
final class SkillEvidence {
  SkillEvidence({
    required String id,
    required this.skillId,
    required String provenanceId,
    required String comparisonKey,
    required String comparableGroupId,
    required this.source,
    required this.scoreBasisPoints,
    required DateTime observedAt,
    required int? schemaVersion,
    required int? scorerVersion,
  }) : id = _requiredValue(id, SkillEvidenceValidationCode.idEmpty),
       provenanceId = _requiredValue(
         provenanceId,
         SkillEvidenceValidationCode.provenanceEmpty,
       ),
       comparisonKey = _requiredValue(
         comparisonKey,
         SkillEvidenceValidationCode.comparisonKeyEmpty,
       ),
       comparableGroupId = _requiredValue(
         comparableGroupId,
         SkillEvidenceValidationCode.comparableGroupEmpty,
       ),
       observedAt = observedAt.toUtc(),
       schemaVersion = _requiredVersion(
         schemaVersion,
         SkillEvidenceValidationCode.schemaVersionMissing,
         SkillEvidenceValidationCode.schemaVersionOutOfRange,
       ),
       scorerVersion = _requiredVersion(
         scorerVersion,
         SkillEvidenceValidationCode.scorerVersionMissing,
         SkillEvidenceValidationCode.scorerVersionOutOfRange,
       ) {
    if (scoreBasisPoints < 0 || scoreBasisPoints > skillBasisPointScale) {
      throw SkillEvidenceValidationException._(
        SkillEvidenceValidationCode.scoreOutOfRange,
      );
    }
  }

  /// Stable evidence identifier used for idempotent import protection.
  final String id;

  /// The skill measured by this observation.
  final SkillId skillId;

  /// Redacted reference to the source record that produced this observation.
  final String provenanceId;

  /// The difficulty and tempo-compatible comparison partition.
  final String comparisonKey;

  /// The session-level group within a [comparisonKey].
  final String comparableGroupId;

  /// Source category used only for documented integer weighting.
  final SkillEvidenceSource source;

  /// Normalized measurement in the inclusive [skillBasisPointScale] range.
  final int scoreBasisPoints;

  /// Injected observation time, normalized to UTC without reading a wall clock.
  final DateTime observedAt;

  /// Version of this evidence envelope.
  final int schemaVersion;

  /// Version of the scorer or adapter that produced the measurement.
  final int scorerVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillEvidence &&
          other.id == id &&
          other.skillId == skillId &&
          other.provenanceId == provenanceId &&
          other.comparisonKey == comparisonKey &&
          other.comparableGroupId == comparableGroupId &&
          other.source == source &&
          other.scoreBasisPoints == scoreBasisPoints &&
          other.observedAt.microsecondsSinceEpoch ==
              observedAt.microsecondsSinceEpoch &&
          other.schemaVersion == schemaVersion &&
          other.scorerVersion == scorerVersion;

  @override
  int get hashCode => Object.hash(
    id,
    skillId,
    provenanceId,
    comparisonKey,
    comparableGroupId,
    source,
    scoreBasisPoints,
    observedAt.microsecondsSinceEpoch,
    schemaVersion,
    scorerVersion,
  );
}

String _requiredValue(String raw, String errorCode) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    throw SkillEvidenceValidationException._(errorCode);
  }
  return normalized;
}

int _requiredVersion(int? value, String missingCode, String outOfRangeCode) {
  if (value == null) {
    throw SkillEvidenceValidationException._(missingCode);
  }
  if (value < 1) {
    throw SkillEvidenceValidationException._(outOfRangeCode);
  }
  return value;
}
