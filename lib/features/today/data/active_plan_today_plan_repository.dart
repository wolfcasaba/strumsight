/// Projects the Practice Generator's ACTIVE plan onto the Today Hub's
/// read-only [TodayPlanSnapshot] (R19, audit M4).
///
/// Until this round `todayPlanRepositoryProvider` resolved to
/// `UnavailableTodayPlanRepository` and NOTHING in `lib/` overrode it, so a
/// learner who generated and activated a plan on the practice hub still met
/// the "start your first practice" hero on the app's landing tab. The plan
/// itself was real all along (`activePracticePlanProvider`, R4/R10) — only
/// the projection was missing.
///
/// The day-level decision is NOT re-implemented here: `TodayPlanController`
/// already resolves "which local day is today, and what is its mode" from
/// an injected clock (rest day / unavailable day / not scheduled /
/// completed / planned), and this class only renames its result into the
/// four fields the hub renders. Two sources of truth for "is today a rest
/// day" would drift.
///
/// Copy comes from the ALREADY SHIPPED practice-generator Today screen keys
/// (`todayPlanRestBody`, `todayPlanUnavailableBody`, …): the two surfaces
/// then say the same thing about the same day, and this round adds no new
/// ARB key.
library;

import '../../../l10n/app_localizations.dart';
import '../../practice_generator/public.dart';
import '../domain/today_plan_repository.dart';
import '../domain/today_plan_snapshot.dart';

final class ActivePlanTodayPlanRepository implements TodayPlanRepository {
  const ActivePlanTodayPlanRepository({
    required this.controller,
    required this.plan,
    required this.l10n,
  });

  /// Resolves the local day and its mode. Injected (not constructed) so the
  /// hub and the plan screen share ONE clock.
  final TodayPlanController controller;

  /// The active plan. `null` and a non-active status both resolve to
  /// [TodayPlanAvailability.unavailable] through the controller.
  final AdaptivePracticePlan? plan;

  final AppLocalizations l10n;

  @override
  TodayPlanSnapshot load() {
    final state = controller.resolve(plan);
    if (state.mode == TodayPlanMode.noActivePlan) {
      return const TodayPlanSnapshot(
        availability: TodayPlanAvailability.unavailable,
      );
    }

    final blocks = state.day?.blocks ?? const <PracticeBlock>[];
    final total = blocks.length;

    // A day the plan itself calls completed reports full completion at DAY
    // granularity, even if individual blocks ended as skipped/substituted:
    // the hub's recap is about the day, and re-deriving it from block
    // statuses would contradict the plan's own verdict.
    if (state.mode == TodayPlanMode.completedDay) {
      return TodayPlanSnapshot(
        availability: TodayPlanAvailability.ready,
        recommendedTaskLabel: total == 0 ? _dayStateMessage(state.mode) : null,
        completedTaskCount: total,
        totalTaskCount: total,
      );
    }

    final next = state.nextBlock;
    return TodayPlanSnapshot(
      availability: TodayPlanAvailability.ready,
      recommendedTaskLabel: next == null
          ? _dayStateMessage(state.mode)
          : _blockLabel(next),
      completedTaskCount: blocks.where(_isCompleted).length,
      totalTaskCount: total,
    );
  }

  static bool _isCompleted(PracticeBlock block) =>
      block.status == PracticeItemStatus.completed;

  /// Why today names no next task. Never "you have no plan" — the plan is
  /// active; today simply has nothing left to run.
  String _dayStateMessage(TodayPlanMode mode) => switch (mode) {
    TodayPlanMode.noActivePlan => l10n.todayPlanEmptyBody,
    TodayPlanMode.notScheduled => l10n.todayPlanNotScheduledBody,
    TodayPlanMode.restDay => l10n.todayPlanRestBody,
    TodayPlanMode.unavailableDay => l10n.todayPlanUnavailableBody,
    TodayPlanMode.completedDay => l10n.todayPlanCompletedBody,
    TodayPlanMode.plannedDay => l10n.todayPlanNothingRemaining,
  };

  /// The block's localized KIND — the same vocabulary `PlanBlockCard` uses.
  /// The raw `exerciseId` is a catalog key, not user-facing copy.
  String _blockLabel(PracticeBlock block) => switch (block.kind) {
    BlockKind.readiness => l10n.planPreviewBlockReadiness,
    BlockKind.warmup => l10n.planPreviewBlockWarmup,
    BlockKind.assessment => l10n.planPreviewBlockAssessment,
    BlockKind.primaryFocus => l10n.planPreviewBlockPrimaryFocus,
    BlockKind.secondaryFocus => l10n.planPreviewBlockSecondaryFocus,
    BlockKind.maintenance => l10n.planPreviewBlockMaintenance,
    BlockKind.song => l10n.planPreviewBlockSong,
    BlockKind.freePlay => l10n.planPreviewBlockFreePlay,
    BlockKind.reflection => l10n.planPreviewBlockReflection,
    BlockKind.rest => l10n.planPreviewBlockRest,
    BlockKind.cooldown => l10n.planPreviewBlockCooldown,
  };
}
