import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('AchievementEvaluator', () {
    test('A2/A7: exact receipt is restart-safe and zero-XP', () async {
      final ledger = _Ledger();
      final evidence = _evidence('event-1', at: _date(21));
      final catalog = _catalog(id: 'first_practice', objective: _count(1));

      final first = await AchievementEvaluator(catalog: catalog, ledger: ledger)
          .evaluate(
            evidence: evidence,
            history: <AchievementEvaluationEvidence>[evidence],
          );
      final restarted =
          await AchievementEvaluator(catalog: catalog, ledger: ledger).evaluate(
            evidence: evidence,
            history: <AchievementEvaluationEvidence>[evidence],
          );

      expect(first.unlocked, hasLength(1));
      expect(restarted.unlocked, isEmpty);
      final receipt = ledger.entries.single;
      expect(receipt.sourceEventId, 'achievement:first_practice');
      expect(receipt.ledgerId, 'achievement:first_practice:event-1');
      expect(receipt.createdAt, _date(21));
      expect(receipt.baseXp, 0);
      expect(receipt.bonusXp, 0);
      expect(receipt.totalXp, 0);
      expect(receipt.reasonCodes, const <RewardReason>[
        RewardReason.achievementUnlocked,
      ]);
    });

    test(
      'A1: exact replay does not inflate count or repeated sequence',
      () async {
        final event = _evidence('replay', at: _date(21));
        final history = <AchievementEvaluationEvidence>[event, event];
        final count = await AchievementEvaluator(
          catalog: _catalog(id: 'count_replay', objective: _count(2)),
          ledger: _Ledger(),
        ).evaluate(evidence: event, history: history);
        final sequence = await AchievementEvaluator(
          catalog: _catalog(
            id: 'sequence_replay',
            objective: SequenceAchievementObjective(
              eventKinds: const <AchievementEventKind>[
                AchievementEventKind.practice,
                AchievementEventKind.practice,
              ],
            ),
          ),
          ledger: _Ledger(),
        ).evaluate(evidence: event, history: history);

        expect(count.progressByAchievement['count_replay']!.value, 0.5);
        expect(count.unlocked, isEmpty);
        expect(sequence.progressByAchievement['sequence_replay']!.value, 0.5);
        expect(sequence.unlocked, isEmpty);
      },
    );

    test('A1: same event ID with a different payload fails closed', () async {
      final first = _evidence('conflict', at: _date(21), score: 0.5);
      final altered = _evidence('conflict', at: _date(21), score: 0.9);
      final result =
          await AchievementEvaluator(
            catalog: _catalog(id: 'conflict_safe', objective: _count(1)),
            ledger: _Ledger(),
          ).evaluate(
            evidence: first,
            history: <AchievementEvaluationEvidence>[first, altered],
          );

      expect(result.unlocked, isEmpty);
      expect(
        result.diagnostics.single.code,
        AchievementEvaluationDiagnosticCode.conflictingEventPayload,
      );
    });

    test(
      'A2: concurrent distinct triggers produce one atomic receipt',
      () async {
        final ledger = _DelayedLedger();
        final catalog = _catalog(id: 'concurrent', objective: _count(1));
        final first = _evidence('trigger-a', at: _date(20));
        final second = _evidence('trigger-b', at: _date(21));

        final results = await Future.wait(<Future<AchievementEvaluationResult>>[
          AchievementEvaluator(catalog: catalog, ledger: ledger).evaluate(
            evidence: first,
            history: <AchievementEvaluationEvidence>[first],
          ),
          AchievementEvaluator(catalog: catalog, ledger: ledger).evaluate(
            evidence: second,
            history: <AchievementEvaluationEvidence>[second],
          ),
        ]);

        expect(ledger.entries, hasLength(1));
        expect(ledger.entries.single.sourceEventId, 'achievement:concurrent');
        expect(
          ledger.entries.single.ledgerId,
          anyOf(
            'achievement:concurrent:trigger-a',
            'achievement:concurrent:trigger-b',
          ),
        );
        expect(results.expand((result) => result.unlocked), hasLength(1));
      },
    );

    test(
      'A3/A4: rebuild sorts history and uses catalog content version',
      () async {
        final ledger = _Ledger();
        final later = _evidence('b', at: _date(21));
        final earlier = _evidence('a', at: _date(20));
        final definition = _definition(id: 'ordered', objective: _count(2));
        final result = await AchievementEvaluator(
          catalog: AchievementCatalog(
            contentVersion: 7,
            definitions: <AchievementDefinition>[definition],
          ),
          ledger: ledger,
        ).rebuild(history: <AchievementEvaluationEvidence>[later, earlier]);

        final progress = result.progressByAchievement['ordered']!;
        expect(progress.completedAt, _date(21));
        expect(progress.rewardLedgerEntryId, 'achievement:ordered:b');
        expect(progress.catalogVersion, 7);
      },
    );

    test('A5: event kind, metric, and dimension routes are distinct', () async {
      final practice = _definition(id: 'practice_only', objective: _count(1));
      final song = _definition(
        id: 'song_only',
        objective: CountAchievementObjective(
          eventKind: AchievementEventKind.song,
          target: 1,
        ),
      );
      final score = _definition(
        id: 'score_route',
        objective: ThresholdAchievementObjective(
          eventKind: AchievementEventKind.practice,
          metric: AchievementMetric.score,
          minimum: 0.8,
        ),
      );
      final duration = _definition(
        id: 'duration_route',
        objective: ThresholdAchievementObjective(
          eventKind: AchievementEventKind.practice,
          metric: AchievementMetric.durationSeconds,
          minimum: 60,
        ),
      );
      final distinct = _definition(
        id: 'source_route',
        objective: DistinctAchievementObjective(
          eventKind: AchievementEventKind.practice,
          dimension: AchievementDistinctDimension.activitySource,
          target: 2,
        ),
      );
      final catalog = AchievementCatalog(
        contentVersion: 1,
        definitions: <AchievementDefinition>[
          practice,
          song,
          score,
          duration,
          distinct,
        ],
      );
      final evaluator = AchievementEvaluator(
        catalog: catalog,
        ledger: _Ledger(),
      );
      final evidence = _evidence('event', at: _date(21));
      final result = await evaluator.evaluate(
        evidence: evidence,
        history: <AchievementEvaluationEvidence>[evidence],
      );

      expect(result.evaluatedAchievementCount, 4);
      expect(result.progressByAchievement.containsKey('song_only'), isFalse);
      expect(
        evaluator.index
            .candidatesForMetric(
              AchievementEventKind.practice,
              AchievementMetric.score,
            )
            .map((definition) => definition.id),
        <String>['score_route'],
      );
      expect(
        evaluator.index
            .candidatesForDimension(
              AchievementEventKind.practice,
              AchievementDistinctDimension.activitySource,
            )
            .map((definition) => definition.id),
        <String>['source_route'],
      );
    });

    test('A6: unknown and missing metric objectives fail closed', () async {
      final evidence = _evidence('event', at: _date(21));
      final unknown =
          await AchievementEvaluator(
            catalog: _catalog(
              id: 'unknown',
              objective: const UnknownAchievementObjective('future_type'),
            ),
            ledger: _Ledger(),
          ).evaluate(
            evidence: evidence,
            history: <AchievementEvaluationEvidence>[evidence],
          );
      final missing =
          await AchievementEvaluator(
            catalog: _catalog(
              id: 'missing_xp',
              objective: ThresholdAchievementObjective(
                eventKind: AchievementEventKind.practice,
                metric: AchievementMetric.totalXp,
                minimum: 1,
              ),
            ),
            ledger: _Ledger(),
          ).evaluate(
            evidence: evidence,
            history: <AchievementEvaluationEvidence>[evidence],
          );

      expect(unknown.unlocked, isEmpty);
      expect(
        unknown.diagnostics.single.code,
        AchievementEvaluationDiagnosticCode.unknownObjective,
      );
      expect(missing.unlocked, isEmpty);
      expect(
        missing.diagnostics.single.code,
        AchievementEvaluationDiagnosticCode.missingMetric,
      );
    });

    test(
      'A7: forged prefix receipt cannot complete or satisfy a prerequisite',
      () async {
        final ledger = _Ledger()
          ..entries.add(
            _ledgerEntry(
              sourceEventId: 'achievement:receipt_safe:forged',
              ledgerId: 'achievement:receipt_safe:forged',
              reasonCodes: const <RewardReason>[RewardReason.baseExperience],
            ),
          );
        final evidence = _evidence('receipt-trigger', at: _date(21));
        final result =
            await AchievementEvaluator(
              catalog: AchievementCatalog(
                contentVersion: 1,
                definitions: <AchievementDefinition>[
                  _definition(id: 'receipt_safe', objective: _count(1)),
                  _definition(
                    id: 'receipt_dependent',
                    objective: _count(1),
                    prerequisites: const <String>['receipt_safe'],
                  ),
                ],
              ),
              ledger: ledger,
            ).evaluate(
              evidence: evidence,
              history: <AchievementEvaluationEvidence>[evidence],
            );

        expect(result.unlocked, isEmpty);
        expect(ledger.entries, hasLength(1));
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.code),
          everyElement(
            AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
          ),
        );
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.achievementId),
          containsAll(<String>['receipt_safe', 'receipt_dependent']),
        );
        expect(
          result.progressByAchievement['receipt_dependent']!.completedAt,
          isNull,
        );
        expect(
          result.diagnostics.first.code,
          AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
        );
      },
    );

    test(
      'A8: backfill excludes old and future events at inclusive cutoff',
      () async {
        final old = _evidence('old', at: _date(21));
        final boundary = _evidence('boundary', at: _date(22));
        final recent = _evidence('recent', at: _date(23));
        final future = _evidence('future', at: _date(22, month: 8));
        final result =
            await AchievementEvaluator(
              catalog: _catalog(id: 'backfill', objective: _count(2)),
              ledger: _Ledger(),
            ).backfill(
              history: <AchievementEvaluationEvidence>[
                old,
                boundary,
                future,
                recent,
              ],
              anchor: _date(21, month: 8),
            );

        expect(result.skippedBackfillEventCount, 2);
        expect(result.progressByAchievement['backfill']!.value, 1);
        expect(
          result.progressByAchievement['backfill']!.completedAt,
          _date(23),
        );
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.code),
          contains(AchievementEvaluationDiagnosticCode.excludedByBackfill),
        );
      },
    );

    test(
      'A8: 9999 and 10000 pass, 10001 is rejected, and receipt scan is once',
      () async {
        for (final count in <int>[9999, 10000]) {
          final ledger = _Ledger();
          final evaluator = AchievementEvaluator(
            catalog: _catalog(id: 'linear$count', objective: _count(count)),
            ledger: ledger,
          );
          final history = List<AchievementEvaluationEvidence>.generate(
            count,
            (index) => _evidence('event-$count-$index', at: _date(21)),
          );

          final result = await evaluator.rebuild(history: history);

          expect(result.progressByAchievement['linear$count']!.value, 1);
          expect(ledger.readPageCalls, 1);
        }
        final tooLarge = List<AchievementEvaluationEvidence>.generate(
          10001,
          (index) => _evidence('too-large-$index', at: _date(21)),
        );
        await expectLater(
          AchievementEvaluator(
            catalog: _catalog(id: 'too_large', objective: _count(1)),
            ledger: _Ledger(),
          ).rebuild(history: tooLarge),
          throwsArgumentError,
        );
      },
    );

    test('A8: backfill caps raw history before date filtering', () async {
      final anchor = _date(21, month: 8);
      for (final count in <int>[9999, 10000]) {
        final history = List<AchievementEvaluationEvidence>.generate(
          count,
          (index) => _evidence('expired-$count-$index', at: _date(21)),
        );

        final result = await AchievementEvaluator(
          catalog: _catalog(id: 'backfill_cap_$count', objective: _count(1)),
          ledger: _Ledger(),
        ).backfill(history: history, anchor: anchor);

        expect(result.skippedBackfillEventCount, count);
        expect(result.unlocked, isEmpty);
      }

      final tooLarge = List<AchievementEvaluationEvidence>.generate(
        10001,
        (index) => _evidence('expired-too-large-$index', at: _date(21)),
      );
      await expectLater(
        AchievementEvaluator(
          catalog: _catalog(id: 'backfill_too_large', objective: _count(1)),
          ledger: _Ledger(),
        ).backfill(history: tooLarge, anchor: anchor),
        throwsArgumentError,
      );
    });
  });
}

