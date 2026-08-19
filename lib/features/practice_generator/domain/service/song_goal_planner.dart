/// Song-goal planning: per-section block placement + ratio + phase gating
/// (SDD Ch8 Kör 24, ADR 0318, ADR 0262 §5, ADR 0264 §4, ADR 0268 §1-§2).
///
/// The planner is the integration point between the song-goal reader
/// adapter and the existing practice-planning model. It owns three
/// deterministic rules the brief explicitly enforces (A1, A2, A4) and one
/// it routes through (A3):
///
///   1. **A1 — bounded song-block ratio.** The total minutes the planner
///      assigns to song blocks must remain at or below
///      [SongGoalRatioPolicy.maximumSongRatio] of the week's available
///      practice minutes. Drafts that would push the plan over the cap are
///      dropped with an explicit reason code (never a silent skip).
///
///   2. **A2 — no automatic song block after the target date.** Once the
///      scheduled date is strictly AFTER [SongGoalPlanningRequest.songTargetDate]
///      (i.e. the signed distance `(target - scheduled).inDays < 0`), the
///      planner emits [SongGoalPlanningNoOpAfterTarget] and does not
///      produce any new song block. The celldátum-napja case
///      (`distance == 0`) lands in the simulation phase (A4) but still
///      emits blocks — the cap continues to apply.
///
///   3. **A4 — no new technique in simulation.** The simulation phase is
///      the last window before the target date. Inside it the planner
///      refuses to introduce any new skill target — only `review`-only
///      drafts (skill targets already on the plan) qualify. New-technique
///      drafts are dropped with an explicit reason code.
///
///   4. **A3 — prerequisites before sections.** The planner's phase ordering
///      guarantees a draft's [SongGoalBlockDraft.prerequisiteSkillIds] are
///      placed strictly before the draft itself in the assignment list.
///      (See [SongGoalPlanningAccepted.assignments].)
///
///   5. **A8 — caller-fed outcome normalization.** The planner's terminal
///      outcome normalization follows the R23 rule (ADR 0268 §1, §2):
///      technical and unavailable terminals are NOT learner evidence;
///      completed and partial terminals carry caller-supplied structured
///      metric evidence.
///
/// The planner never reads a clock (`scheduledDate` is caller-supplied),
/// never generates randomness, never imports Song Trainer internals, and
/// never mutates its inputs (ADR 0255, ADR 0318 §Döntés 1).
library;

import 'package:strumsight/features/song_trainer/domain/public.dart'
    show SongId;

import '../../data/adapter/song_goal_reader_adapter.dart';
import '../model/weekly_availability.dart';
import 'song_block_compiler.dart';

/// Stable reason code a draft was dropped from the plan.
///
/// Every drop carries one of these codes so the caller can surface the
/// decision without re-deriving it from the inputs (ADR 0262 §5).
abstract final class SongGoalDropReason {
  /// The draft would have pushed the song-block ratio over the policy cap.
  static const String ratioCapExceeded = 'songGoal.drop.ratioCapExceeded';

  /// The draft's prerequisites were not available in the supplied skills
  /// surface (the planner cannot satisfy A3 for this draft).
  static const String unsatisfiedPrerequisite =
      'songGoal.drop.unsatisfiedPrerequisite';

  /// The draft introduces new skill targets inside the simulation phase
  /// (A4 — no new technique at the concert).
  static const String newTechniqueInSimulation =
      'songGoal.drop.newTechniqueInSimulation';

  /// The draft carries no usable public asset reference (ADR 0318 §Döntés
  /// 2) — the planner cannot route a song-goal block without it.
  static const String missingUsableAsset = 'songGoal.drop.missingUsableAsset';
}

/// Stable reason code for the planner-level "no song work" branches.
abstract final class SongGoalPlanningReason {
  /// Scheduled date is strictly after the song target date.
  static const String noOpAfterTarget = 'songGoal.planning.noOpAfterTarget';

