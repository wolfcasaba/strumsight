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
/// client cannot self-promote a receipt to `verified` — the in-memory guard
/// in [SyncReceiptValidation.validate] rejects a `verified` upload before
/// the codec ever serialises it (ADR 0394 §5.3). The upload wire envelope
/// does NOT carry a `status` field at all (the field is server-side output
/// only).
enum LedgerEntrySyncStatus { unverified, verified }

/// One ledger receipt in the sync envelope.
///
/// The wire schema is identical to the local [RewardLedgerEntry] JSON shape,
/// minus `totalXp` (which is server-computed, ADR 0394 §5.1) and minus the
/// upload-side `status` field (server-authoritative, ADR 0394 §5.3), plus
/// one envelope-only field: `supersedesLedgerId`. A receipt carrying a
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
/// Upload envelopes drop `status` entirely: the server treats every
/// client-supplied receipt as `unverified` (ADR 0394 §5.3) and the field
/// would be redundant on the wire. A caller-supplied
/// `status == verified` is rejected earlier, by [SyncReceiptValidation
/// .validate], before this codec runs.
sealed class _SyncReceiptCodec {
  static Map<String, Object?> toUploadJson(SyncReceipt receipt) {
    // Flat wire shape — the backend `ReceiptUpload` reads each of these
    // fields at the receipt-element root (`backend/app/gamification/
    // schemas.py`). No nested `receipt` wrapper; `totalXp` is stripped so
    // a tampered client cannot inflate the server-side aggregate.
    final json = receipt.entry.toJson();
    json.remove('totalXp');
    return json;
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
  /// The wire shape is flat: each receipt element carries the receipt
  /// fields directly at its root, with no nested `receipt` wrapper and no
  /// `status` field. The server treats every uploaded receipt as
  /// `unverified` (ADR 0394 §5.3), so the field would be redundant on the
  /// wire. A caller-supplied `status == verified` is rejected upstream by
  /// [SyncReceiptValidation.validate], before this codec runs.
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
  /// - the in-memory `status` is `unverified` (a verified flag on upload
  ///   is rejected — ADR 0394 §5.3). The wire envelope no longer carries a
  ///   `status` field, so the guard fires here, on the in-memory value,
  ///   before the codec serialises anything.
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
