import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('AchievementEvaluator', () {
    test(
      'A1 and A7: evaluates once and writes a stable zero-XP receipt',
      () async {
        final ledger = _Ledger();
        final evaluator = AchievementEvaluator(
          catalog: _catalog(
            id: 'first_practice',
            objective: CountAchievementObjective(
              eventKind: AchievementEventKind.practice,
              target: 1,
            ),
          ),
          ledger: ledger,
        );
        final evidence = _evidence('event-1', at: _date(21));

        final first = await evaluator.evaluate(
          evidence: evidence,
          history: <AchievementEvaluationEvidence>[evidence],
        );
        final second = await evaluator.evaluate(
          evidence: evidence,
          history: <AchievementEvaluationEvidence>[evidence],
        );

        expect(first.unlocked, hasLength(1));
        expect(second.unlocked, isEmpty);
        expect(ledger.entries, hasLength(1));
        final receipt = ledger.entries.single;
        expect(receipt.sourceEventId, 'achievement:first_practice:event-1');
        expect(receipt.ledgerId, 'achievement:first_practice:event-1');
        expect(receipt.createdAt, _date(21));
        expect(receipt.baseXp, 0);
        expect(receipt.bonusXp, 0);
        expect(receipt.totalXp, 0);
        expect(receipt.reasonCodes, <RewardReason>[
          RewardReason.achievementUnlocked,
        ]);
      },
    );

    test(
      'A2: a fresh evaluator honors repository receipt dedup after restart',
      () async {
        final ledger = _Ledger();
        final evidence = _evidence('event-1', at: _date(21));
        final catalog = _catalog(
          id: 'restart_safe',
          objective: CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 1,
          ),
        );

        await AchievementEvaluator(catalog: catalog, ledger: ledger).evaluate(
          evidence: evidence,
          history: <AchievementEvaluationEvidence>[evidence],
        );
        final afterRestart =
            await AchievementEvaluator(
              catalog: catalog,
              ledger: ledger,
            ).evaluate(
              evidence: evidence,
              history: <AchievementEvaluationEvidence>[evidence],
            );

        expect(afterRestart.unlocked, isEmpty);
        expect(ledger.entries, hasLength(1));
      },
    );

    test(
      'A3 and A4: rebuild uses history and preserves receipt completion time',
      () async {
        final ledger = _Ledger();
        final first = _evidence('event-1', at: _date(20));
        final trigger = _evidence('event-2', at: _date(21));
        final evaluator = AchievementEvaluator(
          catalog: _catalog(
            id: 'two_practices',
            objective: CountAchievementObjective(
              eventKind: AchievementEventKind.practice,
              target: 2,
            ),
          ),
          ledger: ledger,
        );
        final history = <AchievementEvaluationEvidence>[first, trigger];

        await evaluator.evaluate(evidence: trigger, history: history);
        final rebuilt = await evaluator.rebuild(history: history);

        final progress = rebuilt.progressByAchievement['two_practices']!;
        expect(progress.value, 1);
        expect(progress.completedAt, _date(21));
        expect(
          progress.rewardLedgerEntryId,
          'achievement:two_practices:event-2',
        );
      },
    );

    test('A5: index evaluates only objectives relevant to an event', () async {
      final ledger = _Ledger();
      final practice = _definition(
        id: 'practice_only',
        objective: CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 1,
        ),
      );
      final song = _definition(
        id: 'song_only',
        objective: CountAchievementObjective(
          eventKind: AchievementEventKind.song,
          target: 1,
        ),
      );
      final evaluator = AchievementEvaluator(
        catalog: AchievementCatalog(
          contentVersion: 1,
          definitions: <AchievementDefinition>[practice, song],
        ),
        ledger: ledger,
      );
      final evidence = _evidence('event-1', at: _date(21));

      final result = await evaluator.evaluate(
        evidence: evidence,
        history: <AchievementEvaluationEvidence>[evidence],
      );

      expect(result.evaluatedAchievementCount, 1);
      expect(result.progressByAchievement.containsKey('song_only'), isFalse);
    });

    test(
      'A6: unknown objectives fail closed with a typed diagnostic',
      () async {
        final ledger = _Ledger();
        final evidence = _evidence('event-1', at: _date(21));
        final evaluator = AchievementEvaluator(
          catalog: _catalog(
            id: 'unknown',
            objective: const UnknownAchievementObjective('future_type'),
          ),
          ledger: ledger,
        );

        final result = await evaluator.evaluate(
          evidence: evidence,
          history: <AchievementEvaluationEvidence>[evidence],
        );

        expect(result.unlocked, isEmpty);
        expect(
          result.diagnostics.single.code,
          AchievementEvaluationDiagnosticCode.unknownObjective,
        );
      },
    );

    test(
      'evaluates distinct, threshold, sequence, compound, and tier prerequisites',
      () async {
        final ledger = _Ledger();
        final first = _evidence(
          'event-1',
          at: _date(20),
          source: ActivitySource.live,
        );
        final second = _evidence(
          'event-2',
          at: _date(21),
          source: ActivitySource.learn,
          score: 0.9,
        );
        final song = _evidence(
          'event-3',
          at: _date(21),
          kind: AchievementEventKind.song,
        );
        final history = <AchievementEvaluationEvidence>[first, second, song];
        final prerequisite = _definition(
          id: 'first_tier',
          objective: CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 1,
          ),
        );
        final dependent = _definition(
          id: 'second_tier',
          prerequisites: const <String>['first_tier'],
          objective: CompoundAchievementObjective(
            objectives: <AchievementObjective>[
              DistinctAchievementObjective(
                eventKind: AchievementEventKind.practice,
                dimension: AchievementDistinctDimension.activitySource,
                target: 2,
              ),
              ThresholdAchievementObjective(
                eventKind: AchievementEventKind.practice,
                metric: AchievementMetric.score,
                minimum: 0.9,
              ),
              SequenceAchievementObjective(
                eventKinds: <AchievementEventKind>[
                  AchievementEventKind.practice,
                  AchievementEventKind.song,
                ],
              ),
            ],
          ),
        );
        final evaluator = AchievementEvaluator(
          catalog: AchievementCatalog(
            contentVersion: 1,
            definitions: <AchievementDefinition>[prerequisite, dependent],
          ),
          ledger: ledger,
        );

        await evaluator.evaluate(
          evidence: first,
          history: <AchievementEvaluationEvidence>[first],
        );
        await evaluator.evaluate(
          evidence: second,
          history: <AchievementEvaluationEvidence>[first, second],
        );
        final result = await evaluator.evaluate(
          evidence: song,
          history: history,
        );

        expect(
          result.unlocked.map((unlock) => unlock.achievementId),
          contains('second_tier'),
        );
        expect(
          ledger.entries.map((entry) => entry.sourceEventId),
          contains('achievement:first_tier:event-1'),
        );
      },
    );

    test(
      'missing explicit XP evidence fails closed without an unlock',
      () async {
        final ledger = _Ledger();
        final evidence = _evidence('event-1', at: _date(21));
        final evaluator = AchievementEvaluator(
          catalog: _catalog(
            id: 'requires_xp',
            objective: ThresholdAchievementObjective(
              eventKind: AchievementEventKind.practice,
              metric: AchievementMetric.totalXp,
              minimum: 1,
            ),
          ),
          ledger: ledger,
        );

        final result = await evaluator.evaluate(
          evidence: evidence,
          history: <AchievementEvaluationEvidence>[evidence],
        );

        expect(result.unlocked, isEmpty);
        expect(
          result.diagnostics.single.code,
          AchievementEvaluationDiagnosticCode.missingMetric,
        );
      },
    );

    test('A8: backfill uses an inclusive 30-day caller anchor', () async {
      final ledger = _Ledger();
      final old = _evidence('old', at: _date(21));
      final boundary = _evidence('boundary', at: _date(22));
      final recent = _evidence('recent', at: _date(23));
      final evaluator = AchievementEvaluator(
        catalog: _catalog(
          id: 'backfill',
          objective: CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 2,
          ),
        ),
        ledger: ledger,
      );

      final result = await evaluator.backfill(
        history: <AchievementEvaluationEvidence>[old, boundary, recent],
        anchor: _date(21, month: 8),
      );

      expect(result.skippedBackfillEventCount, 1);
      expect(result.progressByAchievement['backfill']!.value, 1);
      expect(result.progressByAchievement['backfill']!.completedAt, _date(23));
    });

    test('input and result collections cannot be mutated', () async {
      final metrics = <AchievementMetric, num>{AchievementMetric.totalXp: 7};
      final evidence = AchievementEvaluationEvidence(
        event: _event('event-1', _date(21)),
        metrics: metrics,
      );
      metrics[AchievementMetric.totalXp] = 99;
      final evaluator = AchievementEvaluator(
        catalog: _catalog(
          id: 'immutable',
          objective: CountAchievementObjective(
            eventKind: AchievementEventKind.practice,
            target: 1,
          ),
        ),
        ledger: _Ledger(),
      );

      final result = await evaluator.evaluate(
        evidence: evidence,
        history: <AchievementEvaluationEvidence>[evidence],
      );

      expect(evidence.metrics[AchievementMetric.totalXp], 7);
      expect(
        () => result.progressByAchievement['other'] =
            result.progressByAchievement.values.single,
        throwsUnsupportedError,
      );
      expect(
        () => result.unlocked.add(result.unlocked.single),
        throwsUnsupportedError,
      );
      expect(
        () => result.diagnostics.add(
          const AchievementEvaluationDiagnostic(
            achievementId: 'other',
            code: AchievementEvaluationDiagnosticCode.unknownObjective,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}

AchievementCatalog _catalog({
  required String id,
  required AchievementObjective objective,
}) => AchievementCatalog(
  contentVersion: 1,
  definitions: <AchievementDefinition>[
    _definition(id: id, objective: objective),
  ],
);

AchievementDefinition _definition({
  required String id,
  required AchievementObjective objective,
  List<String> prerequisites = const <String>[],
}) => AchievementDefinition(
  id: id,
  category: AchievementCategory.practice,
  titleKey: 'testTitle',
  descriptionKey: 'testDescription',
  accessibilityDescriptionKey: 'testSemantics',
  objectives: <AchievementObjective>[objective],
  tierPrerequisiteIds: prerequisites,
  hidden: false,
  version: 1,
  deprecated: false,
);

AchievementEvaluationEvidence _evidence(
  String id, {
  required DateTime at,
  AchievementEventKind kind = AchievementEventKind.practice,
  ActivitySource source = ActivitySource.practice,
  double score = 0.8,
}) => AchievementEvaluationEvidence(
  event: _event(id, at, kind: kind, source: source, score: score),
  metrics: const <AchievementMetric, num>{},
);

LearningActivityEvent _event(
  String id,
  DateTime at, {
  AchievementEventKind kind = AchievementEventKind.practice,
  ActivitySource source = ActivitySource.practice,
  double score = 0.8,
}) => switch (kind) {
  AchievementEventKind.practice => PracticeActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  AchievementEventKind.song => SongActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  AchievementEventKind.analysis => AnalysisActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  AchievementEventKind.plan => PlanActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  AchievementEventKind.tutor => TutorActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  AchievementEventKind.vision => VisionActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: source,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
};

DateTime _date(int day, {int month = 7}) => DateTime.utc(2026, month, day, 12);

final class _Ledger implements RewardLedgerRepository {
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
      RewardLedgerPage(entries: entries, nextCursor: null);
}