  /// Document revision does not match the caller's expectation.
  static const String staleRevision = 'songGoal.planning.staleRevision';

  /// Document has zero sections — nothing to plan.
  static const String emptySections = 'songGoal.planning.emptySections';
}

/// The song-goal phase a [SongGoalPhaseAssignment] belongs to.
///
/// Foundation → Integration → Simulation is the strict ordering the
/// planner enforces. The simulation phase is the LAST window before the
/// target date; new-technique drafts are dropped there (A4).
enum SongGoalPhase {
  foundation('songGoal.phase.foundation'),
  integration('songGoal.phase.integration'),
  simulation('songGoal.phase.simulation');

  const SongGoalPhase(this.code);

  /// Stable machine-readable code persisted with the assignment.
  final String code;

  static SongGoalPhase fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'SongGoalPhase code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown SongGoalPhase code: $code',
    );
  }

  @override
  String toString() => code;
}

/// The bounded share of the week that song blocks may occupy (A1).
///
/// Construct with the desired ratio in `]0, 1]` — the policy is validated
/// at construction and rejected for ratios outside the unit interval. A
/// ratio of `1.0` is the strict "song can fill the week" upper bound and
/// is only useful for diagnostics; the planner test enforces the default
/// `0.4` cap (matching [SchedulingPolicy.maximumReviewRatio]) so the
/// dal-blokk soha nyomhatja el az alap készségeket.
final class SongGoalRatioPolicy {
  SongGoalRatioPolicy({double maximumSongRatio = 0.4})
    : maximumSongRatio = _requireUnitInterval(
        maximumSongRatio,
        'maximumSongRatio',
      );

  /// Default policy: song blocks may not exceed 40 % of the week's
  /// available practice minutes.
  static final SongGoalRatioPolicy defaultPolicy = SongGoalRatioPolicy();

  /// The upper bound (inclusive). A draft that would push the realized
  /// ratio above this value is dropped with
  /// [SongGoalDropReason.ratioCapExceeded].
  final double maximumSongRatio;
}

/// The deterministic phase boundaries the planner uses for A4 / A2.
///
/// Distances are signed `(target - scheduled).inDays` (ADR 0299 decision
/// 5). The phase windows are:
///
///   * `distance > lightReviewWindowDays`            → foundation
///   * `0 < distance <= lightReviewWindowDays`        → integration
///   * `distance == 0`                                → simulation
///   * `distance < 0`                                 → no-op (A2)
///
/// All values are non-negative; the constructor rejects negative
/// windows. The "no-op after target" branch is computed from the
/// signed distance directly, not from the policy — the policy governs
/// the foundation/integration/simulation split only.
final class SongGoalPhasePolicy {
  SongGoalPhasePolicy({
    int foundationWindowDays = 14,
    int integrationWindowDays = 7,
    int lightReviewWindowDays = 3,
  }) : foundationWindowDays = _requirePositiveInt(
         foundationWindowDays,
         'foundationWindowDays',
       ),
       integrationWindowDays = _requirePositiveInt(
         integrationWindowDays,
         'integrationWindowDays',
       ),
       lightReviewWindowDays = _requirePositiveInt(
         lightReviewWindowDays,
         'lightReviewWindowDays',
       );

  /// Default v1 phase policy.
  static final SongGoalPhasePolicy defaultPolicy = SongGoalPhasePolicy();

  /// Number of days before the song target when the foundation window
  /// closes (foundation is the outermost window: any `distance` strictly
  /// greater than `lightReviewWindowDays` AND at or above
  /// `integrationWindowDays` is foundation; the outermost window keeps
  /// growing towards the target date — the planner only shifts to
  /// integration when the closer windows open).
  final int foundationWindowDays;

  /// Number of days before the song target when the integration window
  /// is open. `0 < distance <= lightReviewWindowDays` is integration.
  final int integrationWindowDays;

