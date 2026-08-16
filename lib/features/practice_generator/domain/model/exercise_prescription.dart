/// The bounded, measurable execution recipe for one chosen
/// [ExerciseCandidate] (SDD Ch8 Kör 9, ADR 0294).
///
/// Deliberately out of scope (later rounds, ADR 0294 §Kontextus):
/// plan assembly, validator/repair, priority/selection. Flutter-free,
/// `DateTime.now()`-free, `Random`-free — every input is supplied by the
/// caller (ADR 0257 §5-6).
library;

import 'exercise_candidate.dart';
import 'plan_enums.dart';
import 'progression_rule.dart';
import 'success_criteria.dart';

/// The bounded repetition count for one [ExercisePrescription].
///
/// [maximum] is always explicit and positive — there is no "practically
/// infinite" default (ADR 0294 decision 3). [target] must not exceed
/// [maximum]; the boundary itself ([target] == [maximum]) is accepted.
final class RepetitionPrescription {
  RepetitionPrescription({required int target, required int maximum})
    : target = _requirePositiveInt(target, 'target'),
      maximum = _requirePositiveInt(maximum, 'maximum') {
    if (this.target > this.maximum) {
      throw ArgumentError.value(
        target,
        'target',
        'must not exceed maximum ($maximum)',
      );
    }
  }

