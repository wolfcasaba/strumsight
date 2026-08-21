import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show BlockId;

void main() {
  final generator = WeeklyQuestGenerator();

  group('WeeklyQuestGenerator', () {
    test(
      'A1: active-day targets keep the inclusive 3/4/5/6/7 cap boundary',
      () {
        final threeDays = generator.generate(
          _snapshot(
            availableDays: 3,
            candidates: <WeeklyQuestCandidate>[_activeDays()],
          ),
        );
        final below = generator.generate(
          _snapshot(
            availableDays: 4,
            candidates: <WeeklyQuestCandidate>[_activeDays()],
          ),
        );
        final at = generator.generate(
          _snapshot(
            availableDays: 5,
            candidates: <WeeklyQuestCandidate>[_activeDays()],
          ),
        );
        final above = generator.generate(
          _snapshot(
            availableDays: 6,
            candidates: <WeeklyQuestCandidate>[_activeDays()],
          ),
        );
        final sevenDays = generator.generate(
          _snapshot(
            availableDays: 7,
            candidates: <WeeklyQuestCandidate>[_activeDays()],
          ),
        );

        expect(threeDays!.progress.targetUnits, 3);
        expect(below!.progress.targetUnits, 4);
        expect(at!.progress.targetUnits, 5);
        expect(above!.progress.targetUnits, 5);
        expect(sevenDays!.progress.targetUnits, 5);
      },
    );

    test('A1: available days must be in the inclusive weekly range', () {
      expect(
        () => _snapshot(
          availableDays: -1,
          candidates: <WeeklyQuestCandidate>[_activeDays()],
        ),
        throwsArgumentError,
      );
      expect(
        () => _snapshot(
          availableDays: 8,
          candidates: <WeeklyQuestCandidate>[_activeDays()],
        ),
        throwsArgumentError,
      );
    });

    test('A2: targets scale with reduced weekly availability', () {
      final full = generator.generate(
        _snapshot(candidates: <WeeklyQuestCandidate>[_planBlock()]),
      );
      final half = generator.generate(
        _snapshot(
          availableMinutes: 180,
          candidates: <WeeklyQuestCandidate>[_planBlock()],
        ),
      );

      expect(full!.progress.targetUnits, 6);
      expect(half!.progress.targetUnits, 3);
    });

    test(
      'A3 and A8: same-ID progress is max(previous, observed), never a penalty',
      () {
        final reducedPlan = generator.generate(
          _snapshot(
            availableMinutes: 180,
            previousQuestId: 'weekly_plan',
            previousCompletedUnits: 4,
            observedCompletedUnits: 3,
            candidates: <WeeklyQuestCandidate>[_planBlock()],
          ),
        );
        final newObservation = generator.generate(
          _snapshot(
            availableMinutes: 180,
            previousQuestId: 'weekly_plan',
            previousCompletedUnits: 4,
            observedCompletedUnits: 5,
            candidates: <WeeklyQuestCandidate>[_planBlock()],
          ),
        );

        expect(reducedPlan!.progress.targetUnits, 3);
        expect(reducedPlan.progress.completedUnits, 4);
        expect(reducedPlan.progress.isCompleted, isTrue);
        expect(newObservation!.progress.completedUnits, 5);
      },
    );

    test(
      'A3 and A8: a replacement does not inherit filtered improvement progress',
      () {
        final replacement = generator.generate(
          _snapshot(
            previousQuestId: 'weekly_improvement',
            previousCompletedUnits: 4,
            candidates: <WeeklyQuestCandidate>[_improvement(), _activeDays()],
            improvementMeasurementAvailable: false,
          ),
        );

        expect(replacement!.candidate.id, 'weekly_active');
        expect(replacement.progress.completedUnits, 0);
      },
    );

    test('A3: positive previous progress requires its stable quest ID', () {
      expect(
        () => _snapshot(
          previousCompletedUnits: 1,
          candidates: <WeeklyQuestCandidate>[_planBlock()],
        ),
        throwsArgumentError,
      );
    });

    test('A4: target derivation retains its exact caller-fed inputs', () {
      final generated = generator.generate(
        _snapshot(
          availableDays: 3,
          availableMinutes: 180,
          candidates: <WeeklyQuestCandidate>[_planBlock()],
        ),
      );

      expect(generated!.targetDerivation.baseTargetUnits, 6);
      expect(generated.targetDerivation.availableMinutes, 180);
      expect(generated.targetDerivation.baselineWeeklyMinutes, 360);
      expect(generated.targetDerivation.availableDays, 3);
    });

    test('A5: selection uses the pinned weekly UTF-8 FNV ordering', () {
      final snapshot = _snapshot(candidates: _candidates());
      final expected = generator.generate(snapshot)!.definition.id;

      for (var run = 0; run < 100; run++) {
        expect(generator.generate(snapshot)!.definition.id, expected);
      }

      expect(weeklyQuestSeedMaterial(snapshot), '20686|profile_alpha|7');
      expect(
        weeklyQuestSortKey(snapshot, 'weekly_active'),
        -1830493033626131184,
      );
    });

    test('A6: all four typed objective kinds are supported', () {
      final candidates = _candidates();
      for (final candidate in candidates) {
        final generated = generator.generate(
          _snapshot(candidates: <WeeklyQuestCandidate>[candidate]),
        );
        expect(generated!.candidate.kind, candidate.kind);
        expect(generated.definition.objective, same(candidate.objective));
      }
    });

    test('A6: every objective kind rejects each invalid cross-wiring', () {
      final planBlock = PlanBlockQuestObjective(BlockId('block-1'));
      const eventCount = MetricQuestObjective(AchievementMetric.eventCount);
      const diversity = MetricQuestObjective(AchievementMetric.diversityXp);
      const improvement = MetricQuestObjective(AchievementMetric.improvementXp);
      final objectives = <WeeklyQuestObjectiveKind, QuestObjective>{
        WeeklyQuestObjectiveKind.activeDays: eventCount,
        WeeklyQuestObjectiveKind.planBlock: planBlock,
        WeeklyQuestObjectiveKind.modeDiversity: diversity,
        WeeklyQuestObjectiveKind.improvement: improvement,
      };

      for (final entry in objectives.entries) {
        for (final other in objectives.entries) {
          if (entry.key == other.key) continue;
          expect(
            () => _candidate(
              id: 'wrong_${entry.key.name}_${other.key.name}',
              kind: entry.key,
              objective: other.value,
            ),
            throwsArgumentError,
          );
        }
      }
    });

    test('A7: rollover is a typed, language-neutral fact projection', () {
      final completed = generator.generate(
        _snapshot(
          previousQuestId: 'weekly_plan',
          previousCompletedUnits: 6,
          candidates: <WeeklyQuestCandidate>[_planBlock()],
        ),
      );
      final open = generator.generate(
        _snapshot(candidates: <WeeklyQuestCandidate>[_planBlock()]),
      );
      final source = File(
        'lib/features/gamification/application/weekly_quest_generator.dart',
      ).readAsStringSync();

      expect(completed!.rollover.status, WeeklyQuestRolloverStatus.completed);
      expect(completed.rollover.targetUnits, 6);
      expect(completed.rollover.completedUnits, 6);
      expect(open!.rollover.status, WeeklyQuestRolloverStatus.stillOpen);
      expect(source, isNot(contains('DateTime.now')));
      expect(source, isNot(contains('repository')));
    });

    test('A9: unavailable improvement measurements fail closed', () {
      final selected = generator.generate(
        _snapshot(
          improvementMeasurementAvailable: false,
          candidates: <WeeklyQuestCandidate>[_improvement(), _activeDays()],
        ),
      );
      final unavailableOnly = generator.generate(
        _snapshot(
          improvementMeasurementAvailable: false,
          candidates: <WeeklyQuestCandidate>[_improvement()],
        ),
      );

      expect(selected!.candidate.kind, WeeklyQuestObjectiveKind.activeDays);
      expect(unavailableOnly, isNull);
    });

    test(
      'A10: snapshot candidate views are immutable and generation is pure',
      () {
        final snapshot = _snapshot(candidates: _candidates());
        final before = generator.generate(snapshot);
        final after = generator.generate(snapshot);
        final source = File(
          'lib/features/gamification/application/weekly_quest_generator.dart',
        ).readAsStringSync();

        expect(
          () => snapshot.candidates.add(_activeDays()),
          throwsUnsupportedError,
        );
        expect(after!.definition.id, before!.definition.id);
        expect(source, isNot(contains('package:')));
        expect(source, isNot(contains('DateTime.now')));
        expect(source, isNot(contains('Random(')));
      },
    );

    test(
      'zero available days or minutes produces no mandatory weekly quest',
      () {
        expect(
          generator.generate(
            _snapshot(
              availableDays: 0,
              candidates: <WeeklyQuestCandidate>[_planBlock()],
            ),
          ),
          isNull,
        );
        expect(
          generator.generate(
            _snapshot(
              availableMinutes: 0,
              candidates: <WeeklyQuestCandidate>[_planBlock()],
            ),
          ),
          isNull,
        );
      },
    );
  });
}