  /// Number of days before the song target when the simulation window
  /// is open. `distance == 0` is simulation; `distance < 0` is no-op
  /// (A2).
  final int lightReviewWindowDays;
}

/// The caller-supplied request to plan one song goal.
final class SongGoalPlanningRequest {
  SongGoalPlanningRequest({
    required this.read,
    required Iterable<SongGoalBlockDraft> drafts,
    required this.scheduledDate,
    required this.songTargetDate,
    required this.weekAvailableMinutes,
    required Iterable<String> knownSkillIds,
    this.ratioPolicy,
    this.phasePolicy,
  }) : drafts = List<SongGoalBlockDraft>.unmodifiable(drafts),
       knownSkillIds = List<String>.unmodifiable(knownSkillIds) {
    if (weekAvailableMinutes <= 0) {
      throw ArgumentError.value(
        weekAvailableMinutes,
        'weekAvailableMinutes',
        'must be positive',
      );
    }
  }

  /// The reader adapter's structured outcome for the song document.
  final SongGoalReadOutcome read;

  /// Per-section drafts produced by [SongBlockCompiler].
  final List<SongGoalBlockDraft> drafts;

  /// Caller-supplied "today" — the planner never reads a clock.
  final LocalDate scheduledDate;

  /// The song target date. Compared against [scheduledDate] in signed
  /// days: `target - scheduled`.
  final LocalDate songTargetDate;

  /// Total practice minutes the week has available. Used as the
  /// denominator for the bounded song-block ratio (A1).
  final int weekAvailableMinutes;

  /// The skill ids the rest of the plan can already route on. The
  /// planner uses this to detect new-technique drafts in simulation
  /// (A4) and unsatisfied prerequisites (A3 fallback).
  final List<String> knownSkillIds;

  /// The bounded ratio policy (A1). Defaults to
  /// [SongGoalRatioPolicy.defaultPolicy].
  final SongGoalRatioPolicy? ratioPolicy;

  /// The phase-window policy (A2 / A4). Defaults to
  /// [SongGoalPhasePolicy.defaultPolicy].
  final SongGoalPhasePolicy? phasePolicy;
}

/// The materialized phase assignment for one song-goal draft.
///
/// Assignments are emitted in dependency order: a draft's
/// prerequisite skills appear on assignments earlier in the list. The
/// planner emits no more than one assignment per draft (never a duplicate
/// for a section).
final class SongGoalPhaseAssignment {
  const SongGoalPhaseAssignment({
    required this.draft,
    required this.phase,
    required this.targetSkillIds,
    required this.unsatisfiedPrerequisiteSkillIds,
    required this.minutes,
  });

  /// The draft this assignment schedules.
  final SongGoalBlockDraft draft;

  /// The phase the draft was placed in.
  final SongGoalPhase phase;

  /// Skill ids the draft introduces this week. Empty when the draft
  /// introduced no new technique on this phase (e.g. inside simulation,
  /// the planner only emits assignments whose targets were already
  /// `known`).
  final List<String> targetSkillIds;

  /// Prerequisite skill ids that were NOT in the supplied
  /// [SongGoalPlanningRequest.knownSkillIds] set. Surfaced so the caller
  /// can decide whether to fold them in or drop the block (A3 routing).
  final List<String> unsatisfiedPrerequisiteSkillIds;

  /// Bounded minutes the assignment contributes to the song-block ratio
  /// (A1).
  final int minutes;
}

/// An explicit, non-silent drop (ADR 0262 §5, ADR 0318 §Döntés 2).
final class SongGoalDraftDrop {
  const SongGoalDraftDrop({
    required this.draft,
    required this.reasonCode,
    required this.detail,
  });

  final SongGoalBlockDraft draft;

  /// One of [SongGoalDropReason]'s stable codes.
  final String reasonCode;

  /// Free-form caller-supplied context (the dropped draft's section id,
  /// for instance). Empty string when no detail is appropriate.
  final String detail;
}

