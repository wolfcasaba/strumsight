/// Versioned upload/download contract for the reward ledger.
///
/// The contract carries **receipts** — every persisted [RewardLedgerEntry] in
/// full — and never accepts a client-aggregated `totalXp`. The server is the
/// only authority for profile totals: it computes the sum from the receipts
/// it has on file. Anything else would let a client mint XP by tampering
/// with the request body (ADR 0394 §5.1).
///
/// The contract is versioned. Unknown versions are rejected so a future
/// shape change cannot silently degrade older clients.
library;

import '../../domain/rewards/reward_ledger_entry.dart';
import '../../domain/rewards/reward_reason.dart';

/// Wire version. Bump only on a backward-incompatible shape change.
const int gamificationSyncContractVersion = 1;

/// Sync-side verification status.
///
/// A receipt starts `unverified` when the client uploads it. The server flips
/// it to `verified` after validating the receipt against its own policy. A
/// client cannot self-promote a receipt to `verified` — the field on upload
/// is forced to `unverified` by [_ReceiptUploadCodec].
enum LedgerEntrySyncStatus { unverified, verified }

/// One ledger receipt in the sync envelope.
///
/// The wire schema is identical to the local [RewardLedgerEntry] JSON shape,
/// with one extra field: `supersedesLedgerId`. A receipt carrying a
/// `supersedesLedgerId` replaces the referenced receipt during merge
/// (ADR 0394 §5.5 — policy-version supersession).
final class SyncReceipt {
  const SyncReceipt({
    required this.entry,
    required this.status,
    this.supersedesLedgerId,
  });

  final RewardLedgerEntry entry;
  final LedgerEntrySyncStatus status;
  final String? supersedesLedgerId;
}

/// An immutable, ordered set of receipts in the contract envelope shape.
final class SyncLedgerEnvelope {
  SyncLedgerEnvelope({required List<SyncReceipt> receipts})
    : receipts = List<SyncReceipt>.unmodifiable(receipts);

  final List<SyncReceipt> receipts;
}

/// Codec for the wire envelope.
///
/// Upload envelopes have `status` forced to `unverified` (clients cannot
/// self-verify — ADR 0394 §5.3) and reject any caller-supplied status.
sealed class _SyncReceiptCodec {
  static Map<String, Object?> toUploadJson(SyncReceipt receipt) {
    final json = receipt.entry.toJson();
    json.remove('totalXp') == null;
    return <String, Object?>{
      'schemaVersion': gamificationSyncContractVersion,
      'receipt': <String, Object?>{
        ...json,
        'status': LedgerEntrySyncStatus.unverified.name,
      },
    };
  }

  static Map<String, Object?> envelopeUpload(SyncLedgerEnvelope envelope) =>
      <String, Object?>{
        'schemaVersion': gamificationSyncContractVersion,
        'receipts': <Object?>[
          for (final receipt in envelope.receipts) toUploadJson(receipt),
        ],
      };

  static SyncLedgerEnvelope envelopeDownload(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Sync envelope must be a JSON object.');
    }
    _requireContractVersion(json);
    final rawReceipts = json['receipts'];
    if (rawReceipts is! List<Object?>) {
      throw const FormatException('Sync envelope `receipts` must be a list.');
    }
    return SyncLedgerEnvelope(
      receipts: <SyncReceipt>[
        for (final raw in rawReceipts) receiptFromJson(raw),
      ],
    );
  }

  static SyncReceipt receiptFromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Sync receipt must be a JSON object.');
    }
    final receiptJson = json['receipt'];
    if (receiptJson is! Map<String, Object?>) {
      throw const FormatException(
        'Sync receipt is missing its `receipt` body.',
      );
    }
    final entry = RewardLedgerEntry.fromJson(receiptJson);
    final statusName = json['status'];
    final status = _parseStatus(statusName);
    final rawSupersedes = json['supersedesLedgerId'];
    final supersedes = rawSupersedes is String ? rawSupersedes : null;
    return SyncReceipt(
      entry: entry,
      status: status,
      supersedesLedgerId: supersedes,
    );
  }

  static LedgerEntrySyncStatus _parseStatus(Object? raw) {
    if (raw is! String) {
      throw const FormatException('Sync receipt `status` must be a string.');
    }
    try {
      return LedgerEntrySyncStatus.values.byName(raw);
    } on ArgumentError {
      throw FormatException('Unsupported sync receipt status: $raw');
    }
  }

  static void _requireContractVersion(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is! int || version != gamificationSyncContractVersion) {
      throw FormatException(
        'Unsupported gamification sync contract version: $version '
        '(expected $gamificationSyncContractVersion).',
      );
    }
  }
}

