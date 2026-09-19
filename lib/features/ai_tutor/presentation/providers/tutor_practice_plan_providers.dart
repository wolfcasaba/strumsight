/// Practice-plan preview composition for the Tutor chat (E17-R04, ADR 0523).
///
/// Produces the draft `PracticePlanPreviewScreen` is handed — on the LOCAL
/// deterministic path only (§5.2: `aiTutorCloudEnabled` stays off, and this
/// file performs no I/O: every input is an already-resolved provider, so a
/// network probe around a read of [tutorPracticePlanProposalProvider] must
/// observe zero client creations).
///
/// Validation-context sources, per field (the honest map — where a field is
/// empty, the reason is measured, not assumed):
///
///  * `practiceTargetIds` — `practiceCatalogProvider`, the real Practice
///    catalog. The per-entry seed config is read from
///    `practiceSetupControllerProvider`, the SAME seed the Setup screen
///    starts from, so a compiled target block is bit-identical to what
///    Setup → Start would build.
///  * `userAvoidList` / `activeTuning` — `tutorProfileControllerProvider`:
///    the student's avoid list and the primary guitar's tuning
///    (`GuitarProfile.tuning`, the in-feature model of the learner's
///    instrument).
///  * `capabilities` — `practiceTarget` iff the Practice Engine V2 flag is
///    on AND the catalog is non-empty: the `/practice/*` routes are
///    registered only under that flag (`app_router.dart`), so a target that
///    cannot be launched must not validate as launchable. `songRange` is
///    never granted here — see `songIds`.
///  * `songIds` — EMPTY. The songbook (`songsProvider`) lives inside
///    `lib/features/songs/` and that feature's `public.dart` barrel exports
///    only the `Song` model; a cross-feature import must target the barrel
///    (`tool/check_architecture.dart`), and the barrel is outside this
///    round's allowed files. The deterministic template has no song blocks,
///    so nothing validates differently until a song-bearing draft exists.
///  * `availableSkillIds` — EMPTY. No provider in the tree exposes a skill
///    taxonomy (`SkillId` is used by the ai_tutor domain and the compiler;
///    there is no loader or provider behind it). Template blocks require no
///    skills.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../practice/public.dart';
import '../../application/planning/practice_plan_compiler.dart';
import '../../domain/models/practice_plan_block.dart';
import '../../domain/models/practice_plan_draft.dart';
import '../../domain/models/skill_node.dart';
import '../../domain/services/practice_plan_validator.dart';
import 'tutor_privacy_providers.dart';

/// The target duration the chat entry opens by default. One of the durations
/// `PracticePlanDraft.deterministicTemplate` supports (5, 10, 20, 30 min).
const Duration tutorPracticePlanDefaultDuration = Duration(minutes: 10);

/// What the chat hands the preview: the draft, the compilation context the
/// "Start plan" action compiles against, and the launchable catalog the
/// launch resolver picks from.
final class TutorPracticePlanProposal {
  const TutorPracticePlanProposal({
    required this.draft,
    required this.compilationContext,
    required this.launchableCatalog,
  });

  final PracticePlanDraft draft;
  final PracticePlanCompilationContext compilationContext;

  /// The catalog entries `/practice/setup?id=` can open right now — the
  /// full catalog under the Practice Engine V2 flag, empty otherwise.
  final List<PracticeDefinition> launchableCatalog;

  PracticePlanValidationContext get validationContext =>
      compilationContext.validationContext;
}

/// The local deterministic plan proposal for one target duration.
///
/// Family by target duration so the chat can offer more than one template
/// without a second composition path; the entry uses
/// [tutorPracticePlanDefaultDuration].
final tutorPracticePlanProposalProvider =
    Provider.family<TutorPracticePlanProposal, Duration>((ref, targetDuration) {
      final practiceEnabled = ref
          .watch(appConfigProvider)
          .flags
          .practiceEngineV2Enabled;
      final catalog = ref.watch(practiceCatalogProvider);
      final profile = ref.watch(tutorProfileControllerProvider);

      final launchableCatalog = practiceEnabled
          ? catalog
          : const <PracticeDefinition>[];
      final practiceTargets = <String, PracticePlanTargetInput>{
        for (final definition in launchableCatalog)
          definition.id: PracticePlanTargetInput(
            definition: definition,
            config: ref
                .read(practiceSetupControllerProvider(definition))
                .config,
          ),
      };

      final compilationContext = PracticePlanCompilationContext(
        songs: const [],
        practiceTargets: practiceTargets,
        userAvoidList: profile.student.avoidList.value.toSet(),
        activeTuning: profile.guitar.tuning.value,
        capabilities: <PracticePlanCapability>{
          if (launchableCatalog.isNotEmpty)
            PracticePlanCapability.practiceTarget,
        },
        availableSkillIds: const <SkillId>{},
      );

      return TutorPracticePlanProposal(
        draft: PracticePlanDraft.deterministicTemplate(
          targetDuration: targetDuration,
        ),
        compilationContext: compilationContext,
        launchableCatalog: launchableCatalog,
      );
    });