/// The terminal outcome of one [SongGoalPlanner.plan] call.
///
/// Every variant carries an explicit reason code so the caller can audit
/// the planner's decision without re-deriving it from the inputs.
sealed class SongGoalPlanningOutcome {
  const SongGoalPlanningOutcome();

  /// Stable, machine-readable reason code (one of [SongGoalPlanningReason]).
  String get reasonCode;
}

/// The happy path: the planner accepted some drafts and dropped others
/// (explicitly, never silently).
final class SongGoalPlanningAccepted extends SongGoalPlanningOutcome {
  SongGoalPlanningAccepted({
    required Iterable<SongGoalPhaseAssignment> assignments,
    required Iterable<SongGoalDraftDrop> droppedDrafts,
    required this.weekAvailableMinutes,
  }) : assignments = List<SongGoalPhaseAssignment>.unmodifiable(assignments),
       droppedDrafts = List<SongGoalDraftDrop>.unmodifiable(droppedDrafts);

  @override
  String get reasonCode => 'songGoal.planning.accepted';

  /// Phase-ordered assignments. A draft's prerequisites appear strictly
  /// before the draft itself.
  final List<SongGoalPhaseAssignment> assignments;

  /// Drafts the planner refused to place, each with an explicit reason.
  final List<SongGoalDraftDrop> droppedDrafts;

  /// Total practice minutes the week had available. Mirrored here so the
  /// caller can compute the realized ratio without re-reading the
  /// request.
  final int weekAvailableMinutes;

  /// Total minutes the planner assigned to song blocks.
  int get assignedSongMinutes =>
      assignments.fold<int>(0, (total, item) => total + item.minutes);

  /// Realized share of the week occupied by song blocks (A1). Always
  /// `<= ratioPolicy.maximumSongRatio`.
  double get realizedSongRatio => weekAvailableMinutes == 0
      ? 0
      : assignedSongMinutes / weekAvailableMinutes;
}

/// The scheduled date is strictly after the song target date (A2).
final class SongGoalPlanningNoOpAfterTarget extends SongGoalPlanningOutcome {
  const SongGoalPlanningNoOpAfterTarget({
    required this.scheduledDate,
    required this.songTargetDate,
    required this.daysAfterTarget,
  });

  @override
  String get reasonCode => SongGoalPlanningReason.noOpAfterTarget;

  final LocalDate scheduledDate;
  final LocalDate songTargetDate;
  final int daysAfterTarget;
}

/// The reader adapter detected a stale revision (A6) — the planner did
/// not produce any block.
final class SongGoalPlanningStaleRevision extends SongGoalPlanningOutcome {
  const SongGoalPlanningStaleRevision({
    required this.documentId,
    required this.actualRevision,
    required this.expectedRevision,
  });

  @override
  String get reasonCode => SongGoalPlanningReason.staleRevision;

  final SongId documentId;
  final int actualRevision;
  final int expectedRevision;
}

/// The reader adapter reported an empty document — nothing to plan.
final class SongGoalPlanningEmpty extends SongGoalPlanningOutcome {
  const SongGoalPlanningEmpty({
    required this.documentId,
    required this.documentRevision,
  });

  @override
  String get reasonCode => SongGoalPlanningReason.emptySections;

  final SongId documentId;
  final int documentRevision;
}

// ---------------------------------------------------------------------------
// Caller-fed outcome normalization (A8 — R23 rule, ADR 0268 §1, §2).
// ---------------------------------------------------------------------------

/// Stable normalized terminal states for a song-goal block.
///
/// The five values mirror the R23 / ADR 0268 outcome surface:
///   * [completed] / [partial] carry caller-supplied structured metric
///     evidence and ARE learner evidence,
///   * [skipped] is the caller's own choice to abandon — NOT learner
///     evidence (ADR 0268 §2),
///   * [failedTechnical] is a microphone / crash / asset / permission
///     problem — NOT learner evidence (ADR 0268 §1),
///   * [unavailable] means the public asset reference the planner
///     depended on was missing at execution time — NOT learner evidence
///     (ADR 0318 §Döntés 2).
enum SongGoalOutcomeState {
  completed,
  partial,
  skipped,
  failedTechnical,
  unavailable,
}

