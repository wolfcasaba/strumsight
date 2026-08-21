/// Tagged skill a milestone measures evidence against.
enum MasterySkill {
  chordTransition('chordTransition'),
  rhythmAccuracy('rhythmAccuracy'),
  tempoStability('tempoStability'),
  strumConsistency('strumConsistency');

  const MasterySkill(this.code);

  final String code;
}

/// The numeric metric a milestone gathers evidence against.
enum MasteryMetric {
  accuracy('accuracy'),
  tempoAdherence('tempoAdherence'),
  repetitionCount('repetitionCount');

  const MasteryMetric(this.code);

  final String code;
}

/// Difficulty tier a milestone is scoped to. Evidence from a different tier
/// is not comparable (brief §6 A6) and is dropped at evaluation time.
enum MasteryDifficulty {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const MasteryDifficulty(this.code);

  final String code;
}

/// Inclusive BPM bounds for a milestone's tempo scope. Evidence whose tempo
/// falls outside `[minBpm, maxBpm]` is not comparable (brief §6 A6).
final class MasteryTempoRange {
  factory MasteryTempoRange({required num minBpm, required num maxBpm}) {
    _validateRange(minBpm, maxBpm);
    return MasteryTempoRange._(minBpm, maxBpm);
  }

  const MasteryTempoRange._(this._minBpm, this._maxBpm);

  final num _minBpm;
  final num _maxBpm;

  num get minBpm => _minBpm;
  num get maxBpm => _maxBpm;

  /// Returns whether [bpm] falls inside the inclusive tempo scope.
  bool contains(num bpm) {
    if (!bpm.isFinite) return false;
    return bpm >= _minBpm && bpm <= _maxBpm;
  }
}

void _validateRange(num minBpm, num maxBpm) {
  if (!minBpm.isFinite || !maxBpm.isFinite) {
    throw ArgumentError.value(
      '$minBpm..$maxBpm',
      'tempoRange',
      'must contain finite bounds',
    );
  }
  if (minBpm <= 0 || maxBpm <= 0) {
    throw ArgumentError.value(
      '$minBpm..$maxBpm',
      'tempoRange',
      'bounds must be positive BPM',
    );
  }
  if (minBpm > maxBpm) {
    throw ArgumentError.value(
      '$minBpm..$maxBpm',
      'tempoRange',
      'minBpm must not exceed maxBpm',
    );
  }
}

/// Immutable definition of a mastery milestone. Mastery progress is evidence-
/// based (ADR 0289) and one-shot per milestone — see `MasteryProgress`.
final class MasteryMilestone {
  factory MasteryMilestone({
    required String id,
    required int catalogVersion,
    required MasterySkill skill,
    required MasteryMetric metric,
    required num minimumThreshold,
    required MasteryDifficulty difficulty,
    required MasteryTempoRange tempoRange,
    required int minEvidenceSessions,
    required String titleKey,
    required String descriptionKey,
  }) {
    _requireStableId(id, 'id');
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
    if (!minimumThreshold.isFinite || minimumThreshold <= 0) {
      throw ArgumentError.value(
        minimumThreshold,
        'minimumThreshold',
        'must be finite and positive',
      );
    }
    if (minEvidenceSessions < 2) {
      throw ArgumentError.value(
        minEvidenceSessions,
        'minEvidenceSessions',
        'must be at least 2 — single-session proof is not mastery',
      );
    }
    _requireLocalizationKey(titleKey, 'titleKey');
    _requireLocalizationKey(descriptionKey, 'descriptionKey');
    return MasteryMilestone._(
      id: id,
      catalogVersion: catalogVersion,
      skill: skill,
      metric: metric,
      minimumThreshold: minimumThreshold,
      difficulty: difficulty,
      tempoRange: tempoRange,
      minEvidenceSessions: minEvidenceSessions,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
    );
  }

  const MasteryMilestone._({
    required this.id,
    required this.catalogVersion,
    required this.skill,
    required this.metric,
    required this.minimumThreshold,
    required this.difficulty,
    required this.tempoRange,
    required this.minEvidenceSessions,
    required this.titleKey,
    required this.descriptionKey,
  });

  final String id;
  final int catalogVersion;
  final MasterySkill skill;
  final MasteryMetric metric;
  final num minimumThreshold;
  final MasteryDifficulty difficulty;
  final MasteryTempoRange tempoRange;
  final int minEvidenceSessions;
  final String titleKey;
  final String descriptionKey;
}

void _requireStableId(String value, String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be lower snake case');
  }
}

void _requireLocalizationKey(String value, String name) {
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a lowerCamelCase key');
  }
}
