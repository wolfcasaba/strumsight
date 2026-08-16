/// Structured, machine-readable differences between plan revisions.
library;

import '../id/planner_ids.dart';

enum PlanChangeType {
  added('added'),
  removed('removed'),
  updated('updated'),
  moved('moved'),
  statusChanged('statusChanged');

  const PlanChangeType(this.code);

  final String code;

  static PlanChangeType fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'PlanChangeType code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown PlanChangeType code: $code',
    );
  }
}

/// Stable, typed causes for a revision; free-text explanations are excluded.
enum PlanChangeReason {
  learnerReschedule('learnerReschedule'),
  systemAdaptation('systemAdaptation'),
  modelSuggestionAccepted('modelSuggestionAccepted'),
  goalChanged('goalChanged'),
  availabilityChanged('availabilityChanged'),
  missedPractice('missedPractice');

  const PlanChangeReason(this.code);

  final String code;

  static PlanChangeReason fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'Unknown PlanChangeReason: $code');
  }
}

final class PlanChange {
  PlanChange({
    required this.type,
    required String target,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
    required this.reason,
    required Iterable<String> evidenceRefs,
    required this.confidence,
    required this.requiresUserConfirmation,
    required this.reversible,
  }) : target = _text(target, 'target'),
       before = Map<String, Object?>.unmodifiable(before),
       after = Map<String, Object?>.unmodifiable(after),
       evidenceRefs = List<String>.unmodifiable(
         evidenceRefs.map((value) => _text(value, 'evidenceRefs')),
       ) {
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in 0..1');
    }
  }

  final PlanChangeType type;
  final String target;
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  final PlanChangeReason reason;
  final List<String> evidenceRefs;
  final double confidence;
  final bool requiresUserConfirmation;
  final bool reversible;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.code,
    'target': target,
    'before': before,
    'after': after,
    'reason': reason.code,
    'evidenceRefs': evidenceRefs,
    'confidence': confidence,
    'requiresUserConfirmation': requiresUserConfirmation,
    'reversible': reversible,
  };
}

final class PlanChangeSet {
  PlanChangeSet({
    required this.fromRevisionId,
    required this.toRevisionId,
    required Iterable<PlanChange> changes,
  }) : changes = List<PlanChange>.unmodifiable(changes) {
    if (fromRevisionId == toRevisionId) {
      throw ArgumentError('A change set must connect distinct revisions');
    }
  }

  final RevisionId fromRevisionId;
  final RevisionId toRevisionId;
  final List<PlanChange> changes;

  Map<String, Object?> toJson() => <String, Object?>{
    'fromRevisionId': fromRevisionId.toJson(),
    'toRevisionId': toRevisionId.toJson(),
    'changes': [for (final change in changes) change.toJson()],
  };
}

String _text(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return trimmed;
}
