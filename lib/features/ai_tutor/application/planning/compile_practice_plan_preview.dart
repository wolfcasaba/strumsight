/// The application-layer use case behind the tutor's practice-plan preview
/// (WP-H2, 2026-09-06).
///
/// Before this file the whole tutor planning path was unreferenced: nothing in
/// `lib/` called [PracticePlanCompiler] or
/// [PracticePlanDraft.deterministicTemplate], and the compiler's
/// `practiceTargets` input had no producer at all
/// (`docs/ui/remaining-wiring-blockers.md` §2).
///
/// The use case assembles all six [PracticePlanCompilationContext] inputs from
/// real app data, runs the compiler, and yields the draft + validation context
/// pair [PracticePlanPreviewScreen] needs — plus the set of inputs that are
/// honestly ABSENT, so the caller can say so instead of pretending.
///
/// Where each compilation input comes from (all read through public feature
/// boundaries; the Riverpod wiring lives in
/// `presentation/providers/practice_plan_providers.dart`):
///
/// | input | source |
/// |---|---|
/// | `practiceTargets` | [PracticePlanTargetSource] — built-in practice catalog + practice history |
/// | `songs` | the user's songbook (`songs/public.dart`) |
/// | `userAvoidList` | `StudentProfile.avoidList` (tutor profile surface) |
/// | `activeTuning` | `GuitarProfile.tuning` (tutor profile surface) |
/// | `capabilities` | derived from the two inventories above — granted only when the inventory is non-empty |
/// | `availableSkillIds` | `SkillTaxonomy.initial` (the shipped tutor taxonomy) |
library;

import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';

import '../../domain/models/learning_goal.dart';
import '../../domain/models/practice_plan_block.dart';
import '../../domain/models/practice_plan_draft.dart';
import '../../domain/models/skill_node.dart';
import '../../domain/services/practice_plan_validator.dart';
import 'practice_plan_compiler.dart';
import 'practice_plan_target_source.dart';

/// The plan lengths, in whole minutes, that
/// [PracticePlanDraft.deterministicTemplate] supports. Any other duration
/// makes the template throw, so callers pick from this set.
const Set<int> supportedPracticePlanDurationMinutes = <int>{5, 10, 20, 30};

/// Localized text the use case cannot produce itself.
///
/// The draft's `title` and `rationale` are user-visible strings rendered
/// verbatim by [PracticePlanPreviewScreen], so they must come from
/// `AppLocalizations`. The application layer never touches `AppLocalizations`
/// — the caller passes the already-localized sentences in, and the use case
/// picks the ones its MEASUREMENT justifies.
final class PracticePlanPreviewLabels {
  const PracticePlanPreviewLabels({
    required this.title,
    required this.groundedInEvidence,
    required this.withoutGoals,
    required this.withoutHistory,
    required this.withoutPracticeTargets,
  });

  /// The plan title, e.g. "10-minute practice plan".
  final String title;

  /// Used when at least one of goals / history was present.
  final String groundedInEvidence;

  /// Used when no ACTIVE learning goal exists.
  final String withoutGoals;

  /// Used when the practice history is empty or unreadable.
  final String withoutHistory;

  /// Used when at least one block could not be bound to an exercise.
  final String withoutPracticeTargets;
}

/// Everything the preview route needs, including what is missing.
final class PracticePlanPreviewCompilation {
  PracticePlanPreviewCompilation({
    required this.draft,
    required this.compilationContext,
    required this.compilation,
    required Set<String> absentInputs,
  }) : absentInputs = Set<String>.unmodifiable(absentInputs);

  /// The draft the preview screen renders and the user may edit.
  final PracticePlanDraft draft;

  /// The full compilation context — kept so the screen's accept action can
  /// recompile the (possibly user-edited) draft against the same inventory.
  final PracticePlanCompilationContext compilationContext;

  /// The compiler's verdict for [draft] as produced here. A [Failure] carries
  /// a `ValidationFailure` whose cause is the [PracticePlanValidationResult].
  final AppResult<CompiledPracticePlan> compilation;

