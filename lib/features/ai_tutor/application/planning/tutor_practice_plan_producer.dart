/// The tutor's practice-plan producer (R9).
///
/// `PracticePlanPreviewScreen` has always been able to RENDER and EDIT a
/// [PracticePlanDraft]; what the tree never had was a source for one. This
/// file is that source, plus the return trip: turning the (possibly
/// user-edited) draft into the Practice Generator's own
/// [AdaptivePracticePlan] so the preview's accept action can hand it to
/// `LocalPracticePlanRepository` through that feature's public API.
///
/// Two deliberate properties:
///
/// * **The plan is built from the on-device catalog, never invented.** Every
///   block names a real `ExerciseCandidate.exerciseId`, so a block the user
///   accepts is an exercise the app can actually run. An empty catalog is a
///   typed failure, not a plan full of unrunnable blocks.
/// * **Nothing here reaches the network or the clock.** The caller supplies
///   the catalog snapshot, the localised strings and `now` — this file is a
///   pure function of its inputs, so its tests are deterministic.
library;

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show
        AdaptivePracticePlan,
        BlockId,
        BlockKind,
        CapabilitySupport,
        DayId,
        ExerciseCandidate,
        ExerciseCapability,
        ExercisePrescription,
        GenerationRequestId,
        LocalDate,
        PlanId,
        PlanStatus,
        PracticeBlock,
        PracticeCatalogSnapshot,
        PracticeDay,
        PracticeGoal,
        PracticeItemStatus,
        RepetitionPrescription,
        RevisionId,
        SuccessCriteria,
        SuccessCriterionKind;

import '../../domain/models/practice_plan_block.dart';
import '../../domain/models/practice_plan_draft.dart';
import '../../domain/models/skill_node.dart';
import '../../domain/services/practice_plan_validator.dart';

/// The catalog has no runnable candidate, so no honest plan can be built.
const String tutorPlanCatalogEmptyCode = 'tutor.plan.catalog_empty';

/// The requested plan length cannot be split into whole-minute blocks.
const String tutorPlanDurationTooShortCode = 'tutor.plan.duration_too_short';

/// A block references an exercise the catalog no longer contains (a stale
/// draft). Never silently substituted — the user would get a different
/// exercise than the one they accepted.
const String tutorPlanExerciseMissingCode = 'tutor.plan.exercise_missing';

/// No block in the draft maps to a runnable exercise.
const String tutorPlanNotExecutableCode = 'tutor.plan.not_executable';

/// A candidate declares no capability the success criterion could be
/// measured with, so "done" would be unfalsifiable.
const String tutorPlanUnmeasurableCode = 'tutor.plan.unmeasurable';

/// The largest number of blocks a proposed plan is split into.
const int tutorPlanMaxBlocks = 4;

/// A produced draft together with the validation context it is valid in.
///
/// The screen needs both: the draft to render and edit, and the context its
/// [PracticePlanValidator] measures the edited draft against.
final class TutorPracticePlanProposal {
  const TutorPracticePlanProposal({
    required this.draft,
    required this.validationContext,
  });

  final PracticePlanDraft draft;
  final PracticePlanValidationContext validationContext;
}

/// Builds tutor practice-plan drafts from the on-device exercise catalog.
final class TutorPracticePlanProducer {
  const TutorPracticePlanProducer();

