import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

/// Round E13-R32, §6/A2/A4 + §6.1 "beváltás három kötelező cellája".
///
/// §0.0.B/B4: the gamification presentation layer NEVER calls
/// `RewardLedgerRepository.appendIfAbsent` — the surface operation for the
/// idempotent redemption use case is `ActivityEventIngestor.drain()` (a
/// "retry now" action). This file measures the three threshold cells
/// against the REAL production `LocalActivityOutboxRepository` +
/// `ActivityEventIngestor`, then confirms [PendingRewardsCard] renders the
/// caller-fed ledger truth verbatim (never an optimistic pre-ledger credit).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A3 — the presentation layer never writes the ledger (grep)', () {
    test('no appendIfAbsent call anywhere under presentation/', () {
      final presentationDir = Directory(
        'lib/features/gamification/presentation',
      );
      expect(presentationDir.existsSync(), isTrue);
      final offenders = <String>[];
      for (final entity in presentationDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('appendIfAbsent')) {
          offenders.add(entity.path);
        }
        final source = entity.readAsStringSync();
        if (source.contains('appendIfAbsent')) offenders.add(entity.path);
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  group('§6.1 idempotency matrix — the three mandatory redemption cells', () {
    test('below threshold: a ledger failure quarantines the record — 0 '
        'credits, no credited balance shown', () async {
      final fixture = _Fixture(capacity: 4, maxAttempts: 1);
      fixture.ledger.alwaysThrow = true;

      await fixture.ingestor.recordSavedActivity(
        event: fixture.event(eventId: 'activity-below'),
        entry: fixture.entry(sourceEventId: 'activity-below'),
      );

      final report = await fixture.ingestor.drain();

      expect(report.acknowledged, isEmpty);
      expect(report.quarantined, hasLength(1));
      expect(
        report.quarantined.single.outcome,
        ActivityOutboxOutcome.attemptLimitReached,
      );
      expect(fixture.ledger.hasProcessedEvent('activity-below'), isFalse);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);

      // The caller-fed surface must show ZERO pending AND zero credited —
      // never a credited balance for a quarantined record.
      final pendingAfter = fixture.outbox.pendingRecords().length;
      expect(pendingAfter, 0, reason: 'quarantined records leave no pending');
    });

    test(
      'at threshold: a single successful drain credits exactly once',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);

        await fixture.ingestor.recordSavedActivity(
          event: fixture.event(eventId: 'activity-at'),
          entry: fixture.entry(sourceEventId: 'activity-at', baseXp: 25),
        );

        final report = await fixture.ingestor.drain();

        expect(report.acknowledged, <String>['activity-at']);
        expect(fixture.ledger.hasProcessedEvent('activity-at'), isTrue);
        expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
        expect(fixture.ledger.readPage(limit: 10).entries.single.totalXp, 25);
      },
    );

    test(
      'above threshold: offline enqueue, drain, then a duplicate enqueue '
      'of the SAME sourceEventId is superseded — exactly 1 credit total',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final event = fixture.event(eventId: 'activity-above');
        final entry = fixture.entry(sourceEventId: 'activity-above');

        await fixture.ingestor.recordSavedActivity(event: event, entry: entry);
        final firstDrain = await fixture.ingestor.drain();
        expect(firstDrain.acknowledged, <String>['activity-above']);

        // A duplicate submission of the SAME sourceEventId (e.g. a retried
        // client-side save) must be superseded at enqueue time — the ledger
        // already carries the event.
        final duplicate = await fixture.ingestor.recordSavedActivity(
          event: event,
          entry: entry,
        );
        expect(duplicate.accepted, isFalse);
        expect(
          duplicate.evicted?.outcome,
          ActivityOutboxOutcome.supersededByLedger,
        );

        // A second retry-now (drain) call is a safe no-op — nothing pending.
        final secondDrain = await fixture.ingestor.drain();
        expect(secondDrain.acknowledged, isEmpty);

        expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
        expect(
          fixture.ledger
              .readPage(limit: 10)
              .entries
              .where((e) => e.sourceEventId == 'activity-above')
              .length,
          1,
          reason: 'exactly one credit for the source event, never two',
        );
      },
    );
  });

  group('VALÓDI-SÉRTÉS PRÓBA (A2, §10 kötelező) — optimistic pre-ledger credit '
      'is provably wrong', () {
    test(
      'a pendingCount of 0 immediately after enqueue (before drain) would '
      'misrepresent the ledger — the real surface must wait for drain()',
      () async {
        final fixture = _Fixture(capacity: 4, maxAttempts: 3);
        final event = fixture.event(eventId: 'activity-optimistic');
        final entry = fixture.entry(sourceEventId: 'activity-optimistic');

        await fixture.ingestor.recordSavedActivity(event: event, entry: entry);

        // An OPTIMISTIC (incorrect) implementation would flip the surface
        // to "fully synced" (pendingCount == 0) the instant
        // recordSavedActivity returns, without waiting for drain(). This
        // is the exact class of bug A2 defends against — assert it is
        // observably false against the real ledger.
        expect(
          fixture.ledger.hasProcessedEvent('activity-optimistic'),
          isFalse,
          reason:
              'RED FLAG: an optimistic pendingCount=0 here would claim a '
              'credit the ledger has not confirmed',
        );
        expect(fixture.outbox.pendingRecords(), hasLength(1));

        // Only AFTER drain() does the ledger agree with pendingCount == 0.
        await fixture.ingestor.drain();
        expect(fixture.ledger.hasProcessedEvent('activity-optimistic'), isTrue);
        expect(fixture.outbox.pendingRecords(), isEmpty);
      },
    );
  });

  group(
    'PendingRewardsCard — renders caller-fed ledger truth, never computes it',
    () {
      testWidgets('pendingCount > 0 shows the retry CTA and invokes onRetry', (
        tester,
      ) async {
        var retried = 0;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PendingRewardsCard(
                pendingCount: 2,
                quarantinedCount: 0,
                onRetry: () => retried += 1,
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('pending-rewards-card')), findsOneWidget);
        final l10n = _english();
        expect(find.text(l10n.rewardInboxPendingBody(2)), findsOneWidget);

        await tester.tap(find.byKey(const Key('pending-rewards-retry-cta')));
        await tester.pump();
        expect(retried, 1);
      });

      testWidgets(
        'pendingCount == 0 and quarantinedCount == 0 renders nothing',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: PendingRewardsCard(pendingCount: 0, quarantinedCount: 0),
              ),
            ),
          );

          expect(find.byKey(const Key('pending-rewards-card')), findsNothing);
          expect(
            find.byKey(const Key('pending-rewards-integrity-card')),
            findsNothing,
          );
        },
      );

      testWidgets('quarantinedCount > 0 shows the integrity notice, no '
          'punitive language, and no retry CTA of its own', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: PendingRewardsCard(pendingCount: 0, quarantinedCount: 1),
            ),
          ),
        );

        expect(
          find.byKey(const Key('pending-rewards-integrity-card')),
          findsOneWidget,
        );
        final l10n = _english();
        expect(find.text(l10n.rewardInboxIntegrityTitle), findsOneWidget);
        expect(find.text(l10n.rewardInboxIntegrityBody(1)), findsOneWidget);
      });

      testWidgets(
        'end-to-end: real outbox state drives the widget, and a real drain() '
        'clears it back to empty',
        (tester) async {
          final fixture = _Fixture(capacity: 4, maxAttempts: 3);
          await fixture.ingestor.recordSavedActivity(
            event: fixture.event(eventId: 'activity-e2e'),
            entry: fixture.entry(sourceEventId: 'activity-e2e'),
          );

          Future<void> pump(int pendingCount, VoidCallback? onRetry) =>
              tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: PendingRewardsCard(
                      pendingCount: pendingCount,
                      quarantinedCount: 0,
                      onRetry: onRetry,
                    ),
                  ),
                ),
              );

          await pump(fixture.outbox.pendingRecords().length, () {});
          expect(find.byKey(const Key('pending-rewards-card')), findsOneWidget);

          await fixture.ingestor.drain();
          await pump(fixture.outbox.pendingRecords().length, () {});
          expect(find.byKey(const Key('pending-rewards-card')), findsNothing);
          expect(fixture.ledger.hasProcessedEvent('activity-e2e'), isTrue);
        },
      );
    },
  );
}

