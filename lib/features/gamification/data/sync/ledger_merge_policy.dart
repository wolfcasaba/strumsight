/// Sync-side merge policy for the reward ledger.
///
/// Two responsibilities, kept apart on purpose:
///
/// 1. **Online/offline gate** — when the account layer is disabled (no
///    sign-in, or sync turned off), the policy must not issue any network
///    request. This is the §5.4 invariant: signed-out = zero bytes leave the
///    device. The gate is checked BEFORE any transport is touched.
///
/// 2. **Union merge** — the local and remote ledgers are reconciled by
///    receipt identity, never by last-write-wins (ADR 0394 §5.2, §5.3).
///    Two receipts are duplicates iff they describe the SAME LOGICAL EVENT:
///    same `sourceEventId` and identical XP components. The ledgerId is the
///    provenance tag — different ledgerIds for the same event mean
///    cross-device, which we merge; identical ledgerIds mean the same
///    physical entry, which we dedup; rare ledgerId collisions are kept
///    apart (no data loss).
library;

import 'package:flutter/foundation.dart';

import '../../domain/rewards/reward_ledger_entry.dart';
import 'gamification_sync_contract.dart';

/// A pluggable network transport the merge policy can call.
///
/// The interface is intentionally narrow: push uploads, pull downloads. The
/// implementation is responsible for serialising the envelope and adding
/// auth headers. In production the implementation hits the FastAPI
/// `/gamification/ledger` endpoint; in tests it counts calls to prove the
/// §5.4 invariant.
abstract interface class LedgerSyncTransport {
  /// Sends the client's unverified receipts to the server. Returns the
  /// server-canonical view (status-flipped, possibly with additional
  /// receipts the server has from another device).
  Future<SyncLedgerEnvelope> uploadAndPull(SyncLedgerEnvelope outbound);
}

/// Counts (or records) every network call the transport makes.
///
/// Tests assert on [requestCount] to prove §5.4: when account sync is off,
/// this counter must stay at zero regardless of how many times merge runs.
abstract interface class LedgerSyncTransportProbe {
  int get requestCount;
}

/// Pure merge kernel — no I/O, no async, no time. Deterministic: the same
/// inputs produce the same outputs, which is what lets the Dart side and
/// the server agree on the union shape.
@immutable
final class LedgerMergePolicy {
  const LedgerMergePolicy();

  /// Whether the merge should even be considered.
  ///
  /// `true` only when the account layer is enabled AND the transport has
  /// been supplied. The caller MUST short-circuit on `false` BEFORE reaching
  /// for the transport — the §5.4 invariant requires zero bytes to leave
  /// the device when account sync is off.
  bool shouldRun({required bool accountEnabled}) {
    if (!accountEnabled) return false;
    return true;
  }

  /// Merge local and remote into one canonical receipt list.
  ///
  /// - Same entry on both sides (same `ledgerId` + `sourceEventId`) ⇒ keep
  ///   the verified one, or if both unverified, keep the local copy.
  /// - Cross-device same event (same `sourceEventId`, different
  ///   `ledgerId`, identical XP components) ⇒ merge into one receipt,
  ///   preferring the verified side.
  /// - Distinct events on either side ⇒ both kept (union).
  /// - Verified status is preserved; a verified receipt from the server
  ///   surfaces locally as `status = verified` on the merged entry.
  ///
  /// Receipts flagged with `supersedesLedgerId` (ADR 0394 §5.5) replace
  /// the referenced entry — the older one is removed unless it is also
  /// present on the other side, in which case both are kept (defensive).
  LedgerMergeResult merge({
    required List<RewardLedgerEntry> local,
    required SyncLedgerEnvelope remote,
  }) {
    // 1. Apply supersession first so a replaced receipt never shadows its
    //    replacement in the union.
    final remoteReceipts = _applySupersession(remote.receipts);
    final remoteById = <String, SyncReceipt>{
      for (final receipt in remoteReceipts) receipt.entry.ledgerId: receipt,
    };

    // 2. Local entries are deduped by ledgerId (a single device cannot
    //    legitimately have two entries with the same ledgerId), so the
    //    list-as-index in step 3 is safe.

    // 3. Walk every entry by ledgerId; pick the merged form.
    final merged = <String, MergedReceipt>{};
    for (final entry in local) {
      final counterpart = remoteById[entry.ledgerId];
      merged[entry.ledgerId] = _mergeOne(local: entry, remote: counterpart);
    }
    for (final remote in remoteReceipts) {
      merged.putIfAbsent(remote.entry.ledgerId, () => _remoteOnly(remote));
    }

    // 4. Cross-device: same sourceEventId, different ledgerIds. Group by
    //    sourceEventId across merged and only collapse when the XP
    //    components match exactly (a collision of sourceEventId alone
    //    keeps both entries — never silently merge).
    final bySourceEvent = <String, List<MergedReceipt>>{};
    for (final receipt in merged.values) {
      bySourceEvent
          .putIfAbsent(receipt.entry.sourceEventId, () => <MergedReceipt>[])
          .add(receipt);
    }
    final collapsed = <String, MergedReceipt>{};
    final collapsedSources = <String>{};
    for (final sourceEntries in bySourceEvent.values) {
      if (sourceEntries.length <= 1) {
        for (final entry in sourceEntries) {
          collapsed[entry.entry.ledgerId] = entry;
        }
        continue;
      }
      // Try to collapse each group of ≥2 by sourceEventId.
      final collapsedGroup = _collapseGroup(sourceEntries);
      for (final entry in collapsedGroup) {
        collapsed[entry.entry.ledgerId] = entry;
        collapsedSources.add(entry.entry.sourceEventId);
      }
    }

    return LedgerMergeResult._(
      entries: collapsed.values.map((m) => m.entry).toList(growable: false),
      verifiedLedgerIds: collapsed.values
          .where((m) => m.status == LedgerEntrySyncStatus.verified)
          .map((m) => m.entry.ledgerId)
          .toList(growable: false),
      collapsedSources: collapsedSources,
    );
  }

