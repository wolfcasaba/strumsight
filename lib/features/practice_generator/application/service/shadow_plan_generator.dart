/// End-to-end deterministic plan generation for evaluation only.
library;

import '../../../../core/foundation/app_result.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/candidate_decision.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/plan_validation_issue.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/schedule_decision.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/model/skill_priority.dart';
import '../../domain/model/time_budget.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/scheduling_policy.dart';
import '../../domain/service/candidate_selector.dart';
import '../../domain/service/plan_validator.dart';
import '../../domain/service/priority_engine.dart';
import '../../domain/service/time_budget_allocator.dart';
import '../../domain/service/weekly_scheduler.dart';
import 'generation_orchestrator.dart';
import 'skill_estimate_reducer.dart';

/// All explicit inputs for one non-persistent evaluation run.
final class ShadowPlanInput {
  ShadowPlanInput({
    required this.request,
    required this.catalog,
    required Iterable<SkillEvidence> evidence,
    required DateTime asOf,
    required this.planId,
    required this.initialRevisionId,
    CandidateRuntimeContext? candidateContext,
  }) : evidence = List<SkillEvidence>.unmodifiable(evidence),
       asOf = asOf.toUtc(),
       candidateContext = candidateContext ?? CandidateRuntimeContext();

  final PracticeGenerationRequest request;
  final PracticeCatalogSnapshot catalog;
  final List<SkillEvidence> evidence;
  final DateTime asOf;
  final PlanId planId;
  final RevisionId initialRevisionId;
  final CandidateRuntimeContext candidateContext;
}

/// Observable evaluation result. [persistentWrites] is always zero: the
/// injected activation records its invocation but owns no repository.
final class ShadowPlanRun {
  const ShadowPlanRun({
    required this.result,
    required this.activationCalls,
    required this.validationIssues,
    required this.priorities,
    required this.schedule,
  });

  final AppResult<AdaptivePracticePlan> result;
  final int activationCalls;
  final List<PlanValidationIssue> validationIssues;
  final List<SkillPriority> priorities;
  final WeeklyScheduleDecision schedule;

  int get persistentWrites => 0;

  int get hardViolationCount =>
      validationIssues.where((issue) => issue.blocksActivation).length;
}

/// Composes the existing deterministic planner stages without making a plan
/// active in local storage. It is deliberately not a feature-flagged product
/// entry point; rollout remains a separate human decision.
final class ShadowPlanGenerator {
  ShadowPlanGenerator({
    SkillEstimateReducer? skillEstimateReducer,
    SkillPriorityEngine? skillPriorityEngine,
    CandidateSelector? candidateSelector,
    TimeBudgetAllocator? timeBudgetAllocator,
    WeeklyScheduler? weeklyScheduler,
    PlanValidator? planValidator,
  }) : _skillEstimateReducer = skillEstimateReducer ?? SkillEstimateReducer(),
       _skillPriorityEngine =
           skillPriorityEngine ?? const SkillPriorityEngine(),
       _candidateSelector = candidateSelector ?? const CandidateSelector(),
       _timeBudgetAllocator =
           timeBudgetAllocator ?? const TimeBudgetAllocator(),
       _weeklyScheduler = weeklyScheduler ?? const WeeklyScheduler(),
       _planValidator = planValidator ?? const PlanValidator();

  final SkillEstimateReducer _skillEstimateReducer;
  final SkillPriorityEngine _skillPriorityEngine;
  final CandidateSelector _candidateSelector;
  final TimeBudgetAllocator _timeBudgetAllocator;
  final WeeklyScheduler _weeklyScheduler;
  final PlanValidator _planValidator;