  /// Proposes a draft that fills [targetDuration] with catalog exercises.
  ///
  /// [title] and [rationale] are already localised by the caller — this
  /// layer never formats user-facing text.
  AppResult<TutorPracticePlanProposal> propose({
    required PracticeCatalogSnapshot catalog,
    required Duration targetDuration,
    required String title,
    required String rationale,
    List<String> goalIds = const <String>[],
  }) {
    final candidates = catalog.candidates;
    if (candidates.isEmpty) {
      return const AppResult<TutorPracticePlanProposal>.failure(
        ValidationFailure(code: tutorPlanCatalogEmptyCode),
      );
    }
    final totalMinutes = targetDuration.inMinutes;
    if (totalMinutes < 1) {
      return const AppResult<TutorPracticePlanProposal>.failure(
        ValidationFailure(code: tutorPlanDurationTooShortCode),
      );
    }

    final blockCount = _blockCount(totalMinutes, candidates.length);
    final minutes = _splitMinutes(totalMinutes, blockCount);
    final blocks = <PracticePlanBlock>[];
    for (var index = 0; index < blockCount; index++) {
      final candidate = candidates[index];
      blocks.add(
        PracticePlanBlock.practiceTarget(
          id: 'tutor.plan.block.$index',
          type: tutorBlockTypeFor(candidate),
          duration: Duration(minutes: minutes[index]),
          practiceTargetId: candidate.exerciseId,
          requiredCapabilities: const <PracticePlanCapability>{
            PracticePlanCapability.practiceTarget,
          },
          assetAvailableLocally: candidate.offlineAvailable,
        ),
      );
    }

    final draft = PracticePlanDraft(
      id: 'tutor.plan.$totalMinutes',
      title: title,
      targetDuration: Duration(minutes: totalMinutes),
      blocks: blocks,
      goalIds: goalIds,
      rationale: rationale,
      source: PracticePlanSource.deterministicTemplate,
    );

    return AppResult<TutorPracticePlanProposal>.success(
      TutorPracticePlanProposal(
        draft: draft,
        validationContext: validationContextFor(catalog),
      ),
    );
  }

  /// The context a produced (or user-edited) draft is validated against.
  ///
  /// Exposed separately so the screen keeps validating edits against the
  /// SAME catalog the draft was produced from.
  PracticePlanValidationContext validationContextFor(
    PracticeCatalogSnapshot catalog,
  ) => PracticePlanValidationContext(
    songIds: const <String>{},
    practiceTargetIds: <String>{
      for (final candidate in catalog.candidates) candidate.exerciseId,
    },
    userAvoidList: const <String>{},
    activeTuning: const <String>[],
    capabilities: const <PracticePlanCapability>{
      PracticePlanCapability.practiceTarget,
    },
    availableSkillIds: const <SkillId>{},
  );

  /// Compiles an accepted [draft] into the Practice Generator's own plan
  /// document, ready for `LocalPracticePlanRepository.activateAndReport`.
  ///
  /// Ids are derived from the draft, so compiling the same accepted draft
  /// twice produces the same `{planId, revisionId}` pair — the repository's
  /// activation is then structurally idempotent instead of writing a new
  /// revision on every tap.
  AppResult<AdaptivePracticePlan> compileActivePlan({
    required PracticePlanDraft draft,
    required PracticeCatalogSnapshot catalog,
    required DateTime now,
  }) {
    final byId = <String, ExerciseCandidate>{
      for (final candidate in catalog.candidates)
        candidate.exerciseId: candidate,
    };
    final blocks = <PracticeBlock>[];
    final focusSkills = <String>{};
    for (var index = 0; index < draft.blocks.length; index++) {
      final planBlock = draft.blocks[index];
      final exerciseId = planBlock.practiceTargetId;
      if (exerciseId == null) continue;
      final candidate = byId[exerciseId];
      if (candidate == null) {
        return const AppResult<AdaptivePracticePlan>.failure(
          ValidationFailure(code: tutorPlanExerciseMissingCode),
        );
      }
      final prescribed = _prescriptionFor(candidate, planBlock.duration);
      if (prescribed case Failure<ExercisePrescription>(:final error)) {
        return AppResult<AdaptivePracticePlan>.failure(error);
      }
      final prescription = prescribed.valueOrNull!;
      focusSkills.addAll(candidate.skillTargets);
      blocks.add(
        PracticeBlock(
          id: BlockId('${_idSegment(draft.id)}.block.$index'),
          kind: _blockKindFor(planBlock.type),
          order: index + 1,
          prescription: prescription,
          reasonCodes: const <String>['tutor.plan.proposal'],
          evidenceRefs: <String>['tutor.plan.draft:${draft.id}'],
          status: PracticeItemStatus.planned,
          estimatedElapsed: prescription.hardElapsedLimit,
        ),
      );
    }
    if (blocks.isEmpty) {
      return const AppResult<AdaptivePracticePlan>.failure(
        ValidationFailure(code: tutorPlanNotExecutableCode),
      );
    }

    final utcNow = now.toUtc();
    final today = LocalDate(utcNow.year, utcNow.month, utcNow.day);
    final planId = _idSegment(draft.id);
    final day = PracticeDay(
      id: DayId('$planId.day.1'),
      localDate: today,
      status: PracticeItemStatus.planned,
      timeBudget: draft.targetDuration,
      blocks: blocks,
      primaryFocusSkillIds: focusSkills.toList()..sort(),
      reasonCodes: const <String>['tutor.plan.proposal'],
    );

    return AppResult<AdaptivePracticePlan>.success(
      AdaptivePracticePlan(
        id: PlanId(planId),
        schemaVersion: 1,
        status: PlanStatus.active,
        title: draft.title,
        createdAt: utcNow,
        startDate: today,
        endDate: today,
        goals: const <PracticeGoal>[],
        days: <PracticeDay>[day],
        activeRevisionId: RevisionId('$planId.rev.${_revisionOf(draft)}'),
        generationProvenance: GenerationRequestId('$planId.request'),
        policyVersions: const <String, String>{'tutor.plan': 'v1'},
      ),
    );
  }

