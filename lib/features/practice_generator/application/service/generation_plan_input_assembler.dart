/// Production assembly of a Setup-wizard draft into a [GenerationPlanInput]
/// (E17-R05, ADR 0524 / §5.2).
///
/// This is the deterministic catalog + evidence + scheduling pipeline the
/// `generationPlanInputBuilderProvider` seam was left open for (E15-R14,
/// ADR 0482 §Kontextus). It composes ONLY the existing planner stages — the
/// same ones `ShadowPlanGenerator` evaluates offline — and adds no new
/// generation semantics (§3 "NINCS benne"):
///
///   1. the catalog snapshot comes from the injected [PracticeCatalogReader]
///      (production: the shipped Practice Engine catalog, §5.1);
///   2. the skill evidence comes from the injected, PERSISTENT
///      [PracticeEvidenceRepository] — the learner's real practice history,
///      queried per skill at `asOf` (§5.2: never a constant; an empty
///      history simply yields `SkillEstimate.unknown` per skill, which the
///      priority engine already treats as an assessment need);
///   3. priorities, candidate selection, time budgets and the weekly
///      schedule run through [SkillPriorityEngine], [CandidateSelector],
///      [TimeBudgetAllocator] and [WeeklyScheduler] unchanged.
///
/// `plannerAssistEnabled` is untouched: this path is fully deterministic
/// (§5.3).
library;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/candidate_decision.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/learner_constraints.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/schedule_decision.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/model/skill_priority.dart';
import '../../domain/model/time_budget.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/scheduling_policy.dart';
import '../../domain/repository/practice_evidence_repository.dart';
import '../../domain/service/candidate_selector.dart';
import '../../domain/service/plan_validator.dart';
import '../../domain/service/priority_engine.dart';
import '../../domain/service/time_budget_allocator.dart';
import '../../domain/service/weekly_scheduler.dart';
import '../port/practice_catalog_reader.dart';
import 'generation_orchestrator.dart';
import 'skill_estimate_reducer.dart';

/// Builds the immutable [GenerationPlanInput] for one draft.
final class GenerationPlanInputAssembler {
  GenerationPlanInputAssembler({
    required this.catalogReader,
    required this.evidenceRepository,
    required this.clock,
    required this.generateId,
    SkillEstimateReducer? skillEstimateReducer,
    SkillPriorityEngine? skillPriorityEngine,
    CandidateSelector? candidateSelector,
    TimeBudgetAllocator? timeBudgetAllocator,
    WeeklyScheduler? weeklyScheduler,
  }) : _skillEstimateReducer = skillEstimateReducer ?? SkillEstimateReducer(),
       _skillPriorityEngine =
           skillPriorityEngine ?? const SkillPriorityEngine(),
       _candidateSelector = candidateSelector ?? const CandidateSelector(),
       _timeBudgetAllocator =
           timeBudgetAllocator ?? const TimeBudgetAllocator(),
       _weeklyScheduler = weeklyScheduler ?? const WeeklyScheduler();

  final PracticeCatalogReader catalogReader;
  final PracticeEvidenceRepository evidenceRepository;
  final DateTime Function() clock;
  final String Function() generateId;

  final SkillEstimateReducer _skillEstimateReducer;
  final SkillPriorityEngine _skillPriorityEngine;
  final CandidateSelector _candidateSelector;
  final TimeBudgetAllocator _timeBudgetAllocator;
  final WeeklyScheduler _weeklyScheduler;

  /// The `GenerationPlanInputBuilder`-shaped entry point.
  GenerationPlanInput assemble(PracticeGenerationRequest request) {
    final catalog = catalogReader.read();
    final asOf = clock().toUtc();
    final planId = PlanId.generate(generateId);
    final initialRevisionId = RevisionId.generate(generateId);

    final priorities = rankSkills(
      request: request,
      catalog: catalog,
      asOf: asOf,
    );
    final runtimeContext = runtimeContextFor(
      catalog: catalog,
      constraints: request.constraints,
    );
    final selections = <CandidateDecision>[
      for (final priority in priorities)
        _candidateSelector.select(
          priority: priority,
          catalog: catalog,
          context: runtimeContext,
          seed: request.seed,
        ),
    ];

    final availability = request.availability;
    final schedule = _weeklyScheduler.schedule(
      WeeklyScheduleRequest(
        availability: availability,
        dayBudgets: _dayBudgets(availability, initialRevisionId),
        candidates: _scheduleCandidates(selections),
        today: _todayFor(availability, asOf),
      ),
    );

    return GenerationPlanInput(
      request: request,
      schedule: schedule,
      validationContext: validationContextFor(
        catalog: catalog,
        availability: availability,
        repairRevisionId: initialRevisionId,
        runtimeContext: runtimeContext,
      ),
      planId: planId,
      initialRevisionId: initialRevisionId,
    );
  }

