/// Full invariant validation for an [AdaptivePracticePlan] (ADR 0263,
/// SDD Ch8 Kör 11).
///
/// The validator is a pure, deterministic gate: it never mutates its input,
/// never reads the clock, and never generates randomness. It never
/// interprets a [LearnerConstraint]'s free-text `value` — every
/// executability signal it acts on is the typed, identity-based state
/// supplied through [PlanValidationContext] (pre-flight §0.0.1).
library;

import '../id/planner_ids.dart';
import '../model/adaptive_practice_plan.dart';
import '../model/exercise_candidate.dart';
import '../model/learner_constraints.dart';
import '../model/plan_enums.dart';
import '../model/plan_validation_issue.dart';
import '../model/practice_block.dart';
import '../model/practice_catalog_snapshot.dart';
import '../model/practice_day.dart';
import '../model/weekly_availability.dart';

/// The explicit, typed execution truth a caller supplies for validation and
/// repair.
///
/// Every identity below is `source.code:exerciseId`. A candidate, asset,
/// device-capability, offline, or tuning state that is not present in its
/// corresponding set is treated as unconfirmed — there is no optimistic
/// fallback (§0.0.1).
final class PlanValidationContext {
  PlanValidationContext({
    required this.catalog,
    required this.availability,
    required this.repairRevisionId,
    this.previousSnapshot,
    Iterable<String> confirmedAssetIdentities = const <String>[],
    Iterable<String> confirmedDeviceCapabilityIdentities = const <String>[],
    Iterable<String> confirmedOfflineIdentities = const <String>[],
    Iterable<String> confirmedTuningIdentities = const <String>[],
    Iterable<String> hardAvoidIdentities = const <String>[],
  }) : confirmedAssetIdentities = Set<String>.unmodifiable(
         confirmedAssetIdentities,
       ),
       confirmedDeviceCapabilityIdentities = Set<String>.unmodifiable(
         confirmedDeviceCapabilityIdentities,
       ),
       confirmedOfflineIdentities = Set<String>.unmodifiable(
         confirmedOfflineIdentities,
       ),
       confirmedTuningIdentities = Set<String>.unmodifiable(
         confirmedTuningIdentities,
       ),
       hardAvoidIdentities = Set<String>.unmodifiable(hardAvoidIdentities);

  /// The current catalog snapshot: candidate identity, content revision, and
  /// load-profile truth (§0.0.1).
  final PracticeCatalogSnapshot catalog;

  /// The learner's hard/soft weekly availability (ADR 0258).
  final WeeklyAvailability availability;

  /// The revision id a successful repair's [PlanChangeSet] targets. Supplied
  /// by the caller so the repairer never generates an id itself (ADR 0263
  /// §5: no clock, no randomness).
  final RevisionId repairRevisionId;

  /// The previous full plan snapshot, used only to detect a completed-past
  /// modification (§0.0.1, ADR 0256 §1). `null` when there is no prior
  /// revision (e.g. first generation).
  final AdaptivePracticePlan? previousSnapshot;

  final Set<String> confirmedAssetIdentities;
  final Set<String> confirmedDeviceCapabilityIdentities;
  final Set<String> confirmedOfflineIdentities;
  final Set<String> confirmedTuningIdentities;

  /// Identities the caller has determined are hard-avoided for this learner
  /// (ADR 0258 hard constraint truth, resolved outside this boundary).
  final Set<String> hardAvoidIdentities;

  static String identityOf(ExerciseCandidate candidate) =>
      '${candidate.source.code}:${candidate.exerciseId}';

  static String identityOfReference(String sourceCode, String exerciseId) =>
      '$sourceCode:$exerciseId';

  ExerciseCandidate? candidateByIdentity(String identity) {
    for (final candidate in catalog.candidates) {
      if (identityOf(candidate) == identity) return candidate;
    }
    return null;
  }
}