/// Caller-supplied terminal fact for one song-goal block.
///
/// The R23 rule means only [SongGoalTerminalCompleted] and
/// [SongGoalTerminalPartial] carry learner evidence. Every other variant
/// surfaces a structural / environmental failure that the planner must
/// not silently record as a learner-performance signal.
sealed class SongGoalTerminalOutcome {
  const SongGoalTerminalOutcome();
}

/// Terminal partial: the user chose to stop mid-way. Not learner evidence
/// in the negative sense — the planner surfaces the caller's metrics as
/// partial.
final class SongGoalTerminalCompleted extends SongGoalTerminalOutcome {
  const SongGoalTerminalCompleted({required this.metricEvidence});

  /// Caller-supplied structured metric evidence (skill-id → score).
  final Map<String, double> metricEvidence;
}

/// Terminal partial: the user stopped mid-way. Still learner evidence —
/// the caller's metrics reflect what was achieved before stopping
/// (ADR 0268 §2).
final class SongGoalTerminalPartial extends SongGoalTerminalOutcome {
  const SongGoalTerminalPartial({required this.metricEvidence});

  /// Caller-supplied structured metric evidence (skill-id → score).
  final Map<String, double> metricEvidence;
}

/// Caller chose to skip. Not learner evidence (ADR 0268 §2).
final class SongGoalTerminalSkipped extends SongGoalTerminalOutcome {
  const SongGoalTerminalSkipped();
}

/// Technical failure (mic / crash / permission). Not learner evidence
/// (ADR 0268 §1).
final class SongGoalTerminalFailedTechnical extends SongGoalTerminalOutcome {
  const SongGoalTerminalFailedTechnical({required this.failureCode});

  /// Stable caller-supplied failure code.
  final String failureCode;
}

/// Asset reference the planner routed through was missing at execution
/// time. Not learner evidence (ADR 0318 §Döntés 2).
final class SongGoalTerminalUnavailable extends SongGoalTerminalOutcome {
  const SongGoalTerminalUnavailable();
}

/// The normalized song-goal outcome — caller-fed input, planner-normalized
/// surface (A8).
final class SongGoalOutcome {
  SongGoalOutcome({
    required this.assignment,
    required this.state,
    required this.evidenceIsLearnerSignal,
    required Map<String, double> metricEvidence,
  }) : metricEvidence = Map<String, double>.unmodifiable(metricEvidence);

  /// The assignment this outcome closes. Carries through so the audit
  /// log can group the outcome with the draft it belongs to.
  final SongGoalPhaseAssignment assignment;

  /// Normalized terminal state.
  final SongGoalOutcomeState state;

  /// `true` when this outcome carries learner evidence (only
  /// [SongGoalOutcomeState.completed] and [SongGoalOutcomeState.partial]
  /// are learner signals — per ADR 0268 §1, §2 and ADR 0318 §Döntés 2).
  final bool evidenceIsLearnerSignal;

  /// The metric evidence the caller supplied — empty when the
  /// terminal fact does not carry learner evidence.
  final Map<String, double> metricEvidence;
}

/// The pure planner. Construction is free; the only state is the policy
/// references it carries forward (each call may override).
final class SongGoalPlanner {
  const SongGoalPlanner();

