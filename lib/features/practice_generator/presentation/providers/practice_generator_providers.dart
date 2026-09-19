/// The Practice Generator's ONE composition root (E15-R14, ADR 0482 / D1).
///
/// Every mandatory constructor dependency the 6 plan screens need
/// (`PlanSetupScreen`, `PlanPreviewScreen`, `PlanPrivacyScreen`,
/// `PlanChangeReviewScreen`, `TodayPlanScreen`, `WeeklyPlanScreen` — round
/// brief §0.0.B/R4) resolves from providers declared in this single file,
/// with kézzel written Riverpod 3 providers (CLAUDE.md: no codegen).
///
/// This file wires **route-less** composition only: it opens no route, sets
/// no feature flag, and creates no screen (ADR 0482 / D7). Wiring a screen
/// into navigation is the router's (`PlanSetup`, `TodayPlan`) and
/// `TodayPlanScreen`'s (the four plan sub-screens, E17-R06) job.
///
/// E17-R05 closed the two production seams this root used to leave open:
/// [exerciseCandidateResolverProvider] reads the shipped Practice Engine
/// catalog, and [generationPlanInputBuilderProvider] assembles the draft
/// from that catalog plus the persistent practice-evidence history.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider;

import '../../../../core/foundation/app_result.dart';
import '../../../../core/i18n/effective_locale.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../application/controller/active_plan_controller.dart';
import '../../application/controller/today_plan_controller.dart';
import '../../application/service/generation_orchestrator.dart';
import '../../application/service/generation_plan_input_assembler.dart';
import '../../application/usecase/delete_practice_planning_data.dart';
import '../../application/usecase/export_practice_planning_data.dart';
import '../../application/usecase/propose_today_plan_change.dart';
import '../../application/usecase/revise_practice_plan.dart';
import '../../application/usecase/start_plan_generation.dart';
import '../../data/adapter/practice_engine_catalog_reader.dart';
import '../../application/port/catch_up_notice_log.dart';
import '../../data/local/catch_up_notice_store.dart';
import '../../data/local/generation_draft_repository.dart';
import '../../data/local/local_practice_evidence_repository.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../domain/id/planner_ids.dart' show RevisionId;
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart' show ExerciseCandidateResolver;
import '../../domain/model/practice_catalog_snapshot.dart';
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

/// The live exercise catalog as the planner's revisioned snapshot
/// (E17-R05, ADR 0524 / §5.1). Reads the Practice feature's ONE shipped
/// catalog through its public barrel (`practiceCatalogProvider`) — never a
/// generator-specific second list — so overriding the Practice catalog
/// repository (an empty catalog in a test, say) flows straight into every
/// consumer below.
final practiceCatalogSnapshotProvider = Provider<PracticeCatalogSnapshot>(
  (ref) => PracticeEngineCatalogReader(
    definitions: ref.watch(practiceCatalogProvider),
  ).read(),
);

/// Production seam, now closed (E17-R05 / A1): a persisted prescription's
/// `exerciseId` resolves back into the full `ExerciseCandidate` the live
/// catalog snapshot carries for it. An id the shipped catalog no longer
/// contains is a controlled failure of the read that asked for it
/// (`LocalPracticePlanRepository.readActivePlan` surfaces it as a
/// `Failure`, never as a silently substituted exercise). Tests may still
/// override this provider with a fixture resolver.
final exerciseCandidateResolverProvider = Provider<ExerciseCandidateResolver>((
  ref,
) {
  final snapshot = ref.watch(practiceCatalogSnapshotProvider);
  final byExerciseId = {
    for (final candidate in snapshot.candidates)
      candidate.exerciseId: candidate,
  };
  return (exerciseId) {
    final candidate = byExerciseId[exerciseId];
    if (candidate == null) {
      throw StateError(
        'No exercise "$exerciseId" in the shipped practice catalog '
        '(${snapshot.catalogRevision})',
      );
    }
    return candidate;
  };
});