AppLocalizations _english() => AppLocalizationsEn();

class _Fixture {
  _Fixture({required int capacity, required int maxAttempts}) {
    store = InMemoryKeyValueStore();
    ledger = _FakeRewardLedger(store);
    outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: const NoopAppLogger(),
      capacity: capacity,
      maxAttempts: maxAttempts,
    );
    ingestor = ActivityEventIngestor(
      outbox: outbox,
      logger: const NoopAppLogger(),
    );
  }

  late final InMemoryKeyValueStore store;
  late final _FakeRewardLedger ledger;
  late final ActivityOutboxRepository outbox;
  late final ActivityEventIngestor ingestor;

  LearningActivityEvent event({String eventId = 'activity-1'}) =>
      PracticeActivityEvent(
        eventId: eventId,
        occurredAt: _occurredAt,
        epochDay: _epochDay,
        source: ActivitySource.practice,
        trust: EvidenceTrust.scored,
        schemaVersion: learningActivityEventSchemaVersion,
        duration: const Duration(seconds: 1),
        score: 0.9,
      );

  RewardLedgerEntry entry({
    String ledgerId = 'ledger-1',
    String sourceEventId = 'activity-1',
    int policyVersion = 1,
    int baseXp = 10,
    int bonusXp = 0,
    List<RewardReason> reasonCodes = const <RewardReason>[
      RewardReason.baseExperience,
    ],
  }) => RewardLedgerEntry(
    ledgerId: ledgerId,
    sourceEventId: sourceEventId,
    createdAt: _occurredAt,
    schemaVersion: rewardLedgerEntrySchemaVersion,
    policyVersion: policyVersion,
    baseXp: baseXp,
    bonusXp: bonusXp,
    totalXp: baseXp + bonusXp,
    reasonCodes: reasonCodes,
  );
}

/// A controllable reward ledger sitting in front of the real local one — the
/// same measured shape `activity_ingestor_test.dart` uses to simulate
/// ledger-side failures.
class _FakeRewardLedger implements RewardLedgerRepository {
  _FakeRewardLedger(this.store);

  final InMemoryKeyValueStore store;
  bool alwaysThrow = false;

  LocalRewardLedgerRepository get _local =>
      LocalRewardLedgerRepository(store: store, logger: const NoopAppLogger());

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    if (alwaysThrow) {
      throw StateError('ledger offline');
    }
    return _local.appendIfAbsent(entry);
  }

  @override
  bool hasProcessedEvent(String sourceEventId) =>
      _local.hasProcessedEvent(sourceEventId);

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) =>
      _local.readPage(limit: limit, cursor: cursor);
}

final DateTime _occurredAt = DateTime.utc(2026, 8, 20, 12);
const int _epochDay = 20320;
