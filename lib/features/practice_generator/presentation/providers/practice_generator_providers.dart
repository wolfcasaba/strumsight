/// The Practice Generator's ONE composition root (E15-R14, ADR 0482 / D1).
///
/// Every mandatory constructor dependency the 6 plan screens need
/// (`PlanSetupScreen`, `PlanPreviewScreen`, `PlanPrivacyScreen`,
/// `PlanChangeReviewScreen`, `TodayPlanScreen`, `WeeklyPlanScreen` — round
/// brief §0.0.B/R4) resolves from providers declared in this single file,
/// with kézzel written Riverpod 3 providers (CLAUDE.md: no codegen).
///
/// This file wires **route-less** composition only: it opens no route, sets
/// no feature flag, and creates no screen (ADR 0482 / D7 — the 6 screens
/// stay `unreachable` after this round). Wiring a screen into navigation is
/// `E15-R07 / F1`'s job.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../../../../core/i18n/locale_provider.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../application/controller/today_plan_controller.dart';
import '../../application/service/generation_orchestrator.dart';
import '../../application/usecase/delete_practice_planning_data.dart';
import '../../application/usecase/export_practice_planning_data.dart';
import '../../application/usecase/revise_practice_plan.dart';
import '../../application/usecase/start_plan_generation.dart';
import '../../data/local/generation_draft_repository.dart';
import '../../data/local/local_practice_evidence_repository.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart' show ExerciseCandidateResolver;
import '../../domain/model/weekly_availability.dart' show LocalDate;
import '../../domain/repository/practice_evidence_repository.dart';
import '../../domain/service/plan_validator.dart' show PlanValidationContext;
import '../controller/plan_preview_controller.dart';
import '../controller/plan_setup_controller.dart';

// ---------------------------------------------------------------------------
// Cross-cutting seams
// ---------------------------------------------------------------------------

/// Shared, deterministic clock — a plain function so every controller built
/// below reads the same wall-clock reading strategy tests can override.
final practiceGeneratorClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final practiceGeneratorIdGeneratorProvider = Provider<String Function()>(
  (ref) => createPlanSetupId,
);

/// Resolves the on-device directory `ExportPracticePlanningData` writes its
/// export file into. Real `path_provider` lookup — no fake, no seam that
/// only "looks" wired (mirrors `PlanPrivacyScreen.cacheDirectoryResolver`'s
/// test override, `lib/features/audio_analysis/application/
/// analysis_providers.dart`'s root-resolver precedent).
typedef PracticeGeneratorCacheDirectoryResolver = Future<Directory> Function();

final practiceGeneratorCacheDirectoryProvider =
    Provider<PracticeGeneratorCacheDirectoryResolver>(
      (ref) => getApplicationCacheDirectory,
    );

// ---------------------------------------------------------------------------
// Repositories — the real, persistent implementations (ADR 0482 / D2-D4)
// ---------------------------------------------------------------------------

final generationDraftRepositoryProvider = Provider<GenerationDraftRepository>(
  (ref) => GenerationDraftRepository(
    keyValueStore: ref.watch(keyValueStoreProvider),
  ),
);

/// Overridable production seam. Resolving a persisted prescription's
/// `exerciseId` back into a full `ExerciseCandidate` needs the live
/// exercise catalog; wiring that catalog is a later round's composition
/// (round brief §0.0.B/R4 note). Production boot injects the concrete
/// resolver; tests override it with a fixture (the same pattern as
/// `ai_tutor/presentation/providers/tutor_providers.dart`'s
/// `tutorOrchestratorProvider`).
final exerciseCandidateResolverProvider = Provider<ExerciseCandidateResolver>((
  ref,
) {
  throw UnimplementedError(
    'exerciseCandidateResolverProvider must be overridden — production '
    'wires it from the exercise catalog at boot; tests inject a fixture '
    'resolver.',
  );
});

final localPracticePlanRepositoryProvider =
    Provider<LocalPracticePlanRepository>(
      (ref) => LocalPracticePlanRepository(
        keyValueStore: ref.watch(keyValueStoreProvider),
        resolveCandidate: ref.watch(exerciseCandidateResolverProvider),
      ),
    );

/// The PERSISTENT `PracticeEvidenceRepository` (ADR 0482 / D2). Never
/// `InMemoryPracticeEvidenceRepository` — binding that fake here would make
/// `PlanPrivacyScreen`'s delete button a silent no-op the moment this
/// provider is rebuilt (CLAUDE.md "silent no-op" trap).
final practiceEvidenceRepositoryProvider = Provider<PracticeEvidenceRepository>(
  (ref) => LocalPracticeEvidenceRepository(
    keyValueStore: ref.watch(keyValueStoreProvider),
  ),
);

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// `GenerationOrchestrator` holds a broadcast `StreamController`
/// (`generation_orchestrator.dart:74`) — this provider is the one that
/// builds it, so it is the one that closes it (ADR 0482 / D8, the repo's
/// `liveFrameProvider` precedent: a provider that builds a resource-holding
/// object disposes that resource).
final generationOrchestratorProvider = Provider<GenerationOrchestrator>((ref) {
  final orchestrator = GenerationOrchestrator(
    activation: ref.watch(localPracticePlanRepositoryProvider),
  );
  ref.onDispose(() => unawaited(orchestrator.dispose()));
  return orchestrator;
});