/// Validates every hard invariant in an [AdaptivePracticePlan] (ADR 0263
/// §1). The result is a gate, never advice: `error`/`fatal` findings mean
/// the plan must not be activated (`PlanValidationResult.isActivatable`).
final class PlanValidator {
  const PlanValidator({this.maxConsecutiveHighFrettingLoad = 2});

  /// A1 kritérium: legfeljebb ennyi egymást követő, magas fretting-hand
  /// terhelésű blokk engedett egy napon belül warning nélkül (§0.0.1,
  /// alapértelmezés 2).
  final int maxConsecutiveHighFrettingLoad;

  PlanValidationResult validate(
    AdaptivePracticePlan plan,
    PlanValidationContext context,
  ) {
    if (maxConsecutiveHighFrettingLoad < 1) {
      throw StateError('maxConsecutiveHighFrettingLoad must be at least one');
    }
    final issues = <PlanValidationIssue>[
      ..._validateCompletedHistory(plan, context),
      for (final day in plan.days) ..._validateDay(day, context),
    ];
    return PlanValidationResult(issues);
  }

  List<PlanValidationIssue> _validateCompletedHistory(
    AdaptivePracticePlan plan,
    PlanValidationContext context,
  ) {
    final previous = context.previousSnapshot;
    if (previous == null) return const <PlanValidationIssue>[];
    final previousDaysById = <DayId, PracticeDay>{
      for (final day in previous.days) day.id: day,
    };
    final issues = <PlanValidationIssue>[];
    for (final day in plan.days) {
      final previousDay = previousDaysById[day.id];
      if (previousDay == null ||
          previousDay.status != PracticeItemStatus.completed) {
        continue;
      }
      if (day != previousDay) {
        issues.add(
          PlanValidationIssue(
            severity: ValidationSeverity.fatal,
            code: PlanValidationCode.completedHistoryModified,
            message: 'Completed day ${day.id.value} was modified.',
            dayId: day.id,
          ),
        );
      }
    }
    return issues;
  }

  List<PlanValidationIssue> _validateDay(
    PracticeDay day,
    PlanValidationContext context,
  ) {
    final issues = <PlanValidationIssue>[..._validateHardMaximum(day, context)];
    final orderedBlocks = [...day.blocks]
      ..sort((a, b) => a.order.compareTo(b.order));
    var consecutiveHigh = 0;
    for (final block in orderedBlocks) {
      final identity = PlanValidationContext.identityOfReference(
        block.prescription.source.code,
        block.prescription.exerciseId,
      );
      final candidate = context.candidateByIdentity(identity);
      issues.addAll(
        _validateBlockExecutability(day, block, identity, candidate, context),
      );
      if (candidate?.loadProfile.frettingHand == LoadLevel.high) {
        consecutiveHigh += 1;
        if (consecutiveHigh == maxConsecutiveHighFrettingLoad + 1) {
          issues.add(
            PlanValidationIssue(
              severity: ValidationSeverity.warning,
              code: PlanValidationCode.loadSequencingWarning,
              message:
                  'Day ${day.id.value} has more than '
                  '$maxConsecutiveHighFrettingLoad consecutive high '
                  'fretting-hand-load blocks.',
              dayId: day.id,
              blockId: block.id,
            ),
          );
        }
      } else {
        consecutiveHigh = 0;
      }
    }
    return issues;
  }

  List<PlanValidationIssue> _validateHardMaximum(
    PracticeDay day,
    PlanValidationContext context,
  ) {
    final daily = context.availability.forDate(day.localDate);
    if (daily == null || daily.maximumStrength != ConstraintStrength.hard) {
      return const <PlanValidationIssue>[];
    }
    final maxMicros = Duration(minutes: daily.maximumMinutes).inMicroseconds;
    final totalMicros = day.blocks.fold<int>(
      0,
      (total, block) => total + block.estimatedElapsed.inMicroseconds,
    );
    if (totalMicros <= maxMicros) return const <PlanValidationIssue>[];
    return <PlanValidationIssue>[
      PlanValidationIssue(
        severity: ValidationSeverity.error,
        code: PlanValidationCode.hardMaximumExceeded,
        message:
            'Day ${day.id.value} schedules '
            '${Duration(microseconds: totalMicros)} which exceeds the hard '
            'maximum of ${daily.maximumMinutes} minutes.',
        dayId: day.id,
      ),
    ];
  }

