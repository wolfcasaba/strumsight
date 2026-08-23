import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  const policy = LedgerMergePolicy();

  group('A1 — idempotency (sync twice, total XP unchanged)', () {
    test(
      'submitting the same entry twice keeps one entry and one XP total',
      () {
        final entry = _entry(
          ledgerId: 'ledger-1',
          sourceEventId: 'event-1',
          baseXp: 10,
          bonusXp: 0,
        );

        final first = policy.merge(
          local: <RewardLedgerEntry>[entry],
          remote: SyncLedgerEnvelope(receipts: <SyncReceipt>[]),
        );
        final second = policy.merge(
          local: first.entries,
          remote: SyncLedgerEnvelope(
            receipts: <SyncReceipt>[
              SyncReceipt(entry: entry, status: LedgerEntrySyncStatus.verified),
            ],
          ),
        );

        expect(second.entries, <RewardLedgerEntry>[entry]);
        expect(second.totalXp, entry.totalXp);
      },
    );

    test('cross-device same event merges on sourceEventId (single XP)', () {
      final localEntry = _entry(
        ledgerId: 'ledger-A',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final remoteEntry = _entry(
        ledgerId: 'ledger-B',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );

      final result = policy.merge(
        local: <RewardLedgerEntry>[localEntry],
        remote: SyncLedgerEnvelope(
          receipts: <SyncReceipt>[
            SyncReceipt(
              entry: remoteEntry,
              status: LedgerEntrySyncStatus.verified,
            ),
          ],
        ),
      );

      expect(result.entries, hasLength(1));
      expect(result.totalXp, 10);
      expect(result.verifiedLedgerIds, <String>['ledger-B']);
      expect(result.collapsedSources, contains('shared-event'));
    });

    test('§6.1 fault: ledgerId-only dedup → cross-device duplicates XP', () {
      // The bad implementation dedups only on ledgerId; cross-device has
      // different ledgerIds, so both receipts survive → DUPLICATE XP.
      final localEntry = _entry(
        ledgerId: 'ledger-A',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final remoteEntry = _entry(
        ledgerId: 'ledger-B',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final buggy = _dedupByLedgerIdOnly([localEntry, remoteEntry]);
      expect(buggy, hasLength(2));
      final dupXp = buggy.fold<int>(0, (sum, e) => sum + e.totalXp);
      expect(dupXp, 20);
    });

    test('§6.1 fault: sourceEventId-only dedup → collision collapses XP', () {
      // The bad implementation dedups only on sourceEventId; the two
      // entries share a sourceEventId by collision but have different XP
      // components, so silently merging them would erase one event.
      final a = _entry(
        ledgerId: 'ledger-A',
        sourceEventId: 'colliding-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final b = _entry(
        ledgerId: 'ledger-B',
        sourceEventId: 'colliding-event',
        baseXp: 25,
        bonusXp: 5,
      );
      final buggy = _dedupBySourceEventIdOnly([a, b]);
      // The bad implementation merges them (one survives) → DATA LOSS.
      expect(buggy, hasLength(1));
    });
  });

  group('A3 — union (no data loss)', () {
    test('disjoint entries from both sides all survive', () {
      final localEntries = <RewardLedgerEntry>[
        _entry(ledgerId: 'l-1', sourceEventId: 'e-1', baseXp: 10),
        _entry(ledgerId: 'l-2', sourceEventId: 'e-2', baseXp: 15),
      ];
      final remoteEntries = <SyncReceipt>[
        SyncReceipt(
          entry: _entry(ledgerId: 'r-1', sourceEventId: 'e-3', baseXp: 20),
          status: LedgerEntrySyncStatus.unverified,
        ),
        SyncReceipt(
          entry: _entry(ledgerId: 'r-2', sourceEventId: 'e-4', baseXp: 5),
          status: LedgerEntrySyncStatus.unverified,
        ),
      ];

      final result = policy.merge(
        local: localEntries,
        remote: SyncLedgerEnvelope(receipts: remoteEntries),
      );

      expect(result.entries, hasLength(4));
      expect(result.totalXp, 50);
    });

    test('a collision (same sourceEventId, different XP) keeps both', () {
      final a = _entry(
        ledgerId: 'l-1',
        sourceEventId: 'collision',
        baseXp: 10,
        bonusXp: 0,
      );
      final b = _entry(
        ledgerId: 'l-2',
        sourceEventId: 'collision',
        baseXp: 7,
        bonusXp: 3,
      );

      final result = policy.merge(
        local: <RewardLedgerEntry>[a],
        remote: SyncLedgerEnvelope(
          receipts: <SyncReceipt>[
            SyncReceipt(entry: b, status: LedgerEntrySyncStatus.verified),
          ],
        ),
      );

      expect(result.entries, hasLength(2));
      expect(result.totalXp, 20);
    });
  });

  group('A4 — verified/unverified distinction', () {
    test('the client cannot smuggle a verified status onto the wire', () {
      final entry = _entry(ledgerId: 'l-1', sourceEventId: 'e-1');
      final envelope = SyncLedgerEnvelope(
        receipts: <SyncReceipt>[
          SyncReceipt(entry: entry, status: LedgerEntrySyncStatus.verified),
        ],
      );
      final json = GamificationSyncContract.encodeUpload(envelope);
      final rawReceipts = json['receipts']! as List<Object?>;
      final onTheWire = rawReceipts.first! as Map<String, Object?>;
      // Flat wire shape — the receipt fields sit at the element root, with
      // no nested `receipt` wrapper. The server treats every upload as
      // `unverified` (ADR 0394 §5.3), so `status` is omitted from the wire
      // entirely; a client that smuggles `verified` cannot surface it on
      // the wire, because there is no wire field to surface.
      expect(onTheWire['ledgerId'], 'l-1');
      expect(onTheWire.containsKey('receipt'), isFalse);
      expect(onTheWire.containsKey('status'), isFalse);
      expect(onTheWire.containsKey('totalXp'), isFalse);
    });

    test('the server-returned verified flag is preserved on merge', () {
      final entry = _entry(ledgerId: 'r-1', sourceEventId: 'e-1');

      final result = policy.merge(
        local: const <RewardLedgerEntry>[],
        remote: SyncLedgerEnvelope(
          receipts: <SyncReceipt>[
            SyncReceipt(entry: entry, status: LedgerEntrySyncStatus.verified),
          ],
        ),
      );

      expect(result.verifiedLedgerIds, <String>['r-1']);
    });
  });

  group('A5 — account-disabled → zero network requests', () {
    test('the policy refuses to run when accountEnabled is false', () {
      var calls = 0;
      final transport = _CountingTransport(() => calls++);

      expect(policy.shouldRun(accountEnabled: false), isFalse);

      // The contract: caller MUST short-circuit before reaching for the
      // transport. Simulate that here and prove the probe stays at zero.
      if (policy.shouldRun(accountEnabled: false)) {
        unawaited(
          transport.uploadAndPull(SyncLedgerEnvelope(receipts: const [])),
        );
      }
      expect(transport.requestCount, 0);
    });

    test('NullLedgerSyncTransport throws if invoked while sync is off', () {
      const transport = NullLedgerSyncTransport();
      expect(
        () => transport.uploadAndPull(SyncLedgerEnvelope(receipts: const [])),
        throwsStateError,
      );
    });

    test('the policy runs when accountEnabled is true', () {
      expect(policy.shouldRun(accountEnabled: true), isTrue);
    });
  });

  group('A6 — policy-version handling', () {
    test(
      'a receipt with a different policyVersion is preserved (not dropped)',
      () {
        final newer = _entry(
          ledgerId: 'l-1',
          sourceEventId: 'e-1',
          policyVersion: 2,
          baseXp: 10,
        );
        final result = policy.merge(
          local: <RewardLedgerEntry>[newer],
          remote: SyncLedgerEnvelope(receipts: <SyncReceipt>[]),
        );
        expect(result.entries.single.policyVersion, 2);
      },
    );

    test(
      'a superseding receipt replaces the older one by ledgerId reference',
      () {
        final oldEntry = _entry(
          ledgerId: 'ledger-old',
          sourceEventId: 'e-1',
          baseXp: 10,
          bonusXp: 0,
        );
        final newEntry = _entry(
          ledgerId: 'ledger-new',
          sourceEventId: 'e-1',
          policyVersion: 2,
          baseXp: 12,
          bonusXp: 0,
        );

        final result = policy.merge(
          local: const <RewardLedgerEntry>[],
          remote: SyncLedgerEnvelope(
            receipts: <SyncReceipt>[
              SyncReceipt(
                entry: oldEntry,
                status: LedgerEntrySyncStatus.verified,
              ),
              SyncReceipt(
                entry: newEntry,
                status: LedgerEntrySyncStatus.verified,
                supersedesLedgerId: 'ledger-old',
              ),
            ],
          ),
        );

        final ledgerIds = result.entries.map((e) => e.ledgerId).toList();
        expect(ledgerIds, <String>['ledger-new']);
        // Same source-event across both sides → still collapsed (single
        // surviving receipt for that sourceEventId).
        expect(result.entries, hasLength(1));
      },
    );
  });

  group('A7 — versioned contract', () {
    test('an unknown contract version on the wire is rejected', () {
      expect(
        () => GamificationSyncContract.decodeDownload(<String, Object?>{
          'schemaVersion': 999,
          'receipts': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('a well-formed receipt is accepted as unverified', () {
      final receipt = SyncReceipt(
        entry: _entry(ledgerId: 'l-1', sourceEventId: 'e-1'),
        status: LedgerEntrySyncStatus.unverified,
      );
      final decision = SyncReceiptValidation.validate(receipt);
      expect(decision, isA<SyncUploadAccepted>());
      final accepted = decision as SyncUploadAccepted;
      expect(accepted.verified, isTrue);
    });

    test('a receipt attempting to upload with verified status is rejected', () {
      final receipt = SyncReceipt(
        entry: _entry(ledgerId: 'l-1', sourceEventId: 'e-1'),
        status: LedgerEntrySyncStatus.verified,
      );
      final decision = SyncReceiptValidation.validate(receipt);
      expect(decision, isA<SyncUploadRejected>());
      final rejection = decision as SyncUploadRejected;
      expect(
        rejection.reason,
        SyncContractRejectionReason.receiptSchemaMismatch,
      );
    });
  });

  group('A8 — offline works without sync', () {
    test('local-only flow is unaffected by the merge policy', () {
      final entries = <RewardLedgerEntry>[
        _entry(ledgerId: 'l-1', sourceEventId: 'e-1', baseXp: 10),
        _entry(ledgerId: 'l-2', sourceEventId: 'e-2', baseXp: 20),
      ];
      final result = policy.merge(
        local: entries,
        remote: SyncLedgerEnvelope(receipts: <SyncReceipt>[]),
      );
      expect(result.entries, hasLength(2));
      expect(result.totalXp, 30);
    });
  });

  group(
    'F1 — wire-shape compatibility (Dart encoder matches backend schema)',
    () {
      test(
        'encodeUpload produces a flat wire shape — no nested `receipt` key',
        () {
          final receipt = SyncReceipt(
            entry: _entry(
              ledgerId: 'ledger-1',
              sourceEventId: 'event-1',
              baseXp: 10,
              bonusXp: 0,
            ),
            status: LedgerEntrySyncStatus.unverified,
          );
          final envelope = SyncLedgerEnvelope(receipts: <SyncReceipt>[receipt]);

          final json = GamificationSyncContract.encodeUpload(envelope);

          // Envelope-level: schemaVersion carries the contract version, not
          // per-receipt.
          expect(json['schemaVersion'], gamificationSyncContractVersion);
          expect(json['receipts'], hasLength(1));

          final rawReceipts = json['receipts']! as List<Object?>;
          final onTheWire = rawReceipts.first! as Map<String, Object?>;

          // Flat: the receipt fields sit at the element root, so the
          // backend `ReceiptUpload` (which reads each field at root) accepts
          // it. Mirrors the backend acceptance test in
          // `backend/tests/test_gamification_ledger.py`.
          expect(onTheWire['ledgerId'], 'ledger-1');
          expect(onTheWire['sourceEventId'], 'event-1');
          expect(onTheWire['schemaVersion'], rewardLedgerEntrySchemaVersion);
          expect(onTheWire['policyVersion'], 1);
          expect(onTheWire['baseXp'], 10);
          expect(onTheWire['bonusXp'], 0);

          // Forbidden on the wire (these would make the backend 422):
          // - nested `receipt` wrapper — backend would say "Extra inputs are
          //   not permitted";
          // - `status` — server treats every upload as `unverified` so the
          //   field is redundant (ADR 0394 §5.3);
          // - `totalXp` — server-computed aggregate (ADR 0394 §5.1).
          expect(
            onTheWire.containsKey('receipt'),
            isFalse,
            reason: 'Receipt must not be wrapped in a nested `receipt` object',
          );
          expect(
            onTheWire.containsKey('status'),
            isFalse,
            reason: 'Status is server-side output, not on upload wire',
          );
          expect(
            onTheWire.containsKey('totalXp'),
            isFalse,
            reason: 'totalXp is server-computed; clients must not send it',
          );
        },
      );
    },
  );

  group('§6.1 boundary matrix', () {
    test(
      '"below threshold" — only ledgerId dedups cross-device → DUPLICATE',
      () {
        final localEntry = _entry(
          ledgerId: 'ledger-A',
          sourceEventId: 'shared-event',
          baseXp: 10,
          bonusXp: 0,
        );
        final remoteEntry = _entry(
          ledgerId: 'ledger-B',
          sourceEventId: 'shared-event',
          baseXp: 10,
          bonusXp: 0,
        );
        final survivor = _dedupByLedgerIdOnly([localEntry, remoteEntry]);
        expect(survivor, hasLength(2));
      },
    );

    test('"on threshold" — composite key keeps the union idempotent', () {
      final localEntry = _entry(
        ledgerId: 'ledger-A',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final remoteEntry = _entry(
        ledgerId: 'ledger-B',
        sourceEventId: 'shared-event',
        baseXp: 10,
        bonusXp: 0,
      );
      final result = policy.merge(
        local: <RewardLedgerEntry>[localEntry],
        remote: SyncLedgerEnvelope(
          receipts: <SyncReceipt>[
            SyncReceipt(
              entry: remoteEntry,
              status: LedgerEntrySyncStatus.verified,
            ),
          ],
        ),
      );
      expect(result.entries, hasLength(1));
      expect(result.totalXp, 10);
    });

    test(
      '"above threshold" — only sourceEventId dedups a collision → DATA LOSS',
      () {
        final a = _entry(
          ledgerId: 'l-1',
          sourceEventId: 'collision',
          baseXp: 10,
          bonusXp: 0,
        );
        final b = _entry(
          ledgerId: 'l-2',
          sourceEventId: 'collision',
          baseXp: 25,
          bonusXp: 5,
        );
        final survivor = _dedupBySourceEventIdOnly([a, b]);
        expect(survivor, hasLength(1));
      },
    );
  });
}

// ---- helpers --------------------------------------------------------------

RewardLedgerEntry _entry({
  String ledgerId = 'ledger-1',
  String sourceEventId = 'event-1',
  int policyVersion = 1,
  int? schemaVersion,
  int baseXp = 10,
  int bonusXp = 0,
  List<RewardReason> reasonCodes = const <RewardReason>[
    RewardReason.baseExperience,
  ],
}) {
  final totalXp = baseXp + bonusXp;
  return RewardLedgerEntry(
    ledgerId: ledgerId,
    sourceEventId: sourceEventId,
    createdAt: DateTime.utc(2026, 8, 22, 12),
    schemaVersion: schemaVersion ?? rewardLedgerEntrySchemaVersion,
    policyVersion: policyVersion,
    baseXp: baseXp,
    bonusXp: bonusXp,
    totalXp: totalXp,
    reasonCodes: reasonCodes,
  );
}

/// Bad implementation: dedup purely on ledgerId — equivalent to "below the
/// threshold" in §6.1. Cross-device cases (different ledgerIds, same
/// sourceEventId) survive as duplicates.
List<RewardLedgerEntry> _dedupByLedgerIdOnly(List<RewardLedgerEntry> entries) {
  final byLedgerId = <String, RewardLedgerEntry>{};
  for (final entry in entries) {
    byLedgerId.putIfAbsent(entry.ledgerId, () => entry);
  }
  return byLedgerId.values.toList();
}

/// Bad implementation: dedup purely on sourceEventId — equivalent to "above
/// the threshold" in §6.1. Collisions (different ledgerIds, same
/// sourceEventId) collapse into one.
List<RewardLedgerEntry> _dedupBySourceEventIdOnly(
  List<RewardLedgerEntry> entries,
) {
  final bySource = <String, RewardLedgerEntry>{};
  for (final entry in entries) {
    bySource.putIfAbsent(entry.sourceEventId, () => entry);
  }
  return bySource.values.toList();
}

/// Transport probe: counts every `uploadAndPull` invocation. Used by the A5
/// test to prove §5.4 — when the policy refuses to run, this counter stays
/// at zero.
class _CountingTransport implements LedgerSyncTransport {
  _CountingTransport(this._onCall);

  final void Function() _onCall;
  int requestCount = 0;

  @override
  Future<SyncLedgerEnvelope> uploadAndPull(SyncLedgerEnvelope outbound) {
    requestCount++;
    _onCall();
    return Future<SyncLedgerEnvelope>.value(
      SyncLedgerEnvelope(receipts: <SyncReceipt>[]),
    );
  }
}

void unawaited(Future<Object?> future) {
  // Drop the result on the floor intentionally — A5 tests assert on
  // requestCount before the future resolves.
  future.then<void>((_) {}, onError: (_, _) {});
}
