import 'reward_reason.dart';

/// The supported schema of an individual reward-ledger record.
const int rewardLedgerEntrySchemaVersion = 1;

/// Immutable, caller-authored record of one reward decision.
///
/// [ledgerId] and [createdAt] are supplied by the caller so this domain
/// contract neither creates identifiers nor consults a wall clock. Repository
/// persistence enforces the cross-record [sourceEventId] uniqueness invariant.
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
    _validateText(ledgerId, 'ledgerId');
    _validateText(sourceEventId, 'sourceEventId');
    if (schemaVersion != rewardLedgerEntrySchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must equal $rewardLedgerEntrySchemaVersion',
      );
    }
    if (policyVersion <= 0) {
      throw ArgumentError.value(
        policyVersion,
        'policyVersion',
        'must be positive',
      );
    }
    if (baseXp < 0) {
      throw ArgumentError.value(baseXp, 'baseXp', 'must not be negative');
    }
    if (bonusXp < 0) {
      throw ArgumentError.value(bonusXp, 'bonusXp', 'must not be negative');
    }
    if (totalXp != baseXp + bonusXp) {
      throw ArgumentError.value(
        totalXp,
        'totalXp',
        'must equal baseXp + bonusXp',
      );
    }
    if (totalXp > 0 && reasons.isEmpty) {
      throw ArgumentError.value(
        reasons,
        'reasons',
        'must not be empty when totalXp is positive',
      );
    }

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

  /// Decodes only the schema this build understands.
  ///
  /// A repository keeps an entry that fails this decode in raw form when it
  /// later rewrites the enclosing document.
  factory RewardLedgerEntry.fromJson(Object? json) {
    final values = _stringKeyedObject(json);
    final createdAtText = _requiredString(values, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtText);
    if (createdAt == null) {
      throw ArgumentError.value(
        createdAtText,
        'createdAt',
        'must be an ISO-8601 timestamp',
      );
    }

    return RewardLedgerEntry(
      ledgerId: _requiredString(values, 'ledgerId'),
      sourceEventId: _requiredString(values, 'sourceEventId'),
      createdAt: createdAt,
      policyVersion: _requiredInt(values, 'policyVersion'),
      baseXp: _requiredInt(values, 'baseXp'),
      bonusXp: _requiredInt(values, 'bonusXp'),
      totalXp: _requiredInt(values, 'totalXp'),
      reasons: _rewardReasons(values['reasons']),
      schemaVersion: _requiredInt(values, 'schemaVersion'),
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
}

Map<String, Object?> _stringKeyedObject(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw ArgumentError.value(value, 'json', 'must be a JSON object');
  }
  final values = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw ArgumentError.value(entry.key, 'json key', 'must be a String');
    }
    values[entry.key as String] = entry.value;
  }
  return values;
}

String _requiredString(Map<String, Object?> values, String name) {
  final value = values[name];
  if (value is! String) {
    throw ArgumentError.value(value, name, 'must be a String');
  }
  return value;
}

int _requiredInt(Map<String, Object?> values, String name) {
  final value = values[name];
  if (value is! int) {
    throw ArgumentError.value(value, name, 'must be an int');
  }
  return value;
}

List<RewardReason> _rewardReasons(Object? value) {
  if (value is! List<Object?>) {
    throw ArgumentError.value(value, 'reasons', 'must be a JSON array');
  }
  return List<RewardReason>.unmodifiable([
    for (final rawReason in value) _rewardReasonFromName(rawReason),
  ]);
}

RewardReason _rewardReasonFromName(Object? value) {
  if (value is! String) {
    throw ArgumentError.value(value, 'reason', 'must be a String');
  }
  for (final reason in RewardReason.values) {
    if (reason.name == value) return reason;
  }
  throw ArgumentError.value(
    value,
    'reason',
    'is not a supported reward reason',
  );
}

void _validateText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
}

bool _sameReasons(List<RewardReason> left, List<RewardReason> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