  List<PlanValidationIssue> _validateBlockExecutability(
    PracticeDay day,
    PracticeBlock block,
    String identity,
    ExerciseCandidate? candidate,
    PlanValidationContext context,
  ) {
    if (candidate == null) {
      return <PlanValidationIssue>[
        PlanValidationIssue(
          severity: ValidationSeverity.error,
          code: PlanValidationCode.candidateIdentityMissing,
          message:
              'Block ${block.id.value} references unknown candidate '
              '$identity.',
          dayId: day.id,
          blockId: block.id,
        ),
      ];
    }
    final issues = <PlanValidationIssue>[];
    if (candidate.contentRevision != block.prescription.contentRevision) {
      issues.add(
        PlanValidationIssue(
          severity: ValidationSeverity.error,
          code: PlanValidationCode.contentRevisionMismatch,
          message:
              'Block ${block.id.value} content revision '
              '${block.prescription.contentRevision} no longer matches '
              'catalog revision ${candidate.contentRevision}.',
          dayId: day.id,
          blockId: block.id,
        ),
      );
    }
    if (context.hardAvoidIdentities.contains(identity)) {
      issues.add(
        PlanValidationIssue(
          severity: ValidationSeverity.error,
          code: PlanValidationCode.hardAvoidViolated,
          message:
              'Block ${block.id.value} schedules a hard-avoided exercise '
              '$identity.',
          dayId: day.id,
          blockId: block.id,
        ),
      );
    }
    final needsAsset =
        candidate.capabilities[ExerciseCapability.requiresSongAsset] ==
            CapabilitySupport.supported ||
        candidate.capabilities[ExerciseCapability.requiresBackingTrack] ==
            CapabilitySupport.supported;
    if (needsAsset && !context.confirmedAssetIdentities.contains(identity)) {
      issues.add(
        _unconfirmed(
          day,
          block,
          identity,
          PlanValidationCode.assetNotConfirmed,
          'asset',
        ),
      );
    }
    final needsDeviceCapability =
        candidate.capabilities[ExerciseCapability.requiresMicrophone] ==
            CapabilitySupport.supported ||
        candidate.capabilities[ExerciseCapability.requiresCamera] ==
            CapabilitySupport.supported;
    if (needsDeviceCapability &&
        !context.confirmedDeviceCapabilityIdentities.contains(identity)) {
      issues.add(
        _unconfirmed(
          day,
          block,
          identity,
          PlanValidationCode.deviceCapabilityNotConfirmed,
          'device capability',
        ),
      );
    }
    if (!candidate.offlineAvailable &&
        !context.confirmedOfflineIdentities.contains(identity)) {
      issues.add(
        _unconfirmed(
          day,
          block,
          identity,
          PlanValidationCode.offlineNotConfirmed,
          'offline availability',
        ),
      );
    }
    if (candidate.prerequisites.isNotEmpty &&
        !context.confirmedTuningIdentities.contains(identity)) {
      issues.add(
        _unconfirmed(
          day,
          block,
          identity,
          PlanValidationCode.tuningNotConfirmed,
          'tuning/prerequisite',
        ),
      );
    }
    return issues;
  }

  PlanValidationIssue _unconfirmed(
    PracticeDay day,
    PracticeBlock block,
    String identity,
    String code,
    String label,
  ) => PlanValidationIssue(
    severity: ValidationSeverity.error,
    code: code,
    message:
        'Block ${block.id.value} $label for $identity is not confirmed by '
        'the caller.',
    dayId: day.id,
    blockId: block.id,
  );
}
