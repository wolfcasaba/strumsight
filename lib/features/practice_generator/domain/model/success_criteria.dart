/// Measurable success criteria for one [ExercisePrescription] (ADR 0294).
///
/// A [SuccessCriteria] is never vacuously satisfied: [requiredCapabilities]
/// is always explicit and non-empty, and no [SuccessCriterionKind] — not
/// even [SuccessCriterionKind.completion] or
/// [SuccessCriterionKind.assessmentOnly] — is an implicit exception to that
/// rule (ADR 0294 decision 2). There is deliberately no free-text
/// metric-code -> capability inference: the required capabilities are always
/// supplied explicitly by the caller.
library;

import 'exercise_candidate.dart';

/// A stable category for what a [SuccessCriteria] represents.
enum SuccessCriterionKind {
  completion('completion'),
  assessmentOnly('assessmentOnly'),
  accuracyThreshold('accuracyThreshold'),
  tempoSustained('tempoSustained');

  const SuccessCriterionKind(this.code);

  final String code;

  static SuccessCriterionKind fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'SuccessCriterionKind',
  );
}

/// A single, explicit, capability-backed definition of "done" for one
/// [ExercisePrescription] (ADR 0294 decision 1-2).
final class SuccessCriteria {
  SuccessCriteria({
    required this.kind,
    required String description,
    required Iterable<ExerciseCapability> requiredCapabilities,
    double? minimumAccuracy,
  }) : description = _requireText(description, 'description'),
       requiredCapabilities = _requireNonEmptyCapabilities(
         requiredCapabilities,
       ),
       minimumAccuracy = _validateAccuracy(minimumAccuracy);

  final SuccessCriterionKind kind;
  final String description;
  final Set<ExerciseCapability> requiredCapabilities;
  final double? minimumAccuracy;

  /// Throws an [ArgumentError] unless every one of [requiredCapabilities] is
  /// [CapabilitySupport.supported] on [candidateCapabilities]. This is the
  /// only measurability check a criterion performs — there is no metric-code
  /// inference (ADR 0294 decision 1).
  void ensureMeasurableFor(ExerciseCapabilities candidateCapabilities) {
    final unsupported = requiredCapabilities
        .where(
          (capability) =>
              candidateCapabilities[capability] != CapabilitySupport.supported,
        )
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw ArgumentError.value(
        [for (final capability in unsupported) capability.code],
        'requiredCapabilities',
        'success criterion requires capabilities the candidate does not '
            'support',
      );
    }
  }

  /// Non-throwing form of [ensureMeasurableFor].
  bool isMeasurableFor(ExerciseCapabilities candidateCapabilities) =>
      requiredCapabilities.every(
        (capability) =>
            candidateCapabilities[capability] == CapabilitySupport.supported,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.code,
    'description': description,
    'requiredCapabilities': [
      for (final capability in requiredCapabilities) capability.code,
    ],
    'minimumAccuracy': minimumAccuracy,
  };

  static SuccessCriteria fromJson(Map<String, dynamic> json) {
    final kindCode = json['kind'];
    final description = json['description'];
    final requiredRaw = json['requiredCapabilities'];
    if (kindCode is! String) {
      throw ArgumentError.value(
        kindCode,
        'kind',
        'SuccessCriteria JSON requires a String kind',
      );
    }
    if (description is! String) {
      throw ArgumentError.value(
        description,
        'description',
        'SuccessCriteria JSON requires a String description',
      );
    }
    if (requiredRaw is! List) {
      throw ArgumentError.value(
        requiredRaw,
        'requiredCapabilities',
        'SuccessCriteria JSON requires a requiredCapabilities list',
      );
    }
    final minimumAccuracyRaw = json['minimumAccuracy'];
    if (minimumAccuracyRaw != null && minimumAccuracyRaw is! num) {
      throw ArgumentError.value(
        minimumAccuracyRaw,
        'minimumAccuracy',
        'must be numeric when present',
      );
    }
    return SuccessCriteria(
      kind: SuccessCriterionKind.fromCode(kindCode),
      description: description,
      requiredCapabilities: [
        for (final entry in requiredRaw) _capabilityFromCode(entry),
      ],
      minimumAccuracy: (minimumAccuracyRaw as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuccessCriteria &&
          other.kind == kind &&
          other.description == description &&
          _sameCapabilitySet(
            other.requiredCapabilities,
            requiredCapabilities,
          ) &&
          other.minimumAccuracy == minimumAccuracy;

  @override
  int get hashCode => Object.hash(
    kind,
    description,
    Object.hashAllUnordered(requiredCapabilities),
    minimumAccuracy,
  );
}

Set<ExerciseCapability> _requireNonEmptyCapabilities(
  Iterable<ExerciseCapability> values,
) {
  final set = Set<ExerciseCapability>.unmodifiable(values.toSet());
  if (set.isEmpty) {
    throw ArgumentError.value(
      values,
      'requiredCapabilities',
      'must not be empty — a success criterion is never vacuously satisfied',
    );
  }
  return set;
}

double? _validateAccuracy(double? value) {
  if (value == null) return null;
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      'minimumAccuracy',
      'must be a finite value from 0 to 1',
    );
  }
  return value;
}

bool _sameCapabilitySet(
  Set<ExerciseCapability> left,
  Set<ExerciseCapability> right,
) => left.length == right.length && left.containsAll(right);

ExerciseCapability _capabilityFromCode(Object? code) {
  if (code is! String) {
    throw ArgumentError.value(
      code,
      'requiredCapabilities',
      'each ExerciseCapability code must be a String',
    );
  }
  for (final capability in ExerciseCapability.values) {
    if (capability.code == code) return capability;
  }
  throw ArgumentError.value(
    code,
    'code',
    'Unknown ExerciseCapability code: $code',
  );
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
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