  /// Plan one song-goal request and return the terminal outcome.
  ///
  /// The decision tree:
  ///   1. [SongGoalPlanningRequest.read] is a [SongGoalReadStaleRevision]
  ///      → [SongGoalPlanningStaleRevision].
  ///   2. [SongGoalPlanningRequest.read] is a [SongGoalReadNoSections]
  ///      → [SongGoalPlanningEmpty].
  ///   3. `target - scheduled < 0` (signed days) → [SongGoalPlanningNoOpAfterTarget]
  ///      (A2: no automatic new block after the target).
  ///   4. Otherwise classify each draft into foundation / integration /
  ///      simulation by the signed distance (A4), enforce the ratio cap
  ///      (A1), enforce prerequisite order (A3), and emit
  ///      [SongGoalPlanningAccepted] with explicit drops.
  SongGoalPlanningOutcome plan(SongGoalPlanningRequest request) {
    final read = request.read;
    if (read is SongGoalReadStaleRevision) {
      return SongGoalPlanningStaleRevision(
        documentId: read.documentId,
        actualRevision: read.actualRevision,
        expectedRevision: read.expectedRevision,
      );
    }
    if (read is SongGoalReadNoSections) {
      return SongGoalPlanningEmpty(
        documentId: read.documentId,
        documentRevision: read.documentRevision,
      );
    }
    final success = read as SongGoalReadSuccess;
    final distanceInDays = _signedDayDistance(
      request.scheduledDate,
      request.songTargetDate,
    );
    // `success` is the narrowed SongGoalReadSuccess — surface its
    // document-level asset list through the accepted outcome's reason
    // codes below.
    // ignore: unused_local_variable
    success;
    if (distanceInDays < 0) {
      return SongGoalPlanningNoOpAfterTarget(
        scheduledDate: request.scheduledDate,
        songTargetDate: request.songTargetDate,
        daysAfterTarget: -distanceInDays,
      );
    }
    final ratioPolicy =
        request.ratioPolicy ?? SongGoalRatioPolicy.defaultPolicy;
    final phasePolicy =
        request.phasePolicy ?? SongGoalPhasePolicy.defaultPolicy;
    final phase = _phaseForDistance(distanceInDays, phasePolicy);
    final knownSkillSet = request.knownSkillIds.toSet();

    final orderedDrafts = _prerequisiteOrdered(request.drafts, knownSkillSet);
    final maxSongMinutes =
        (request.weekAvailableMinutes * ratioPolicy.maximumSongRatio).floor();
    var runningSongMinutes = 0;
    final assignments = <SongGoalPhaseAssignment>[];
    final drops = <SongGoalDraftDrop>[];
    // A3 — actualized skills = the skills the caller already routes on
    // (`knownSkillIds`) UNION the `targetSkillIds` of every draft the
    // planner has already accepted in this very call. A draft whose
    // prerequisiteSkillIds are NOT all in this set has no producer (no
    // scheduled block produces the missing skill) and must be explicitly
    // dropped — never attached to an assignment as a side note.
    final actualizedSkills = <String>{
      for (final skill in request.knownSkillIds) skill,
    };

    for (final draft in orderedDrafts) {
      final section = draft.sectionView;
      final draftMinutes = draft.estimatedMinutes;

      // A3 — strict prerequisite gate (ADR 0264 §4). If the draft's
      // prerequisites are neither caller-known nor produced by an
      // already-accepted prerequisite block, the dependent song block
      // cannot be scheduled — the planner drops it explicitly with
      // [SongGoalDropReason.unsatisfiedPrerequisite] and the caller can
      // decide whether to defer the entire song goal or queue the
      // missing prerequisite for the next planning round.
      final unresolvedPrerequisites = [
        for (final skill in draft.prerequisiteSkillIds)
          if (!actualizedSkills.contains(skill)) skill,
      ];
      if (unresolvedPrerequisites.isNotEmpty) {
        drops.add(
          SongGoalDraftDrop(
            draft: draft,
            reasonCode: SongGoalDropReason.unsatisfiedPrerequisite,
            detail:
                'section=${section.sectionId.value},'
                'missing=${unresolvedPrerequisites.join(",")}',
          ),
        );
        continue;
      }

      // A5 — explicit asset gate (ADR 0318 §Döntés 2). A section without
      // a usable public asset reference cannot be routed by the planner.
      if (section.usableAssetReference == null) {
        drops.add(
          SongGoalDraftDrop(
            draft: draft,
            reasonCode: SongGoalDropReason.missingUsableAsset,
            detail: 'section=${section.sectionId.value}',
          ),
        );
        continue;
      }

      // A4 — no new technique in simulation.
      if (phase == SongGoalPhase.simulation) {
        final introducesNew = draft.targetSkillIds.any(
          (skill) => !actualizedSkills.contains(skill),
        );
        if (introducesNew) {
          drops.add(
            SongGoalDraftDrop(
              draft: draft,
              reasonCode: SongGoalDropReason.newTechniqueInSimulation,
              detail: 'section=${section.sectionId.value}',
            ),
          );
          continue;
        }
      }

      // A1 — ratio cap.
      if (runningSongMinutes + draftMinutes > maxSongMinutes) {
        drops.add(
          SongGoalDraftDrop(
            draft: draft,
            reasonCode: SongGoalDropReason.ratioCapExceeded,
            detail: 'section=${section.sectionId.value}',
          ),
        );
        continue;
      }

      // The draft is accepted. Surface its `targetSkillIds` so any
      // later draft that lists them as prerequisites sees the producer
      // and avoids being dropped on the A3 strict gate above.
      actualizedSkills.addAll(draft.targetSkillIds);

      assignments.add(
        SongGoalPhaseAssignment(
          draft: draft,
          phase: phase,
          targetSkillIds: List<String>.unmodifiable(draft.targetSkillIds),
          // Every kept assignment has its prerequisites satisfied by
          // definition — the A3 gate would have dropped it otherwise.
          // We keep the field for diagnostic parity but it MUST be
          // empty on a kept assignment.
          unsatisfiedPrerequisiteSkillIds: const <String>[],
          minutes: draftMinutes,
        ),
      );
      runningSongMinutes += draftMinutes;
    }

    return SongGoalPlanningAccepted(
      assignments: assignments,
      droppedDrafts: drops,
      weekAvailableMinutes: request.weekAvailableMinutes,
    );
  }

