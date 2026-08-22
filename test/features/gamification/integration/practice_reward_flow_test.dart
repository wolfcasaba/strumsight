// E08-R24 — Practice/Learn → gamification reward flow integration tests.
//
// Covers brief §6 acceptance cells A1, A3, A5, A6, A7 (plus the §6.1
// valódi-sértés próba for A7) for BOTH the practice and the lesson adapter.
// The complementary A2/A4/A8 cells live in `test/features/learn/` and
// `test/core/architecture_dependency_test.dart` respectively, per the brief
// §6 evidence column.
//
// The lesson group also carries the F1 regression test (same lessonId, two
// attempts on different days → two distinct eventIds, both ledger entries).

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/learn/application/gamification_lesson_adapter.dart'
    as lesson_adapter;
import 'package:strumsight/features/practice/application/gamification_practice_adapter.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _defaultSessionId = 'session-42';
const String _defaultLessonId = 'lesson-blue-bird';
const int _defaultEpochDay = 20400;
final DateTime _defaultOccurredAt = DateTime.utc(2026, 8, 22, 12, 30);

const String _defaultAttemptId = 'attempt-42';

void main() {
  group('Practice → gamification reward flow (E08-R24)', () {
    test('A1: a completed practice session runs through event → outbox → '
        'eligibility → XP → ledger', () async {
      final fixture = _Fixture.build();
      final signal = _completedSignal();

      final outcome = await fixture.adapter.recordSession(signal);

      expect(outcome.accepted, isTrue);
      expect(
        outcome.eventId,
        GamificationPracticeAdapter.stableEventId(signal.sessionId),
      );
      // Before drain: outbox holds the record, ledger is empty.
      expect(fixture.outbox.pendingRecords(), hasLength(1));
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);

      // Drain: the entry lands in the ledger exactly once.
      final report = await fixture.ingestor.drain();
      expect(report.acknowledged, <String>[outcome.eventId!]);
      final entries = fixture.ledger.readPage(limit: 10).entries;
      expect(entries, hasLength(1));
      expect(entries.single.sourceEventId, outcome.eventId);
      expect(entries.single.totalXp, greaterThan(0));
      expect(fixture.outbox.pendingRecords(), isEmpty);
    });

    test(
      'A1: the outbox enqueue carries the same eventId the ledger receives',
      () async {
        final fixture = _Fixture.build();
        final signal = _completedSignal();

        await fixture.adapter.recordSession(signal);

        final pending = fixture.outbox.pendingRecords();
        expect(pending, hasLength(1));
        expect(
          pending.single.event.eventId,
          GamificationPracticeAdapter.stableEventId(signal.sessionId),
        );
        expect(pending.single.event.source, ActivitySource.practice);
        expect(
          pending.single.entry.sourceEventId,
          pending.single.event.eventId,
        );
      },
    );

    test('A3: result-screen reopen produces the same eventId and the ledger '
        'stays at one entry', () async {
      final fixture = _Fixture.build();
      final signal = _completedSignal();

      final first = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));

      // Simulate the result-screen handler invoking the adapter a second
      // time with the SAME sessionId.
      final reopened = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();

      expect(reopened.eventId, first.eventId);
      expect(reopened.accepted, isTrue);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A5: a cancelled session is denied by the R05 gate — no event, no '
        'ledger entry', () async {
      final fixture = _Fixture.build();
      final outcome = await fixture.adapter.recordSession(
        _completedSignal(outcome: ActivityOutcome.cancelled),
      );
      await fixture.ingestor.drain();

      expect(outcome, equals(const PracticeGamificationOutcome.noOp()));
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
    });

    test('A5: a failed session is denied by the R05 gate — no event, no '
        'ledger entry', () async {
      final fixture = _Fixture.build();
      final outcome = await fixture.adapter.recordSession(
        _completedSignal(outcome: ActivityOutcome.failed),
      );
      await fixture.ingestor.drain();

      expect(outcome, equals(const PracticeGamificationOutcome.noOp()));
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
    });

    test(
      'A5: a session shorter than the per-source minimum is denied',
      () async {
        final fixture = _Fixture.build();
        final outcome = await fixture.adapter.recordSession(
          _completedSignal(validDuration: const Duration(seconds: 5)),
        );
        await fixture.ingestor.drain();

        expect(outcome, equals(const PracticeGamificationOutcome.noOp()));
        expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
      },
    );

    test('A5: a partial session below the minimum yields no XP; above it, '
        'it pays the same XP shape as a completed one', () async {
      final tooShort = _Fixture.build();
      final tooShortOutcome = await tooShort.adapter.recordSession(
        _completedSignal(
          validDuration: const Duration(seconds: 59),
          outcome: ActivityOutcome.completed,
        ),
      );
      await tooShort.ingestor.drain();
      expect(tooShortOutcome, equals(const PracticeGamificationOutcome.noOp()));
      expect(tooShort.ledger.readPage(limit: 10).entries, isEmpty);

      final valid = _Fixture.build();
      final validOutcome = await valid.adapter.recordSession(
        _completedSignal(
          validDuration: const Duration(minutes: 2, seconds: 30),
          outcome: ActivityOutcome.completed,
        ),
      );
      await valid.ingestor.drain();
      expect(validOutcome.accepted, isTrue);
      expect(
        valid.ledger.readPage(limit: 10).entries.single.totalXp,
        greaterThan(0),
      );
    });

    test('A6: switch in OFF mode is a no-op — no event, no ledger entry, '
        'no legacy sink call', () async {
      var legacyCalls = 0;
      final fixture = _Fixture.build(
        dualWriteMode: GamificationDualWriteMode.off,
        legacySink: (signal) =>
            _countingLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordSession(_completedSignal());
      await fixture.ingestor.drain();

      expect(outcome, equals(const PracticeGamificationOutcome.noOp()));
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
      expect(legacyCalls, 0);
    });

    test('A6: switch in DUAL mode enqueues the event AND calls the legacy '
        'sink exactly once', () async {
      var legacyCalls = 0;
      final fixture = _Fixture.build(
        dualWriteMode: GamificationDualWriteMode.dual,
        legacySink: (signal) =>
            _countingLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordSession(_completedSignal());
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.dualWriteInvoked, isTrue);
      expect(legacyCalls, 1);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A6: switch in NEW-ONLY mode enqueues the event but does NOT call '
        'the legacy sink', () async {
      var legacyCalls = 0;
      final fixture = _Fixture.build(
        dualWriteMode: GamificationDualWriteMode.newOnly,
        legacySink: (signal) =>
            _countingLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordSession(_completedSignal());
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.dualWriteInvoked, isFalse);
      expect(legacyCalls, 0);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A7: dual-write with a non-XP legacy sink keeps XP duplication-free '
        '(the documented happy path)', () async {
      var legacyCalls = 0;
      final fixture = _Fixture.build(
        dualWriteMode: GamificationDualWriteMode.dual,
        legacySink: (signal) =>
            _countingLegacySink(signal, () => legacyCalls++),
      );

      await fixture.adapter.recordSession(_completedSignal());
      await fixture.ingestor.drain();

      expect(legacyCalls, 1);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test(
      'A7: even when the legacy sink writes XP to the same ledger, the '
      'adapter itself never duplicates XP (valódi-sértés próba, §6.1)',
      () async {
        // The "buggy" legacy sink that the §6.1 valódi-sértés próba
        // describes: it directly calls the ledger with a fresh
        // RewardLedgerEntry for the same eventId. The adapter must NOT also
        // write XP through its own enqueue path, so the final ledger count
        // stays exactly one. The buggy legacy sink does try to write — but
        // the ledger's append-if-absent absorbs the second attempt because
        // it uses the SAME sourceEventId the adapter already wrote.
        final fixture = _Fixture.build(
          dualWriteMode: GamificationDualWriteMode.dual,
        );
        fixture.legacySink = (signal) async {
          await fixture.ledger.appendIfAbsent(
            _syntheticLedgerEntry(signal: signal),
          );
        };

        await fixture.adapter.recordSession(_completedSignal());
        await fixture.ingestor.drain();

        final entries = fixture.ledger.readPage(limit: 10).entries;
        expect(entries, hasLength(1));
        expect(
          entries.single.sourceEventId,
          GamificationPracticeAdapter.stableEventId(_defaultSessionId),
        );
      },
    );
  });

  group('Lesson → gamification reward flow (E08-R24)', () {
    test('A1: a completed lesson runs through event → outbox → '
        'eligibility → XP → ledger', () async {
      final fixture = _LessonFixture.build();
      final signal = _completedLessonSignal();

      final outcome = await fixture.adapter.recordLesson(signal);

      expect(outcome.accepted, isTrue);
      expect(
        outcome.eventId,
        lesson_adapter.GamificationLessonAdapter.stableEventId(
          signal.attemptId,
        ),
      );
      // Before drain: outbox holds the record, ledger is empty.
      expect(fixture.outbox.pendingRecords(), hasLength(1));
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);

      // Drain: the entry lands in the ledger exactly once.
      final report = await fixture.ingestor.drain();
      expect(report.acknowledged, <String>[outcome.eventId!]);
      final entries = fixture.ledger.readPage(limit: 10).entries;
      expect(entries, hasLength(1));
      expect(entries.single.sourceEventId, outcome.eventId);
      expect(entries.single.totalXp, greaterThan(0));
      expect(fixture.outbox.pendingRecords(), isEmpty);
    });

    test('A1: the outbox enqueue carries the same eventId the ledger receives '
        'and pins the source to learn', () async {
      final fixture = _LessonFixture.build();
      final signal = _completedLessonSignal();

      await fixture.adapter.recordLesson(signal);

      final pending = fixture.outbox.pendingRecords();
      expect(pending, hasLength(1));
      expect(
        pending.single.event.eventId,
        lesson_adapter.GamificationLessonAdapter.stableEventId(
          signal.attemptId,
        ),
      );
      expect(pending.single.event.source, ActivitySource.learn);
      expect(pending.single.entry.sourceEventId, pending.single.event.eventId);
    });

    test('A3: result-screen reopen produces the same eventId and the ledger '
        'stays at one entry', () async {
      final fixture = _LessonFixture.build();
      final signal = _completedLessonSignal();

      final first = await fixture.adapter.recordLesson(signal);
      await fixture.ingestor.drain();
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));

      // Simulate the result-screen handler invoking the adapter a second
      // time with the SAME attemptId.
      final reopened = await fixture.adapter.recordLesson(signal);
      await fixture.ingestor.drain();

      expect(reopened.eventId, first.eventId);
      expect(reopened.accepted, isTrue);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A5: a cancelled lesson produces no event, no ledger entry '
        '(lesson-side outcome branch denies before eligibility)', () async {
      final fixture = _LessonFixture.build();
      final outcome = await fixture.adapter.recordLesson(
        _completedLessonSignal(outcome: ActivityOutcome.cancelled),
      );
      await fixture.ingestor.drain();

      expect(
        outcome,
        equals(const lesson_adapter.LessonGamificationOutcome.noOp()),
      );
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
    });

    test('A5: a failed lesson produces no event, no ledger entry', () async {
      final fixture = _LessonFixture.build();
      final outcome = await fixture.adapter.recordLesson(
        _completedLessonSignal(outcome: ActivityOutcome.failed),
      );
      await fixture.ingestor.drain();

      expect(
        outcome,
        equals(const lesson_adapter.LessonGamificationOutcome.noOp()),
      );
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
    });

    test(
      'A5: a lesson shorter than the per-source minimum is denied',
      () async {
        final fixture = _LessonFixture.build();
        final outcome = await fixture.adapter.recordLesson(
          _completedLessonSignal(validDuration: const Duration(seconds: 5)),
        );
        await fixture.ingestor.drain();

        expect(
          outcome,
          equals(const lesson_adapter.LessonGamificationOutcome.noOp()),
        );
        expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
      },
    );

    test('A5: a partial lesson below the minimum yields no XP; above it, '
        'it pays the same XP shape as a completed one', () async {
      final tooShort = _LessonFixture.build();
      final tooShortOutcome = await tooShort.adapter.recordLesson(
        _completedLessonSignal(
          validDuration: const Duration(seconds: 59),
          outcome: ActivityOutcome.completed,
        ),
      );
      await tooShort.ingestor.drain();
      expect(
        tooShortOutcome,
        equals(const lesson_adapter.LessonGamificationOutcome.noOp()),
      );
      expect(tooShort.ledger.readPage(limit: 10).entries, isEmpty);

      final valid = _LessonFixture.build();
      final validOutcome = await valid.adapter.recordLesson(
        _completedLessonSignal(
          validDuration: const Duration(minutes: 2, seconds: 30),
          outcome: ActivityOutcome.completed,
        ),
      );
      await valid.ingestor.drain();
      expect(validOutcome.accepted, isTrue);
      expect(
        valid.ledger.readPage(limit: 10).entries.single.totalXp,
        greaterThan(0),
      );
    });

    test('A6: switch in OFF mode is a no-op — no event, no ledger entry, '
        'no legacy sink call', () async {
      var legacyCalls = 0;
      final fixture = _LessonFixture.build(
        dualWriteMode: lesson_adapter.GamificationDualWriteMode.off,
        legacySink: (signal) =>
            _countingLessonLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordLesson(
        _completedLessonSignal(),
      );
      await fixture.ingestor.drain();

      expect(
        outcome,
        equals(const lesson_adapter.LessonGamificationOutcome.noOp()),
      );
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 10).entries, isEmpty);
      expect(legacyCalls, 0);
    });

    test('A6: switch in DUAL mode enqueues the event AND calls the legacy '
        'sink exactly once', () async {
      var legacyCalls = 0;
      final fixture = _LessonFixture.build(
        dualWriteMode: lesson_adapter.GamificationDualWriteMode.dual,
        legacySink: (signal) =>
            _countingLessonLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordLesson(
        _completedLessonSignal(),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.dualWriteInvoked, isTrue);
      expect(legacyCalls, 1);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A6: switch in NEW-ONLY mode enqueues the event but does NOT call '
        'the legacy sink', () async {
      var legacyCalls = 0;
      final fixture = _LessonFixture.build(
        dualWriteMode: lesson_adapter.GamificationDualWriteMode.newOnly,
        legacySink: (signal) =>
            _countingLessonLegacySink(signal, () => legacyCalls++),
      );

      final outcome = await fixture.adapter.recordLesson(
        _completedLessonSignal(),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.dualWriteInvoked, isFalse);
      expect(legacyCalls, 0);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('A7: dual-write with a non-XP legacy sink keeps XP duplication-free '
        '(the documented happy path)', () async {
      var legacyCalls = 0;
      final fixture = _LessonFixture.build(
        dualWriteMode: lesson_adapter.GamificationDualWriteMode.dual,
        legacySink: (signal) =>
            _countingLessonLegacySink(signal, () => legacyCalls++),
      );

      await fixture.adapter.recordLesson(_completedLessonSignal());
      await fixture.ingestor.drain();

      expect(legacyCalls, 1);
      expect(fixture.ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test(
      'A7: even when the legacy sink writes XP to the same ledger, the '
      'adapter itself never duplicates XP (valódi-sértés próba, §6.1)',
      () async {
        // The "buggy" lesson-side legacy sink: it directly writes to the
        // ledger with the SAME sourceEventId the adapter uses. The
        // append-if-absent absorbs the second write, so the final ledger
        // count stays at one — proving the adapter does not duplicate XP.
        final fixture = _LessonFixture.build(
          dualWriteMode: lesson_adapter.GamificationDualWriteMode.dual,
        );
        fixture.legacySink = (signal) async {
          await fixture.ledger.appendIfAbsent(
            _syntheticLessonLedgerEntry(signal: signal),
          );
        };

        await fixture.adapter.recordLesson(_completedLessonSignal());
        await fixture.ingestor.drain();

        final entries = fixture.ledger.readPage(limit: 10).entries;
        expect(entries, hasLength(1));
        expect(
          entries.single.sourceEventId,
          lesson_adapter.GamificationLessonAdapter.stableEventId(
            _defaultAttemptId,
          ),
        );
      },
    );

    test(
      'F1 regression: same lessonId, two different attempts on '
      'different days produce TWO distinct eventIds and TWO ledger entries',
      () async {
        // Regression for the F1 BLOCKER: the eventId MUST come from the
        // per-attempt id, not from the lesson id. With the old
        // `stableEventId(lessonId)` implementation, both attempts would
        // collapse to one ledger entry because the ledger's append-if-absent
        // absorbs the second write. With the fix, each attempt carries its
        // own attemptId (caller-fed) and produces a distinct eventId.
        final fixture = _LessonFixture.build();
        const day1 = _defaultEpochDay; // 20400
        const day5 = _defaultEpochDay + 4; // 20404
        final signal1 = _completedLessonSignal(
          attemptId: 'attempt-day1',
          lessonId: _defaultLessonId,
          epochDay: day1,
        );
        final signal5 = _completedLessonSignal(
          attemptId: 'attempt-day5',
          lessonId: _defaultLessonId,
          epochDay: day5,
        );

        final first = await fixture.adapter.recordLesson(signal1);
        final second = await fixture.adapter.recordLesson(signal5);
        await fixture.ingestor.drain();

        // Distinct eventIds, both accepted.
        expect(first.accepted, isTrue);
        expect(second.accepted, isTrue);
        expect(
          first.eventId,
          isNot(equals(second.eventId)),
          reason:
              'two distinct attempt ids must produce two distinct event ids',
        );
        expect(
          first.eventId,
          lesson_adapter.GamificationLessonAdapter.stableEventId(
            'attempt-day1',
          ),
        );
        expect(
          second.eventId,
          lesson_adapter.GamificationLessonAdapter.stableEventId(
            'attempt-day5',
          ),
        );

        // Both ledger entries landed (the second may have a reduced XP via the
        // diminishing-returns curve, but it must NOT be zero nor absorbed by
        // the identifier-level dedup).
        final entries = fixture.ledger.readPage(limit: 10).entries;
        expect(entries, hasLength(2));
        final sourceIds = entries.map((e) => e.sourceEventId).toSet();
        expect(sourceIds, <String>{
          lesson_adapter.GamificationLessonAdapter.stableEventId(
            'attempt-day1',
          ),
          lesson_adapter.GamificationLessonAdapter.stableEventId(
            'attempt-day5',
          ),
        });
        // Diminishing returns: the second occurrence's XP can be lower than
        // the first, but neither is zero (R05/R06 allows reduced, not zero).
        expect(entries.every((e) => e.totalXp > 0), isTrue);
      },
    );
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

PracticeGamificationSignal _completedSignal({
  String sessionId = _defaultSessionId,
  String lessonId = _defaultLessonId,
  ActivityOutcome outcome = ActivityOutcome.completed,
  Duration validDuration = const Duration(minutes: 3),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) => PracticeGamificationSignal(
  sessionId: sessionId,
  lessonId: lessonId,
  outcome: outcome,
  validDuration: validDuration,
  quality: quality,
  evidenceTrust: trust,
  score: score,
  epochDay: epochDay,
  occurredAt: occurredAt ?? _defaultOccurredAt,
);

RewardLedgerEntry _syntheticLedgerEntry({
  required PracticeGamificationSignal signal,
}) => RewardLedgerEntry(
  ledgerId: 'legacy-${signal.sessionId}',
  sourceEventId: GamificationPracticeAdapter.stableEventId(signal.sessionId),
  createdAt: signal.occurredAt,
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: 1,
  baseXp: 99,
  bonusXp: 0,
  totalXp: 99,
  reasonCodes: const <RewardReason>[RewardReason.baseExperience],
);

Future<void> _countingLegacySink(
  PracticeGamificationSignal _,
  void Function() onCall,
) async {
  onCall();
}

class _Fixture {
  _Fixture._({
    required this.dualWriteMode,
    required PracticeLegacySink legacySink,
  }) : _legacySinkImpl = legacySink;

  factory _Fixture.build({
    GamificationDualWriteMode dualWriteMode = GamificationDualWriteMode.dual,
    PracticeLegacySink? legacySink,
  }) {
    final store = InMemoryKeyValueStore(<String, Object>{});
    const logger = NoopAppLogger();
    final ledger = LocalRewardLedgerRepository(store: store, logger: logger);
    final outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: logger,
      capacity: 16,
      maxAttempts: 3,
    );
    final ingestor = ActivityEventIngestor(outbox: outbox, logger: logger);
    final eligibility = DefaultRewardEligibilityPolicy(
      config: RewardEligibilityPolicyConfig.standard(),
    );
    final rewardPolicy = DefaultRewardPolicy(
      config: RewardPolicyConfig.standard(),
    );
    final historyBuilder = _emptyHistory;
    final fixture =
        _Fixture._(
            dualWriteMode: dualWriteMode,
            legacySink: legacySink ?? _noLegacy,
          )
          ..store = store
          ..logger = logger
          ..ledger = ledger
          ..outbox = outbox
          ..ingestor = ingestor
          ..eligibility = eligibility
          ..rewardPolicy = rewardPolicy
          ..historyBuilder = historyBuilder
          ..adapter = _buildAdapter(
            ingestor: ingestor,
            eligibility: eligibility,
            rewardPolicy: rewardPolicy,
            historyBuilder: historyBuilder,
            dualWriteMode: dualWriteMode,
            legacySink: legacySink ?? _noLegacy,
          );
    return fixture;
  }

  final GamificationDualWriteMode dualWriteMode;
  late PracticeLegacySink _legacySinkImpl;
  late InMemoryKeyValueStore store;
  late AppLogger logger;
  late LocalRewardLedgerRepository ledger;
  late LocalActivityOutboxRepository outbox;
  late ActivityEventIngestor ingestor;
  late RewardEligibilityPolicy eligibility;
  late RewardPolicy rewardPolicy;
  late PracticeHistoryBuilder historyBuilder;
  late GamificationPracticeAdapter adapter;

  /// Override the legacy sink AFTER construction. Used by the §6.1
  /// valódi-sértés próba, which needs a closure that captures the fixture
  /// after it has been built.
  set legacySink(PracticeLegacySink sink) {
    _legacySinkImpl = sink;
    adapter = _buildAdapter(
      ingestor: ingestor,
      eligibility: eligibility,
      rewardPolicy: rewardPolicy,
      historyBuilder: historyBuilder,
      dualWriteMode: dualWriteMode,
      legacySink: _legacySinkImpl,
    );
  }

  static GamificationPracticeAdapter _buildAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required PracticeHistoryBuilder historyBuilder,
    required GamificationDualWriteMode dualWriteMode,
    required PracticeLegacySink legacySink,
  }) => GamificationPracticeAdapter(
    ingestor: ingestor,
    eligibility: eligibility,
    rewardPolicy: rewardPolicy,
    historyBuilder: historyBuilder,
    dualWriteMode: dualWriteMode,
    legacySink: legacySink,
  );

  static Future<void> _noLegacy(PracticeGamificationSignal _) async {}

  static PracticeRewardHistorySnapshot _emptyHistory(int epochDay, String _) =>
      const PracticeRewardHistorySnapshot(
        earnedTodayXp: 0,
        practiceOccurrenceCount: 0,
        uniqueSourcesToday: 1,
        rewardedEventIds: <String>{},
        rewardedParentIds: <String>{},
        rewardedChildParentIds: <String>{},
      );
}

// ── lesson helpers (E08-R24 lesson-side mirror) ────────────────────────────

lesson_adapter.LessonGamificationSignal _completedLessonSignal({
  String attemptId = _defaultAttemptId,
  String lessonId = _defaultLessonId,
  ActivityOutcome outcome = ActivityOutcome.completed,
  Duration validDuration = const Duration(minutes: 3),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) => lesson_adapter.LessonGamificationSignal(
  attemptId: attemptId,
  lessonId: lessonId,
  outcome: outcome,
  validDuration: validDuration,
  quality: quality,
  evidenceTrust: trust,
  score: score,
  epochDay: epochDay,
  occurredAt: occurredAt ?? _defaultOccurredAt,
);

RewardLedgerEntry _syntheticLessonLedgerEntry({
  required lesson_adapter.LessonGamificationSignal signal,
}) => RewardLedgerEntry(
  ledgerId: 'legacy-${signal.attemptId}',
  sourceEventId: lesson_adapter.GamificationLessonAdapter.stableEventId(
    signal.attemptId,
  ),
  createdAt: signal.occurredAt,
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: 1,
  baseXp: 99,
  bonusXp: 0,
  totalXp: 99,
  reasonCodes: const <RewardReason>[RewardReason.baseExperience],
);

Future<void> _countingLessonLegacySink(
  lesson_adapter.LessonGamificationSignal _,
  void Function() onCall,
) async {
  onCall();
}

class _LessonFixture {
  _LessonFixture._({
    required this.dualWriteMode,
    required lesson_adapter.LessonLegacySink legacySink,
  }) : _legacySinkImpl = legacySink;

  factory _LessonFixture.build({
    lesson_adapter.GamificationDualWriteMode dualWriteMode =
        lesson_adapter.GamificationDualWriteMode.dual,
    lesson_adapter.LessonLegacySink? legacySink,
  }) {
    final store = InMemoryKeyValueStore(<String, Object>{});
    const logger = NoopAppLogger();
    final ledger = LocalRewardLedgerRepository(store: store, logger: logger);
    final outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: logger,
      capacity: 16,
      maxAttempts: 3,
    );
    final ingestor = ActivityEventIngestor(outbox: outbox, logger: logger);
    final eligibility = DefaultRewardEligibilityPolicy(
      config: RewardEligibilityPolicyConfig.standard(),
    );
    final rewardPolicy = DefaultRewardPolicy(
      config: RewardPolicyConfig.standard(),
    );
    final historyBuilder = _emptyHistory;
    final fixture =
        _LessonFixture._(
            dualWriteMode: dualWriteMode,
            legacySink: legacySink ?? _noLegacy,
          )
          ..store = store
          ..logger = logger
          ..ledger = ledger
          ..outbox = outbox
          ..ingestor = ingestor
          ..eligibility = eligibility
          ..rewardPolicy = rewardPolicy
          ..historyBuilder = historyBuilder
          ..adapter = _buildAdapter(
            ingestor: ingestor,
            eligibility: eligibility,
            rewardPolicy: rewardPolicy,
            historyBuilder: historyBuilder,
            dualWriteMode: dualWriteMode,
            legacySink: legacySink ?? _noLegacy,
          );
    return fixture;
  }

  final lesson_adapter.GamificationDualWriteMode dualWriteMode;
  late lesson_adapter.LessonLegacySink _legacySinkImpl;
  late InMemoryKeyValueStore store;
  late AppLogger logger;
  late LocalRewardLedgerRepository ledger;
  late LocalActivityOutboxRepository outbox;
  late ActivityEventIngestor ingestor;
  late RewardEligibilityPolicy eligibility;
  late RewardPolicy rewardPolicy;
  late lesson_adapter.LessonHistoryBuilder historyBuilder;
  late lesson_adapter.GamificationLessonAdapter adapter;

  /// Override the legacy sink AFTER construction. Used by the §6.1
  /// valódi-sértés próba, which needs a closure that captures the fixture
  /// after it has been built.
  set legacySink(lesson_adapter.LessonLegacySink sink) {
    _legacySinkImpl = sink;
    adapter = _buildAdapter(
      ingestor: ingestor,
      eligibility: eligibility,
      rewardPolicy: rewardPolicy,
      historyBuilder: historyBuilder,
      dualWriteMode: dualWriteMode,
      legacySink: _legacySinkImpl,
    );
  }

  static lesson_adapter.GamificationLessonAdapter _buildAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required lesson_adapter.LessonHistoryBuilder historyBuilder,
    required lesson_adapter.GamificationDualWriteMode dualWriteMode,
    required lesson_adapter.LessonLegacySink legacySink,
  }) => lesson_adapter.GamificationLessonAdapter(
    ingestor: ingestor,
    eligibility: eligibility,
    rewardPolicy: rewardPolicy,
    historyBuilder: historyBuilder,
    dualWriteMode: dualWriteMode,
    legacySink: legacySink,
  );

  static Future<void> _noLegacy(
    lesson_adapter.LessonGamificationSignal _,
  ) async {}

  static lesson_adapter.LessonRewardHistorySnapshot _emptyHistory(
    int epochDay,
    String _,
  ) => const lesson_adapter.LessonRewardHistorySnapshot(
    earnedTodayXp: 0,
    lessonOccurrenceCount: 0,
    uniqueSourcesToday: 1,
    rewardedEventIds: <String>{},
    rewardedParentIds: <String>{},
    rewardedChildParentIds: <String>{},
  );
}
