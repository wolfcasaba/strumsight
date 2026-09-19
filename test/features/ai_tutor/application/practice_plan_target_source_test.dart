// WP-H2 (2026-09-06) — the producer for `PracticePlanTargetInput`, the one
// `PracticePlanCompilationContext` input that had NO source in `lib/`.
//
// Every cell runs against the REAL shipped catalog (`BuiltinPracticeCatalog`)
// and real `PracticeHistoryEntry` records — the point of the producer is that
// it invents nothing, so a fake catalog would test the wrong thing.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_target_source.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/practice/public.dart';

import '../../../support/practice_history_fixtures.dart';

List<PracticeDefinition> _catalog() => const BuiltinPracticeCatalog().all();

List<PracticePlanBlock> _templateBlocks() => <PracticePlanBlock>[
  PracticePlanBlock.basic(
    id: 'b0',
    type: PracticePlanBlockType.warmup,
    duration: const Duration(minutes: 2),
  ),
  PracticePlanBlock.basic(
    id: 'b1',
    type: PracticePlanBlockType.technique,
    duration: const Duration(minutes: 5),
  ),
  PracticePlanBlock.basic(
    id: 'b2',
    type: PracticePlanBlockType.rhythm,
    duration: const Duration(minutes: 3),
  ),
];

LearningGoal _goal(LearningGoalCategory category) => LearningGoal(
  id: 'goal-${category.name}',
  statement: 'Improve ${category.name}',
  category: category,
  priority: LearningGoalPriority.high,
  status: LearningGoalStatus.active,
);

