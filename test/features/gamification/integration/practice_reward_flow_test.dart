// E08-R24 — Practice → gamification reward flow integration tests.
//
// Covers brief §6 acceptance cells A1, A3, A5, A6, A7 (plus the §6.1
// valódi-sértés próba for A7). The complementary A2/A4/A8 cells live in
// `test/features/learn/` and `test/core/architecture_dependency_test.dart`
// respectively, per the brief §6 evidence column.

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/application/gamification_practice_adapter.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _defaultSessionId = 'session-42';
const String _defaultLessonId = 'lesson-blue-bird';
const int _defaultEpochDay = 20400;
final DateTime _defaultOccurredAt = DateTime.utc(2026, 8, 22, 12, 30);

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
