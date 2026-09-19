/// Riverpod wiring for the tutor practice-plan flow (WP-H2, 2026-09-06).
///
/// Two seams:
///
/// * [compilePracticePlanPreviewProvider] — reads the six compilation inputs
///   from the REAL app providers and runs `CompilePracticePlanPreview`. Async
///   only because the practice history is a repository read; everything else
///   is a synchronous provider read.
/// * [practicePlanLaunchProvider] — the accept handoff. It recompiles the
///   (possibly user-edited) draft and hands the first runnable block to the
///   Practice Engine through the SAME `practicePrepareSinkProvider` the
///   Practice Setup screen uses. That is the only receiving side that exists
///   today; saving a tutor plan has none (see the screen's
///   `saveUnavailableMessage`).
///
/// A history read FAILURE is not silently turned into "no history": it is
/// reported as [PracticePlanInputCode.historyUnavailable] so the rationale can
/// say the tempos are catalog defaults because the store could not be read.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';
import '../../application/planning/compile_practice_plan_preview.dart';
import '../../application/planning/practice_plan_compiler.dart';
import '../../application/planning/practice_plan_target_source.dart';
import '../../domain/models/practice_plan_draft.dart';
import 'tutor_privacy_providers.dart';

/// Compiles a preview for [targetDuration] from live app data.
typedef PracticePlanPreviewBuilder =
    Future<PracticePlanPreviewCompilation> Function({
      required Duration targetDuration,
      required PracticePlanPreviewLabels labels,
    });

final compilePracticePlanPreviewProvider = Provider<PracticePlanPreviewBuilder>(
  (ref) {
    return ({required targetDuration, required labels}) async {
      final catalog = ref.read(practiceCatalogProvider);
      final songs = ref.read(songsProvider);
      final goals = ref.read(tutorLearningGoalControllerProvider);
      final profile = ref.read(tutorProfileControllerProvider);

      final loaded = await ref.read(practiceHistoryRepositoryProvider).load();
      final history = switch (loaded) {
        Success<List<PracticeHistoryEntry>>(:final value) => value,
        Failure<List<PracticeHistoryEntry>>() => const <PracticeHistoryEntry>[],
      };
      final historyUnavailable = loaded is Failure<List<PracticeHistoryEntry>>;

      return const CompilePracticePlanPreview()(
        targetDuration: targetDuration,
        labels: labels,
        catalog: catalog,
        history: history,
        goals: goals,
        songs: songs,
        userAvoidList: profile.student.avoidList.value,
        activeTuning: profile.guitar.tuning.value,
        extraAbsentInputs: <String>{
          if (historyUnavailable) PracticePlanInputCode.historyUnavailable,
        },
      );
    };
  },
);

/// What happened when the user accepted a plan.
enum PracticePlanLaunchOutcome {
  /// The first runnable block was handed to the Practice Engine.
  launched,

  /// The (edited) draft no longer compiles — nothing was launched.
  invalidPlan,

  /// The plan compiles but holds no block with a runnable exercise
  /// (e.g. every block is a plain timer). Nothing was launched.
  noRunnableBlock,
}

/// Hands the first runnable block of [draft] to the Practice Engine.
typedef PracticePlanLauncher =
    PracticePlanLaunchOutcome Function(
      PracticePlanDraft draft,
      PracticePlanCompilationContext context,
    );

final practicePlanLaunchProvider = Provider<PracticePlanLauncher>((ref) {
  return (draft, context) {
    final compiled = const PracticePlanCompiler().compile(
      draft: draft,
      context: context,
    );
    switch (compiled) {
      case Failure<CompiledPracticePlan>():
        return PracticePlanLaunchOutcome.invalidPlan;
      case Success<CompiledPracticePlan>(:final value):
        for (final block in value.blocks) {
          final definition = block.definition;
          final config = block.config;
          if (definition == null || config == null) continue;
          ref
              .read(practicePrepareSinkProvider)
              .call(PreparePractice(definition: definition, config: config));
          return PracticePlanLaunchOutcome.launched;
        }
        return PracticePlanLaunchOutcome.noRunnableBlock;
    }
  };
});