final localPracticePlanRepositoryProvider =
    Provider<LocalPracticePlanRepository>(
      (ref) => LocalPracticePlanRepository(
        keyValueStore: ref.watch(keyValueStoreProvider),
        resolveCandidate: ref.watch(exerciseCandidateResolverProvider),
      ),
    );

/// The PERSISTENT `PracticeEvidenceRepository` (ADR 0482 / D2). Never the
/// never-forgets in-memory test-fake declared alongside the interface —
/// binding that fake here would make `PlanPrivacyScreen`'s delete button a
/// silent no-op the moment this provider is rebuilt (CLAUDE.md "silent
/// no-op" trap).
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
///
/// M5 fix (E15-R14 fix1, brief §5.5): `autoDispose`. A plain, non-disposed
/// `Provider` never tears down once the app has read it even once — the
/// `ref.onDispose` above would then only ever run when the WHOLE
/// `ProviderScope` is torn down (app shutdown), i.e. never in practice.
/// `autoDispose` closes the stream as soon as nothing watches this
/// provider anymore, exactly the posture brief §5.5 requires ("NEM
/// elfogadható gyengítés: lezáratlan `StreamController` egy globális,
/// sosem eldobott providerben"). A caller that needs the orchestrator to
/// survive an active generation must `ref.watch` it (keeping it alive for
/// as long as it is watched), the same `liveFrameProvider` precedent.
final generationOrchestratorProvider =
    Provider.autoDispose<GenerationOrchestrator>((ref) {
      final orchestrator = GenerationOrchestrator(
        activation: ref.watch(localPracticePlanRepositoryProvider),
      );
      ref.onDispose(() => unawaited(orchestrator.dispose()));
      return orchestrator;
    });

/// The deterministic catalog + evidence + scheduling pipeline behind
/// [generationPlanInputBuilderProvider] (E17-R05, ADR 0524 / §5.2). Its
/// evidence source is the PERSISTENT [practiceEvidenceRepositoryProvider]
/// — the learner's real practice history — never a constant.
final generationPlanInputAssemblerProvider =
    Provider<GenerationPlanInputAssembler>(
      (ref) => GenerationPlanInputAssembler(
        catalogReader: PracticeEngineCatalogReader(
          definitions: ref.watch(practiceCatalogProvider),
        ),
        evidenceRepository: ref.watch(practiceEvidenceRepositoryProvider),
        clock: ref.watch(practiceGeneratorClockProvider),
        generateId: ref.watch(practiceGeneratorIdGeneratorProvider),
      ),
    );

/// Production seam, now closed (E17-R05 / A1, A3): a Setup-wizard draft
/// becomes a `GenerationPlanInput` through
/// [generationPlanInputAssemblerProvider]. Tests may still override this
/// provider with a fixture builder.
final generationPlanInputBuilderProvider = Provider<GenerationPlanInputBuilder>(
  (ref) => ref.watch(generationPlanInputAssemblerProvider).assemble,
);

