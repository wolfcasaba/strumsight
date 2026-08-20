import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/progress/public.dart';

void main() {
  group('Legacy practice migration', () {
    test(
      'A1: a snapshot has stable event ids and retains exact duplicates',
      () {
        const duplicate = PracticeEntry(
          day: 20400,
          source: PracticeSource.learn,
          seconds: 45,
          strokes: 30,
          chords: 4,
          directionAccuracy: 0.8,
        );
        final entries = <PracticeEntry>[duplicate, duplicate];
        final adapter = LegacyPracticeAdapter();

        final first = adapter.adapt(entries);
        final second = adapter.adapt(entries);

        expect(
          first.map((event) => event.eventId),
          second.map((event) => event.eventId),
        );
        expect(first.map((event) => event.eventId).toSet(), hasLength(2));
      },
    );

    test(
      'A2: a fresh checkpoint cannot duplicate deterministic receipts',
      () async {
        final ledger = _FakeRewardLedgerRepository();
        final entries = _entries();

        await _migrator(ledger: ledger).migrate(entries);
        expect(ledger.entries, hasLength(entries.length));

        final report = await _migrator(ledger: ledger).migrate(entries);
        expect(ledger.entries, hasLength(entries.length));
        expect(report.events, hasLength(entries.length));
      },
    );

    test(
      'A3: backfill reports all baseline totals but grants zero XP',
      () async {
        final ledger = _FakeRewardLedgerRepository();

        final report = await _migrator(ledger: ledger).migrate(_entries());

        expect(report.recordCount, 3);
        expect(report.totalSeconds, 90);
        expect(report.totalStrokes, 60);
        expect(report.totalChords, 7);
        for (final receipt in ledger.entries) {
          expect(receipt.baseXp, 0);
          expect(receipt.bonusXp, 0);
          expect(receipt.totalXp, 0);
          expect(receipt.reasonCodes, isEmpty);
        }
      },
    );

    test('A4: each legacy source maps to the matching activity source', () {
      final events = LegacyPracticeAdapter().adapt(<PracticeEntry>[
        const PracticeEntry(day: 1, source: PracticeSource.live),
        const PracticeEntry(day: 2, source: PracticeSource.analyze),
        const PracticeEntry(day: 3, source: PracticeSource.learn),
      ]);

      expect(events.map((event) => event.source), <ActivitySource>[
        ActivitySource.live,
        ActivitySource.analyze,
        ActivitySource.learn,
      ]);
    });

    test('A5: checkpoint points at the first unprocessed index', () async {
      final ledger = _FakeRewardLedgerRepository()..failOnAttempt = 3;
      final repository = _FakeGamificationRepository();
      final entries = <PracticeEntry>[
        for (var index = 0; index < 4; index++)
          PracticeEntry(day: 20000 + index, source: PracticeSource.live),
      ];
      final migrator = GamificationMigrator(
        gamificationRepository: repository,
        rewardLedgerRepository: ledger,
      );

      await expectLater(migrator.migrate(entries), throwsStateError);
      expect(repository.processedCount, 2);
      final eventIds = LegacyPracticeAdapter()
          .adapt(entries)
          .map((event) => event.eventId)
          .toList();
      expect(ledger.attemptedSourceEventIds, eventIds.take(3));

      ledger.failOnAttempt = null;
      await migrator.migrate(entries);
      expect(repository.processedCount, 4);
      expect(ledger.entries, hasLength(4));
      expect(ledger.attemptedSourceEventIds.skip(3), eventIds.skip(2));
    });

    test('A5: an R08 placeholder state defaults its checkpoint to zero', () {
      final state = GamificationMigrationState.fromJson(<String, dynamic>{
        'schemaVersion': gamificationStorageSchemaVersion,
      });

      expect(state.processedCount, 0);
    });

    test(
      'A6: migration is read-only with respect to caller-supplied history',
      () async {
        final entries = _entries();
        final original = List<PracticeEntry>.of(entries);

        await _migrator().migrate(entries);

        expect(entries, original);
      },
    );

    test('A7: post-migration activity can still receive normal XP', () async {
      final ledger = _FakeRewardLedgerRepository();
      await _migrator(ledger: ledger).migrate(_entries());
      final normal = _receipt(
        ledgerId: 'normal-ledger',
        sourceEventId: 'normal-event',
        totalXp: 12,
      );

      await ledger.appendIfAbsent(normal);

      expect(ledger.entries.last.totalXp, 12);
    });

    test('A8: every valid legacy record becomes one canonical event', () {
      final entries = <PracticeEntry>[
        const PracticeEntry(day: 1, source: PracticeSource.live),
        const PracticeEntry(day: 1, source: PracticeSource.live),
        const PracticeEntry(day: 2, source: PracticeSource.learn),
      ];

      expect(LegacyPracticeAdapter().adapt(entries), hasLength(entries.length));
    });

    test('A9: all 400 newest-last records are retained', () async {
      final entries = <PracticeEntry>[
        for (var index = 0; index < 400; index++)
          PracticeEntry(
            day: 19000 + index,
            source: PracticeSource.values[index % PracticeSource.values.length],
            seconds: index,
          ),
      ];
      final ledger = _FakeRewardLedgerRepository();

      final report = await _migrator(ledger: ledger).migrate(entries);

      expect(report.recordCount, 400);
      expect(report.events, hasLength(400));
      expect(ledger.entries, hasLength(400));
    });

    test(
      'A10: an unknown persisted source degrades to live before migration',
      () {
        final legacy = PracticeEntry.fromJson(<String, dynamic>{
          'day': 20000,
          'src': 'future_source',
          'sec': 5,
        });

        final event = LegacyPracticeAdapter().adapt(<PracticeEntry>[
          legacy,
        ]).single;

        expect(legacy.source, PracticeSource.live);
        expect(event.source, ActivitySource.live);
      },
    );

    test(
      'A11: invalid negative legacy records cannot produce events or receipts',
      () async {
        const invalid = PracticeEntry(
          day: 20000,
          source: PracticeSource.live,
          seconds: -1,
        );
        final ledger = _FakeRewardLedgerRepository();

        expect(
          LegacyPracticeAdapter().adapt(<PracticeEntry>[invalid]),
          isEmpty,
        );
        final report = await _migrator(
          ledger: ledger,
        ).migrate(<PracticeEntry>[invalid]);
        expect(report.events, isEmpty);
        expect(ledger.entries, isEmpty);
        expect(
          () => PracticeEntry.fromJson(<String, dynamic>{
            'day': 20000,
            'src': 'live',
            'sec': -1,
          }),
          throwsA(isA<Object>()),
        );
      },
    );
  });
}

