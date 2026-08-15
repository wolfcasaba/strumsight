/// The complete, versioned input to one practice-plan generation attempt
/// (ADR 0259, SDD Ch8 §10).
library;

import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import 'learner_constraints.dart';
import 'plan_enums.dart';
import 'practice_goal.dart';
import 'weekly_availability.dart';

/// Typed identifier for a [PracticeGenerationRequest] (ADR 0257 pattern).
final class GenerationRequestId {
  factory GenerationRequestId(String value) =>
      GenerationRequestId._(_validateId(value));

  factory GenerationRequestId.generate(String Function() generateId) =>
      GenerationRequestId(generateId());

  const GenerationRequestId._(this.value);

  final String value;

  static GenerationRequestId fromJson(Object? json) =>
      GenerationRequestId(_decodeJsonId(json));

  String toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is GenerationRequestId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GenerationRequestId($value)';
}

final RegExp _validIdPattern = RegExp(r'^[A-Za-z0-9._:-]+$');

String _validateId(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(
      value,
      'GenerationRequestId',
      'must not be empty or blank',
    );
  }
  if (!_validIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'GenerationRequestId',
      'must match ${_validIdPattern.pattern}',
    );
  }
  return value;
}

String _decodeJsonId(Object? json) {
  if (json is! String) {
    throw ArgumentError.value(
      json,
      'GenerationRequestId',
      'GenerationRequestId JSON must be a String',
    );
  }
  return json;
}

/// The complete, immutable input to a practice-plan generation attempt.
///
/// Two invariants make the request reproducible (ADR 0259):
///
/// 1. [seed] is *computed* from the request's content — never injected,
///    never derived from [createdAt] or any other wall-clock reading. The
///    same content always yields the same seed, on any device, at any time.
/// 2. [seed] and [contentHash] are built from a canonical, key-sorted JSON
///    snapshot of the content fields, so a change to serialized field order
///    alone can never change either value (ADR 0259 §2).
///
/// [id] and [createdAt] are provenance, not content: they identify *which*
/// request this is and *when* it was made, but deliberately play no part in
/// [seed] or [contentHash] — two requests with identical goals,
/// availability, constraints, mode, horizon and locale are the same
/// generation input even if one was typed today and the other a year ago.
/// The same exclusion applies to each goal's own `createdAt`.
final class PracticeGenerationRequest {
  PracticeGenerationRequest({
    required this.id,
    required DateTime createdAt,
    required String locale,
    required this.generationMode,
    required this.planHorizonDays,
    required this.availability,
    required this.constraints,
    Iterable<PracticeGoal> goals = const <PracticeGoal>[],
  }) : createdAt = createdAt.toUtc(),
       locale = _requireText(locale, 'locale'),
       goals = List<PracticeGoal>.unmodifiable(goals) {
    if (planHorizonDays < 1) {
      throw ArgumentError.value(
        planHorizonDays,
        'planHorizonDays',
        'must be at least 1 day',
      );
    }
  }

  final GenerationRequestId id;
  final DateTime createdAt;
  final String locale;
  final GenerationMode generationMode;
  final int planHorizonDays;
  final WeeklyAvailability availability;
  final LearnerConstraints constraints;
  final List<PracticeGoal> goals;

  /// Deterministic seed derived from [contentHash] (ADR 0259 §1). Always a
  /// non-negative value in `[0, 2^32)`, stable across devices and time for
  /// the same content.
  int get seed {
    final bytes = _contentDigestBytes;
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  /// Hex SHA-256 of the canonical content snapshot — a compact
  /// provenance/dedup key alongside [seed].
  String get contentHash => _contentDigest.toString();

  crypto.Digest get _contentDigest =>
      crypto.sha256.convert(utf8.encode(_canonicalContentJson));

  List<int> get _contentDigestBytes => _contentDigest.bytes;

  String get _canonicalContentJson =>
      jsonEncode(_canonicalize(_contentSnapshot()));

  /// Everything that defines *what* was requested. Deliberately excludes
  /// [id] and every `DateTime` (both [createdAt] and each goal's own
  /// `createdAt`) — those are provenance, not content (ADR 0259 §1).
  Map<String, Object?> _contentSnapshot() => <String, Object?>{
    'locale': locale,
    'generationMode': generationMode.code,
    'planHorizonDays': planHorizonDays,
    'goals': <Object?>[for (final goal in goals) _goalSnapshot(goal)],
    'availability': <Object?>[
      for (final day in availability.days) _dailyAvailabilitySnapshot(day),
    ],
    'constraints': <Object?>[
      for (final constraint in constraints.constraints)
        _constraintSnapshot(constraint),
    ],
  };

  static Map<String, Object?> _goalSnapshot(PracticeGoal goal) =>
      <String, Object?>{
        'id': goal.id.value,
        'type': goal.type.code,
        'priority': goal.priority.code,
        'status': goal.status.code,
        'targetDate': goal.targetDate == null
            ? null
            : _localDateToJson(goal.targetDate!),
        'skillIds': goal.skillIds,
        'songReference': goal.songReference,
        'metricTarget': goal.metricTarget == null
            ? null
            : _metricTargetSnapshot(goal.metricTarget!),
        'userNote': goal.userNote,
        'normalizedTargetId': goal.normalizedTargetId,
      };

  static Map<String, Object?> _metricTargetSnapshot(MetricTarget target) =>
      <String, Object?>{
        'metricCode': target.metricCode,
        'direction': target.direction.code,
        'threshold': target.threshold,
        'measurementCapability': target.measurementCapability,
        'minimumConfidence': target.minimumConfidence,
        'minimumSampleCount': target.minimumSampleCount,
        'targetDate': target.targetDate == null
            ? null
            : _localDateToJson(target.targetDate!),
      };

  static Map<String, Object?> _dailyAvailabilitySnapshot(
    DailyAvailability day,
  ) => <String, Object?>{
    'date': _localDateToJson(day.date),
    'status': day.status.code,
    'minimumMinutes': day.minimumMinutes,
    'targetMinutes': day.targetMinutes,
    'maximumMinutes': day.maximumMinutes,
    'maximumStrength': day.maximumStrength.code,
    'preferredStartMinute': day.preferredStartMinute,
    'note': day.note,
    'softExcessMinuteCost': day.softExcessMinuteCost,
  };

  static Map<String, Object?> _constraintSnapshot(
    LearnerConstraint constraint,
  ) => <String, Object?>{
    'category': constraint.category.code,
    'strength': constraint.strength.code,
    'code': constraint.code,
    'value': constraint.value,
    'softViolationCost': constraint.softViolationCost,
  };

  @override
  bool operator ==(Object other) =>
      other is PracticeGenerationRequest &&
      id == other.id &&
      createdAt == other.createdAt &&
      locale == other.locale &&
      generationMode == other.generationMode &&
      planHorizonDays == other.planHorizonDays &&
      _sameGoals(goals, other.goals) &&
      availability == other.availability &&
      constraints == other.constraints;

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    locale,
    generationMode,
    planHorizonDays,
    Object.hashAll(goals),
    availability,
    constraints,
  );
}

bool _sameGoals(List<PracticeGoal> a, List<PracticeGoal> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _localDateToJson(LocalDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

/// Recursively sorts every [Map]'s keys so the resulting structure encodes
/// to the same JSON string regardless of original insertion order (ADR 0259
/// §2 — the hash must depend on meaning, not on field order).
Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in sortedKeys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalize(item)];
  }
  return value;
}
