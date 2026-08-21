import '../rewards/reward_ledger_entry.dart';
import '../rewards/reward_reason.dart';
import 'quest_definition.dart';

/// The complete, closed lifecycle vocabulary for one quest progress record.
enum QuestStatus { active, completed, expired, replaced, archived }

/// Stable reasons emitted for successful lifecycle commands.
enum QuestTransitionReason {
  completed,
  completionAlreadyRecorded,
  expired,
  replacedForCatalogRefresh,
  replacedForContentRetirement,
  archived,
}

/// Stable failures emitted instead of a silent lifecycle no-op.
enum QuestTransitionFailure { invalidTransition, expired, notExpired }

/// The documented source of a generated quest replacement.
enum QuestReplacementReason { catalogRefresh, contentRetirement }

/// Current schema for persisted [QuestProgress] records.
const int questProgressSchemaVersion = 1;

/// The explicit result of a quest lifecycle command.
final class QuestTransitionResult {
  const QuestTransitionResult._success({
    required this.progress,
    required this.reason,
    this.receipt,
  }) : failure = null;

  const QuestTransitionResult._failure({
    required this.progress,
    required this.failure,
  }) : reason = null,
       receipt = null;

  final QuestProgress progress;
  final QuestTransitionReason? reason;
  final QuestTransitionFailure? failure;
  final RewardLedgerEntry? receipt;

  bool get isSuccess => failure == null;
}

/// Immutable progress that owns no repository, clock, or UI dependency.
final class QuestProgress {
  QuestProgress.active({
    required this.definition,
    required this.completedUnits,
    required List<String> practiceResultIds,
  }) : schemaVersion = questProgressSchemaVersion,
       status = QuestStatus.active,
       completionAt = null,
       rewardLedgerId = null,
       replacementReason = null,
       practiceResultIds = List<String>.unmodifiable(practiceResultIds) {
    _validate();
  }

  QuestProgress._({
    required this.schemaVersion,
    required this.definition,
    required this.status,
    required this.completedUnits,
    required this.practiceResultIds,
    required this.completionAt,
    required this.rewardLedgerId,
    required this.replacementReason,
  }) {
    _validate();
  }

  final int schemaVersion;
  final QuestDefinition definition;
  final QuestStatus status;
  final int completedUnits;
  final List<String> practiceResultIds;
  final DateTime? completionAt;
  final String? rewardLedgerId;
  final QuestReplacementReason? replacementReason;

