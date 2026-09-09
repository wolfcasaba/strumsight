import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ten_minute_flow.dart';

/// The stored "10 useful minutes" chain (Ch14 Kör 36), or `null` when no
/// chain is running.
///
/// Session-scoped by construction: the state lives in this notifier only, so
/// it survives navigating away from the Today hub and back (that is the
/// resume-after-interruption case the round is about) but NOT a process
/// death. Cross-launch resume needs a `StorageKeys` entry, which this
/// package does not own — see the round brief §10 for the exact proposed
/// patch. Until it lands, a killed app honestly starts with no chain rather
/// than pretending to remember one.
class TenMinuteFlowController extends Notifier<TenMinuteFlowState?> {
  @override
  TenMinuteFlowState? build() => null;

  /// Begin the chain at its first step.
  ///
  /// [activeSecondsToday] is the daily-goal active-time reading AT THIS
  /// MOMENT: it becomes the baseline the play step's evidence is measured
  /// against, so practice minutes the user had already logged today can
  /// never be counted as this session's work.
  void start({
    required DateTime now,
    required int activeSecondsToday,
    Duration total = TenMinutePlan.defaultTotal,
  }) {
    state = TenMinuteFlowState(
      plan: TenMinutePlan.of(total),
      step: TenMinutePlan.steps.first,
      startedAt: now,
      baselineActiveSeconds: activeSecondsToday,
    );
  }

  /// Commit the move to the next step. [from] is the step the UI actually
  /// showed the user — passing it makes the transition idempotent against a
  /// double tap and against the derived `play → review` promotion
  /// ([resolveTenMinuteFlow]) having already happened in the view.
  void advance({required TenMinuteStep from}) {
    final current = state;
    if (current == null) return;
    final base = current.step == from ? current : current.copyWith(step: from);
    state = base.advanced();
  }

  /// The user left the chain on purpose (or finished the recap): drop it.
  void abandon() => state = null;
}

final tenMinuteFlowProvider =
    NotifierProvider<TenMinuteFlowController, TenMinuteFlowState?>(
      TenMinuteFlowController.new,
    );