  /// Ranks every skill the draft or the catalog can address, each estimated
  /// from the learner's stored evidence for that skill valid at [asOf].
  ///
  /// The skill universe is the union of the draft's goal skills and the
  /// catalog's skill targets: a skill nobody can practise (no candidate
  /// targets it) is still ranked so a goal can surface as unmet, and a
  /// skill nobody asked for is still ranked so evidence-backed weaknesses
  /// get coverage (the priority engine's coverage-debt factor).
  List<SkillPriority> rankSkills({
    required PracticeGenerationRequest request,
    required PracticeCatalogSnapshot catalog,
    required DateTime asOf,
  }) {
    final skillIds = <String>{
      for (final goal in request.goals) ...goal.skillIds,
      for (final candidate in catalog.candidates) ...candidate.skillTargets,
    }.toList()..sort();
    return _skillPriorityEngine.rank(
      asOf: asOf,
      candidates: <SkillPriorityCandidate>[
        for (final skillId in skillIds)
          _priorityCandidate(
            skillId: skillId,
            evidence: evidenceRepository.query(skillId: skillId, asOf: asOf),
            request: request,
            asOf: asOf,
          ),
      ],
    );
  }

  SkillPriorityCandidate _priorityCandidate({
    required String skillId,
    required List<SkillEvidence> evidence,
    required PracticeGenerationRequest request,
    required DateTime asOf,
  }) {
    DateTime? lastPracticedAt;
    for (final item in evidence) {
      if (lastPracticedAt == null || item.measuredAt.isAfter(lastPracticedAt)) {
        lastPracticedAt = item.measuredAt;
      }
    }
    return SkillPriorityCandidate(
      estimate: _skillEstimateReducer.reduce(
        skillId: skillId,
        evidence: evidence,
        asOf: asOf,
      ),
      goals: request.goals,
      evidence: evidence,
      lastPracticedAt: lastPracticedAt,
    );
  }

  /// The typed execution truth the selector and validator filter on,
  /// derived from the catalog and the learner's declared constraints.
  ///
  /// * `hardAvoidIdentities` — every `avoid`-category HARD constraint whose
  ///   value names a catalog exercise (by id or by full identity).
  /// * `confirmedDeviceCapabilityIdentities` — candidates whose only device
  ///   need is the microphone. Every shipped Practice Engine exercise runs
  ///   on the microphone the app exists for, and the practice session
  ///   itself requests the permission at launch
  ///   (`PracticeSessionController.permissions`) — so the capability is
  ///   confirmed by the executor, not assumed by the planner. A candidate
  ///   that needs the camera stays unconfirmed (no vision confirmation
  ///   source is wired here).
  /// * offline / asset / tuning confirmations stay empty: the catalog
  ///   reader marks built-in content offline-available itself, no shipped
  ///   exercise needs a song asset, and no tuning-confirmation source
  ///   exists (see `PracticeEngineCatalogReader`).
  static CandidateRuntimeContext runtimeContextFor({
    required PracticeCatalogSnapshot catalog,
    required LearnerConstraints constraints,
  }) {
    final avoidedValues = <String>{
      for (final constraint in constraints.constraints)
        if (constraint.category == ConstraintCategory.avoid &&
            constraint.strength == ConstraintStrength.hard)
          constraint.value,
    };
    final hardAvoid = <String>[];
    final microphoneOnly = <String>[];
    for (final candidate in catalog.candidates) {
      final identity = CandidateRuntimeContext.identityOf(candidate);
      if (avoidedValues.contains(identity) ||
          avoidedValues.contains(candidate.exerciseId)) {
        hardAvoid.add(identity);
      }
      final needsMicrophone =
          candidate.capabilities[ExerciseCapability.requiresMicrophone] ==
          CapabilitySupport.supported;
      final needsCamera =
          candidate.capabilities[ExerciseCapability.requiresCamera] ==
          CapabilitySupport.supported;
      if (needsMicrophone && !needsCamera) microphoneOnly.add(identity);
    }
    return CandidateRuntimeContext(
      hardAvoidIdentities: hardAvoid,
      confirmedDeviceCapabilityIdentities: microphoneOnly,
    );
  }

  /// The [PlanValidationContext] matching [runtimeContextFor]'s truth —
  /// the same identity sets, mapped through the validator's own identity
  /// scheme (the mirror of `ShadowPlanGenerator._validationContext`).
  static PlanValidationContext validationContextFor({
    required PracticeCatalogSnapshot catalog,
    required WeeklyAvailability availability,
    required RevisionId repairRevisionId,
    required CandidateRuntimeContext runtimeContext,
    AdaptivePracticePlan? previousSnapshot,
  }) {
    Iterable<String> references(Set<String> identities) => catalog.candidates
        .where(
          (candidate) => identities.contains(
            CandidateRuntimeContext.identityOf(candidate),
          ),
        )
        .map(PlanValidationContext.identityOf);
    return PlanValidationContext(
      catalog: catalog,
      availability: availability,
      repairRevisionId: repairRevisionId,
      previousSnapshot: previousSnapshot,
      confirmedAssetIdentities: references(
        runtimeContext.confirmedAssetIdentities,
      ),
      confirmedDeviceCapabilityIdentities: references(
        runtimeContext.confirmedDeviceCapabilityIdentities,
      ),
      confirmedOfflineIdentities: references(
        runtimeContext.confirmedOfflineIdentities,
      ),
      confirmedTuningIdentities: references(
        runtimeContext.confirmedTuningIdentities,
      ),
      hardAvoidIdentities: references(runtimeContext.hardAvoidIdentities),
    );
  }