  Future<ShadowPlanRun> generate(ShadowPlanInput input) async {
    final priorities = _priorities(input);
    final selections = <CandidateDecision>[
      for (final priority in priorities)
        _candidateSelector.select(
          priority: priority,
          catalog: input.catalog,
          context: input.candidateContext,
          seed: input.request.seed,
        ),
    ];
    final availability = input.request.availability;
    final dayBudgets = _dayBudgets(input);
    final schedule = _weeklyScheduler.schedule(
      WeeklyScheduleRequest(
        availability: availability,
        dayBudgets: dayBudgets,
        candidates: _scheduleCandidates(selections),
        today: availability.days.first.date,
      ),
    );
    final validationContext = _validationContext(input);
    final activation = _ShadowActivation();
    final orchestrator = GenerationOrchestrator(
      activation: activation,
      validator: _planValidator,
    );
    final result = await orchestrator.generate(
      GenerationPlanInput(
        request: input.request,
        schedule: schedule,
        validationContext: validationContext,
        planId: input.planId,
        initialRevisionId: input.initialRevisionId,
      ),
    );
    await orchestrator.dispose();

    final plan = result.valueOrNull;
    final issues = plan == null
        ? const <PlanValidationIssue>[]
        : _planValidator.validate(plan, validationContext).issues;
    return ShadowPlanRun(
      result: result,
      activationCalls: activation.calls,
      validationIssues: List<PlanValidationIssue>.unmodifiable(issues),
      priorities: List<SkillPriority>.unmodifiable(priorities),
      schedule: schedule,
    );
  }

  List<SkillPriority> _priorities(ShadowPlanInput input) {
    final skillIds = <String>{
      for (final goal in input.request.goals) ...goal.skillIds,
      for (final evidence in input.evidence) evidence.skillId,
    }.toList()..sort();
    return _skillPriorityEngine.rank(
      asOf: input.asOf,
      candidates: <SkillPriorityCandidate>[
        for (final skillId in skillIds)
          SkillPriorityCandidate(
            estimate: _skillEstimateReducer.reduce(
              skillId: skillId,
              evidence: input.evidence.where((item) => item.skillId == skillId),
              asOf: input.asOf,
            ),
            goals: input.request.goals,
            evidence: input.evidence.where((item) => item.skillId == skillId),
          ),
      ],
    );
  }

  Map<LocalDate, TimeBudget> _dayBudgets(ShadowPlanInput input) => {
    for (final day in input.request.availability.days)
      if (day.isAvailable)
        day.date: _timeBudgetAllocator
            .allocate(
              availability: day,
              fromRevisionId: input.initialRevisionId,
              toRevisionId: RevisionId(
                '${input.initialRevisionId.value}.budget',
              ),
            )
            .budget,
  };

  Iterable<ScheduleCandidate> _scheduleCandidates(
    Iterable<CandidateDecision> selections,
  ) sync* {
    var index = 0;
    for (final selection in selections) {
      final selected = selection.selected;
      if (selected == null) continue;
      yield ScheduleCandidate(
        identity: selected.candidate.sortKey,
        focus: index++ == 0
            ? CandidateFocus.primaryFocus
            : CandidateFocus.secondaryFocus,
        materialKind: CandidateMaterialKind.newMaterial,
        loadLevel: _loadLevel(selected.candidate),
        duration: selected.candidate.supportedDurations.minimum,
        skillTargets: selected.candidate.skillTargets,
      );
    }
  }

  PlanValidationContext _validationContext(ShadowPlanInput input) {
    final selectedContext = input.candidateContext;
    String reference(ExerciseCandidate candidate) =>
        PlanValidationContext.identityOf(candidate);
    Iterable<String> references(Set<String> identities) => input
        .catalog
        .candidates
        .where(
          (candidate) => identities.contains(
            CandidateRuntimeContext.identityOf(candidate),
          ),
        )
        .map(reference);
    return PlanValidationContext(
      catalog: input.catalog,
      availability: input.request.availability,
      repairRevisionId: input.initialRevisionId,
      confirmedAssetIdentities: references(
        selectedContext.confirmedAssetIdentities,
      ),
      confirmedDeviceCapabilityIdentities: references(
        selectedContext.confirmedDeviceCapabilityIdentities,
      ),
      confirmedOfflineIdentities: references(
        selectedContext.confirmedOfflineIdentities,
      ),
      confirmedTuningIdentities: references(
        selectedContext.confirmedTuningIdentities,
      ),
      hardAvoidIdentities: references(selectedContext.hardAvoidIdentities),
    );
  }

  LoadLevel _loadLevel(ExerciseCandidate candidate) {
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

final class _ShadowActivation implements GenerationPlanActivation {
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    calls += 1;
  }
}