  QuestTransitionResult complete({required DateTime at}) {
    if (status == QuestStatus.completed) {
      return QuestTransitionResult._success(
        progress: this,
        reason: QuestTransitionReason.completionAlreadyRecorded,
        receipt: _receipt(),
      );
    }
    if (status != QuestStatus.active) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.invalidTransition,
      );
    }
    if (!definition.schedule.isActiveAt(at)) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.expired,
      );
    }
    final completedAt = at.toUtc();
    final completed = _copyWith(
      status: QuestStatus.completed,
      completionAt: completedAt,
      rewardLedgerId: _ledgerIdFor(definition.id),
    );
    return QuestTransitionResult._success(
      progress: completed,
      reason: QuestTransitionReason.completed,
      receipt: completed._receipt(),
    );
  }

  QuestTransitionResult expire({required DateTime at}) {
    if (status != QuestStatus.active) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.invalidTransition,
      );
    }
    if (definition.schedule.isActiveAt(at)) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.notExpired,
      );
    }
    return QuestTransitionResult._success(
      progress: _copyWith(status: QuestStatus.expired),
      reason: QuestTransitionReason.expired,
    );
  }

  QuestTransitionResult replace({required QuestReplacementReason reason}) {
    if (status != QuestStatus.active) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.invalidTransition,
      );
    }
    return QuestTransitionResult._success(
      progress: _copyWith(
        status: QuestStatus.replaced,
        replacementReason: reason,
      ),
      reason: switch (reason) {
        QuestReplacementReason.catalogRefresh =>
          QuestTransitionReason.replacedForCatalogRefresh,
        QuestReplacementReason.contentRetirement =>
          QuestTransitionReason.replacedForContentRetirement,
      },
    );
  }

  QuestTransitionResult archive() {
    if (status == QuestStatus.active || status == QuestStatus.archived) {
      return QuestTransitionResult._failure(
        progress: this,
        failure: QuestTransitionFailure.invalidTransition,
      );
    }
    return QuestTransitionResult._success(
      progress: _copyWith(status: QuestStatus.archived),
      reason: QuestTransitionReason.archived,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'definition': definition.toJson(),
    'status': status.name,
    'completedUnits': completedUnits,
    'practiceResultIds': practiceResultIds,
    'completionAt': completionAt?.toIso8601String(),
    'rewardLedgerId': rewardLedgerId,
    'replacementReason': replacementReason?.name,
  };

  factory QuestProgress.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final schemaVersion = _requireInt(json, 'schemaVersion');
    if (schemaVersion != questProgressSchemaVersion) {
      throw ArgumentError.value(
        json['schemaVersion'],
        'schemaVersion',
        'is not supported',
      );
    }
    return QuestProgress._(
      schemaVersion: schemaVersion,
      definition: QuestDefinition.fromJson(json['definition']),
      status: _statusFromName(_requireString(json, 'status')),
      completedUnits: _requireInt(json, 'completedUnits'),
      practiceResultIds: List<String>.unmodifiable(
        _requireStringList(json, 'practiceResultIds'),
      ),
      completionAt: _optionalUtcDate(json['completionAt'], 'completionAt'),
      rewardLedgerId: _optionalString(json['rewardLedgerId'], 'rewardLedgerId'),
      replacementReason: _optionalReplacementReason(json['replacementReason']),
    );
  }

  QuestProgress _copyWith({
    required QuestStatus status,
    DateTime? completionAt,
    String? rewardLedgerId,
    QuestReplacementReason? replacementReason,
  }) => QuestProgress._(
    schemaVersion: schemaVersion,
    definition: definition,
    status: status,
    completedUnits: completedUnits,
    practiceResultIds: practiceResultIds,
    completionAt: completionAt ?? this.completionAt,
    rewardLedgerId: rewardLedgerId ?? this.rewardLedgerId,
    replacementReason: replacementReason ?? this.replacementReason,
  );

  RewardLedgerEntry _receipt() {
    final completedAt = completionAt;
    final ledgerId = rewardLedgerId;
    if (completedAt == null || ledgerId == null) {
      throw StateError('only completed progress has a reward receipt');
    }
    return RewardLedgerEntry(
      ledgerId: ledgerId,
      sourceEventId: 'quest:${definition.id}',
      createdAt: completedAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: definition.reward.policyVersion,
      baseXp: definition.reward.baseXp,
      bonusXp: definition.reward.bonusXp,
      totalXp: definition.reward.totalXp,
      reasonCodes: const <RewardReason>[RewardReason.questCompleted],
    );
  }

  void _validate() {
    if (completedUnits < 0) {
      throw ArgumentError.value(
        completedUnits,
        'completedUnits',
        'must not be negative',
      );
    }
    if (practiceResultIds.any((id) => id.trim().isEmpty) ||
        practiceResultIds.toSet().length != practiceResultIds.length) {
      throw ArgumentError.value(
        practiceResultIds,
        'practiceResultIds',
        'must be unique, non-blank IDs',
      );
    }
    final hasCompletion = completionAt != null && rewardLedgerId != null;
    if ((completionAt == null) != (rewardLedgerId == null) ||
        (status == QuestStatus.completed && !hasCompletion) ||
        (status != QuestStatus.completed &&
            status != QuestStatus.archived &&
            hasCompletion)) {
      throw ArgumentError(
        'completion and reward receipt must be recorded together',
      );
    }
    if (status == QuestStatus.replaced && replacementReason == null) {
      throw ArgumentError('a replacement must record its reason');
    }
    if (status != QuestStatus.replaced &&
        status != QuestStatus.archived &&
        replacementReason != null) {
      throw ArgumentError(
        'only replacement records carry a replacement reason',
      );
    }
  }
}

String _ledgerIdFor(String questId) => 'quest:$questId:completion';

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

String _requireString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

List<String> _requireStringList(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw ArgumentError.value(value, field, 'must be a string list');
  }
  return value.cast<String>();
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be null or a string');
}

DateTime? _optionalUtcDate(Object? value, String field) {
  if (value == null) return null;
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    throw ArgumentError.value(value, field, 'must be null or a UTC ISO date');
  }
  return parsed;
}

QuestStatus _statusFromName(String name) {
  for (final status in QuestStatus.values) {
    if (status.name == name) return status;
  }
  throw ArgumentError.value(name, 'status', 'is not supported');
}

QuestReplacementReason? _optionalReplacementReason(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw ArgumentError.value(
      value,
      'replacementReason',
      'must be null or a string',
    );
  }
  for (final reason in QuestReplacementReason.values) {
    if (reason.name == value) return reason;
  }
  throw ArgumentError.value(value, 'replacementReason', 'is not supported');
}
