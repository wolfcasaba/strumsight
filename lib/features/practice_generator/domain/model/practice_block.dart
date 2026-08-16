/// One immutable, executable block in a practice day (SDD Ch8 §16.3).
library;

import '../id/planner_ids.dart';
import 'exercise_candidate.dart';
import 'exercise_prescription.dart';
import 'plan_enums.dart';

/// Persisted status shared by a [PracticeDay] and a [PracticeBlock].
///
/// The values and stable codes are specified by SDD Ch8 §16.5. A status is
/// terminal within its revision unless a later revision introduces a new item.
enum PracticeItemStatus {
  planned('planned'),
  ready('ready'),
  inProgress('inProgress'),
  completed('completed'),
  skipped('skipped'),
  substituted('substituted'),
  unavailable('unavailable'),
  expired('expired');

  const PracticeItemStatus(this.code);

  final String code;

  static PracticeItemStatus fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(code, 'code', 'PracticeItemStatus is required');
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown PracticeItemStatus: $code',
    );
  }
}

/// Resolves the catalog candidate referenced by persisted prescriptions.
typedef ExerciseCandidateResolver =
    ExerciseCandidate Function(String exerciseId);

/// A bounded, immutable prescription with its planning provenance.
final class PracticeBlock {
  PracticeBlock({
    required this.id,
    required this.kind,
    required int order,
    required this.prescription,
    required Iterable<String> reasonCodes,
    required Iterable<String> evidenceRefs,
    required this.status,
    required this.estimatedElapsed,
  }) : order = _positive(order, 'order'),
       reasonCodes = _codes(reasonCodes, 'reasonCodes'),
       evidenceRefs = _codes(evidenceRefs, 'evidenceRefs') {
    if (estimatedElapsed <= Duration.zero) {
      throw ArgumentError.value(
        estimatedElapsed,
        'estimatedElapsed',
        'must be positive',
      );
    }
  }

  final BlockId id;
  final BlockKind kind;
  final int order;
  final ExercisePrescription prescription;
  final List<String> reasonCodes;
  final List<String> evidenceRefs;
  final PracticeItemStatus status;
  final Duration estimatedElapsed;

  bool canTransitionTo(PracticeItemStatus next) => switch (status) {
    PracticeItemStatus.planned =>
      next == PracticeItemStatus.ready ||
          next == PracticeItemStatus.inProgress ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.expired,
    PracticeItemStatus.ready =>
      next == PracticeItemStatus.inProgress ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.expired,
    PracticeItemStatus.inProgress =>
      next == PracticeItemStatus.completed ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable,
    PracticeItemStatus.completed ||
    PracticeItemStatus.skipped ||
    PracticeItemStatus.substituted ||
    PracticeItemStatus.unavailable ||
    PracticeItemStatus.expired => false,
  };

  PracticeBlock transitionTo(PracticeItemStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Cannot transition block $id from ${status.code} to ${next.code}',
      );
    }
    return PracticeBlock(
      id: id,
      kind: kind,
      order: order,
      prescription: prescription,
      reasonCodes: reasonCodes,
      evidenceRefs: evidenceRefs,
      status: next,
      estimatedElapsed: estimatedElapsed,
    );
  }

  /// Replaces future block content. Completed blocks belong to immutable past.
  PracticeBlock replaceContent({
    ExercisePrescription? prescription,
    Duration? estimatedElapsed,
    Iterable<String>? reasonCodes,
    Iterable<String>? evidenceRefs,
  }) {
    if (status == PracticeItemStatus.completed) {
      throw StateError(
        'Completed block $id cannot be modified in this revision',
      );
    }
    return PracticeBlock(
      id: id,
      kind: kind,
      order: order,
      prescription: prescription ?? this.prescription,
      reasonCodes: reasonCodes ?? this.reasonCodes,
      evidenceRefs: evidenceRefs ?? this.evidenceRefs,
      status: status,
      estimatedElapsed: estimatedElapsed ?? this.estimatedElapsed,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.toJson(),
    'kind': kind.code,
    'order': order,
    'prescription': prescription.toJson(),
    'reasonCodes': reasonCodes,
    'evidenceRefs': evidenceRefs,
    'status': status.code,
    'estimatedElapsedMicros': estimatedElapsed.inMicroseconds,
  };

  static PracticeBlock fromJson(
    Map<String, Object?> json, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final prescriptionJson = _object(json['prescription'], 'prescription');
    final exerciseId = _text(prescriptionJson['exerciseId'], 'exerciseId');
    return PracticeBlock(
      id: BlockId.fromJson(json['id']),
      kind: BlockKind.fromCode(_text(json['kind'], 'kind')),
      order: _integer(json['order'], 'order'),
      prescription: ExercisePrescription.fromJson(
        Map<String, dynamic>.from(prescriptionJson),
        candidate: resolveCandidate(exerciseId),
      ),
      reasonCodes: _textList(json['reasonCodes'], 'reasonCodes'),
      evidenceRefs: _textList(json['evidenceRefs'], 'evidenceRefs'),
      status: PracticeItemStatus.fromCode(_text(json['status'], 'status')),
      estimatedElapsed: Duration(
        microseconds: _integer(
          json['estimatedElapsedMicros'],
          'estimatedElapsedMicros',
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeBlock &&
          id == other.id &&
          kind == other.kind &&
          order == other.order &&
          prescription == other.prescription &&
          _sameList(reasonCodes, other.reasonCodes) &&
          _sameList(evidenceRefs, other.evidenceRefs) &&
          status == other.status &&
          estimatedElapsed == other.estimatedElapsed;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    order,
    prescription,
    Object.hashAll(reasonCodes),
    Object.hashAll(evidenceRefs),
    status,
    estimatedElapsed,
  );
}

int _positive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

List<String> _codes(Iterable<String> values, String name) {
  final result = values
      .map((value) => _text(value, name))
      .toList(growable: false);
  if (result.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'must be an object');
  }
  return Map<String, Object?>.from(value);
}

String _text(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must be a non-empty String');
  }
  return value.trim();
}

int _integer(Object? value, String name) {
  if (value is! num || value.toInt() != value) {
    throw ArgumentError.value(value, name, 'must be an integer');
  }
  return value.toInt();
}

List<String> _textList(Object? value, String name) {
  if (value is! List) {
    throw ArgumentError.value(value, name, 'must be a list');
  }
  return [for (final item in value) _text(item, name)];
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