/// `autoDispose` because it watches [generationOrchestratorProvider] (M5):
/// a non-autoDispose provider watching an autoDispose one would itself
/// keep the orchestrator pinned forever, defeating the fix above (the
/// same `liveFrameProvider`-precedent rule applies transitively).
final startPlanGenerationProvider = Provider.autoDispose<StartPlanGeneration>(
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
    // MINOR-3 fix (E15-R14 fix1): `ref.read`, not `ref.watch`. The
    // `locale` constructor parameter is a plain `String` snapshot
    // (`PlanSetupController` lives in the forbidden `presentation/
    // controller/` zone for this round, so it cannot be changed to accept
    // a locale-reading function the way `clock` does). Watching the locale
    // here would rebuild — and so dispose — this whole provider on every
    // runtime locale change, discarding an in-progress wizard draft the
    // controller is holding in memory. `ref.read` takes the locale once,
    // at first build, without subscribing to later changes.
    //
    // M5 (re-audit 2026-09-08): `effectiveLocaleProvider`, NOT
    // `localeProvider`. The stored preference is `null` for "follow the
    // system" — its default — and `?? 'en'` turned that into an ENGLISH
    // generated plan on a Hungarian phone whose owner never opened the
    // language setting.
    locale: ref.read(effectiveLocaleProvider).languageCode,
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

/// The [PlanValidationContext] an already-compiled plan is previewed
/// against from Today (E17-R06): the live catalog snapshot plus the
/// availability reconstructed from the plan's own persisted day budgets.
final planValidationContextForPlanProvider =
    Provider<PlanValidationContext Function(AdaptivePracticePlan plan)>(
      (ref) => ref
          .watch(generationPlanInputAssemblerProvider)
          .validationContextForPlan,
    );

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

final proposeTodayPlanChangeProvider = Provider<ProposeTodayPlanChange>(
  (ref) => ProposeTodayPlanChange(
    activePlanController: ref.watch(activePlanControllerProvider),
    revisePracticePlan: ref.watch(revisePracticePlanProvider),
  ),
);

/// The proposal `PlanChangeReviewScreen` shows when opened from Today
/// (E17-R06 / §5.2): today's first pending block of the ACTIVE plan,
/// shortened to its catalog minimum. `null` when there is no active plan
/// or nothing is scheduled today. `autoDispose` so a review re-reads the
/// plan every time it opens; a read failure of the active plan surfaces as
/// this provider's own `AsyncError` (M4 discipline, never reclassified).
final todayPlanChangeProposalProvider =
    FutureProvider.autoDispose<TodayPlanChangeProposal?>((ref) async {
      // Every dependency is read synchronously, before the first `await`
      // — the same discipline as [activePracticePlanProvider].
      final repository = ref.watch(localPracticePlanRepositoryProvider);
      final propose = ref.watch(proposeTodayPlanChangeProvider);
      final today = ref.watch(practiceGeneratorTodayProvider);
      final planFuture = ref.watch(activePracticePlanProvider.future);

      final plan = await planFuture;
      if (plan == null) return null;
      final archive = await repository.readArchive(plan.id);
      final revisionCount = switch (archive) {
        Success<ArchivedPracticeLog>(:final value) => value.revisions.length,
        Failure<ArchivedPracticeLog>() => 0,
      };
      return propose(
        plan: plan,
        today: today(),
        currentRevisionNumber: revisionCount < 1 ? 1 : revisionCount,
      );
    }, retry: (retryCount, error) => null);

// ---------------------------------------------------------------------------
// Screen 5/6 — TodayPlanScreen
// ---------------------------------------------------------------------------

/// Where "this plan revision's catch-up explainer was already offered"
/// lives (ADR 0269 §5 — offered once, never nagged).
///
/// The PERSISTENT binding, never the in-memory default that ships with
/// `TodayPlanController`: an offer that is forgotten on every app start
/// would put the notice back on the Today screen every single launch,
/// which is the pressure the ADR's tone rule exists to prevent.
final catchUpNoticeLogProvider = Provider<CatchUpNoticeLog>(
  (ref) =>
      StoredCatchUpNoticeLog(keyValueStore: ref.watch(keyValueStoreProvider)),
);

final todayPlanControllerProvider = Provider<TodayPlanController>(
  (ref) => TodayPlanController(
    clock: ref.watch(practiceGeneratorClockProvider),
    catchUpNoticeLog: ref.watch(catchUpNoticeLogProvider),
  ),
);

/// The learner-side reschedules (skip / shorten / pause) over the ACTIVE
/// plan (javító sáv 2026-09-06 — until then the controller had zero callers
/// in `lib/`, so the Today screen's buttons stayed disabled). The block's
/// `exerciseId` is the catalog key, resolved through the same fail-loud
/// resolver the repository uses.
/// The pool a learner-initiated SWAP draws from: the very catalog snapshot
/// the generator itself planned with (javító sáv 2026-09-07 — until then
/// `ActivePlanController` had no swap operation at all, so the Today
/// screen's Swap button stayed disabled). The same-skill and contract
/// filters live in `ActivePlanController.swap`, so this provider hands over
/// the snapshot as-is instead of duplicating that rule here.
final activePlanAlternativeResolverProvider =
    Provider<ActivePlanAlternativeResolver>((ref) {
      final snapshot = ref.watch(practiceCatalogSnapshotProvider);
      return (_) => snapshot.candidates;
    });

final activePlanControllerProvider = Provider<ActivePlanController>((ref) {
  final generateId = ref.watch(practiceGeneratorIdGeneratorProvider);
  final resolve = ref.watch(exerciseCandidateResolverProvider);
  return ActivePlanController(
    generateRevisionId: () => RevisionId.generate(generateId),
    resolveCandidate: (block) => resolve(block.prescription.exerciseId),
    resolveAlternatives: ref.watch(activePlanAlternativeResolverProvider),
  );
});

// ---------------------------------------------------------------------------
// Screen 6/6 — WeeklyPlanScreen
// ---------------------------------------------------------------------------

/// Computes "today" at READ time — never a [LocalDate] cached in provider
/// state (M3 fix, E15-R14 fix1). A `Provider<LocalDate>` that calls the
/// clock once, in its build function, freezes on the FIRST read forever:
/// nothing invalidates a plain `Provider` at midnight, so the app's
/// "today" would silently stay stuck on whatever day it was first read —
/// exactly the "stale `DateTime.now()` in provider state" trap CLAUDE.md
/// warns about. This mirrors `TodayPlanController.resolve()`
/// (`today_plan_controller.dart:54`), which calls the clock on every
/// access rather than caching a `LocalDate` field; the same discipline
/// applies to [practiceGeneratorClockProvider] itself (a function, not a
/// cached `DateTime`). A caller (`WeeklyPlanScreen`'s eventual binding)
/// reads the provider to get the function, then calls it exactly when it
/// needs "today" — never earlier.
final practiceGeneratorTodayProvider = Provider<LocalDate Function()>((ref) {
  final clock = ref.watch(practiceGeneratorClockProvider);
  return () {
    final now = clock();
    return LocalDate(now.year, now.month, now.day);
  };
});

/// M4 fix (E15-R14 fix1): a read [Failure] surfaces as an `AsyncError`,
/// never as `null`. `LocalPracticePlanRepository.readActivePlan`'s own
/// doc-contract (`local_practice_plan_repository.dart:358-361`) is
/// explicit: "A present-but-corrupt pointer is a controlled failure,
/// never silently reclassified as first launch." Collapsing every
/// `Failure` to `null` via `.valueOrNull` would make `WeeklyPlanScreen`
/// show "no plan yet" for a learner whose plan is actually present but
/// unreadable — the exact silent-reclassification the contract forbids.
/// Throwing the [AppFailure] lets `FutureProvider`'s implicit
/// `AsyncValue.guard` turn it into `AsyncError`, which the UI can render
/// distinctly from "no active plan".
///
/// `retry: (_, _) => null` — Riverpod 3 auto-retries a `FutureProvider`
/// that throws a plain (non-`ProviderException`) error, with a growing
/// backoff, by default. A read failure here is [AppFailure.retryable]
/// `false` by construction (`StorageFailure`'s default): a corrupt
/// pointer will not become readable by simply trying again, so retrying
/// only delays the `AsyncError` the UI is waiting to render. Disabling
/// it is a correctness fix, not just a test-timing one — measured via a
/// hang: without it, awaiting `activePracticePlanProvider.future` on a
/// corrupt store did not settle within a 30s test timeout.
final activePracticePlanProvider = FutureProvider<AdaptivePracticePlan?>((
  ref,
) async {
  final repository = ref.watch(localPracticePlanRepositoryProvider);
  final result = await repository.readActivePlan();
  return switch (result) {
    Success<AdaptivePracticePlan?>(:final value) => value,
    Failure<AdaptivePracticePlan?>(:final error) => throw error,
  };
}, retry: (retryCount, error) => null);
