import '../../../../core/foundation/json_validation.dart';
import 'reward_reason.dart';

/// Schema version for one reward-ledger record, inside its storage document.
const int rewardLedgerEntrySchemaVersion = 1;

/// An immutable, audit-friendly record of a single reward decision.
final class RewardLedgerEntry {
  factory RewardLedgerEntry({
    required String ledgerId,
    required String sourceEventId,
    required DateTime createdAt,
    required int policyVersion,
    required int baseXp,
    required int bonusXp,
    required int totalXp,
    required List<RewardReason> reasons,
    int schemaVersion = rewardLedgerEntrySchemaVersion,
  }) {
    _validate(
      ledgerId: ledgerId,
      sourceEventId: sourceEventId,
      policyVersion: policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasons: reasons,
      schemaVersion: schemaVersion,
    );
    return RewardLedgerEntry._(
      ledgerId: ledgerId,
      sourceEventId: sourceEventId,
      createdAt: createdAt,
      policyVersion: policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasons: List<RewardReason>.unmodifiable(reasons),
      schemaVersion: schemaVersion,
    );
  }

  const RewardLedgerEntry._({
    required this.ledgerId,
    required this.sourceEventId,
    required this.createdAt,
    required this.policyVersion,
    required this.baseXp,
    required this.bonusXp,
    required this.totalXp,
    required this.reasons,
    required this.schemaVersion,
  });

  final String ledgerId;
  final String sourceEventId;
  final DateTime createdAt;
  final int policyVersion;
  final int baseXp;
  final int bonusXp;
  final int totalXp;
  final List<RewardReason> reasons;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'ledgerId': ledgerId,
    'sourceEventId': sourceEventId,
    'createdAt': createdAt.toIso8601String(),
    'policyVersion': policyVersion,
    'baseXp': baseXp,
    'bonusXp': bonusXp,
    'totalXp': totalXp,
    'reasons': <String>[for (final reason in reasons) reason.name],
  };

  /// Decodes only this build's record schema. A caller that meets an unknown
  /// version must preserve the raw JSON rather than calling this method.
  factory RewardLedgerEntry.fromJson(Object? json) {
    final decoded = requireObject(json);
    final schemaVersion = requireInt(decoded, 'schemaVersion', min: 1);
    if (schemaVersion != rewardLedgerEntrySchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported by this reward ledger build',
      );
    }
    final reasons = requireList(decoded, 'reasons', maxLength: 32)
        .map((Object? reason) {
          if (reason is! String) {
            throw const JsonRecordException(
              RecordDecodeReason.notAString,
              field: 'reasons',
            );
          }
          for (final value in RewardReason.values) {
            if (value.name == reason) return value;
          }
          throw const JsonRecordException(
            RecordDecodeReason.unknownEnum,
            field: 'reasons',
          );
        })
        .toList(growable: false);
    return RewardLedgerEntry(
      ledgerId: requireString(decoded, 'ledgerId'),
      sourceEventId: requireString(decoded, 'sourceEventId'),
      createdAt: requireDateTime(decoded, 'createdAt'),
      policyVersion: requireInt(decoded, 'policyVersion', min: 1),
      baseXp: requireInt(decoded, 'baseXp'),
      bonusXp: requireInt(decoded, 'bonusXp'),
      totalXp: requireInt(decoded, 'totalXp'),
      reasons: reasons,
      schemaVersion: schemaVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RewardLedgerEntry &&
      ledgerId == other.ledgerId &&
      sourceEventId == other.sourceEventId &&
      createdAt == other.createdAt &&
      policyVersion == other.policyVersion &&
      baseXp == other.baseXp &&
      bonusXp == other.bonusXp &&
      totalXp == other.totalXp &&
      schemaVersion == other.schemaVersion &&
      _sameReasons(reasons, other.reasons);

  @override
  int get hashCode => Object.hash(
    ledgerId,
    sourceEventId,
    createdAt,
    policyVersion,
    baseXp,
    bonusXp,
    totalXp,
    schemaVersion,
    Object.hashAll(reasons),
  );

  static void _validate({
    required String ledgerId,
    required String sourceEventId,
    required int policyVersion,
    required int baseXp,
    required int bonusXp,
    required int totalXp,
    required List<RewardReason> reasons,
    required int schemaVersion,
  }) {
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
    if (policyVersion <= 0) {
      throw ArgumentError.value(
        policyVersion,
        'policyVersion',
        'must be positive',
      );
    }
    if (baseXp < 0 || bonusXp < 0) {
      throw ArgumentError('XP components must not be negative');
    }
    if (totalXp != baseXp + bonusXp) {
      throw ArgumentError('totalXp must equal baseXp + bonusXp');
    }
    if (totalXp > 0 && reasons.isEmpty) {
      throw ArgumentError('a positive reward requires at least one reason');
    }
    if (schemaVersion != rewardLedgerEntrySchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported by this reward ledger build',
      );
    }
  }
}

bool _sameReasons(List<RewardReason> left, List<RewardReason> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