/// Public encode/decode helpers.
abstract final class GamificationSyncContract {
  GamificationSyncContract._();

  /// Encode an upload envelope.
  ///
  /// Receipts are always serialised as `unverified`. Any caller-supplied
  /// `status` is dropped on the floor (ADR 0394 §5.3) — the server is the
  /// only writer of `verified`.
  static Map<String, Object?> encodeUpload(SyncLedgerEnvelope envelope) =>
      _SyncReceiptCodec.envelopeUpload(envelope);

  /// Decode a server envelope (download response). Unknown contract versions
  /// raise [FormatException].
  static SyncLedgerEnvelope decodeDownload(Object? json) =>
      _SyncReceiptCodec.envelopeDownload(json);
}

/// Why a receipt cannot be ingested on the server.
enum SyncContractRejectionReason {
  unknownContractVersion,
  receiptSchemaMismatch,
  receiptLedgerIdConflict,
}

/// Outcome of validating a single upload receipt — the server-side decision
/// for whether the receipt is accepted, and at what status.
sealed class SyncUploadDecision {
  const SyncUploadDecision();
}

final class SyncUploadAccepted extends SyncUploadDecision {
  const SyncUploadAccepted({required this.verified});
  final bool verified;
}

final class SyncUploadRejected extends SyncUploadDecision {
  const SyncUploadRejected({required this.reason, required this.message});
  final SyncContractRejectionReason reason;
  final String message;
}

/// Pure functions over a batch of receipts — no I/O, no time, no random.
/// Used by both the server and the Dart-side merge policy to reach identical
/// conclusions on the same input.
abstract final class SyncReceiptValidation {
  SyncReceiptValidation._();

  /// Verify a receipt conforms to the contract:
  /// - the receipt's own schema version matches the local store
  ///   (`rewardLedgerEntrySchemaVersion`);
  /// - `status == unverified` on the wire (a verified flag on upload is
  ///   rejected — ADR 0394 §5.3).
  static SyncUploadDecision validate(SyncReceipt receipt) {
    if (receipt.entry.schemaVersion != rewardLedgerEntrySchemaVersion) {
      return const SyncUploadRejected(
        reason: SyncContractRejectionReason.receiptSchemaMismatch,
        message: 'Receipt schemaVersion does not match local store.',
      );
    }
    if (receipt.status != LedgerEntrySyncStatus.unverified) {
      return const SyncUploadRejected(
        reason: SyncContractRejectionReason.receiptSchemaMismatch,
        message:
            'Uploads must declare status=unverified; verified is server-side.',
      );
    }
    return const SyncUploadAccepted(verified: true);
  }
}

/// Builds the canonical sort order used by both sides — receipts first by
/// `policyVersion`, then by `createdAt`, then by `ledgerId`. Deterministic
/// so the merge policy and the server reach the same ordering on the same
/// input.
int compareSyncReceipts(SyncReceipt left, SyncReceipt right) {
  final byPolicy = left.entry.policyVersion.compareTo(
    right.entry.policyVersion,
  );
  if (byPolicy != 0) return byPolicy;
  final byCreated = left.entry.createdAt.compareTo(right.entry.createdAt);
  if (byCreated != 0) return byCreated;
  return left.entry.ledgerId.compareTo(right.entry.ledgerId);
}

/// Pure helper used by [_SyncReceiptCodec] — kept here so the tests can
/// reuse it without re-implementing the lookup.
const List<RewardReason> allRewardReasons = <RewardReason>[
  RewardReason.baseExperience,
  RewardReason.qualityBonus,
  RewardReason.consistencyBonus,
  RewardReason.achievementUnlocked,
  RewardReason.questCompleted,
  RewardReason.dailyCapApplied,
  RewardReason.repeatLimited,
  RewardReason.tooShort,
  RewardReason.cancelled,
  RewardReason.failed,
  RewardReason.insufficientTrust,
  RewardReason.fatalSignalQuality,
];