AchievementObjective _count(int target) => CountAchievementObjective(
  eventKind: AchievementEventKind.practice,
  target: target,
);

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
  double score = 0.8,
}) => AchievementEvaluationEvidence(
  event: PracticeActivityEvent(
    eventId: id,
    occurredAt: at,
    epochDay: 0,
    source: ActivitySource.practice,
    trust: EvidenceTrust.verified,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: const Duration(minutes: 10),
    score: score,
  ),
  metrics: const <AchievementMetric, num>{},
);

RewardLedgerEntry _ledgerEntry({
  required String sourceEventId,
  required String ledgerId,
  required List<RewardReason> reasonCodes,
}) => RewardLedgerEntry(
  sourceEventId: sourceEventId,
  ledgerId: ledgerId,
  createdAt: _date(21),
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: achievementEvaluatorPolicyVersion,
  baseXp: 0,
  bonusXp: 0,
  totalXp: 0,
  reasonCodes: reasonCodes,
);

DateTime _date(int day, {int month = 7}) => DateTime.utc(2026, month, day, 12);

class _Ledger implements RewardLedgerRepository {
  final List<RewardLedgerEntry> entries = <RewardLedgerEntry>[];
  var readPageCalls = 0;

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
  RewardLedgerPage readPage({required int limit, String? cursor}) {
    readPageCalls++;
    return RewardLedgerPage(entries: entries, nextCursor: null);
  }
}

final class _DelayedLedger extends _Ledger {
  Future<void> _appendTail = Future<void>.value();

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) {
    final scheduled = _appendTail.then((_) => super.appendIfAbsent(entry));
    _appendTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }
}