/// Overridable production seam, mirroring [exerciseCandidateResolverProvider]:
/// turning a Setup-wizard draft into a `GenerationPlanInput` needs the
/// candidate catalog + evidence-ranking pipeline (ADR 0482 §Kontextus), which
/// is out of this round's scope (round brief STOP-protocol: "az ÚJ
/// start_plan_generation.dart use case KIZÁRÓLAG a meglévő
/// GenerationOrchestrator-t hívja, nem ír új generálási logikát").
final generationPlanInputBuilderProvider = Provider<GenerationPlanInputBuilder>(
  (ref) {
    throw UnimplementedError(
      'generationPlanInputBuilderProvider must be overridden — production '
      'wires it once the candidate catalog + evidence pipeline lands; '
      'tests inject a fixture builder.',
    );
  },
);

final startPlanGenerationProvider = Provider<StartPlanGeneration>(
  (ref) => StartPlanGeneration(
    orchestrator: ref.watch(generationOrchestratorProvider),
    buildInput: ref.watch(generationPlanInputBuilderProvider),
  ),
);

// ---------------------------------------------------------------------------
// Screen 1/6 — PlanSetupScreen
// ---------------------------------------------------------------------------

final planSetupControllerProvider = Provider<PlanSetupController>((ref) {
  final controller = PlanSetupController(
    draftRepository: ref.watch(generationDraftRepositoryProvider),
    clock: ref.watch(practiceGeneratorClockProvider),
    generateId: ref.watch(practiceGeneratorIdGeneratorProvider),
    locale: ref.watch(localeProvider)?.languageCode ?? 'en',
  );
  ref.onDispose(controller.dispose);
  return controller;
});

// ---------------------------------------------------------------------------
// Screen 2/6 — PlanPreviewScreen
// ---------------------------------------------------------------------------

/// The plan under preview is per-generation data, so the composition root
/// exposes a factory (not a plain instance) — the same shape as
/// `PlanPreviewScreen.withPlan`'s `buildController` parameter.
typedef PlanPreviewControllerFactory =
    PlanPreviewController Function({
      required AdaptivePracticePlan initialPlan,
      required PlanValidationContext validationContext,
    });

final planPreviewControllerFactoryProvider =
    Provider<PlanPreviewControllerFactory>((ref) {
      // ADR 0482 / D4: the concrete, real LocalPracticePlanRepository — never
      // a no-op GenerationPlanActivation.
      final activation = ref.watch(localPracticePlanRepositoryProvider);
      return ({required initialPlan, required validationContext}) =>
          PlanPreviewController(
            initialPlan: initialPlan,
            validationContext: validationContext,
            activation: activation,
          );
    });

// ---------------------------------------------------------------------------
// Screen 3/6 — PlanPrivacyScreen
// ---------------------------------------------------------------------------

final deletePracticePlanningDataProvider = Provider<DeletePracticePlanningData>(
  (ref) => DeletePracticePlanningData(
    planRepository: ref.watch(localPracticePlanRepositoryProvider),
    draftRepository: ref.watch(generationDraftRepositoryProvider),
    evidenceRepository: ref.watch(practiceEvidenceRepositoryProvider),
  ),
);

final exportPracticePlanningDataProvider = Provider<ExportPracticePlanningData>(
  (ref) => ExportPracticePlanningData(
    planRepository: ref.watch(localPracticePlanRepositoryProvider),
    evidenceRepository: ref.watch(practiceEvidenceRepositoryProvider),
    cacheDirectory: ref.watch(practiceGeneratorCacheDirectoryProvider),
    clock: ref.watch(practiceGeneratorClockProvider),
  ),
);

// ---------------------------------------------------------------------------
// Screen 4/6 — PlanChangeReviewScreen
// ---------------------------------------------------------------------------

final revisePracticePlanProvider = Provider<RevisePracticePlan>(
  (ref) => RevisePracticePlan(clock: ref.watch(practiceGeneratorClockProvider)),
);

// ---------------------------------------------------------------------------
// Screen 5/6 — TodayPlanScreen
// ---------------------------------------------------------------------------

final todayPlanControllerProvider = Provider<TodayPlanController>(
  (ref) =>
      TodayPlanController(clock: ref.watch(practiceGeneratorClockProvider)),
);

// ---------------------------------------------------------------------------
// Screen 6/6 — WeeklyPlanScreen
// ---------------------------------------------------------------------------

final practiceGeneratorTodayProvider = Provider<LocalDate>((ref) {
  final now = ref.watch(practiceGeneratorClockProvider)();
  return LocalDate(now.year, now.month, now.day);
});

final activePracticePlanProvider = FutureProvider<AdaptivePracticePlan?>((
  ref,
) async {
  final repository = ref.watch(localPracticePlanRepositoryProvider);
  final result = await repository.readActivePlan();
  return result.valueOrNull;
});