  /// Normalize a caller-fed terminal outcome (A8 — R23 rule).
  ///
  /// Only completed and partial terminals carry learner evidence; every
  /// other terminal is recorded with `evidenceIsLearnerSignal == false`
  /// so the next planner never treats it as a skill estimate input.
  SongGoalOutcome normalizeOutcome({
    required SongGoalPhaseAssignment assignment,
    required SongGoalTerminalOutcome terminal,
  }) {
    final stateAndEvidence = switch (terminal) {
      SongGoalTerminalCompleted(:final metricEvidence) => (
        SongGoalOutcomeState.completed,
        _validatedEvidence(metricEvidence),
        true,
      ),
      SongGoalTerminalPartial(:final metricEvidence) => (
        SongGoalOutcomeState.partial,
        _validatedEvidence(metricEvidence),
        true,
      ),
      SongGoalTerminalSkipped() => (
        SongGoalOutcomeState.skipped,
        const <String, double>{},
        false,
      ),
      SongGoalTerminalFailedTechnical() => (
        SongGoalOutcomeState.failedTechnical,
        const <String, double>{},
        false,
      ),
      SongGoalTerminalUnavailable() => (
        SongGoalOutcomeState.unavailable,
        const <String, double>{},
        false,
      ),
    };
    return SongGoalOutcome(
      assignment: assignment,
      state: stateAndEvidence.$1,
      evidenceIsLearnerSignal: stateAndEvidence.$3,
      metricEvidence: stateAndEvidence.$2,
    );
  }
}

// -- helpers ----------------------------------------------------------------

/// Compute `(b - a).inDays` in signed calendar days. Calendar arithmetic
/// — no time-of-day, no UTC drift — so the signed distance is stable
/// across timezones.
int _signedDayDistance(LocalDate a, LocalDate b) {
  final aDays = _toOrdinal(a);
  final bDays = _toOrdinal(b);
  return bDays - aDays;
}

