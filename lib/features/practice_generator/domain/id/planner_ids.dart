/// Typed identifiers for the AI Practice Generator domain (ADR 0257).
///
/// Each ID is a distinct type, so a value built for one kind can never be
/// substituted for another at compile time — passing a [PlanId] where a
/// [DayId] is expected is a compile error, not a runtime bug. Validation
/// happens once, at construction: an existing instance is always valid.
/// Every ID also has an explicit, stable JSON round-trip (`toJson`/
/// `fromJson`) and a deterministic generation entry point that validates an
/// injected `String Function()`'s output through that same constructor.
library;

final class PlanId {
  factory PlanId(String value) => PlanId._(_validateId(value, 'PlanId'));

  factory PlanId.generate(String Function() generateId) => PlanId(generateId());

  const PlanId._(this.value);

  final String value;

  static PlanId fromJson(Object? json) => PlanId(_decodeJsonId(json, 'PlanId'));

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is PlanId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PlanId($value)';
}

final class DayId {
  factory DayId(String value) => DayId._(_validateId(value, 'DayId'));

  factory DayId.generate(String Function() generateId) => DayId(generateId());

  const DayId._(this.value);

  final String value;

  static DayId fromJson(Object? json) => DayId(_decodeJsonId(json, 'DayId'));

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is DayId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DayId($value)';
}

final class BlockId {
  factory BlockId(String value) => BlockId._(_validateId(value, 'BlockId'));

  factory BlockId.generate(String Function() generateId) =>
      BlockId(generateId());

  const BlockId._(this.value);

  final String value;

  static BlockId fromJson(Object? json) =>
      BlockId(_decodeJsonId(json, 'BlockId'));

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is BlockId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BlockId($value)';
}

final class GoalId {
  factory GoalId(String value) => GoalId._(_validateId(value, 'GoalId'));

  factory GoalId.generate(String Function() generateId) => GoalId(generateId());

  const GoalId._(this.value);

  final String value;

  static GoalId fromJson(Object? json) => GoalId(_decodeJsonId(json, 'GoalId'));

  String toJson() => value;

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

  factory RevisionId.generate(String Function() generateId) =>
      RevisionId(generateId());

  const RevisionId._(this.value);

  final String value;

  static RevisionId fromJson(Object? json) =>
      RevisionId(_decodeJsonId(json, 'RevisionId'));

  String toJson() => value;

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

  factory OutcomeId.generate(String Function() generateId) =>
      OutcomeId(generateId());

  const OutcomeId._(this.value);

  final String value;

  static OutcomeId fromJson(Object? json) =>
      OutcomeId(_decodeJsonId(json, 'OutcomeId'));

  String toJson() => value;

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

/// Shared JSON-decode routine for every ID type above: a decoded value that
/// is missing or not a [String] fails loudly here, and a decoded [String]
/// that fails format validation fails in the constructor it is handed to
/// immediately after — so no decoded ID ever exists in an invalid state.
String _decodeJsonId(Object? json, String typeName) {
  if (json is! String) {
    throw ArgumentError.value(
      json,
      typeName,
      '$typeName JSON must be a String',
    );
  }
  return json;
}
