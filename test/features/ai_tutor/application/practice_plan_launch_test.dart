// E17-R04 (ADR 0523 §5.1) — the launch resolver behind "Start plan".
//
// Pure-domain cells: which catalog entry a compiled plan opens through the
// EXISTING `/practice/setup?id=` route. The resolver never builds a session
// itself; it only picks the definition id the Setup screen will look up.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_compiler.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_launch.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/practice/public.dart';

void main() {
  group('practiceModeForPlanBlockType', () {
    test('maps every playable block type onto a catalog mode', () {
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.warmup),
        PracticeMode.rhythmOnly,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.rhythm),
        PracticeMode.rhythmOnly,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.technique),
        PracticeMode.strumPattern,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.speedBuilder),
        PracticeMode.strumPattern,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.chordChange),
        PracticeMode.chordChanges,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.songRange),
        PracticeMode.chordProgression,
      );
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.freePractice),
        PracticeMode.freePractice,
      );
    });

    test('reflection, rest and unknown types are not playable', () {
      expect(
        practiceModeForPlanBlockType(PracticePlanBlockType.reflection),
        isNull,
      );
      expect(practiceModeForPlanBlockType(PracticePlanBlockType.rest), isNull);
      expect(practiceModeForPlanBlockType('somethingElse'), isNull);
    });
  });

  group('resolvePracticePlanLaunchTarget', () {
    test('an empty catalog launches nothing', () {
      final plan = _plan(<CompiledPracticePlanBlock>[
        _basic('w', PracticePlanBlockType.warmup),
      ]);

      expect(
        resolvePracticePlanLaunchTarget(
          plan: plan,
          catalog: const <PracticeDefinition>[],
        ),
        isNull,
      );
    });

    test('a block compiled against a catalog definition launches it', () {
      final strum = _definition('builtin.strum', PracticeMode.strumPattern);
      final rhythm = _definition('builtin.rhythm', PracticeMode.rhythmOnly);
      final plan = _plan(<CompiledPracticePlanBlock>[
        CompiledPracticePlanBlock(
          id: 'target',
          type: PracticePlanBlockType.technique,
          duration: const Duration(minutes: 3),
          definition: strum,
          config: null,
          compiledTarget: null,
        ),
      ]);

      expect(
        resolvePracticePlanLaunchTarget(plan: plan, catalog: [rhythm, strum]),
        const PracticePlanLaunchTarget(
          blockId: 'target',
          definitionId: 'builtin.strum',
        ),
      );
    });

    test('a synthesised (non-catalog) definition falls back to the mode '
        'mapping of its block type', () {
      final synthesised = _definition(
        'song.abc',
        PracticeMode.chordProgression,
      );
      final progression = _definition(
        'builtin.progression',
        PracticeMode.chordProgression,
      );
      final plan = _plan(<CompiledPracticePlanBlock>[
        CompiledPracticePlanBlock(
          id: 'song',
          type: PracticePlanBlockType.songRange,
          duration: const Duration(minutes: 4),
          definition: synthesised,
          config: null,
          compiledTarget: null,
        ),
      ]);

      expect(
        resolvePracticePlanLaunchTarget(plan: plan, catalog: [progression]),
        const PracticePlanLaunchTarget(
          blockId: 'song',
          definitionId: 'builtin.progression',
        ),
      );
    });

    test('plan order wins: the first playable block picks the target', () {
      final strum = _definition('builtin.strum', PracticeMode.strumPattern);
      final rhythm = _definition('builtin.rhythm', PracticeMode.rhythmOnly);
      final plan = _plan(<CompiledPracticePlanBlock>[
        _basic('reflect', PracticePlanBlockType.reflection),
        _basic('tech', PracticePlanBlockType.technique),
        _basic('warm', PracticePlanBlockType.warmup),
      ]);

      expect(
        resolvePracticePlanLaunchTarget(plan: plan, catalog: [rhythm, strum]),
        const PracticePlanLaunchTarget(
          blockId: 'tech',
          definitionId: 'builtin.strum',
        ),
      );
    });

    test('a plan of only reflection and rest blocks launches nothing', () {
      final plan = _plan(<CompiledPracticePlanBlock>[
        _basic('r1', PracticePlanBlockType.reflection),
        _basic('r2', PracticePlanBlockType.rest),
      ]);

      expect(
        resolvePracticePlanLaunchTarget(
          plan: plan,
          catalog: [_definition('builtin.strum', PracticeMode.strumPattern)],
        ),
        isNull,
      );
    });

    test('the local deterministic template compiles and launches its '
        'warm-up onto the first rhythm-only catalog entry', () {
      final rhythmA = _definition('builtin.rhythm.a', PracticeMode.rhythmOnly);
      final rhythmB = _definition('builtin.rhythm.b', PracticeMode.rhythmOnly);
      final draft = PracticePlanDraft.deterministicTemplate(
        targetDuration: const Duration(minutes: 10),
      );
      final compiled = const PracticePlanCompiler().compile(
        draft: draft,
        context: PracticePlanCompilationContext(
          songs: const [],
          practiceTargets: const <String, PracticePlanTargetInput>{},
          userAvoidList: const <String>{},
          activeTuning: const <String>[],
          capabilities: const <PracticePlanCapability>{},
          availableSkillIds: const <SkillId>{},
        ),
      );

      expect(compiled.isSuccess, isTrue);
      expect(
        resolvePracticePlanLaunchTarget(
          plan: compiled.valueOrNull!,
          catalog: [rhythmA, rhythmB],
        ),
        const PracticePlanLaunchTarget(
          blockId: 'template.10.0',
          definitionId: 'builtin.rhythm.a',
        ),
      );
    });
  });
}

CompiledPracticePlan _plan(List<CompiledPracticePlanBlock> blocks) =>
    CompiledPracticePlan(
      draftId: 'plan',
      blocks: blocks,
      isOfflineRunnable: true,
    );

CompiledPracticePlanBlock _basic(String id, String type) =>
    CompiledPracticePlanBlock(
      id: id,
      type: type,
      duration: const Duration(minutes: 2),
      definition: null,
      config: null,
      compiledTarget: null,
    );

PracticeDefinition _definition(String id, PracticeMode mode) =>
    PracticeDefinition(
      id: id,
      schemaVersion: 1,
      titleKey: 'practice.title',
      descriptionKey: 'practice.description',
      mode: mode,
      source: PracticeSource.builtin,
      meter: const Meter(beatsPerBar: 4),
      defaultTempo: const Tempo(120),
      totalBeats: const BeatPosition(1920),
      events: const <PracticeEvent>[
        PracticeEvent(
          id: 'event',
          position: BeatPosition(0),
          direction: StrumDirection.down,
        ),
      ],
      scoringProfile: ScoringProfile.legacyLearnParity,
      skillTags: const <String>[],
    );