  /// [PracticePlanInputCode] values measured as absent for this compilation.
  final Set<String> absentInputs;

  /// The validation context the preview screen re-validates against.
  PracticePlanValidationContext get validationContext =>
      compilationContext.validationContext;
}

/// Assembles the compilation context, runs the compiler, and reports what is
/// absent. Pure — every input is supplied by the caller.
final class CompilePracticePlanPreview {
  const CompilePracticePlanPreview({
    this.targetSource = const PracticePlanTargetSource(),
    this.compiler = const PracticePlanCompiler(),
  });

  final PracticePlanTargetSource targetSource;
  final PracticePlanCompiler compiler;

  PracticePlanPreviewCompilation call({
    required Duration targetDuration,
    required PracticePlanPreviewLabels labels,
    required List<PracticeDefinition> catalog,
    required List<PracticeHistoryEntry> history,
    required List<LearningGoal> goals,
    required List<Song> songs,
    required List<String> userAvoidList,
    required List<String> activeTuning,
    Set<String> extraAbsentInputs = const <String>{},
  }) {
    final minutes = targetDuration.inMinutes;
    if (Duration(minutes: minutes) != targetDuration ||
        !supportedPracticePlanDurationMinutes.contains(minutes)) {
      throw ArgumentError.value(
        targetDuration,
        'targetDuration',
        'Deterministic templates support '
            '${supportedPracticePlanDurationMinutes.join(', ')} minutes.',
      );
    }

    final activeGoals = <LearningGoal>[
      for (final goal in goals)
        if (goal.status == LearningGoalStatus.active) goal,
    ];
    final template = PracticePlanDraft.deterministicTemplate(
      targetDuration: targetDuration,
    );
    final selection = targetSource.bind(
      templateBlocks: template.blocks,
      catalog: catalog,
      history: history,
      activeGoals: activeGoals,
    );

    final absentInputs = <String>{
      ...selection.absentInputs,
      ...extraAbsentInputs,
      if (songs.isEmpty) PracticePlanInputCode.songsAbsent,
      if (activeTuning.isEmpty) PracticePlanInputCode.tuningAbsent,
    };

    final draft = template.copyWith(
      title: labels.title,
      blocks: selection.blocks,
      goalIds: <String>[for (final goal in activeGoals) goal.id],
      rationale: _rationale(labels, absentInputs),
    );

    final context = PracticePlanCompilationContext(
      songs: songs,
      practiceTargets: selection.targets,
      userAvoidList: userAvoidList.toSet(),
      activeTuning: activeTuning,
      // A capability is granted only when the inventory behind it actually
      // exists. Granting `songRange` with an empty songbook would let an
      // unbuildable block validate.
      capabilities: <PracticePlanCapability>{
        if (selection.targets.isNotEmpty) PracticePlanCapability.practiceTarget,
        if (songs.isNotEmpty) PracticePlanCapability.songRange,
      },
      availableSkillIds: <SkillId>{
        for (final node in SkillTaxonomy.initial.nodes) node.id,
      },
    );

    return PracticePlanPreviewCompilation(
      draft: draft,
      compilationContext: context,
      compilation: compiler.compile(draft: draft, context: context),
      absentInputs: absentInputs,
    );
  }

  String _rationale(
    PracticePlanPreviewLabels labels,
    Set<String> absentInputs,
  ) {
    final goalsAbsent = absentInputs.contains(
      PracticePlanInputCode.goalsAbsent,
    );
    final historyAbsent =
        absentInputs.contains(PracticePlanInputCode.historyAbsent) ||
        absentInputs.contains(PracticePlanInputCode.historyUnavailable);
    final sentences = <String>[
      if (!goalsAbsent || !historyAbsent) labels.groundedInEvidence,
      if (goalsAbsent) labels.withoutGoals,
      if (historyAbsent) labels.withoutHistory,
      if (absentInputs.contains(PracticePlanInputCode.practiceTargetsAbsent))
        labels.withoutPracticeTargets,
    ];
    return sentences.join(' ');
  }
}
