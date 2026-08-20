import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/progress/public.dart';

void main() {
  group('Legacy practice migration', () {
    test('A1: ids are opaque digests and retain stable exact duplicates', () {
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
      final ids = first.map((event) => event.eventId).toList();

      expect(ids, second.map((event) => event.eventId));
      expect(ids.toSet(), hasLength(2));
      for (final id in ids) {
        expect(id, matches(r'^legacy-practice/v1/[0-9a-f]{64}/[0-9]+$'));
        expect(id, isNot(contains('20400:learn:45:30:4:0.8')));
      }
    });

    test(
      'A2: migration keeps the ledger unchanged and has no dependency',
      () async {
        final ledger = _FakeRewardLedgerRepository()
          ..entries.add(
            _receipt(ledgerId: 'existing', sourceEventId: 'existing'),
          );
        final entries = _entries();
        final before = List<RewardLedgerEntry>.of(ledger.entries);

        await _migrator().migrate(entries);
        await _migrator().migrate(entries);

        expect(ledger.entries, before);
        final source = File(
          'lib/features/gamification/data/migration/gamification_migrator.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('RewardLedgerRepository')));
        expect(source, isNot(contains('RewardLedgerEntry')));
        expect(source, isNot(contains('appendIfAbsent')));
      },
    );

    test(
      'A3: backfill reports all baseline totals without XP receipts',
      () async {
        final report = await _migrator().migrate(_entries());

        expect(report.recordCount, 3);
        expect(report.totalSeconds, 90);
        expect(report.totalStrokes, 60);
        expect(report.totalChords, 7);
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

    test(
      'A5: checkpoint resumes at the first unprocessed snapshot index',
      () async {
        final repository = _FakeGamificationRepository(processedCount: 2);
        final entries = <PracticeEntry>[
          for (var index = 0; index < 4; index++)
            PracticeEntry(day: 20000 + index, source: PracticeSource.live),
        ];

        await _migrator(repository: repository).migrate(entries);

        expect(repository.writtenProcessedCounts, <int>[3, 4]);
        expect(repository.processedCount, 4);
      },
    );

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
      await _migrator().migrate(_entries());
      final normal = _receipt(
        ledgerId: 'normal-ledger',
        sourceEventId: 'normal',
      );

      await ledger.appendIfAbsent(normal);

      expect(ledger.entries.single.totalXp, 12);
    });

    test('A8: every valid legacy record becomes one canonical event', () {
      final entries = <PracticeEntry>[
        const PracticeEntry(day: 1, source: PracticeSource.live),
        const PracticeEntry(day: 1, source: PracticeSource.live),
        const PracticeEntry(day: 2, source: PracticeSource.learn),
      ];

      expect(LegacyPracticeAdapter().adapt(entries), hasLength(entries.length));
    });

    test('A9: 400 records are retained and 401 records are rejected', () async {
      final entries = <PracticeEntry>[
        for (var index = 0; index < 400; index++)
          PracticeEntry(
            day: 19000 + index,
            source: PracticeSource.values[index % PracticeSource.values.length],
            seconds: index,
          ),
      ];

      final report = await _migrator().migrate(entries);

      expect(report.recordCount, 400);
      expect(report.events, hasLength(400));
      expect(
        () => LegacyPracticeAdapter().adapt(<PracticeEntry>[
          ...entries,
          entries.first,
        ]),
        throwsArgumentError,
      );
      expect(
        () => _migrator().migrate(<PracticeEntry>[...entries, entries.first]),
        throwsArgumentError,
      );
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
      'A11: invalid days are skipped without losing neighboring valid events',
      () async {
        const valid = PracticeEntry(day: 20000, source: PracticeSource.live);
        const negativeDay = PracticeEntry(day: -1, source: PracticeSource.live);
        final extremeDay = PracticeEntry.fromJson(<String, dynamic>{
          'day': 1 << 40,
          'src': 'learn',
        });
        final entries = <PracticeEntry>[negativeDay, valid, extremeDay];

        expect(() => LegacyPracticeAdapter().adapt(entries), returnsNormally);
        final report = await _migrator().migrate(entries);
        expect(report.events.map((event) => event.epochDay), <int>[valid.day]);
      },
    );

    test('A11: negative numeric fields cannot produce an event', () {
      const invalid = PracticeEntry(
        day: 20000,
        source: PracticeSource.live,
        seconds: -1,
      );

      expect(LegacyPracticeAdapter().adapt(<PracticeEntry>[invalid]), isEmpty);
    });

    test('S4a: an invalid record below the checkpoint still advances the '
        'checkpoint through the original snapshot index space (security '
        'review S4)', () async {
      final repository = _FakeGamificationRepository(processedCount: 2);
      const entries = <PracticeEntry>[
        PracticeEntry(day: 20000, source: PracticeSource.live),
        PracticeEntry(day: -1, source: PracticeSource.live),
        PracticeEntry(day: 20002, source: PracticeSource.live),
        PracticeEntry(day: 20003, source: PracticeSource.live),
      ];

      await _migrator(repository: repository).migrate(entries);

      expect(repository.writtenProcessedCounts, <int>[3, 4]);
      expect(repository.processedCount, entries.length);
    });

    test('S4b: an invalid record exactly at the checkpoint still advances the '
        'checkpoint through the original snapshot index space', () async {
      final repository = _FakeGamificationRepository(processedCount: 2);
      const entries = <PracticeEntry>[
        PracticeEntry(day: 20000, source: PracticeSource.live),
        PracticeEntry(day: 20001, source: PracticeSource.live),
        PracticeEntry(day: -1, source: PracticeSource.live),
        PracticeEntry(day: 20003, source: PracticeSource.live),
      ];

      await _migrator(repository: repository).migrate(entries);

      expect(repository.writtenProcessedCounts, <int>[3, 4]);
      expect(repository.processedCount, entries.length);
    });

    test('S4c: an invalid record above the checkpoint still advances the '
        'checkpoint through the original snapshot index space', () async {
      final repository = _FakeGamificationRepository(processedCount: 2);
      const entries = <PracticeEntry>[
        PracticeEntry(day: 20000, source: PracticeSource.live),
        PracticeEntry(day: 20001, source: PracticeSource.live),
        PracticeEntry(day: 20002, source: PracticeSource.live),
        PracticeEntry(day: -1, source: PracticeSource.live),
      ];

      await _migrator(repository: repository).migrate(entries);

      expect(repository.writtenProcessedCounts, <int>[3, 4]);
      expect(repository.processedCount, entries.length);
    });

    test(
      'S4d: a full run always ends with processedCount == entries.length, '
      'even with multiple invalid records scattered through the snapshot',
      () async {
        final repository = _FakeGamificationRepository();
        const entries = <PracticeEntry>[
          PracticeEntry(day: -1, source: PracticeSource.live),
          PracticeEntry(day: 20001, source: PracticeSource.live),
          PracticeEntry(day: -1, source: PracticeSource.live),
          PracticeEntry(day: 20003, source: PracticeSource.live),
          PracticeEntry(day: 20004, source: PracticeSource.live),
        ];

        await _migrator(repository: repository).migrate(entries);

        expect(repository.writtenProcessedCounts, <int>[1, 2, 3, 4, 5]);
        expect(repository.processedCount, entries.length);
      },
    );
  });
}

GamificationMigrator _migrator({_FakeGamificationRepository? repository}) =>
    GamificationMigrator(
      gamificationRepository: repository ?? _FakeGamificationRepository(),
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
}) => RewardLedgerEntry(
  ledgerId: ledgerId,
  sourceEventId: sourceEventId,
  createdAt: DateTime.utc(2026, 8, 20),
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: 1,
  baseXp: 12,
  bonusXp: 0,
  totalXp: 12,
  reasonCodes: const <RewardReason>[RewardReason.baseExperience],
);

final class _FakeRewardLedgerRepository implements RewardLedgerRepository {
  final List<RewardLedgerEntry> entries = <RewardLedgerEntry>[];

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
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
  _FakeGamificationRepository({int processedCount = 0})
    : _migrationState = processedCount == 0
          ? null
          : GamificationMigrationState(processedCount: processedCount);

  GamificationMigrationState? _migrationState;
  final List<int> writtenProcessedCounts = <int>[];

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
    writtenProcessedCounts.add(state.processedCount);
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