  /// One prescription for [candidate] filling [slot].
  ///
  /// The builtin catalog reports an EXACT supported duration per exercise
  /// (`SupportedDurations.exact`, measured from the definition's own tempo
  /// and length), so a longer block is filled by repeating the exercise —
  /// never by stretching it past what its content supports.
  AppResult<ExercisePrescription> _prescriptionFor(
    ExerciseCandidate candidate,
    Duration slot,
  ) {
    final supported = candidate.supportedDurations;
    var active = slot;
    if (active < supported.minimum) active = supported.minimum;
    if (active > supported.maximum) active = supported.maximum;
    if (active <= Duration.zero) {
      return const AppResult<ExercisePrescription>.failure(
        ValidationFailure(code: tutorPlanNotExecutableCode),
      );
    }
    final capability = _measurableCapabilityFor(candidate);
    if (capability == null) {
      return const AppResult<ExercisePrescription>.failure(
        ValidationFailure(code: tutorPlanUnmeasurableCode),
      );
    }
    var loops = slot.inMicroseconds ~/ active.inMicroseconds;
    if (loops < 1) loops = 1;
    return AppResult<ExercisePrescription>.success(
      ExercisePrescription(
        candidate: candidate,
        activeDuration: active,
        restDuration: Duration.zero,
        repetition: RepetitionPrescription(target: loops, maximum: loops),
        loopCount: loops,
        hardElapsedLimit: active * loops,
        successCriteria: SuccessCriteria(
          kind: SuccessCriterionKind.completion,
          description: 'Complete the prescribed repetitions.',
          requiredCapabilities: <ExerciseCapability>[capability],
        ),
      ),
    );
  }

  /// The first capability the candidate actually supports, in a fixed
  /// preference order. Returns null when it supports none — the criterion
  /// would then be unmeasurable, and we refuse instead of pretending.
  ExerciseCapability? _measurableCapabilityFor(ExerciseCandidate candidate) {
    const preference = <ExerciseCapability>[
      ExerciseCapability.supportsChordScoring,
      ExerciseCapability.supportsDirectionScoring,
      ExerciseCapability.requiresMicrophone,
      ExerciseCapability.supportsLoop,
      ExerciseCapability.supportsOffline,
    ];
    for (final capability in preference) {
      final support = candidate.capabilities[capability];
      if (support == CapabilitySupport.supported) return capability;
    }
    return null;
  }
}