  final int target;
  final int maximum;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'target': target,
    'maximum': maximum,
  };

  static RepetitionPrescription fromJson(Map<String, dynamic> json) {
    final targetRaw = json['target'];
    final maximumRaw = json['maximum'];
    if (targetRaw is! num) {
      throw ArgumentError.value(
        targetRaw,
        'target',
        'RepetitionPrescription JSON requires a numeric target',
      );
    }
    if (maximumRaw is! num) {
      throw ArgumentError.value(
        maximumRaw,
        'maximum',
        'RepetitionPrescription JSON requires a numeric, explicit maximum — '
            'there is no implicit unbounded default',
      );
    }
    return RepetitionPrescription(
      target: targetRaw.round(),
      maximum: maximumRaw.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepetitionPrescription &&
          other.target == target &&
          other.maximum == maximum;

  @override
  int get hashCode => Object.hash(target, maximum);
}

/// A skill-compatible alternative to the primary candidate, kept for
/// accessibility fallback — never a target substitution (ADR 0294 decision
/// 5): its [skillTargets] set is validated to match the primary's at
/// [ExercisePrescription] construction time.
final class FallbackReference {
  FallbackReference({
    required String exerciseId,
    required this.source,
    required Iterable<String> skillTargets,
  }) : exerciseId = _requireText(exerciseId, 'exerciseId'),
       skillTargets = _requireNonEmptyCodes(skillTargets, 'skillTargets');

  final String exerciseId;
  final CandidateSource source;
  final List<String> skillTargets;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'exerciseId': exerciseId,
    'source': source.code,
    'skillTargets': skillTargets,
  };

  static FallbackReference fromJson(Map<String, dynamic> json) {
    final exerciseId = json['exerciseId'];
    final sourceCode = json['source'];
    final skillTargetsRaw = json['skillTargets'];
    if (exerciseId is! String) {
      throw ArgumentError.value(
        exerciseId,
        'exerciseId',
        'FallbackReference JSON requires a String exerciseId',
      );
    }
    if (sourceCode is! String) {
      throw ArgumentError.value(
        sourceCode,
        'source',
        'FallbackReference JSON requires a String source',
      );
    }
    if (skillTargetsRaw is! List) {
      throw ArgumentError.value(
        skillTargetsRaw,
        'skillTargets',
        'FallbackReference JSON requires a skillTargets list',
      );
    }
    return FallbackReference(
      exerciseId: exerciseId,
      source: CandidateSource.fromCode(sourceCode),
      skillTargets: [
        for (final entry in skillTargetsRaw)
          if (entry is String)
            entry
          else
            throw ArgumentError.value(
              entry,
              'skillTargets',
              'each skillTargets entry must be a String',
            ),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FallbackReference &&
          other.exerciseId == exerciseId &&
          other.source == source &&
          _sameList(other.skillTargets, skillTargets);

  @override
  int get hashCode =>
      Object.hash(exerciseId, source, Object.hashAll(skillTargets));
}

/// The concrete, bounded, measurable execution recipe for one chosen
/// [ExerciseCandidate].
///
/// Construction fails controlledly — never silently downgrades — when:
/// - [tempoBpm] is set but the candidate does not support tempo control
///   (ADR 0294 decision handled together with ADR 0262 candidate truth);
/// - [successCriteria] requires a capability the candidate does not support
///   (ADR 0294 decision 1);
/// - the total active+rest elapsed time exceeds [hardElapsedLimit]
///   (ADR 0294 decision 4, ADR 0258 §3 inclusive boundary);
/// - any [fallbackCandidates] entry targets a different skill set
///   (ADR 0294 decision 5).
final class ExercisePrescription {
  ExercisePrescription({
    required ExerciseCandidate candidate,
    required this.activeDuration,
    required this.restDuration,
    this.tempoBpm,
    required this.repetition,
    required int loopCount,
    required this.hardElapsedLimit,
    required this.successCriteria,
    Iterable<ExerciseCandidate> fallbackCandidates =
        const <ExerciseCandidate>[],
    this.progressionRule,
  }) : exerciseId = candidate.exerciseId,
       source = candidate.source,
       skillTargets = List<String>.unmodifiable(candidate.skillTargets),
       loopCount = _requirePositiveInt(loopCount, 'loopCount'),
       fallbacks = _buildFallbacks(fallbackCandidates, candidate.skillTargets) {
    if (activeDuration <= Duration.zero) {
      throw ArgumentError.value(
        activeDuration,
        'activeDuration',
        'must be positive',
      );
    }
    if (restDuration.isNegative) {
      throw ArgumentError.value(
        restDuration,
        'restDuration',
        'must not be negative',
      );
    }
    if (hardElapsedLimit <= Duration.zero) {
      throw ArgumentError.value(
        hardElapsedLimit,
        'hardElapsedLimit',
        'must be positive',
      );
    }
    final tempo = tempoBpm;
    if (tempo != null) {
      if (tempo <= 0) {
        throw ArgumentError.value(tempo, 'tempoBpm', 'must be positive');
      }
      if (candidate.capabilities[ExerciseCapability.supportsTempo] !=
          CapabilitySupport.supported) {
        throw ArgumentError.value(
          tempo,
          'tempoBpm',
          'candidate ${candidate.exerciseId} does not support tempo control',
        );
      }
    }
    successCriteria.ensureMeasurableFor(candidate.capabilities);
    final elapsed = (activeDuration + restDuration) * this.loopCount;
    if (elapsed > hardElapsedLimit) {
      throw ArgumentError.value(
        elapsed,
        'elapsed',
        'exceeds hardElapsedLimit ($hardElapsedLimit)',
      );
    }
  }

  final String exerciseId;
  final CandidateSource source;
  final List<String> skillTargets;
  final Duration activeDuration;
  final Duration restDuration;
  final int? tempoBpm;
  final RepetitionPrescription repetition;
  final int loopCount;
  final Duration hardElapsedLimit;
  final SuccessCriteria successCriteria;
  final List<FallbackReference> fallbacks;
  final ProgressionRule? progressionRule;

  /// The total active+rest wall-clock time this recipe consumes, inclusive
  /// of every loop iteration (ADR 0294 decision 4).
  Duration get elapsed => (activeDuration + restDuration) * loopCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'exerciseId': exerciseId,
    'source': source.code,
    'skillTargets': skillTargets,
    'activeDurationMicros': activeDuration.inMicroseconds,
    'restDurationMicros': restDuration.inMicroseconds,
    'tempoBpm': tempoBpm,
    'repetition': repetition.toJson(),
    'loopCount': loopCount,
    'hardElapsedLimitMicros': hardElapsedLimit.inMicroseconds,
    'successCriteria': successCriteria.toJson(),
    'fallbacks': [for (final fallback in fallbacks) fallback.toJson()],
    'progressionRule': progressionRule?.toJson(),
  };

  /// Decodes a previously-serialized [ExercisePrescription].
  ///
  /// This re-validates every invariant against [candidate] and
  /// [fallbackCandidates] — a corrupted or hand-edited document that would
  /// violate a bound (e.g. an over-limit elapsed time) fails controlledly,
  /// exactly as fresh construction would.
  static ExercisePrescription fromJson(
    Map<String, dynamic> json, {
    required ExerciseCandidate candidate,
    Iterable<ExerciseCandidate> fallbackCandidates =
        const <ExerciseCandidate>[],
  }) {
    final activeMicros = json['activeDurationMicros'];
    final restMicros = json['restDurationMicros'];
    final hardLimitMicros = json['hardElapsedLimitMicros'];
    final repetitionRaw = json['repetition'];
    final loopCountRaw = json['loopCount'];
    final successCriteriaRaw = json['successCriteria'];
    if (activeMicros is! num) {
      throw ArgumentError.value(
        activeMicros,
        'activeDurationMicros',
        'ExercisePrescription JSON requires a numeric activeDurationMicros',
      );
    }
    if (restMicros is! num) {
      throw ArgumentError.value(
        restMicros,
        'restDurationMicros',
        'ExercisePrescription JSON requires a numeric restDurationMicros',
      );
    }
    if (hardLimitMicros is! num) {
      throw ArgumentError.value(
        hardLimitMicros,
        'hardElapsedLimitMicros',
        'ExercisePrescription JSON requires a numeric hardElapsedLimitMicros',
      );
    }
    if (repetitionRaw is! Map) {
      throw ArgumentError.value(
        repetitionRaw,
        'repetition',
        'ExercisePrescription JSON requires a repetition object',
      );
    }
    if (loopCountRaw is! num) {
      throw ArgumentError.value(
        loopCountRaw,
        'loopCount',
        'ExercisePrescription JSON requires a numeric loopCount',
      );
    }
    if (successCriteriaRaw is! Map) {
      throw ArgumentError.value(
        successCriteriaRaw,
        'successCriteria',
        'ExercisePrescription JSON requires a successCriteria object — a '
            'missing success criterion is a decoding error, never treated as '
            'already satisfied',
      );
    }
    final tempoBpmRaw = json['tempoBpm'];
    if (tempoBpmRaw != null && tempoBpmRaw is! num) {
      throw ArgumentError.value(
        tempoBpmRaw,
        'tempoBpm',
        'must be numeric when present',
      );
    }
    final fallbacksRaw = json['fallbacks'];
    if (fallbacksRaw is! List) {
      throw ArgumentError.value(
        fallbacksRaw,
        'fallbacks',
        'ExercisePrescription JSON requires a fallbacks list',
      );
    }
    final progressionRuleRaw = json['progressionRule'];
    if (progressionRuleRaw != null && progressionRuleRaw is! Map) {
      throw ArgumentError.value(
        progressionRuleRaw,
        'progressionRule',
        'must be an object when present',
      );
    }
    return ExercisePrescription(
      candidate: candidate,
      activeDuration: Duration(microseconds: activeMicros.round()),
      restDuration: Duration(microseconds: restMicros.round()),
      tempoBpm: (tempoBpmRaw as num?)?.round(),
      repetition: RepetitionPrescription.fromJson(
        Map<String, dynamic>.from(repetitionRaw),
      ),
      loopCount: loopCountRaw.round(),
      hardElapsedLimit: Duration(microseconds: hardLimitMicros.round()),
      successCriteria: SuccessCriteria.fromJson(
        Map<String, dynamic>.from(successCriteriaRaw),
      ),
      fallbackCandidates: fallbackCandidates,
      progressionRule: progressionRuleRaw == null
          ? null
          : ProgressionRule.fromJson(
              Map<String, dynamic>.from(progressionRuleRaw),
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExercisePrescription &&
          other.exerciseId == exerciseId &&
          other.source == source &&
          _sameList(other.skillTargets, skillTargets) &&
          other.activeDuration == activeDuration &&
          other.restDuration == restDuration &&
          other.tempoBpm == tempoBpm &&
          other.repetition == repetition &&
          other.loopCount == loopCount &&
          other.hardElapsedLimit == hardElapsedLimit &&
          other.successCriteria == successCriteria &&
          _sameList(other.fallbacks, fallbacks) &&
          other.progressionRule == progressionRule;

  @override
  int get hashCode => Object.hash(
    exerciseId,
    source,
    Object.hashAll(skillTargets),
    activeDuration,
    restDuration,
    tempoBpm,
    repetition,
    loopCount,
    hardElapsedLimit,
    successCriteria,
    Object.hashAll(fallbacks),
    progressionRule,
  );
}

List<FallbackReference> _buildFallbacks(
  Iterable<ExerciseCandidate> fallbackCandidates,
  List<String> primarySkillTargets,
) {
  final primarySet = primarySkillTargets.toSet();
  final result = <FallbackReference>[];
  for (final fallback in fallbackCandidates) {
    final fallbackSet = fallback.skillTargets.toSet();
    if (fallbackSet.length != primarySet.length ||
        !fallbackSet.containsAll(primarySet)) {
      throw ArgumentError.value(
        fallback.skillTargets,
        'fallbackCandidates',
        'fallback ${fallback.exerciseId} must target the same skill set as '
            'the primary candidate',
      );
    }
    result.add(
      FallbackReference(
        exerciseId: fallback.exerciseId,
        source: fallback.source,
        skillTargets: fallback.skillTargets,
      ),
    );
  }
  return List<FallbackReference>.unmodifiable(result);
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

List<String> _requireNonEmptyCodes(Iterable<String> values, String name) {
  final result = [for (final value in values) _requireText(value, name)];
  if (result.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<String>.unmodifiable(result);
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