GamificationMigrator _migrator({
  _FakeGamificationRepository? repository,
  _FakeRewardLedgerRepository? ledger,
}) => GamificationMigrator(
  gamificationRepository: repository ?? _FakeGamificationRepository(),
  rewardLedgerRepository: ledger ?? _FakeRewardLedgerRepository(),
);

List<PracticeEntry> _entries() => const <PracticeEntry>[
  PracticeEntry(
    day: 20000,
    source: PracticeSource.live,
    seconds: 30,
    strokes: 20,
    chords: 1,
  ),
  PracticeEntry(
    day: 20001,
    source: PracticeSource.analyze,
    seconds: 20,
    strokes: 15,
    chords: 2,
  ),
  PracticeEntry(
    day: 20002,
    source: PracticeSource.learn,
    seconds: 40,
    strokes: 25,
    chords: 4,
    directionAccuracy: 0.9,
  ),
];

RewardLedgerEntry _receipt({
  required String ledgerId,
  required String sourceEventId,
  required int totalXp,
}) => RewardLedgerEntry(
  ledgerId: ledgerId,
  sourceEventId: sourceEventId,
  createdAt: DateTime.utc(2026, 8, 20),
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: 1,
  baseXp: totalXp,
  bonusXp: 0,
  totalXp: totalXp,
  reasonCodes: totalXp == 0
      ? const <RewardReason>[]
      : const <RewardReason>[RewardReason.baseExperience],
);

final class _FakeRewardLedgerRepository implements RewardLedgerRepository {
  final List<RewardLedgerEntry> entries = <RewardLedgerEntry>[];
  final List<String> attemptedSourceEventIds = <String>[];
  int? failOnAttempt;

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    attemptedSourceEventIds.add(entry.sourceEventId);
    if (failOnAttempt == attemptedSourceEventIds.length) {
      throw StateError('simulated append failure');
    }
    if (hasProcessedEvent(entry.sourceEventId)) return false;
    entries.add(entry);
    return true;
  }

  @override
  bool hasProcessedEvent(String sourceEventId) =>
      entries.any((entry) => entry.sourceEventId == sourceEventId);

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) =>
      RewardLedgerPage(entries: entries.take(limit).toList(), nextCursor: null);
}

final class _FakeGamificationRepository implements GamificationRepository {
  GamificationMigrationState? _migrationState;

  int get processedCount => _migrationState?.processedCount ?? 0;

  @override
  GamificationRead<GamificationMigrationState> readMigrationState() =>
      _migrationState == null
      ? const GamificationRead<GamificationMigrationState>.missing()
      : GamificationRead<GamificationMigrationState>.available(
          _migrationState!,
        );

  @override
  Future<void> replaceMigrationState(GamificationMigrationState state) async {
    _migrationState = state;
  }

  @override
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot() =>
      const GamificationRead<GamificationProfileSnapshot>.missing();

  @override
  Future<void> replaceProfileSnapshot(
    GamificationProfileSnapshot snapshot,
  ) async {}

  @override
  Stream<GamificationRead<GamificationProfileSnapshot>>
  watchProfileSnapshots() =>
      const Stream<GamificationRead<GamificationProfileSnapshot>>.empty();

  @override
  GamificationRead<GamificationCatalogVersion> readCatalogVersion() =>
      const GamificationRead<GamificationCatalogVersion>.missing();

  @override
  Future<void> replaceCatalogVersion(
    GamificationCatalogVersion version,
  ) async {}

  @override
  GamificationRead<List<GamificationInboxItem>> readInbox() =>
      const GamificationRead<List<GamificationInboxItem>>.missing();

  @override
  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> items,
  ) async => const GamificationInboxWriteReport(trimmedCount: 0);

  @override
  Future<void> dispose() async {}
}
