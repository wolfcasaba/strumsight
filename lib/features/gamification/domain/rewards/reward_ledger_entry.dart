import 'reward_reason.dart';

/// Current schema for a persisted [RewardLedgerEntry].
const int rewardLedgerEntrySchemaVersion = 1;

/// An immutable receipt for one rewarded learning activity.
final class RewardLedgerEntry {
  RewardLedgerEntry({
    required this.ledgerId,
    required this.sourceEventId,
    required this.createdAt,
    required this.schemaVersion,
    required this.policyVersion,
    required this.baseXp,
    required this.bonusXp,
    required this.totalXp,
    required List<RewardReason> reasonCodes,
  }) : reasonCodes = List<RewardReason>.unmodifiable(reasonCodes) {
    if (ledgerId.trim().isEmpty) {
      throw ArgumentError.value(ledgerId, 'ledgerId', 'must not be blank');
    }
    if (sourceEventId.trim().isEmpty) {
      throw ArgumentError.value(
        sourceEventId,
        'sourceEventId',
        'must not be blank',
      );
    }
    if (schemaVersion != rewardLedgerEntrySchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (policyVersion < 1) {
      throw ArgumentError.value(
        policyVersion,
        'policyVersion',
        'must be positive',
      );
    }
    if (baseXp < 0 || bonusXp < 0 || totalXp < 0) {
      throw ArgumentError('experience components must not be negative');
    }
    if (totalXp != baseXp + bonusXp) {
      throw ArgumentError('totalXp must equal baseXp + bonusXp');
    }
    if (totalXp > 0 && this.reasonCodes.isEmpty) {
      throw ArgumentError('a positive reward must have a reason code');
    }
  }

  final String ledgerId;
  final String sourceEventId;
  final DateTime createdAt;
  final int schemaVersion;
  final int policyVersion;
  final int baseXp;
  final int bonusXp;
  final int totalXp;
  final List<RewardReason> reasonCodes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'ledgerId': ledgerId,
    'sourceEventId': sourceEventId,
    'createdAt': createdAt.toIso8601String(),
    'policyVersion': policyVersion,
    'baseXp': baseXp,
    'bonusXp': bonusXp,
    'totalXp': totalXp,
    'reasonCodes': reasonCodes.map((reason) => reason.name).toList(),
  };

  factory RewardLedgerEntry.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final createdAt = json['createdAt'];
    final parsedCreatedAt = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    if (parsedCreatedAt == null) {
      throw ArgumentError.value(createdAt, 'createdAt', 'must be an ISO date');
    }

    final reasonCodes = json['reasonCodes'];
    if (reasonCodes is! List<Object?>) {
      throw ArgumentError.value(reasonCodes, 'reasonCodes', 'must be a list');
    }

    return RewardLedgerEntry(
      ledgerId: _requireString(json, 'ledgerId'),
      sourceEventId: _requireString(json, 'sourceEventId'),
      createdAt: parsedCreatedAt,
      schemaVersion: _requireInt(json, 'schemaVersion'),
      policyVersion: _requireInt(json, 'policyVersion'),
      baseXp: _requireInt(json, 'baseXp'),
      bonusXp: _requireInt(json, 'bonusXp'),
      totalXp: _requireInt(json, 'totalXp'),
      reasonCodes: <RewardReason>[
        for (final code in reasonCodes) _reasonFromJson(code),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardLedgerEntry &&
          ledgerId == other.ledgerId &&
          sourceEventId == other.sourceEventId &&
          createdAt == other.createdAt &&
          schemaVersion == other.schemaVersion &&
          policyVersion == other.policyVersion &&
          baseXp == other.baseXp &&
          bonusXp == other.bonusXp &&
          totalXp == other.totalXp &&
          _sameReasonCodes(reasonCodes, other.reasonCodes);

  @override
  int get hashCode => Object.hash(
    ledgerId,
    sourceEventId,
    createdAt,
    schemaVersion,
    policyVersion,
    baseXp,
    bonusXp,
    totalXp,
    Object.hashAll(reasonCodes),
  );
}

String _requireString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

int _requireInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

RewardReason _reasonFromJson(Object? json) {
  if (json is! String) {
    throw ArgumentError.value(json, 'reasonCode', 'must be a string');
  }
  try {
    return RewardReason.values.byName(json);
  } on ArgumentError {
    throw ArgumentError.value(json, 'reasonCode', 'is not supported');
  }
}

bool _sameReasonCodes(List<RewardReason> left, List<RewardReason> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
