// WP-H2 (2026-09-06) — the use case that assembles all six
// `PracticePlanCompilationContext` inputs, runs `PracticePlanCompiler`, and
// reports what is honestly ABSENT.
//
// Every input is the real shipped type: the built-in practice catalog, real
// `PracticeHistoryEntry` records, real `LearningGoal`s and real `Song`s.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/ai_tutor/application/planning/compile_practice_plan_preview.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_compiler.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_target_source.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';

import '../../../support/practice_history_fixtures.dart';

const _labels = PracticePlanPreviewLabels(
  title: '10-minute practice plan',
  groundedInEvidence: 'GROUNDED',
  withoutGoals: 'NO_GOALS',
  withoutHistory: 'NO_HISTORY',
  withoutPracticeTargets: 'NO_TARGETS',
);

const _standardTuning = <String>['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];

List<PracticeDefinition> _catalog() => const BuiltinPracticeCatalog().all();

LearningGoal _rhythmGoal({
  LearningGoalStatus status = LearningGoalStatus.active,
}) => LearningGoal(
  id: 'goal-rhythm',
  statement: 'Get steadier in rhythm',
  category: LearningGoalCategory.improveRhythm,
  priority: LearningGoalPriority.high,
  status: status,
);

Song _song() => const Song(
  id: 'song-1',
  name: 'Campfire',
  chords: <String>['C', 'G'],
  pattern: <StrumDirection?>[StrumDirection.down, null],
  bpm: 90,
);

PracticePlanPreviewCompilation _compile({
  Duration targetDuration = const Duration(minutes: 10),
  List<PracticeDefinition>? catalog,
  List<PracticeHistoryEntry> history = const <PracticeHistoryEntry>[],
  List<LearningGoal> goals = const <LearningGoal>[],
  List<Song> songs = const <Song>[],
  List<String> userAvoidList = const <String>[],
  List<String> activeTuning = _standardTuning,
  Set<String> extraAbsentInputs = const <String>{},
}) => const CompilePracticePlanPreview()(
  targetDuration: targetDuration,
  labels: _labels,
  catalog: catalog ?? _catalog(),
  history: history,
  goals: goals,
  songs: songs,
  userAvoidList: userAvoidList,
  activeTuning: activeTuning,
  extraAbsentInputs: extraAbsentInputs,
);

void main() {
  group('a seeded profile compiles a non-empty, runnable plan', () {
    test('the draft carries real blocks and the compiler accepts it', () {
      final result = _compile(
        goals: <LearningGoal>[_rhythmGoal()],
        history: <PracticeHistoryEntry>[
          practiceHistoryFixture(
            id: 's1',
            definitionId: 'builtin.quarterDownstrokes.v1',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ],
        songs: <Song>[_song()],
      );

      expect(result.draft.blocks, isNotEmpty);
      expect(result.draft.title, '10-minute practice plan');
      expect(result.draft.goalIds, <String>['goal-rhythm']);
      expect(result.draft.targetDuration, const Duration(minutes: 10));
      expect(
        result.draft.blocks.fold(
          Duration.zero,
          (total, block) => total + block.duration,
        ),
        const Duration(minutes: 10),
      );
      expect(result.compilation, isA<Success<CompiledPracticePlan>>());

      final compiled =
          (result.compilation as Success<CompiledPracticePlan>).value;
      // At least one block is genuinely runnable — it carries the definition
      // and config the Practice Engine needs.
      expect(
        compiled.blocks.any(
          (block) => block.definition != null && block.config != null,
        ),
        isTrue,
      );
    });

    test('the rationale names the evidence when goals and history exist', () {
      final result = _compile(
        goals: <LearningGoal>[_rhythmGoal()],
        history: <PracticeHistoryEntry>[
          practiceHistoryFixture(
            id: 's1',
            definitionId: 'builtin.quarterDownstrokes.v1',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      expect(result.draft.rationale, contains('GROUNDED'));
      expect(result.draft.rationale, isNot(contains('NO_GOALS')));
      expect(result.draft.rationale, isNot(contains('NO_HISTORY')));
    });

    test('the validation context lists exactly the produced target ids', () {
      final result = _compile();

      final boundIds = <String>{
        for (final block in result.draft.blocks)
          if (block.practiceTargetId != null) block.practiceTargetId!,
      };
      expect(result.validationContext.practiceTargetIds, boundIds);
      expect(result.compilationContext.practiceTargets.keys.toSet(), boundIds);
      expect(result.validationContext.availableSkillIds, <SkillId>{
        for (final node in SkillTaxonomy.initial.nodes) node.id,
      });
    });
  });

  group('absent inputs are reported, never defaulted away', () {
    test('a brand-new user: no goal, no history, no songbook, no tuning', () {
      final result = _compile(activeTuning: const <String>[]);

      expect(
        result.absentInputs,
        containsAll(<String>[
          PracticePlanInputCode.goalsAbsent,
          PracticePlanInputCode.historyAbsent,
          PracticePlanInputCode.songsAbsent,
          PracticePlanInputCode.tuningAbsent,
        ]),
      );
      expect(result.draft.rationale, contains('NO_GOALS'));
      expect(result.draft.rationale, contains('NO_HISTORY'));
      expect(result.draft.rationale, isNot(contains('GROUNDED')));
    });

    test('an INACTIVE goal is not an active goal', () {
      final result = _compile(
        goals: <LearningGoal>[_rhythmGoal(status: LearningGoalStatus.inactive)],
      );

      expect(result.draft.goalIds, isEmpty);
      expect(result.absentInputs, contains(PracticePlanInputCode.goalsAbsent));
    });

    test('an unreadable history is distinguished from an empty one', () {
      final result = _compile(
        extraAbsentInputs: const <String>{
          PracticePlanInputCode.historyUnavailable,
        },
      );

      expect(
        result.absentInputs,
        contains(PracticePlanInputCode.historyUnavailable),
      );
      expect(result.draft.rationale, contains('NO_HISTORY'));
    });

    test('an empty catalog leaves timer-only blocks and says so in the '
        'rationale', () {
      final result = _compile(catalog: const <PracticeDefinition>[]);

      expect(
        result.absentInputs,
        contains(PracticePlanInputCode.practiceTargetsAbsent),
      );
      expect(result.draft.rationale, contains('NO_TARGETS'));
      // The plan still validates — a timer block is honest, not invalid.
      expect(result.compilation, isA<Success<CompiledPracticePlan>>());
      final compiled =
          (result.compilation as Success<CompiledPracticePlan>).value;
      expect(
        compiled.blocks.every(
          (block) => block.definition == null && block.config == null,
        ),
        isTrue,
      );
    });
  });

  group('capabilities follow the real inventory', () {
    test('songRange is NOT granted with an empty songbook', () {
      final result = _compile();

      expect(
        result.validationContext.capabilities,
        isNot(contains(PracticePlanCapability.songRange)),
      );
      expect(
        result.validationContext.capabilities,
        contains(PracticePlanCapability.practiceTarget),
      );
      expect(result.validationContext.songIds, isEmpty);
    });

    test('songRange IS granted once the songbook has a song', () {
      final result = _compile(songs: <Song>[_song()]);

      expect(
        result.validationContext.capabilities,
        contains(PracticePlanCapability.songRange),
      );
      expect(result.validationContext.songIds, <String>{'song-1'});
    });

    test('practiceTarget is NOT granted when nothing could be bound', () {
      final result = _compile(catalog: const <PracticeDefinition>[]);

      expect(result.validationContext.capabilities, isEmpty);
    });
  });

  group('the compiler gate still holds', () {
    test('a user avoid entry turns the plan invalid with a stable code', () {
      final result = _compile(
        userAvoidList: const <String>[PracticePlanBlockType.rhythm],
      );

      expect(result.compilation, isA<Failure<CompiledPracticePlan>>());
      expect(
        result.validationContext.userAvoidList,
        contains(PracticePlanBlockType.rhythm),
      );
    });

    test('an unsupported plan length is refused, not silently rounded', () {
      expect(
        () => _compile(targetDuration: const Duration(minutes: 7)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () =>
            _compile(targetDuration: const Duration(minutes: 10, seconds: 30)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('every supported plan length compiles', () {
      for (final minutes in supportedPracticePlanDurationMinutes) {
        final result = _compile(targetDuration: Duration(minutes: minutes));
        expect(
          result.compilation,
          isA<Success<CompiledPracticePlan>>(),
          reason: '$minutes-minute plan',
        );
        expect(result.draft.source, PracticePlanSource.deterministicTemplate);
      }
    });
  });
}
