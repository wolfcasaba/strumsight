/// Typed identifiers for the AI Practice Generator domain (ADR 0257).
///
/// Each ID is a distinct type, so a value built for one kind can never be
/// substituted for another at compile time — passing a [PlanId] where a
/// [DayId] is expected is a compile error, not a runtime bug. Validation
/// happens once, at construction: an existing instance is always valid.
library;

final class PlanId {
  factory PlanId(String value) => PlanId._(_validateId(value, 'PlanId'));

  const PlanId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is PlanId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PlanId($value)';
}

final class DayId {
  factory DayId(String value) => DayId._(_validateId(value, 'DayId'));

  const DayId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is DayId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DayId($value)';
}

final class BlockId {
  factory BlockId(String value) => BlockId._(_validateId(value, 'BlockId'));

  const BlockId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is BlockId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BlockId($value)';
}

final class GoalId {
  factory GoalId(String value) => GoalId._(_validateId(value, 'GoalId'));

  const GoalId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is GoalId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GoalId($value)';
}

final class RevisionId {
  factory RevisionId(String value) =>
      RevisionId._(_validateId(value, 'RevisionId'));

  const RevisionId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is RevisionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RevisionId($value)';
}

final class OutcomeId {
  factory OutcomeId(String value) =>
      OutcomeId._(_validateId(value, 'OutcomeId'));

  const OutcomeId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is OutcomeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OutcomeId($value)';
}

final RegExp _validIdPattern = RegExp(r'^[A-Za-z0-9._:-]+$');

/// Rejects empty, whitespace-only, and otherwise malformed values before an
/// ID instance can ever exist, so no caller has to re-validate one.
String _validateId(String value, String typeName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, typeName, 'must not be empty or blank');
  }
  if (!_validIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      typeName,
      'must match ${_validIdPattern.pattern}',
    );
  }
  return value;
}