WeeklyQuestGenerationSnapshot _snapshot({
  int availableDays = 6,
  int availableMinutes = 360,
  String? previousQuestId,
  int previousCompletedUnits = 0,
  int observedCompletedUnits = 0,
  required List<WeeklyQuestCandidate> candidates,
  bool improvementMeasurementAvailable = true,
}) => WeeklyQuestGenerationSnapshot(
  schedule: QuestSchedule(
    schemaVersion: questScheduleSchemaVersion,
    generationEpochDay: 20686,
    timezoneOffsetMinutes: 120,
    catalogVersion: 7,
    expiresAt: DateTime.utc(2026, 8, 28),
  ),
  profileSnapshotKey: 'profile_alpha',
  availableDays: availableDays,
  availableMinutes: availableMinutes,
  baselineWeeklyMinutes: 360,
  previousQuestId: previousQuestId,
  previousCompletedUnits: previousCompletedUnits,
  observedCompletedUnits: observedCompletedUnits,
  candidates: candidates,
  improvementMeasurementAvailable: improvementMeasurementAvailable,
);

List<WeeklyQuestCandidate> _candidates() => <WeeklyQuestCandidate>[
  _activeDays(),
  _planBlock(),
  _modeDiversity(),
  _improvement(),
];

WeeklyQuestCandidate _activeDays() => _candidate(
  id: 'weekly_active',
  kind: WeeklyQuestObjectiveKind.activeDays,
  objective: const MetricQuestObjective(AchievementMetric.eventCount),
);

WeeklyQuestCandidate _planBlock() => _candidate(
  id: 'weekly_plan',
  kind: WeeklyQuestObjectiveKind.planBlock,
  objective: PlanBlockQuestObjective(BlockId('block-1')),
);

WeeklyQuestCandidate _modeDiversity() => _candidate(
  id: 'weekly_diversity',
  kind: WeeklyQuestObjectiveKind.modeDiversity,
  objective: const MetricQuestObjective(AchievementMetric.diversityXp),
);

WeeklyQuestCandidate _improvement() => _candidate(
  id: 'weekly_improvement',
  kind: WeeklyQuestObjectiveKind.improvement,
  objective: const MetricQuestObjective(AchievementMetric.improvementXp),
);

WeeklyQuestCandidate _candidate({
  required String id,
  required WeeklyQuestObjectiveKind kind,
  required QuestObjective objective,
}) => WeeklyQuestCandidate(
  id: id,
  kind: kind,
  objective: objective,
  baseTargetUnits: 6,
  reward: QuestReward(baseXp: 20, bonusXp: 0, policyVersion: 1),
);