  MergedReceipt _mergeOne({
    required RewardLedgerEntry local,
    required SyncReceipt? remote,
  }) {
    if (remote == null) {
      return MergedReceipt(
        entry: local,
        status: LedgerEntrySyncStatus.unverified,
      );
    }
    final verified = remote.status == LedgerEntrySyncStatus.verified;
    return MergedReceipt(
      entry: _preferReceipt(local, remote.entry),
      status: verified
          ? LedgerEntrySyncStatus.verified
          : LedgerEntrySyncStatus.unverified,
    );
  }

  MergedReceipt _remoteOnly(SyncReceipt remote) =>
      MergedReceipt(entry: remote.entry, status: remote.status);

  /// Collapse a group of receipts that share a `sourceEventId`. Two
  /// receipts in the group are mergeable iff their XP components
  /// (`baseXp`, `bonusXp`, `totalXp`, `reasonCodes`) match — different
  /// XP means distinct logical events sharing a sourceEventId by
  /// collision, and we never silently merge those.
  List<MergedReceipt> _collapseGroup(List<MergedReceipt> group) {
    // Stable ordering so the chosen "primary" is deterministic.
    final ordered = [...group]
      ..sort((a, b) => a.entry.ledgerId.compareTo(b.entry.ledgerId));
    final result = <MergedReceipt>[];
    final consumed = <int>{};
    for (var i = 0; i < ordered.length; i++) {
      if (consumed.contains(i)) continue;
      final head = ordered[i];
      final bucket = <MergedReceipt>[head];
      consumed.add(i);
      for (var j = i + 1; j < ordered.length; j++) {
        if (consumed.contains(j)) continue;
        final candidate = ordered[j];
        if (_sameLogicalEvent(head, candidate)) {
          bucket.add(candidate);
          consumed.add(j);
        }
      }
      if (bucket.length == 1) {
        result.add(head);
      } else {
        result.add(_collapseBucket(bucket));
      }
    }
    return result;
  }

  MergedReceipt _collapseBucket(List<MergedReceipt> bucket) {
    // Prefer the verified receipt; otherwise the locally-first one.
    final verified = bucket.firstWhere(
      (entry) => entry.status == LedgerEntrySyncStatus.verified,
      orElse: () => bucket.first,
    );
    return MergedReceipt(entry: verified.entry, status: verified.status);
  }

  bool _sameLogicalEvent(MergedReceipt left, MergedReceipt right) {
    final l = left.entry;
    final r = right.entry;
    return l.baseXp == r.baseXp &&
        l.bonusXp == r.bonusXp &&
        l.totalXp == r.totalXp &&
        _sameReasons(l.reasonCodes, r.reasonCodes);
  }

  RewardLedgerEntry _preferReceipt(
    RewardLedgerEntry local,
    RewardLedgerEntry remote,
  ) {
    // Same XP components — entries describe the same logical event. If
    // their createdAt agrees, prefer the local one (it was here first).
    if (local.createdAt == remote.createdAt) return local;
    return local.createdAt.isBefore(remote.createdAt) ? local : remote;
  }

  List<SyncReceipt> _applySupersession(List<SyncReceipt> receipts) {
    final supersededIds = <String>{
      for (final receipt in receipts)
        if (receipt.supersedesLedgerId != null) receipt.supersedesLedgerId!,
    };
    if (supersededIds.isEmpty) return receipts;
    return [
      for (final receipt in receipts)
        if (!supersededIds.contains(receipt.entry.ledgerId)) receipt,
    ];
  }

  bool _sameReasons(List<dynamic> left, List<dynamic> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

/// The receipt produced by [LedgerMergePolicy.merge] — an entry plus its
/// verified/unverified status. Internal to the merge step.
@immutable
final class MergedReceipt {
  const MergedReceipt({required this.entry, required this.status});
  final RewardLedgerEntry entry;
  final LedgerEntrySyncStatus status;
}

/// The outcome of [LedgerMergePolicy.merge].
@immutable
final class LedgerMergeResult {
  const LedgerMergeResult._({
    required this.entries,
    required this.verifiedLedgerIds,
    required this.collapsedSources,
  });

  /// The merged ledger entries, deduplicated.
  final List<RewardLedgerEntry> entries;

  /// LedgerIds that came back as `verified` from the server.
  final List<String> verifiedLedgerIds;

  /// Source-event ids whose receipts were collapsed into a single entry.
  final Set<String> collapsedSources;

  /// Sum of `totalXp` across the merged set.
  int get totalXp => entries.fold<int>(0, (sum, entry) => sum + entry.totalXp);
}

/// A no-op transport used in tests and when account sync is disabled.
final class NullLedgerSyncTransport implements LedgerSyncTransport {
  const NullLedgerSyncTransport();

  @override
  Future<SyncLedgerEnvelope> uploadAndPull(SyncLedgerEnvelope outbound) =>
      throw StateError(
        'NullLedgerSyncTransport must not be called when account sync is '
        'disabled (ADR 0394 §5.4).',
      );
}
