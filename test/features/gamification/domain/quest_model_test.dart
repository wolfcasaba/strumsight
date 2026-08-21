import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  final expiresAt = DateTime.utc(2026, 8, 22);

  group('Quest domain model', () {
    test(
      'A1/A2: completing an active quest creates its receipt without a claim',
      () {
        final progress = _progress();
        final completed = progress.complete(
          at: expiresAt.subtract(const Duration(seconds: 1)),
        );

        expect(completed.isSuccess, isTrue);
        expect(completed.progress.status, QuestStatus.completed);
        expect(completed.receipt, isNotNull);
        expect(completed.receipt!.reasonCodes, const <RewardReason>[
          RewardReason.questCompleted,
        ]);
        expect(completed.receipt!.ledgerId, 'quest:daily_rhythm:completion');
        expect(
          completed.progress.completionAt,
          expiresAt.subtract(const Duration(seconds: 1)),
        );
      },
    );

    test(
      'A3: expiry preserves the accumulated progress and practice evidence',
      () {
        final progress = _progress(
          completedUnits: 3,
          practiceResultIds: const <String>['practice-1'],
        );
        final expired = progress.expire(at: expiresAt);

        expect(expired.isSuccess, isTrue);
        expect(expired.progress.status, QuestStatus.expired);
        expect(expired.progress.completedUnits, 3);
        expect(expired.progress.practiceResultIds, const <String>[
          'practice-1',
        ]);
        expect(expired.progress.rewardLedgerId, isNull);
      },
    );

    test(
      'A4/A5: only the closed lifecycle edges succeed with reason codes',
      () {
        final active = _progress();
        final completed = active.complete(
          at: expiresAt.subtract(const Duration(seconds: 1)),
        );
        final expired = active.expire(at: expiresAt);
        final replaced = active.replace(
          reason: QuestReplacementReason.catalogRefresh,
        );

        expect(completed.reason, QuestTransitionReason.completed);
        expect(expired.reason, QuestTransitionReason.expired);
        expect(
          replaced.reason,
          QuestTransitionReason.replacedForCatalogRefresh,
        );
        expect(
          completed.progress.archive().reason,
          QuestTransitionReason.archived,
        );
        expect(
          expired.progress.archive().reason,
          QuestTransitionReason.archived,
        );
        expect(
          replaced.progress.archive().reason,
          QuestTransitionReason.archived,
        );
        expect(
          completed.progress.expire(at: expiresAt).failure,
          QuestTransitionFailure.invalidTransition,
        );
        expect(
          active.archive().failure,
          QuestTransitionFailure.invalidTransition,
        );
      },
    );

    test(
      'A6: accepts supported typed objective references and rejects unknown objectives',
      () {
        final objectives = <QuestObjective>[
          SkillTagQuestObjective('rhythm_basics'),
          PlanBlockQuestObjective(BlockId('block-1')),
          PracticeModeQuestObjective(PracticeMode.rhythmOnly),
          MetricQuestObjective(AchievementMetric.durationSeconds),
        ];

        expect(objectives, hasLength(4));
        expect(
          () => _definition(objective: const UnknownQuestObjective('future')),
          throwsArgumentError,
        );
      },
    );

    test(
      'A7/A8: versioned schedule round-trips persisted boundary fields and rejects unknown versions',
      () {
        final schedule = _schedule();
        final decoded = QuestSchedule.fromJson(schedule.toJson());

        expect(decoded.generationEpochDay, 20686);
        expect(decoded.timezoneOffsetMinutes, 120);
        expect(decoded.catalogVersion, 4);
        expect(decoded.expiresAt, expiresAt);
        expect(
          () => QuestSchedule.fromJson(<String, Object?>{
            ...schedule.toJson(),
            'schemaVersion': 99,
          }),
          throwsArgumentError,
        );
        expect(
          () => QuestDefinition.fromJson(<String, Object?>{
            ..._definition().toJson(),
            'schemaVersion': 99,
          }),
          throwsArgumentError,
        );
        final progress = _progress();
        expect(progress.schemaVersion, questProgressSchemaVersion);
        expect(
          () => QuestProgress.fromJson(<String, Object?>{
            ...progress.toJson(),
            'schemaVersion': 99,
          }),
          throwsArgumentError,
        );
      },
    );

    test(
      'validates quest rewards at runtime before they can enter a definition',
      () {
        expect(
          () => QuestReward(baseXp: -1, bonusXp: 0, policyVersion: 1),
          throwsArgumentError,
        );
        expect(
          () => QuestReward(baseXp: 0, bonusXp: 0, policyVersion: 1),
          throwsArgumentError,
        );
      },
    );

    test(
      'A9: repeated completion preserves the original completion and receipt identity',
      () {
        final first = _progress().complete(
          at: expiresAt.subtract(const Duration(seconds: 1)),
        );
        final repeated = first.progress.complete(
          at: expiresAt.subtract(const Duration(minutes: 1)),
        );

        expect(repeated.isSuccess, isTrue);
        expect(
          repeated.reason,
          QuestTransitionReason.completionAlreadyRecorded,
        );
        expect(repeated.progress.completionAt, first.progress.completionAt);
        expect(repeated.receipt!.ledgerId, first.receipt!.ledgerId);
        expect(repeated.receipt, first.receipt);
      },
    );

    test('expiry boundary is exclusive for active quests', () {
      final progress = _progress();

      expect(
        progress
            .complete(at: expiresAt.subtract(const Duration(seconds: 1)))
            .isSuccess,
        isTrue,
      );
      expect(
        progress.complete(at: expiresAt).failure,
        QuestTransitionFailure.expired,
      );
      expect(progress.expire(at: expiresAt).isSuccess, isTrue);
      expect(
        progress
            .complete(at: expiresAt.add(const Duration(seconds: 1)))
            .failure,
        QuestTransitionFailure.expired,
      );
    });
  });
}

QuestProgress _progress({
  int completedUnits = 0,
  List<String> practiceResultIds = const <String>[],
}) => QuestProgress.active(
  definition: _definition(),
  completedUnits: completedUnits,
  practiceResultIds: practiceResultIds,
);

QuestDefinition _definition({QuestObjective? objective}) => QuestDefinition(
  id: 'daily_rhythm',
  schemaVersion: questDefinitionSchemaVersion,
  cadence: QuestCadence.daily,
  objective: objective ?? PracticeModeQuestObjective(PracticeMode.rhythmOnly),
  schedule: _schedule(),
  reward: QuestReward(baseXp: 25, bonusXp: 0, policyVersion: 1),
);

QuestSchedule _schedule() => QuestSchedule(
  schemaVersion: questScheduleSchemaVersion,
  generationEpochDay: 20686,
  timezoneOffsetMinutes: 120,
  catalogVersion: 4,
  expiresAt: DateTime.utc(2026, 8, 22),
);
