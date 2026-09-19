// WP-H2 (2026-09-06) — the accept handoff.
//
// "Start" is the ONLY receiving side that exists for a tutor practice plan:
// the first runnable block goes to the Practice Engine through the same
// `practicePrepareSinkProvider` the Practice Setup screen uses. These cells
// measure that the command actually arrives, and that the two honest
// non-launch outcomes are distinct rather than a silent no-op.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/planning/compile_practice_plan_preview.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/practice_plan_providers.dart';
import 'package:strumsight/features/practice/public.dart';

const _labels = PracticePlanPreviewLabels(
  title: '10-minute practice plan',
  groundedInEvidence: 'grounded',
  withoutGoals: 'no goals',
  withoutHistory: 'no history',
  withoutPracticeTargets: 'no targets',
);

PracticePlanPreviewCompilation _compilation({
  List<PracticeDefinition>? catalog,
}) => const CompilePracticePlanPreview()(
  targetDuration: const Duration(minutes: 10),
  labels: _labels,
  catalog: catalog ?? const BuiltinPracticeCatalog().all(),
  history: const <PracticeHistoryEntry>[],
  goals: const [],
  songs: const [],
  userAvoidList: const <String>[],
  activeTuning: const <String>['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
);

void main() {
  late List<PreparePractice> commands;
  late ProviderContainer container;

  setUp(() {
    commands = <PreparePractice>[];
    container = ProviderContainer(
      overrides: <Override>[
        practicePrepareSinkProvider.overrideWithValue(commands.add),
      ],
    );
    addTearDown(container.dispose);
  });

  test('the first runnable block reaches the Practice Engine sink', () {
    final compilation = _compilation();
    final outcome = container.read(practicePlanLaunchProvider)(
      compilation.draft,
      compilation.compilationContext,
    );

    expect(outcome, PracticePlanLaunchOutcome.launched);
    expect(commands, hasLength(1));

    final firstBound = compilation.draft.blocks.firstWhere(
      (block) => block.adapter == PracticePlanBlockAdapter.practiceTarget,
    );
    final expected = compilation
        .compilationContext
        .practiceTargets[firstBound.practiceTargetId]!;
    expect(commands.single.definition.id, expected.definition.id);
    expect(commands.single.config, expected.config);
    // The plan's own block duration travelled with the command.
    expect(commands.single.config.sessionTimeout, firstBound.duration);
  });

  test('a plan with no runnable block reports it instead of no-opping', () {
    final compilation = _compilation(catalog: const <PracticeDefinition>[]);
    final outcome = container.read(practicePlanLaunchProvider)(
      compilation.draft,
      compilation.compilationContext,
    );

    expect(outcome, PracticePlanLaunchOutcome.noRunnableBlock);
    expect(commands, isEmpty);
  });

  test('a user edit that breaks validation launches nothing', () {
    final compilation = _compilation();
    // Drop a block without adjusting the target duration — exactly what the
    // preview screen's delete action produces before it recomputes, and what
    // the validator's duration-mismatch code exists for.
    final broken = compilation.draft.copyWith(
      blocks: compilation.draft.blocks.sublist(1),
    );

    final outcome = container.read(practicePlanLaunchProvider)(
      broken,
      compilation.compilationContext,
    );

    expect(outcome, PracticePlanLaunchOutcome.invalidPlan);
    expect(commands, isEmpty);
  });
}