/// Maps a tutor plan-block type onto the Practice Generator's block kind.
BlockKind _blockKindFor(String type) => switch (type) {
  PracticePlanBlockType.warmup => BlockKind.warmup,
  PracticePlanBlockType.freePractice => BlockKind.freePlay,
  PracticePlanBlockType.reflection => BlockKind.reflection,
  PracticePlanBlockType.rest => BlockKind.rest,
  PracticePlanBlockType.songRange => BlockKind.song,
  _ => BlockKind.primaryFocus,
};

/// The block type a candidate is presented under.
///
/// This is a PRESENTATION category derived from the exercise's own declared
/// skill tags — not a pedagogical claim about the exercise. The tags come
/// from the catalog, so a retagged exercise moves category by itself.
String tutorBlockTypeFor(ExerciseCandidate candidate) {
  final tags = candidate.skillTargets.toSet();
  if (tags.contains('freePlay')) return PracticePlanBlockType.freePractice;
  if (tags.contains('chordChanges') || tags.contains('chordProgression')) {
    return PracticePlanBlockType.chordChange;
  }
  if (tags.contains('downstrokes')) return PracticePlanBlockType.warmup;
  if (tags.contains('syncopation')) return PracticePlanBlockType.speedBuilder;
  if (tags.contains('rhythm') ||
      tags.contains('quarterNotes') ||
      tags.contains('eighthNotes') ||
      tags.contains('rhythmOnly')) {
    return PracticePlanBlockType.rhythm;
  }
  return PracticePlanBlockType.technique;
}

/// How many blocks a plan of [totalMinutes] is split into: at most
/// [tutorPlanMaxBlocks], never more than the catalog can back, and never so
/// many that a block would be shorter than one whole minute.
int _blockCount(int totalMinutes, int candidateCount) {
  var count = tutorPlanMaxBlocks;
  if (count > candidateCount) count = candidateCount;
  if (count > totalMinutes) count = totalMinutes;
  return count;
}

/// Splits [totalMinutes] into [blockCount] whole minutes that sum EXACTLY
/// back to the total — the validator rejects any mismatch, and a plan whose
/// blocks do not add up to its own length is a lie about practice time.
List<int> _splitMinutes(int totalMinutes, int blockCount) {
  final base = totalMinutes ~/ blockCount;
  var remainder = totalMinutes % blockCount;
  final minutes = <int>[];
  for (var index = 0; index < blockCount; index++) {
    var value = base;
    if (remainder > 0) {
      value += 1;
      remainder -= 1;
    }
    minutes.add(value);
  }
  return minutes;
}

/// A CONTENT-derived revision tag: block order, targets and minutes.
///
/// It must change whenever the accepted plan changes, and must NOT change
/// when it does not. A revision id that ignored the user's duration edits
/// would make `activate` a structural no-op and silently drop the edit —
/// the exact silent-no-op trap this repo has been bitten by before. Digest
/// is FNV-1a so the value is stable across runs and platforms (unlike
/// `String.hashCode`, which is not).
String _revisionOf(PracticePlanDraft draft) {
  final buffer = StringBuffer(draft.targetDuration.inMinutes.toString());
  for (var index = 0; index < draft.blocks.length; index++) {
    final block = draft.blocks[index];
    buffer
      ..write('|$index:')
      ..write(block.practiceTargetId ?? block.id)
      ..write(':${block.duration.inMinutes}');
  }
  return _fnv1a(buffer.toString()).toRadixString(36);
}

/// 32-bit FNV-1a over the UTF-16 code units — small, dependency-free and
/// deterministic. Used only to name a revision, never for security.
int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Reduces a draft id to the identifier alphabet the planner ids accept.
String _idSegment(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._:-]'), '-');
  return cleaned.isEmpty ? 'tutor.plan' : cleaned;
}