void main() {
  const source = PracticePlanTargetSource();

  group('binding template blocks to the real catalog', () {
    test(
      'every runnable block gets a real definition and a matching config',
      () {
        final selection = source.bind(
          templateBlocks: _templateBlocks(),
          catalog: _catalog(),
          history: const <PracticeHistoryEntry>[],
          activeGoals: const <LearningGoal>[],
        );

        expect(selection.blocks, hasLength(3));
        expect(selection.targets, hasLength(3));

        final catalogIds = _catalog().map((d) => d.id).toSet();
        for (final block in selection.blocks) {
          expect(block.adapter, PracticePlanBlockAdapter.practiceTarget);
          expect(catalogIds, contains(block.practiceTargetId));
          expect(
            block.requiredCapabilities,
            contains(PracticePlanCapability.practiceTarget),
          );

          final target = selection.targets[block.practiceTargetId]!;
          expect(target.definition.id, block.practiceTargetId);
          expect(target.config.definitionId, target.definition.id);
          // The block's own duration is the session timeout — not a fixed
          // five minutes as the Practice Setup seed would use.
          expect(target.config.sessionTimeout, block.duration);
          expect(target.config.validate(), isEmpty);
        }
      },
    );

    test('the same definition is never prescribed twice in one plan', () {
      final selection = source.bind(
        templateBlocks: _templateBlocks(),
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: const <LearningGoal>[],
      );

      final ids = selection.blocks.map((b) => b.practiceTargetId).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a block type with no runnable exercise stays a plain timer and is '
        'NOT reported as a missing target', () {
      final selection = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'reflect',
            type: PracticePlanBlockType.reflection,
            duration: const Duration(minutes: 3),
          ),
        ],
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: const <LearningGoal>[],
      );

      expect(selection.blocks.single.adapter, PracticePlanBlockAdapter.none);
      expect(selection.targets, isEmpty);
      expect(
        selection.absentInputs,
        isNot(contains(PracticePlanInputCode.practiceTargetsAbsent)),
      );
    });

    test('an EMPTY catalog leaves every block a timer and says so', () {
      final selection = source.bind(
        templateBlocks: _templateBlocks(),
        catalog: const <PracticeDefinition>[],
        history: const <PracticeHistoryEntry>[],
        activeGoals: const <LearningGoal>[],
      );

      expect(
        selection.blocks.every(
          (b) => b.adapter == PracticePlanBlockAdapter.none,
        ),
        isTrue,
      );
      expect(selection.targets, isEmpty);
      expect(selection.absentInputs, <String>{
        PracticePlanInputCode.goalsAbsent,
        PracticePlanInputCode.historyAbsent,
        PracticePlanInputCode.practiceTargetsAbsent,
      });
    });
  });

  group('the practice history is real evidence, not decoration', () {
    test('a measured stable tempo replaces the catalog default', () {
      final definition = _catalog().firstWhere(
        (d) => d.mode == PracticeMode.chordChanges,
      );
      expect(definition.defaultTempo.bpm, isNot(96));

      final selection = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'tech',
            type: PracticePlanBlockType.technique,
            duration: const Duration(minutes: 5),
          ),
        ],
        catalog: <PracticeDefinition>[definition],
        history: <PracticeHistoryEntry>[
          practiceHistoryFixture(
            id: 's1',
            definitionId: definition.id,
            createdAt: DateTime.utc(2026, 9, 1),
            highestStableTempoBpm: 96,
          ),
        ],
        activeGoals: const <LearningGoal>[],
      );

      expect(selection.targets[definition.id]!.config.effectiveTempo.bpm, 96);
      expect(selection.blocks.single.tempoBpm, 96);
      expect(
        selection.absentInputs,
        isNot(contains(PracticePlanInputCode.historyAbsent)),
      );
    });

    test('an out-of-range measured tempo falls back to the catalog default '
        'instead of producing an invalid block', () {
      final definition = _catalog().firstWhere(
        (d) => d.mode == PracticeMode.chordChanges,
      );

      final selection = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'tech',
            type: PracticePlanBlockType.technique,
            duration: const Duration(minutes: 5),
          ),
        ],
        catalog: <PracticeDefinition>[definition],
        history: <PracticeHistoryEntry>[
          practiceHistoryFixture(
            id: 's1',
            definitionId: definition.id,
            createdAt: DateTime.utc(2026, 9, 1),
            highestStableTempoBpm: 999,
          ),
        ],
        activeGoals: const <LearningGoal>[],
      );

      expect(
        selection.targets[definition.id]!.config.effectiveTempo,
        definition.defaultTempo,
      );
    });

    test('the least recently practiced candidate wins a tie', () {
      final candidates = _catalog()
          .where((d) => d.mode == PracticeMode.chordChanges)
          .toList();
      expect(candidates.length, greaterThanOrEqualTo(2));
      final recentlyPracticed = candidates.first;
      final untouched = candidates[1];

      final selection = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'tech',
            type: PracticePlanBlockType.technique,
            duration: const Duration(minutes: 5),
          ),
        ],
        catalog: candidates,
        history: <PracticeHistoryEntry>[
          practiceHistoryFixture(
            id: 's1',
            definitionId: recentlyPracticed.id,
            createdAt: DateTime.utc(2026, 9, 5),
          ),
        ],
        activeGoals: const <LearningGoal>[],
      );

      expect(selection.blocks.single.practiceTargetId, untouched.id);
    });
  });

  group('active goals steer the choice', () {
    test('a rhythm goal pulls a rhythm-tagged definition into the warmup', () {
      final withoutGoal = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'warm',
            type: PracticePlanBlockType.warmup,
            duration: const Duration(minutes: 2),
          ),
        ],
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: const <LearningGoal>[],
      );
      final withGoal = source.bind(
        templateBlocks: <PracticePlanBlock>[
          PracticePlanBlock.basic(
            id: 'warm',
            type: PracticePlanBlockType.warmup,
            duration: const Duration(minutes: 2),
          ),
        ],
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: <LearningGoal>[_goal(LearningGoalCategory.improveRhythm)],
      );

      final chosen = withGoal.targets[withGoal.blocks.single.practiceTargetId]!;
      expect(
        chosen.definition.skillTags.any(
          <String>{
            'rhythm',
            'rhythmOnly',
            'quarterNotes',
            'eighthNotes',
            'offBeat',
            'syncopation',
          }.contains,
        ),
        isTrue,
      );
      // The goal actually MOVED the choice — otherwise the cell would pass
      // even if goals were ignored entirely.
      expect(
        withGoal.blocks.single.practiceTargetId,
        isNot(withoutGoal.blocks.single.practiceTargetId),
      );
    });

    test('a goal category the shipped catalog cannot serve steers nothing, '
        'and the plan still binds', () {
      final neutral = source.bind(
        templateBlocks: _templateBlocks(),
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: const <LearningGoal>[],
      );
      final theory = source.bind(
        templateBlocks: _templateBlocks(),
        catalog: _catalog(),
        history: const <PracticeHistoryEntry>[],
        activeGoals: <LearningGoal>[
          _goal(LearningGoalCategory.understandTheory),
        ],
      );

      expect(
        theory.blocks.map((b) => b.practiceTargetId),
        neutral.blocks.map((b) => b.practiceTargetId),
      );
      expect(
        theory.absentInputs,
        isNot(contains(PracticePlanInputCode.goalsAbsent)),
      );
    });
  });

  test('no bound block declares a required skill id — the catalog tag '
      'vocabulary and the tutor taxonomy are disjoint', () {
    final selection = source.bind(
      templateBlocks: _templateBlocks(),
      catalog: _catalog(),
      history: const <PracticeHistoryEntry>[],
      activeGoals: const <LearningGoal>[],
    );

    expect(
      selection.blocks.every((block) => block.requiredSkillIds.isEmpty),
      isTrue,
    );
  });
}