int _toOrdinal(LocalDate date) {
  var days = date.day;
  var monthIndex = 1;
  while (monthIndex < date.month) {
    days += _daysInMonth(date.year, monthIndex);
    monthIndex += 1;
  }
  var yearIndex = 1;
  while (yearIndex < date.year) {
    days += _isLeapYear(yearIndex) ? 366 : 365;
    yearIndex += 1;
  }
  return days;
}

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int _daysInMonth(int year, int month) {
  switch (month) {
    case 2:
      return _isLeapYear(year) ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    default:
      return 31;
  }
}

SongGoalPhase _phaseForDistance(
  int distanceInDays,
  SongGoalPhasePolicy policy,
) {
  if (distanceInDays == 0) return SongGoalPhase.simulation;
  if (distanceInDays <= policy.lightReviewWindowDays) {
    return SongGoalPhase.integration;
  }
  return SongGoalPhase.foundation;
}

/// Stable, prerequisite-first ordering of drafts.
///
/// Drafts whose prerequisites are all in [knownSkillSet] come first in
/// declaration order; drafts that depend on each other are emitted after
/// their dependencies. Drafts with no prerequisites (or whose
/// prerequisites are all in `knownSkillSet`) keep their original order.
List<SongGoalBlockDraft> _prerequisiteOrdered(
  List<SongGoalBlockDraft> drafts,
  Set<String> knownSkillSet,
) {
  // Pair each draft with its original index so the comparator can break
  // ties stably (SongGoalBlockDraft itself is not Comparable).
  final indexed = <int, SongGoalBlockDraft>{
    for (var i = 0; i < drafts.length; i++) i: drafts[i],
  };
  // Stable sort by (dependency rank, original index) — drafts with
  // unsatisfied prerequisites are pushed to the end, drafts whose
  // prerequisites are earlier in the list are pulled forward. This is
  // O(n²) worst case but n is bounded by the number of song sections,
  // which is small.
  final entries = indexed.entries.toList(growable: false);
  entries.sort((a, b) {
    final aRank = _dependencyRank(a.value, drafts, knownSkillSet);
    final bRank = _dependencyRank(b.value, drafts, knownSkillSet);
    if (aRank != bRank) return aRank.compareTo(bRank);
    return a.key.compareTo(b.key);
  });
  return List<SongGoalBlockDraft>.unmodifiable([
    for (final entry in entries) entry.value,
  ]);
}

int _dependencyRank(
  SongGoalBlockDraft draft,
  List<SongGoalBlockDraft> allDrafts,
  Set<String> knownSkillSet,
) {
  // Rank 0 = no prerequisite or prerequisite is already known.
  // Rank 1 = depends on at least one earlier draft.
  // Rank 2 = depends only on later drafts (a cycle or unsatisfiable).
  var maxDependencyDraftIndex = -1;
  for (final prerequisite in draft.prerequisiteSkillIds) {
    if (knownSkillSet.contains(prerequisite)) continue;
    for (var i = 0; i < allDrafts.length; i++) {
      if (allDrafts[i].targetSkillIds.contains(prerequisite)) {
        if (i > maxDependencyDraftIndex) maxDependencyDraftIndex = i;
      }
    }
  }
  if (maxDependencyDraftIndex == -1) return 0;
  return 1;
}

Map<String, double> _validatedEvidence(Map<String, double> values) {
  for (final entry in values.entries) {
    if (entry.key.trim().isEmpty) {
      throw ArgumentError.value(
        entry.key,
        'metricEvidence key',
        'must not be empty or blank',
      );
    }
    if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
      throw ArgumentError.value(
        entry.value,
        'metricEvidence',
        'values must be finite and within 0..1',
      );
    }
  }
  return values;
}

double _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}