  /// A validation context for an ALREADY-COMPILED plan (the preview of the
  /// active plan from Today, E17-R06): the catalog is the live snapshot and
  /// the availability is reconstructed from the plan's own persisted day
  /// budgets — the plan is the only surviving record of what it was
  /// compiled against once the Setup draft is gone.
  PlanValidationContext validationContextForPlan(AdaptivePracticePlan plan) {
    final catalog = catalogReader.read();
    return validationContextFor(
      catalog: catalog,
      availability: availabilityOfPlan(plan),
      repairRevisionId: RevisionId.generate(generateId),
      runtimeContext: runtimeContextFor(
        catalog: catalog,
        constraints: LearnerConstraints(const <LearnerConstraint>[]),
      ),
    );
  }

  /// Each plan day's budget as a hard, exact daily availability.
  static WeeklyAvailability availabilityOfPlan(AdaptivePracticePlan plan) {
    final days = <DailyAvailability>[];
    final seen = <LocalDate>{};
    for (final day in plan.days) {
      if (!seen.add(day.localDate)) continue;
      final minutes = (day.timeBudget.inSeconds / 60).ceil();
      days.add(
        DailyAvailability(
          date: day.localDate,
          status: AvailabilityStatus.available,
          minimumMinutes: 0,
          targetMinutes: minutes,
          maximumMinutes: minutes,
          maximumStrength: ConstraintStrength.hard,
        ),
      );
    }
    return WeeklyAvailability(days);
  }

  Map<LocalDate, TimeBudget> _dayBudgets(
    WeeklyAvailability availability,
    RevisionId initialRevisionId,
  ) => {
    for (final day in availability.days)
      if (day.isAvailable)
        day.date: _timeBudgetAllocator
            .allocate(
              availability: day,
              fromRevisionId: initialRevisionId,
              toRevisionId: RevisionId('${initialRevisionId.value}.budget'),
            )
            .budget,
  };

  /// The scheduler's `today`: the wall-clock date when it lies inside the
  /// requested week, otherwise the week's first date (a plan requested
  /// ahead of its start walks from its own first day).
  static LocalDate _todayFor(WeeklyAvailability availability, DateTime asOf) {
    final today = LocalDate(asOf.year, asOf.month, asOf.day);
    if (availability.days.isEmpty || availability.forDate(today) != null) {
      return today;
    }
    final dates = <LocalDate>[for (final day in availability.days) day.date];
    dates.sort((left, right) => left.compareTo(right));
    return dates.first;
  }

  /// One [ScheduleCandidate] per successful selection; a candidate whose
  /// executable duration is not positive cannot become a block
  /// (`PracticeBlock.estimatedElapsed` must be positive) and is left out.
  /// One [ScheduleCandidate] per DISTINCT selected exercise, in priority
  /// order. Two ranked skills may resolve to the same catalog exercise
  /// (its `skillTargets` cover both); `WeeklyScheduleRequest` rejects a
  /// repeated identity, so the first — highest-priority — selection wins
  /// and the exercise's own skill targets carry the rest.
  static Iterable<ScheduleCandidate> _scheduleCandidates(
    Iterable<CandidateDecision> selections,
  ) sync* {
    var index = 0;
    final seen = <String>{};
    for (final selection in selections) {
      final selected = selection.selected;
      if (selected == null) continue;
      final candidate = selected.candidate;
      if (candidate.supportedDurations.minimum <= Duration.zero) continue;
      if (!seen.add(candidate.sortKey)) continue;
      yield ScheduleCandidate(
        identity: candidate.sortKey,
        focus: index++ == 0
            ? CandidateFocus.primaryFocus
            : CandidateFocus.secondaryFocus,
        materialKind: CandidateMaterialKind.newMaterial,
        loadLevel: _loadLevel(candidate),
        duration: candidate.supportedDurations.minimum,
        skillTargets: candidate.skillTargets,
      );
    }
  }

  static LoadLevel _loadLevel(ExerciseCandidate candidate) {
    final profile = candidate.loadProfile;
    final levels = <LoadLevel>[
      profile.cognitive,
      profile.frettingHand,
      profile.pickingHand,
      profile.repetition,
      profile.novelty,
      profile.concentration,
    ];
    return levels.reduce(
      (current, next) => current.index >= next.index ? current : next,
    );
  }
}
