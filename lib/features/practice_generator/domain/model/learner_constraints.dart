/// Typed learner constraints for deterministic practice planning (ADR 0258).
library;

/// The planning concern a learner constraint applies to.
enum ConstraintCategory {
  equipment('equipment'),
  tuning('tuning'),
  capability('capability'),
  comfort('comfort'),
  accessibility('accessibility'),
  preference('preference'),
  avoid('avoid');

  const ConstraintCategory(this.code);

  final String code;

  static ConstraintCategory fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'ConstraintCategory',
  );
}

/// Whether a constraint excludes a plan or merely influences its cost.
///
/// This is deliberately independent of [ConstraintCategory]. For example, a
/// comfort constraint can be a hard safety boundary or a soft preference.
enum ConstraintStrength {
  hard('hard'),
  soft('soft');

  const ConstraintStrength(this.code);

  final String code;

  static ConstraintStrength fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'ConstraintStrength',
  );
}

/// A single named planning restriction supplied by the learner.
///
/// A hard restriction is never represented by a cost: it has a zero
/// [softViolationCost] and a violation is an error. A soft restriction has a
/// positive, explicit cost that a later prioritisation round may use.
final class LearnerConstraint {
  LearnerConstraint({
    required this.category,
    required this.strength,
    required String code,
    required String value,
    this.softViolationCost = 0,
  }) : code = _requireText(code, 'code'),
       value = _requireText(value, 'value') {
    if (strength == ConstraintStrength.hard && softViolationCost != 0) {
      throw ArgumentError.value(
        softViolationCost,
        'softViolationCost',
        'must be zero for a hard constraint',
      );
    }
    if (strength == ConstraintStrength.soft && softViolationCost <= 0) {
      throw ArgumentError.value(
        softViolationCost,
        'softViolationCost',
        'must be positive for a soft constraint',
      );
    }
  }

  final ConstraintCategory category;
  final ConstraintStrength strength;
  final String code;
  final String value;
  final int softViolationCost;

  bool get isHard => strength == ConstraintStrength.hard;

  bool get isSoft => strength == ConstraintStrength.soft;

  @override
  bool operator ==(Object other) =>
      other is LearnerConstraint &&
      category == other.category &&
      strength == other.strength &&
      code == other.code &&
      value == other.value &&
      softViolationCost == other.softViolationCost;

  @override
  int get hashCode =>
      Object.hash(category, strength, code, value, softViolationCost);
}

/// The complete immutable constraint set for one learner.
final class LearnerConstraints {
  LearnerConstraints(Iterable<LearnerConstraint> constraints)
    : constraints = List<LearnerConstraint>.unmodifiable(constraints) {
    final identities = <String>{};
    for (final constraint in this.constraints) {
      final identity = '${constraint.category.code}:${constraint.code}';
      if (!identities.add(identity)) {
        throw ArgumentError.value(
          constraints,
          'constraints',
          'contains duplicate constraint $identity',
        );
      }
    }
  }

  final List<LearnerConstraint> constraints;

  Iterable<LearnerConstraint> get hardConstraints =>
      constraints.where((constraint) => constraint.isHard);

  Iterable<LearnerConstraint> get softConstraints =>
      constraints.where((constraint) => constraint.isSoft);

  @override
  bool operator ==(Object other) =>
      other is LearnerConstraints && _sameList(constraints, other.constraints);

  @override
  int get hashCode => Object.hashAll(constraints);
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
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
